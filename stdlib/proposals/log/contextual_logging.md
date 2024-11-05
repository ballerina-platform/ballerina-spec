# Contextual logging support for ballerina/log
- Authors
  - Sameera Jayasoma
- Reviewed by
    - TBD
- Created date
    - 2021-11-04
- Issue
    - [1321](https://github.com/ballerina-platform/ballerina-spec/issues/1321)
- State
    - Submitted

## Summary 
This proposal introduces contextual logging support in the `ballerina/log` package. The primary goal is to enable persistent key/value metadata across logs within a defined scope to allow developers to add contexts, such as correlation IDs and environment-specific information automatically to every log entry. 

Additionally, this proposal makes loggers explicit constructs in the API, allowing developers to create custom loggers with unique configurations, such as different log levels, formats, or destinations for specialized needs like audits or metrics.

Please add any comments to issue [#1321](https://github.com/ballerina-platform/ballerina-spec/issues/1321
).

## Goals,
- Provide fine-grained control over logging configurations. 
- Support contextual logging by enabling persistent key/value metadata across logs within a given scope to reduce redundancy.
- Maintain backward compatibility with the current ballerina/log API.

## Motivation 
Logging is a fundamental aspect of observability. Logs allow developers to analyze the behavior of programs and are often the first place to look at when the program is not behaving correctly. 

The `ballerina/log` package, released three years ago, offers a simple set of utilities for logging. The top-level functions in the log package allow structured and leveled logging. Based on user feedback and recent feature requests, we learned that contextual logging with the ability to pass down the logging context as key/value pairs and the fine-grained controller over how the logging format, logging level, and destinations are important to Ballerina programmers working on real-world integrations and applications. 

Some applications require the separation of distinct logs, such as audits and metrics, from general application logs. Audit logs track critical security and compliance events. Metrics logs capture performance and usage metrics. Application logs are well, application logs. The ability to control the log level, destination, and format for each log kind is a critical requirement.

Typically, a set of logs is associated with a single request in any request-driven application, and you often want to add contextual information such as request details, correlation ID, or transaction ID to all such logs. They are critical for debugging, but the current `ballerina/log` library requires repeating them in every log entry. Our goal here is to simplify this by allowing you to persist the logging context, such that all logs related to a request contain required key/value pairs. 

Also, the `ballerina/log` library is one of the most used packages in the Ballerina standard library. We don’t want to segment the ecosystem by introducing a new library or major version of the current log library. Our aim is to introduce the above features as backward-compatible improvements as much as possible. 

## Design 
Backward compatibility is the key. The following usages should work regardless of any improvements proposed in this document. 

```ballerina
log:printInfo("Hello World!");
```

```shell
time=2024-11-04T12:29:03.542-08:00 level=INFO module=ballerina/log message="Hello World!"
```

### Default log context and destinations
This proposal introduces two new configurable variables to specify the default log context as key-value pairs and log destinations.

```ballerina
// Existing configurable variables
configurable LogFormat format = "logfmt";
configurable LogLevel level = "INFO";

// Proposed variables
# Default key-values to add to the root logger.
configurable KeyValues keyValues = {};

# destinations is a list of file paths to which the logs should be written.
# stderr and stdout are supported as special destinations.
configurable string[] destinations = ["stderr"];
``` 

The default context will be added to every log. Here is a sample configuration. 

```toml
[ballerina.log]
level = "INFO"
format = "logfmt"
destinations = ["stderr", "./logs/app.log"]
keyValues = {env = "prod", nodeId = "delivery-svc-001"}
```

The current ‘ballerina/log’ module has an implicit root logger, which we configure using the above configurable variables. Conceptually, functions such as `log:printInfo()` use the root logger underneath the log. The following section describes a way to make loggers explicit in the API. 

### Loggers
Loggers are a fundamental concept in almost every log library on this planet. Loggers define the front end of a log library that developers interact with. This proposal makes Loggers an explicit construct in the `ballerina/log` module by allowing developers to create new loggers, child loggers from a parent, etc.  

A logger can be configured with a format, a level, a list of destinations, and a default context, enabling developers to isolate general application logs from other special loggers such as audits and metrics. 

The following object type defines the Logger. All print* function signatures are the same as the top-level print* functions in the current log module. 

```ballerina
public type Logger isolated object {
   // Matches with existing top-level functions.
   public isolated function printDebug(string msg, ...);
   public isolated function printInfo(string msg, ...);
   public isolated function printWarn(string msg, ...);
   public isolated function printError(string msg, ...);

   // Creates a new child/derived logger with the given key-values.
   public isolated function withContext(*KeyValues keyValues) returns Logger;
};
```

#### Root logger 
The root logger is created automatically when the Ballerina program starts and is always present. It can be configured via configurable variables defined in the `ballerina/log` module. Since it’s the ancestor of all other loggers, any configurable applied to the root logger can affect all child loggers unless they are specifically overridden.

The following proposed function allows you to access the root logger instance. 

```ballerina
public isolated function root() returns Logger {
}
``` 

#### Child loggers 
This proposal describes two ways to create child loggers: 
The everyday use case is to create a child logger with just additional context (key-value pairs). 
Some applications require loggers with unique logging configurations. For example, audit logs might need a different format or a destination.

Thia approach lets developers choose between context-enhanced child loggers and loggers with custom configurations for distinct logging needs. 

#### Loggers with additional context
This approach is ideal for passing a logger with added context specific to a task or request. These loggers inherit configurations from the parent loggers, allowing you to conveniently create a logger hierarchy. 

```ballerina
log:Logger rootLogger = log:root();
...	
log:Logger logger1 = rootLogger.withContext(correlationId = "value1");
logger1.printInfo("Hello World!");
...
log:Logger logger2 = logger1.withContext(workerId = "value2");
logger2.printInfo("Hello World!");
```

#### Loggers with new configurations 
Creating a logger from the root with different configurations provides flexibility for specific requirements. E.g., audit loggers and metrics loggers. 

All these loggers inherit the initial context provided via the configurable variable `ballerina.log.keyValues`.  This proposal does not allow loggers to discard the initial context. The assumption is that the environment defines the initial context, and all logs must contain the initial context. 

```ballerina
// The default values of these fields use already defined configurable variables in the log module.
public type Config record {
   LogFormat format = format;
   LogLevel level = level;
   string[] destinations = destinations;
   KeyValues keyValues = {};
};

# Creates a new logger with the given configuration.
public isolated function fromConfig(Config config) returns Logger {
}
```

Here is a sample usage of this API:

```ballerina
   log:Config auditLogConfig = {
       level: log:INFO,
       format: "json",
       destinations: ["./logs/audit.log"]
   };

   log:Logger auditLogger = log:fromConfig(auditLogConfig);
   auditLogger.printInfo("Hello World from the audit logger!");

```

### Deprecate `setOutputFile` function
This proposal recommends to deprecate the current `setOutputFile` function. This function allows developers to configure the root logger destination programmatically. 

However, programmatically configuring the destination does not make sense; destinations should be configured when creating the logger. 

```ballerina
public isolated function setOutputFile(string path, FileWriteOption option = APPEND) returns Error?;

```
