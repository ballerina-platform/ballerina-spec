# Runtime Log Level Modification Support for ballerina/log

- Authors
  - @daneshk
- Reviewed by
  - @TharmiganK
- Created date
  - 2026-02-03
- Issue
  - [1424](https://github.com/ballerina-platform/ballerina-spec/issues/1424)
- State
  - Submitted

## Summary

This proposal introduces Java APIs to modify log levels at runtime without application restart. The primary goal is to enable the WSO2 Integrator: ICP (Integration Control Plane) agent to dynamically adjust log levels for the root logger level, module-specific log levels, and custom loggers level created via the `fromConfig` API.

## Goals

- Provide Java APIs to retrieve the current log configuration at runtime.
- Enable runtime modification of the global root log level.
- Support adding, updating, and removing module-level log configurations at runtime.
- Allow modification of log levels for custom loggers created via `fromConfig` API (when explicitly identified by the user).
- Maintain backward compatibility with the existing `ballerina/log` API.
- Ensure thread-safe operations for concurrent log level modifications.

## Non-Goals

- This proposal does not provide Ballerina-level public APIs for runtime log modification (APIs are Java-only for ICP agent use).
- Log levels of custom loggers created without an explicit ID cannot be modified via ICP.
- This proposal does not support modifying other logger configurations (format, destinations) at runtime.

## Motivation

In production environments, the ability to change log levels dynamically is crucial for debugging and monitoring without requiring application restarts. Currently, the only way to change log levels in Ballerina applications is through the `Config.toml` file, which requires an application restart to take effect.

The WSO2 Integrator: ICP (Integration Control Plane) dashboard needs to provide operators with the ability to:
1. View the current logging configuration of running applications.
2. Increase log verbosity (e.g., switch to DEBUG) when investigating issues.
3. Reduce log verbosity (e.g., switch to ERROR) to reduce noise and storage costs.
4. Configure logging differently for specific modules without affecting others.

This capability is essential for:
- **Production debugging**: Temporarily enable DEBUG logging to diagnose issues without restarting the application.
- **Performance optimization**: Reduce logging overhead by increasing log levels during high-load periods.
- **Compliance**: Enable detailed audit logging on demand for compliance investigations.

## Design

### Backward Compatibility

This proposal maintains full backward compatibility. All existing logging functionality continues to work unchanged:

```ballerina
// Existing usage - unchanged
log:printInfo("Hello World!");

// Existing custom logger - unchanged
log:Logger myLogger = check log:fromConfig(level = log:DEBUG);
myLogger.printInfo("Custom logger message");
```

### Custom Logger Identification

To enable ICP to modify a custom logger's level, users must provide an explicit `id` when creating the logger. This proposal adds an optional `id` field to the `Config` record:

```ballerina
public type Config record {|
    # Optional unique identifier for this logger. If provided, the logger will be visible
    # in the ICP dashboard and its log level can be modified at runtime.
    # If not provided, the logger's level cannot be changed via ICP.
    string id?;
    LogFormat format = format;
    Level level = level;
    readonly & OutputDestination[] destinations = destinations;
    readonly & AnydataKeyValues keyValues = {...keyValues};
    boolean enableSensitiveDataMasking = enableSensitiveDataMasking;
|};
```

#### Usage Examples

**Logger visible to ICP (can be configured at runtime):**
```ballerina
// Create a logger with an explicit ID - visible in ICP dashboard
log:Logger paymentLogger = check log:fromConfig(id = "payment-service", level = log:INFO);
paymentLogger.printInfo("Processing payment");

// ICP agent can later change this logger's level to DEBUG for debugging
```

**Logger not visible to ICP (internal use only):**
```ballerina
// Create a logger without ID - not visible in ICP dashboard
log:Logger internalLogger = check log:fromConfig(level = log:DEBUG);
internalLogger.printDebug("Internal debug message");

// This logger's level cannot be changed via ICP
```

### Java APIs

The following Java APIs are provided in `io.ballerina.stdlib.log.LogConfigManager` for ICP agent integration:

#### Get Current Configuration

```java
/**
 * Get the current log configuration.
 *
 * @return BMap containing:
 *   - "rootLevel": current root log level (String)
 *   - "modules": map of module name -> log level
 *   - "customLoggers": map of logger ID -> log level (only user-named loggers)
 */
public static BMap<BString, Object> getLogConfig();
```

#### Root Log Level Management

```java
/**
 * Get the current global root log level.
 *
 * @return the root log level as BString
 */
public static BString getGlobalLogLevel();

/**
 * Set the global root log level.
 *
 * @param level the new log level (DEBUG, INFO, WARN, ERROR)
 * @return null on success, BError on invalid level
 */
public static Object setGlobalLogLevel(BString level);
```

#### Module Log Level Management

```java
/**
 * Set or update a module's log level.
 *
 * @param moduleName the fully qualified module name (e.g., "myorg/mymodule")
 * @param level the new log level
 * @return null on success, BError on invalid level
 */
public static Object setModuleLevel(BString moduleName, BString level);

/**
 * Remove a module's log level configuration.
 * After removal, the module will use the root log level.
 *
 * @param moduleName the module name
 * @return true if removed, false if not found
 */
public static boolean removeModuleLevel(BString moduleName);
```

#### Custom Logger Management

```java
/**
 * Set a custom logger's log level.
 * Only works for loggers created with an explicit ID.
 *
 * @param loggerId the logger ID provided during creation
 * @param level the new log level
 * @return null on success, BError if logger not found or invalid level
 */
public static Object setLoggerLevel(BString loggerId, BString level);
```

### Configuration Response Structure

The `getLogConfig()` method returns a map with the following structure:

```json
{
  "rootLevel": "INFO",
  "modules": {
    "myorg/payment": "DEBUG",
    "myorg/notification": "WARN"
  },
  "customLoggers": {
    "payment-service": "INFO",
    "audit-logger": "DEBUG"
  }
}
```

Note: Only custom loggers created with an explicit `id` appear in the `customLoggers` map.

### Thread Safety

All runtime configuration changes are thread-safe:
- Root log level uses `AtomicReference<String>`
- Module log levels use `ConcurrentHashMap<String, String>`
- Custom logger levels use `ConcurrentHashMap<String, String>`

### Log Level Validation

All set operations validate the log level and return an error for invalid values:
- Valid levels: `DEBUG`, `INFO`, `WARN`, `ERROR`
- Level comparison is case-insensitive

### Capabilities Summary

**Can Do:**
- Adjust the global root logger's log level
- Add new module-level log configurations
- Update existing module-level log configurations
- Remove specific module-level log configurations
- Modify log levels for custom loggers created with an explicit `id` via `fromConfig` API

**Cannot Do:**
- Modify log levels for custom loggers created without an `id`
- Modify other logger configurations (format, destinations) at runtime
- Access or modify loggers created directly using the `Logger` interface (not via `fromConfig`)

## Future Considerations

- Support for modifying log format at runtime
- Support for adding/removing destinations at runtime
- Ballerina-level public APIs for runtime log modification (if needed beyond ICP)
