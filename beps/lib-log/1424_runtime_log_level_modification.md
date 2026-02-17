# Runtime Log Level Modification Support for ballerina/log

- Authors
  - @daneshk
- Reviewed by
  - @sameerajayasoma, @shafreenAnfar, @manuranga, @anuruddhal, @TharmiganK
- Created date
  - 2026-02-03
- Last revised
  - 2026-02-13
- Issue
  - [1424](https://github.com/ballerina-platform/ballerina-spec/issues/1424)
- State
  - Submitted

## Summary

This proposal introduces Ballerina-level public APIs to modify log levels at runtime without application restart. The primary goal is to enable both developers (programmatic use) and the ICP (Integration Control Panel) agent to dynamically adjust log levels for the root logger, module-specific log levels, and loggers created via the `fromConfig` API. Additionally, a logger registry is introduced to provide visibility into all registered loggers and their current log levels.

## Goals

- Provide Ballerina-level public APIs (`setLevel`, `getLevel`) on the `Logger` interface for runtime log level modification.
- Provide a `LoggerRegistry` class with `getDetails()`, `getById()`, and `setLevel()` APIs for discovering and managing registered loggers.
- Track logger kind (`root`, `module`, `custom`, `child`) in the registry for runtime differentiation of logger behaviour.
- Enable runtime modification of the global root log level.
- Allow modification of log levels for all loggers — root logger, module loggers, loggers created via `fromConfig`, and child loggers created via `withContext`.
- Treat each configured module as a separate logger in the unified logger registry, using the module name as the logger ID.
- Auto-generate readable identifiers for loggers when no explicit ID is provided.
- Ensure thread-safe operations for concurrent log level modifications.

## Non-Goals

- Dynamic log level changes for custom loggers (created by implementing the `Logger` interface from scratch) are not supported in the initial phase. A plan to support this will be designed in the future.
- This proposal does not support modifying other logger configurations (format, destinations) at runtime.

## Motivation

In production environments, the ability to change log levels dynamically is crucial for debugging and monitoring without requiring application restarts. Currently, the only way to change log levels in Ballerina applications is through the `Config.toml` file, which requires an application restart to take effect.

The ICP (Integrated Control Panel) dashboard needs to provide operators with the ability to:
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
| Enumerate all loggers | Java `getLoggerNames()`, Logback `getLoggerList()` | `LoggerRegistry.getDetails()` |
| Lookup by ID | Java/Logback `getLogger(name)`, Python `getLogger(name)` | `LoggerRegistry.getById(id)` |
| Runtime level change | Java/Python `setLevel()` | `Logger.setLevel(level)` / `LoggerRegistry.setLevel(id, level)` |
| Get effective level | Java/Python `getEffectiveLevel()` | `Logger.getLevel()` (returns effective level) |
| Reset to parent level | Java `setLevel(null)`, Python `setLevel(NOTSET)` | Deferred to future phase |
| Independent child logger levels | Java/Python hierarchical model | `setLevel()` on child loggers |
| Logger kind tracking | Java logger hierarchy types | `LoggerInfo.kind` (`root` / `module` / `custom` / `child`) |

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
    # This sets an explicit level override on this logger, independent of its parent.
    # + level - the new log level to set
    public isolated function setLevel(Level level);

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

All loggers created via `fromConfig` are registered in the logger registry and are identifiable. An optional `id` field is added to the `Config` record. If the user provides an `id`, it is used as-is. If not provided, the log module auto-generates a readable identifier using the **module name + caller function name + counter** pattern.

#### Config Record

```ballerina
public type Config record {|
    # Optional unique identifier for this logger. If provided, this ID is used to identify
    # the logger in the logger registry and ICP dashboard.
    # If not provided, a readable identifier is auto-generated using the pattern:
    # <module>:<function>-<counter> (e.g., "myorg/payment:processOrder-1").
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

- **Format**: `<module>:<functionName>-<counter>`
- **Examples**:
  - `myorg/payment:processOrder-1`
  - `myorg/payment:init-1`
  - `myorg/payment:init-2` (second logger created in the same function)

The counter ensures uniqueness when multiple loggers are created in the same function. Stack frame inspection is performed only once at logger creation time, so there is no runtime performance impact on logging operations.

#### Usage Examples

**Logger with explicit ID:**
```ballerina
// Create a logger with an explicit ID - clearly identifiable in ICP dashboard
log:Logger paymentLogger = check log:fromConfig(id = "payment-service", level = log:INFO);
paymentLogger.printInfo("Processing payment");

// Programmatically change log level
paymentLogger.setLevel(log:DEBUG);

// ICP agent can also change this logger's level using the ID "payment-service"
```

**Logger with auto-generated ID:**
```ballerina
// Create a logger without explicit ID - auto-generated ID (e.g., "myorg/payment:init-1")
log:Logger internalLogger = check log:fromConfig(level = log:DEBUG);
internalLogger.printDebug("Internal debug message");

// This logger is still visible in ICP and its level can be changed via the auto-generated ID
```

### Logger Registry

The log module maintains an internal logger registry that tracks all registered loggers. Access to the registry is provided via the `LoggerRegistry` class, obtained by calling `getLoggerRegistry()`. The registry groups all discovery and management operations in one place, avoiding standalone function proliferation and making it easy to extend in the future.

The registry tracks:

- Module loggers (each configured module is registered using the module name as its logger ID)
- All loggers created via `fromConfig` (with explicit or auto-generated IDs)
- All child loggers created via `withContext`

Each registry entry includes a `kind` field (`"root"`, `"module"`, `"custom"`, or `"child"`) that enables runtime differentiation of logger behaviour. This is important because:

- **Root logger** (`kind: "root"`): The global root logger, registered with the well-known ID `"root"`. Changing its level affects all module-level `log:printInfo(...)` calls that don't have a module-specific level.
- **Module loggers** (`kind: "module"`): Changing their level affects ALL `log:printInfo(...)` calls in that module.
- **Custom loggers** (`kind: "custom"`): Created via `fromConfig()`. Changing their level only affects log statements made through that logger instance and its children.
- **Child loggers** (`kind: "child"`): Inherit their parent's level by default; can be overridden independently via `setLevel()`.

Note: Loggers implemented from scratch by implementing the `Logger` interface are referred to as **external loggers**. They are not tracked by the LoggerRegistry in the initial phase.

```ballerina
# The kind of a registered logger, used for runtime differentiation of logger behaviour.
public type LoggerKind "root"|"module"|"custom"|"child";

# Represents information about a registered logger (JSON-serializable).
public type LoggerInfo readonly & record {|
    # The current log level
    Level level;
    # The kind of the logger
    LoggerKind kind;
|};

# Provides access to the logger registry for discovering and managing registered loggers.
public isolated class LoggerRegistry {

    # Returns a JSON-friendly map of all registered loggers.
    # The map key is the logger ID (user-provided or auto-generated),
    # and the value contains the current log level and kind.
    # + return - a map of logger ID to LoggerInfo
    public isolated function getDetails() returns map<LoggerInfo>;

    # Returns a specific logger instance by its ID.
    # + id - the logger identifier (user-provided or auto-generated)
    # + return - the Logger instance if found, or nil if no logger with the given ID exists
    public isolated function getById(string id) returns Logger?;

    # Sets the log level for a registered logger by its ID.
    # + id - the logger ID
    # + level - the new log level
    # + return - an error if the logger is not found
    public isolated function setLevel(string id, Level level) returns error?;
}

# Returns the logger registry for discovering and managing registered loggers.
# + return - the LoggerRegistry instance
public isolated function getLoggerRegistry() returns LoggerRegistry;
```

#### Usage Examples

**ICP usage — list all loggers as JSON:**
```ballerina
import ballerina/log;

// Get the registry
log:LoggerRegistry registry = log:getLoggerRegistry();

// ICP retrieves the JSON-friendly map to render in the web editor
map<log:LoggerInfo> loggers = registry.getDetails();
// Result (JSON-serializable):
// {
//     "myorg/payment": { "level": "DEBUG", "kind": "module" },
//     "payment-service": { "level": "INFO", "kind": "custom" },
//     "myorg/myapp:main-1": { "level": "INFO", "kind": "child" }
// }
```

**Developer usage — get a logger instance and change its level:**
```ballerina
import ballerina/log;

public function main() returns error? {
    log:Logger logger1 = check log:fromConfig(id = "payment-service", level = log:INFO);
    log:Logger logger2 = check log:fromConfig(level = log:DEBUG);

    log:LoggerRegistry registry = log:getLoggerRegistry();

    // Look up a logger by ID and change its level
    log:Logger? logger = registry.getById("payment-service");
    if logger is log:Logger {
        logger.setLevel(log:DEBUG);
        log:Level level = logger.getLevel(); // DEBUG
    }

    // Or change level directly via the registry using the logger ID
    check registry.setLevel("payment-service", log:ERROR);
}
```

**ICP usage — change a specific logger's level:**
```ballerina
// ICP changes a logger's level by ID through the registry
log:LoggerRegistry registry = log:getLoggerRegistry();
check registry.setLevel("payment-service", log:DEBUG);
```

### Module Loggers

Each module configured in `Config.toml` is automatically registered as a separate logger in the unified logger registry. The module name is used as the logger ID (e.g., `myorg/payment`). Module loggers are children of the root logger and participate in the same registry as `fromConfig` and `withContext` loggers.

This unified approach means:

- Module log levels can be modified at runtime using the same `setLevel()` / `getLevel()` APIs.
- Module loggers appear in `registry.getDetails()` alongside all other loggers with `kind: "module"`, giving ICP a single, consistent view.
- `registry.getById("myorg/payment")` returns the module's `Logger` instance for programmatic control.
- `registry.setLevel("myorg/payment", log:ERROR)` changes the module's level by ID.
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
    paymentLogger.setLevel(log:ERROR);  // Change at runtime
}

// Or change level directly via registry
check registry.setLevel("myorg/payment", log:DEBUG);

// getDetails() shows module loggers with kind: "module"
map<log:LoggerInfo> loggers = registry.getDetails();
// {
//     "myorg/payment": { "level": "DEBUG", "kind": "module" },
//     "myorg/inventory": { "level": "WARN", "kind": "module" },
//     "payment-service": { "level": "INFO", "kind": "custom" }
// }
```

**ID collision protection:** If a user calls `fromConfig(id = "myorg/payment")` using a name that matches a configured module, the existing duplicate-ID check returns an error, preventing collisions.

### Child Loggers

Child loggers can be created from the root logger or from loggers created using `fromConfig` using the `withContext` method.

Child loggers inherit their log level from their parent logger by default, but support independent level overrides:

- By default, a child logger inherits its level from the parent. When the parent's level changes, the child's effective level changes too.
- A child logger can have its own explicit level set via `setLevel()`, which overrides the inherited level.
- Once a child has an explicit level, parent changes no longer affect it.
- Child loggers are registered in the logger registry with auto-generated IDs and `kind: "child"`, so they are discoverable and modifiable via ICP.

```ballerina
// Root logger is initialized automatically from Config.toml (e.g., INFO)

// Create a logger via fromConfig — this is a child of the root logger
log:Logger paymentLogger = check log:fromConfig(id = "payment-service", level = log:INFO);

// Create child loggers with additional context
log:Logger orderLogger = check paymentLogger.withContext(component = "order-handler");
log:Logger refundLogger = check paymentLogger.withContext(component = "refund-handler");

// All three loggers use INFO level initially
paymentLogger.printInfo("Payment processed");
orderLogger.printInfo("Order created");
refundLogger.printInfo("Refund initiated");

// Change parent level — affects child loggers that haven't set their own level
paymentLogger.setLevel(log:DEBUG);
orderLogger.getLevel();   // DEBUG (inherited from parent)
refundLogger.getLevel();  // DEBUG (inherited from parent)

// Set an independent level on a child logger
orderLogger.setLevel(log:ERROR);
orderLogger.getLevel();   // ERROR (explicit override)
refundLogger.getLevel();  // DEBUG (still inherited from parent)

// Parent changes no longer affect orderLogger (has explicit level)
paymentLogger.setLevel(log:WARN);
orderLogger.getLevel();   // ERROR (still explicit)
refundLogger.getLevel();  // WARN (inherited from parent)
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

The only breaking change is for developers who have implemented the `Logger` interface from scratch — they must add `getLevel` and `setLevel` method implementations.

### Thread Safety

All runtime configuration changes are thread-safe. The internal logger registry and level modifications use Ballerina's `isolated` guarantees to ensure safe concurrent access.

### Log Level Validation

All set operations validate the log level and return an error for invalid values:
- Valid levels: `DEBUG`, `INFO`, `WARN`, `ERROR`
- Level comparison is case-insensitive

### Capabilities Summary

**Can Do:**
- Retrieve and set log levels programmatically via `getLevel()` / `setLevel()` on any logger instance
- Set independent level overrides on child loggers
- Adjust the global root logger's log level
- Discover and manage all registered loggers via `LoggerRegistry` (`getDetails()`, `getById()`, `setLevel()`)
- Differentiate logger behaviour at runtime via `kind` (`root`, `module`, `custom`, `child`) in `LoggerInfo`
- Modify log levels for module loggers (configured in `Config.toml`) via ICP, using the module name as the logger ID
- Modify log levels for all loggers created via `fromConfig` API (with explicit or auto-generated IDs) via ICP
- Modify log levels for child loggers created via `withContext` via ICP

**Cannot Do (Initial Phase):**
- Reset a child logger's level to inherit from its parent (`resetLevel`) — deferred to future phase along with parent-child tree tracking in the registry
- Modify log levels dynamically for custom loggers created by implementing the `Logger` interface from scratch (future enhancement)
- Modify other logger configurations (format, destinations) at runtime

## Future Considerations

- Add `resetLevel(string id)` to `LoggerRegistry` — requires parent-child tree tracking in the registry. This will allow resetting a child logger's level to inherit from its parent, similar to Java's `setLevel(null)` and Python's `setLevel(NOTSET)`.
- Support dynamic log level changes for custom loggers (created by implementing the `Logger` interface from scratch).
- Support for modifying log format at runtime.
- Support for adding/removing destinations at runtime.
