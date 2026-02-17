# Runtime Log Level Modification Support for ballerina/log

- Authors
  - @daneshk
- Reviewed by
  - @sameerajayasoma, @shafreenAnfar, @manuranga, @anuruddhal, @TharmiganK
- Created date
  - 2026-02-03
- Last revised
  - 2026-02-17
- Issue
  - [1424](https://github.com/ballerina-platform/ballerina-spec/issues/1424)
- State
  - Submitted

## Summary

This proposal introduces Ballerina-level public APIs to modify log levels at runtime without application restart. The primary goal is to enable both developers (programmatic use) and the ICP (Integration Control Panel) agent to dynamically adjust log levels for the root logger, module-specific log levels, and loggers created via the `fromConfig` API. Additionally, a logger registry is introduced to provide visibility into all registered loggers and their current log levels.

## Goals

- Provide Ballerina-level public APIs (`setLevel`, `getLevel`) on the `Logger` interface for runtime log level modification.
- Provide a `LoggerRegistry` class with `getIds()` and `getById()` APIs for discovering registered loggers.
- Enable runtime modification of the global root log level.
- Allow modification of log levels for root logger, module loggers, and loggers created via `fromConfig`.
- Child loggers (created via `withContext`) inherit their level from the parent and cannot have independent levels — `setLevel()` returns an unsupported operation error.
- Child loggers are not registered in the registry.
- Module-prefix user-provided logger IDs: `<org>/<module>:<user_id>`.
- Treat each configured module as a separate logger in the unified logger registry, using the module name as the logger ID.
- Auto-generate readable identifiers for loggers when no explicit ID is provided.
- Ensure thread-safe operations for concurrent log level modifications.

## Non-Goals

- Dynamic log level changes for custom loggers (created by implementing the `Logger` interface from scratch) are not supported in the initial phase. A plan to support this will be designed in the future.
- This proposal does not support modifying other logger configurations (format, destinations) at runtime.

## Motivation

In production environments, the ability to change log levels dynamically is crucial for debugging and monitoring without requiring application restarts. Currently, the only way to change log levels in Ballerina applications is through the `Config.toml` file, which requires an application restart to take effect.

The ICP (Integration Control Panel) dashboard needs to provide operators with the ability to:
1. View the current logging configuration of running applications.
2. Increase log verbosity (e.g., switch to DEBUG) when investigating issues.
3. Reduce log verbosity (e.g., switch to ERROR) to reduce noise and storage costs.
4. Configure logging differently for specific modules without affecting others.

Beyond ICP, developers also need the ability to change log levels programmatically for use cases such as:
- Adjusting log verbosity based on application state or external signals.
- Building custom admin endpoints or control mechanisms.

This capability is essential for:
- **Production debugging**: Temporarily enable DEBUG logging to diagnose issues without restarting the application.
- **Performance optimization**: Reduce logging overhead by increasing log levels during high-load periods.
- **Compliance**: Enable detailed audit logging on demand for compliance investigations.

## Logger Registry in Other Languages

The following comparison of logger registry support across popular logging libraries informed the design decisions in this proposal.

| Feature | Java (JUL / Logback) | Python (`logging`) | Go (`slog` / `zap`) | .NET (`Microsoft.Extensions.Logging`) | Rust (`log` / `tracing`) |
|---|---|---|---|---|---|
| **Auto-registration** | Yes | Yes | No registry | Yes (get-or-create) | N/A (single global) |
| **Enumerate all loggers** | `getLoggerNames()` / `getLoggerList()` | `manager.loggerDict` | Not supported | Not exposed publicly | N/A |
| **Lookup by name** | `getLogger(name)` / `exists(name)` | `getLogger(name)` | Not supported | `CreateLogger(name)` | N/A |
| **Runtime level change** | `setLevel()` | `setLevel()` | `LevelVar.Set()` / `AtomicLevel.SetLevel()` | Config reload | `set_max_level()` (global only) |
| **Hierarchical loggers** | Yes (dot-separated) | Yes (dot-separated) | No | Partial (filter rules) | No |
| **Reset to parent level** | `setLevel(null)` | `setLevel(NOTSET)` | N/A | Remove filter rule + reload | N/A |
| **Attach handlers at runtime** | `addHandler()` / `removeHandler()` | `addHandler()` / `removeHandler()` | No | `AddProvider()` (no remove) | No |
| **Level change callbacks** | `LoggerContextListener` (Logback) | No | No | `IOptionsMonitor.OnChange()` | No |

### Key Observations

- **Java and Python have the richest registry models** — true named-logger registries with hierarchical inheritance, enumeration, lookup, and the ability to reset a logger to inherit from its parent via `setLevel(null)` / `setLevel(NOTSET)`.
- **Go has no logger registry** — loggers are values passed around explicitly. Dynamic levels are handled via atomic variables (`LevelVar`, `AtomicLevel`). Zap's `AtomicLevel` also serves as an `http.Handler` for operational tooling.
- **.NET is configuration-driven** — the logger cache is internal and not exposed. Level changes flow through the options/configuration system with file-watcher-based reload.
- **Rust is intentionally minimal** — one global logger, one global level. The `tracing` crate adds composable layers with a `reload` module for swapping filters at runtime, but has no named-logger registry.
- **Only Java and Python support "reset to parent level"** — this proposal defers `resetLevel()` to a future phase to avoid burdening custom logger implementors with parent-child semantics they may not have.

### Features Adopted in This Proposal

Based on this analysis, the following features are included in this proposal:

| Feature | Inspiration | Ballerina API |
|---|---|---|
| Enumerate all loggers | Java `getLoggerNames()`, Logback `getLoggerList()` | `LoggerRegistry.getIds()` |
| Lookup by ID | Java/Logback `getLogger(name)`, Python `getLogger(name)` | `LoggerRegistry.getById(id)` |
| Runtime level change | Java/Python `setLevel()` | `Logger.setLevel(level)` (returns `error?`) |
| Get effective level | Java/Python `getEffectiveLevel()` | `Logger.getLevel()` (returns effective level) |
| Reset to parent level | Java `setLevel(null)`, Python `setLevel(NOTSET)` | Deferred to future phase |

## Design

### Changes to the `Logger` Interface

The `Logger` object type is extended with two new methods: `getLevel` and `setLevel`. This is a **breaking change** for developers who have implemented custom loggers from scratch by implementing the `Logger` interface. However, this does not affect the most common use cases — root loggers and child loggers — which will continue to work without any changes.

Note: `resetLevel()` is intentionally **not** included on the `Logger` interface. Custom logger implementors may not have a parent-child concept, so `resetLevel()` would be confusing and have no meaningful implementation. The `resetLevel` capability is deferred to a future phase and will be added to the `LoggerRegistry` class, where it can operate on internally managed loggers that have parent-child relationships.

```ballerina
# Logger object type defines an interface for logging messages
public type Logger isolated object {

    # Get the effective log level of this logger.
    # If this logger has an explicitly set level, returns that level.
    # If not, returns the inherited level from the parent logger.
    # + return - the effective log level
    public isolated function getLevel() returns Level;

    # Set the log level of this logger at runtime.
    # Returns an error if the operation is not supported (e.g., on child loggers).
    # + level - the new log level to set
    # + return - an error if the operation is not supported, nil on success
    public isolated function setLevel(Level level) returns error?;

    # Existing methods (unchanged)
    public isolated function printDebug(string|PrintableRawTemplate msg, error? 'error = (), error:StackFrame[]? stackTrace = (), *KeyValues keyValues);

    public isolated function printInfo(string|PrintableRawTemplate msg, error? 'error = (), error:StackFrame[]? stackTrace = (), *KeyValues keyValues);

    public isolated function printWarn(string|PrintableRawTemplate msg, error? 'error = (), error:StackFrame[]? stackTrace = (), *KeyValues keyValues);

    public isolated function printError(string|PrintableRawTemplate msg, error? 'error = (), error:StackFrame[]? stackTrace = (), *KeyValues keyValues);

    public isolated function withContext(*KeyValues keyValues) returns Logger|error;
};
```

#### Breaking Change Impact

| Logger Type | Impact |
|---|---|
| Root logger (`log:printInfo(...)`) | No change |
| Child loggers (via `withContext`) | No change |
| Loggers from `fromConfig` | No change (implementation updated internally) |
| Custom loggers (implementing `Logger` interface from scratch) | **Breaking** — must add `getLevel` and `setLevel` implementations |

This breaking change is intentional and accepted by the design review. It is better to introduce it now while the custom logger adoption is low.

### Logger Identification

All loggers created via `fromConfig` are registered in the logger registry and are identifiable. An optional `id` field is added to the `Config` record. If the user provides an `id`, it is module-prefixed to produce a fully qualified ID of the form `<org>/<module>:<user_id>`. If no `id` is provided, the log module auto-generates a readable identifier using the **module name + caller function name** pattern (with a counter suffix only for subsequent loggers in the same function).

#### Config Record

```ballerina
public type Config record {|
    # Optional unique identifier for this logger. If provided, this ID is module-prefixed
    # to produce a fully qualified ID: <org>/<module>:<user_id> (e.g., "myorg/payment:payment-service").
    # If not provided, a readable identifier is auto-generated using the pattern:
    # <module>:<function> for the first logger, <module>:<function>-<counter> for subsequent ones.
    string id?;
    LogFormat format = format;
    Level level = level;
    readonly & OutputDestination[] destinations = destinations;
    readonly & AnydataKeyValues keyValues = {...keyValues};
    boolean enableSensitiveDataMasking = enableSensitiveDataMasking;
|};
```

#### Auto-Generated Identifier

When no `id` is provided, the log module generates a readable identifier by inspecting the caller's stack frame at logger creation time:

- **Format**: `<module>:<functionName>` for the first logger in a function, `<module>:<functionName>-<counter>` for subsequent ones
- **Examples**:
  - `myorg/payment:processOrder` (first logger in `processOrder`)
  - `myorg/payment:processOrder-2` (second logger in `processOrder`)
  - `myorg/payment:init` (first logger in `init`)

The counter suffix is only added for the second and subsequent loggers in the same function, keeping IDs clean. Stack frame inspection is performed only once at logger creation time, so there is no runtime performance impact on logging operations.

#### Usage Examples

**Logger with explicit ID:**
```ballerina
// Create a logger with an explicit ID - module-prefixed in the registry
// Registered as "myorg/payment:payment-service" (assuming called from myorg/payment module)
log:Logger paymentLogger = check log:fromConfig(id = "payment-service", level = log:INFO);
paymentLogger.printInfo("Processing payment");

// Programmatically change log level
check paymentLogger.setLevel(log:DEBUG);

// ICP agent can also change this logger's level using the full ID "myorg/payment:payment-service"
```

**Logger with auto-generated ID:**
```ballerina
// Create a logger without explicit ID - auto-generated ID (e.g., "myorg/payment:init")
log:Logger internalLogger = check log:fromConfig(level = log:DEBUG);
internalLogger.printDebug("Internal debug message");

// This logger is still visible in ICP and its level can be changed via the auto-generated ID
```

### Logger Registry

The log module maintains an internal logger registry that tracks all registered loggers. Access to the registry is provided via the `LoggerRegistry` class, obtained by calling `getLoggerRegistry()`. The registry groups all discovery and management operations in one place, avoiding standalone function proliferation and making it easy to extend in the future.

The registry tracks:

- The root logger (registered with the well-known ID `"root"`)
- Module loggers (each configured module is registered using the module name as its logger ID)
- All loggers created via `fromConfig` (with module-prefixed or auto-generated IDs)

Child loggers (created via `withContext`) are **not** registered in the registry. They always inherit their level from the parent logger and cannot have independent levels. The ID format is sufficient to differentiate logger types — no separate `LoggerKind` type is needed.

Note: Loggers implemented from scratch by implementing the `Logger` interface are referred to as **external loggers**. They are not tracked by the LoggerRegistry in the initial phase.

```ballerina
# Provides access to the logger registry for discovering and managing registered loggers.
public isolated class LoggerRegistry {

    # Returns the IDs of all registered loggers.
    # + return - an array of logger IDs
    public isolated function getIds() returns string[];

    # Returns a specific logger instance by its ID.
    # + id - the logger identifier (user-provided or auto-generated)
    # + return - the Logger instance if found, or nil if no logger with the given ID exists
    public isolated function getById(string id) returns Logger?;
}

# Returns the logger registry for discovering and managing registered loggers.
# + return - the LoggerRegistry instance
public isolated function getLoggerRegistry() returns LoggerRegistry;
```

#### Usage Examples

**ICP usage — list all loggers:**
```ballerina
import ballerina/log;

// Get the registry
log:LoggerRegistry registry = log:getLoggerRegistry();

// ICP retrieves all logger IDs
string[] ids = registry.getIds();
// Result: ["root", "myorg/payment", "myorg/payment:payment-service", "myorg/payment:init"]
```

**Developer usage — get a logger instance and change its level:**
```ballerina
import ballerina/log;

public function main() returns error? {
    log:Logger logger1 = check log:fromConfig(id = "payment-service", level = log:INFO);
    // Registered as "myorg/myapp:payment-service" (module-prefixed)

    log:LoggerRegistry registry = log:getLoggerRegistry();

    // Look up a logger by ID and change its level
    log:Logger? logger = registry.getById("myorg/myapp:payment-service");
    if logger is log:Logger {
        check logger.setLevel(log:DEBUG);
        log:Level level = logger.getLevel(); // DEBUG
    }
}
```

### Module Loggers

Each module configured in `Config.toml` is automatically registered as a separate logger in the unified logger registry. The module name is used as the logger ID (e.g., `myorg/payment`). Module loggers participate in the same registry as `fromConfig` loggers.

This unified approach means:

- Module log levels can be modified at runtime using the same `setLevel()` / `getLevel()` APIs.
- Module loggers appear in `registry.getIds()` alongside all other loggers, giving ICP a single, consistent view.
- `registry.getById("myorg/payment")` returns the module's `Logger` instance for programmatic control.
- There is no separate module-level configuration path — everything flows through the unified logger registry.

**Config.toml:**
```toml
[ballerina.log]
level = "INFO"

[[ballerina.log.modules]]
name = "myorg/payment"
level = "DEBUG"

[[ballerina.log.modules]]
name = "myorg/inventory"
level = "WARN"
```

**Runtime modification:**
```ballerina
import ballerina/log;

log:LoggerRegistry registry = log:getLoggerRegistry();

// Module loggers are automatically registered — look them up by module name
log:Logger? paymentLogger = registry.getById("myorg/payment");
if paymentLogger is log:Logger {
    check paymentLogger.setLevel(log:ERROR);  // Change at runtime
}

// getIds() lists all registered loggers
string[] ids = registry.getIds();
// ["root", "myorg/payment", "myorg/inventory", "myorg/payment:payment-service"]
```

**ID collision protection:** If a user calls `fromConfig(id = "myorg/payment")` using a name that matches a configured module, the existing duplicate-ID check returns an error, preventing collisions.

### Child Loggers

Child loggers can be created from the root logger or from loggers created using `fromConfig` using the `withContext` method.

Child loggers always inherit their log level from the parent logger:

- A child logger's `getLevel()` always delegates to the parent's `getLevel()`. When the parent's level changes, the child's effective level changes too.
- Calling `setLevel()` on a child logger returns an unsupported operation error. To change a child logger's effective level, change the parent's level instead.
- Child loggers are **not** registered in the logger registry.
- Child loggers can be chained (grandchild loggers) — each delegates `getLevel()` up the chain.

```ballerina
// Create a logger via fromConfig
log:Logger paymentLogger = check log:fromConfig(id = "payment-service", level = log:INFO);

// Create child loggers with additional context
log:Logger orderLogger = check paymentLogger.withContext(component = "order-handler");
log:Logger refundLogger = check paymentLogger.withContext(component = "refund-handler");

// All three loggers use INFO level initially
paymentLogger.printInfo("Payment processed");
orderLogger.printInfo("Order created");
refundLogger.printInfo("Refund initiated");

// Change parent level — all child loggers follow
check paymentLogger.setLevel(log:DEBUG);
orderLogger.getLevel();   // DEBUG (inherited from parent)
refundLogger.getLevel();  // DEBUG (inherited from parent)

// Attempting to set level on a child returns an error
error? result = orderLogger.setLevel(log:ERROR);
// result is error("Unsupported operation: cannot set log level on a child logger...")
```

### Backward Compatibility

This proposal maintains backward compatibility for the most common use cases. All existing root logger and child logger usage continues to work unchanged:

```ballerina
// Existing usage - unchanged
log:printInfo("Hello World!");

// Existing custom logger - unchanged
log:Logger myLogger = check log:fromConfig(level = log:DEBUG);
myLogger.printInfo("Custom logger message");
```

The only breaking change is for developers who have implemented the `Logger` interface from scratch — they must add `getLevel` and `setLevel` method implementations. Note that `setLevel` returns `error?` to allow child loggers to return an unsupported operation error.

### Thread Safety

All runtime configuration changes are thread-safe. The internal logger registry and level modifications use Ballerina's `isolated` guarantees to ensure safe concurrent access.

### Log Level Validation

All set operations validate the log level and return an error for invalid values:
- Valid levels: `DEBUG`, `INFO`, `WARN`, `ERROR`
- Level comparison is case-insensitive

### Capabilities Summary

**Can Do:**
- Retrieve and set log levels programmatically via `getLevel()` / `setLevel()` on root loggers, module loggers, and `fromConfig` loggers
- Adjust the global root logger's log level
- Discover all registered loggers via `LoggerRegistry` (`getIds()`, `getById()`)
- Modify log levels for module loggers (configured in `Config.toml`) via ICP, using the module name as the logger ID
- Modify log levels for all loggers created via `fromConfig` API (with module-prefixed or auto-generated IDs) via ICP
- Child loggers automatically inherit level changes from their parent

**Cannot Do (Initial Phase):**
- Set independent log levels on child loggers — `setLevel()` returns an unsupported operation error
- Modify log levels dynamically for custom loggers created by implementing the `Logger` interface from scratch (future enhancement)
- Modify other logger configurations (format, destinations) at runtime

## Future Considerations

- Add `resetLevel(string id)` to `LoggerRegistry` — requires parent-child tree tracking in the registry. This will allow resetting a child logger's level to inherit from its parent, similar to Java's `setLevel(null)` and Python's `setLevel(NOTSET)`.
- Support dynamic log level changes for custom loggers (created by implementing the `Logger` interface from scratch).
- Support for modifying log format at runtime.
- Support for adding/removing destinations at runtime.
