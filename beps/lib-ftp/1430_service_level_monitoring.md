# 1430: Service Level Monitoring

  - Authors - @niveathika  
  - Reviewed by -   
  - Created date - 2026/02/05  
  - Updated date - 2026/02/06  
  - [1374](https://github.com/ballerina-platform/ballerina-spec/issues/1374)  
  - State - Submitted

## Summary

Currently, the FTP listener's monitoring configuration (`path`, `fileNamePattern`, `fileAgeFilter`, `fileDependencyConditions`) is specified at the listener level in `ListenerConfiguration`. This limits flexibility when multiple services are attached to a single listener, as all services share the same monitoring path and file patterns.

This proposal introduces a new service-level annotation `@ftp:ServiceConfig` to allow each service to define its own monitoring configuration. The existing listener-level fields will be deprecated but maintained for backward compatibility.

## Motivation

### Current Limitation

Currently, the monitoring path and file patterns are configured at the listener level:

```ballerina
listener ftp:Listener ftpListener = check new({
    host: "ftp.example.com",
    path: "/home/incoming",           // Single path for ALL services
    fileNamePattern: ".*\\.csv",      // Single pattern for ALL services
    fileDependencyConditions: [...]   // Single dependency config for ALL services
});

// All services attached to this listener share the same path and patterns
service on ftpListener {
    remote function onFileCsv(record {}[] content) { /* handles /home/incoming/*.csv */ }
}

service on ftpListener {
    remote function onFileJson(json content) { /* also handles /home/incoming - cannot have different path */ }
}
```

### Proposed Solution

With service-level configuration, each service can have its own monitoring path:

```ballerina
listener ftp:Listener ftpListener = check new({
    host: "ftp.example.com"
    // No path/pattern at listener level when using service-level config
});

@ftp:ServiceConfig {
    path: "/home/incoming/csv",
    fileNamePattern: ".*\\.csv"
}
service on ftpListener {
    remote function onFileCsv(record {}[] content) { /* handles /home/incoming/csv/*.csv */ }
}

@ftp:ServiceConfig {
    path: "/home/incoming/json",
    fileNamePattern: ".*\\.json"
}
service on ftpListener {
    remote function onFileJson(json content) { /* handles /home/incoming/json/*.json */ }
}
```

## Goals

- Introduce a new `@ftp:ServiceConfig` annotation for service-level monitoring configuration
- Deprecate `path`, `fileNamePattern`, `fileAgeFilter`, and `fileDependencyConditions` fields in `ListenerConfiguration`
- Enable multiple services on a single listener to monitor different paths/patterns independently
- Maintain full backward compatibility with existing code
- Provide clear runtime validation rules and error messages

## Non-Goals

- Removing the deprecated listener-level fields (these will remain for backward compatibility)
- Changing the behavior of existing applications that don't use the new annotation

## Design

### New Annotation: `@ftp:ServiceConfig`

A new service-level annotation will be introduced:

```ballerina
# Configuration for FTP service monitoring.
# Use this to specify the directory path and file patterns this service should monitor.
#
# + path - Directory path on the FTP server to monitor for file changes
# + fileNamePattern - File name pattern (regex) to filter which files trigger events
# + fileAgeFilter - Configuration for filtering files based on age (optional)
# + fileDependencyConditions - Array of dependency conditions for conditional file processing
public type ServiceConfiguration record {|
    string path;
    string fileNamePattern?;
    FileAgeFilter fileAgeFilter?;
    FileDependencyCondition[] fileDependencyConditions = [];
|};

# Annotation to configure FTP service monitoring path and file patterns.
public annotation ServiceConfiguration ServiceConfig on service;
```

### Deprecated Fields in `ListenerConfiguration`

The following fields will be marked as deprecated:

```ballerina
public type ListenerConfiguration record {|
    Protocol protocol = FTP;
    string host = "127.0.0.1";
    int port = 21;
    AuthConfiguration auth?;

    # Deprecated: Use @ftp:ServiceConfig annotation on service instead.
    # This field will be ignored if any attached service has @ftp:ServiceConfig.
    @deprecated
    string path = "/";

    # Deprecated: Use @ftp:ServiceConfig annotation on service instead.
    # This field will be ignored if any attached service has @ftp:ServiceConfig.
    @deprecated
    string fileNamePattern?;

    # Deprecated: Use @ftp:ServiceConfig annotation on service instead.
    # This field will be ignored if any attached service has @ftp:ServiceConfig.
    @deprecated
    FileAgeFilter fileAgeFilter?;

    # Deprecated: Use @ftp:ServiceConfig annotation on service instead.
    # This field will be ignored if any attached service has @ftp:ServiceConfig.
    @deprecated
    FileDependencyCondition[] fileDependencyConditions = [];

    // ... other fields remain unchanged
    decimal pollingInterval = 60;
    boolean userDirIsRoot = false;
    boolean laxDataBinding = false;
    decimal connectTimeout = 30.0;
    SocketConfig socketConfig?;
    ProxyConfiguration proxy?;
    FileTransferMode fileTransferMode = BINARY;
    TransferCompression[] sftpCompression = [NO];
    string sftpSshKnownHosts?;
    FailSafeOptions csvFailSafe?;
    CoordinationConfig coordination?;
|};
```

### Runtime Validation Rules

The following validation rules will be enforced at service attachment time:

1. **Consistency Rule**: If ANY service attached to a listener uses `@ftp:ServiceConfig`, then ALL services attached to that listener MUST use `@ftp:ServiceConfig`.

2. **Mutual Exclusion**: When `@ftp:ServiceConfig` is used on any service:
   - The listener-level `path`, `fileNamePattern`, `fileAgeFilter`, and `fileDependencyConditions` will be completely ignored
   - A deprecation warning will be logged if these fields were explicitly set in listener config

3. **Backward Compatibility**: If NO service uses `@ftp:ServiceConfig`:
   - The listener-level configuration will be used as before
   - Existing applications continue to work without modification

4. **Required Field**: The `path` field is mandatory in `@ftp:ServiceConfig` (no default value)

### Validation Error Messages

| Scenario | Error Code | Message |
|----------|------------|---------|
| Mixed usage (some services with annotation, some without) | FTP_140 | "All services attached to a listener must use @ftp:ServiceConfig annotation when any service uses it. Service '{serviceName}' is missing the annotation." |
| Invalid path pattern | FTP_142 | "Invalid path '{path}' in @ftp:ServiceConfig. Path must be an absolute path starting with '/'." |
| Invalid fileNamePattern regex | FTP_143 | "Invalid regex pattern '{pattern}' in @ftp:ServiceConfig.fileNamePattern: {error}" |

## Examples

### Example 1: Multiple Services Monitoring Different Directories

```ballerina
import ballerina/ftp;
import ballerina/log;

listener ftp:Listener ftpListener = check new({
    protocol: ftp:SFTP,
    host: "ftp.example.com",
    port: 22,
    auth: {
        credentials: {username: "user", password: "pass"}
    },
    pollingInterval: 30
});

// Service for CSV files in /incoming/data
@ftp:ServiceConfig {
    path: "/incoming/data",
    fileNamePattern: ".*\\.csv"
}
service on ftpListener {
    remote function onFileCsv(record {}[] content, ftp:FileInfo fileInfo, ftp:Caller caller) returns error? {
        log:printInfo("Processing CSV from /incoming/data: " + fileInfo.name);
        // Process CSV data
        check caller->move(fileInfo.path, "/processed/data/" + fileInfo.name);
    }
}

// Service for JSON config files in /incoming/config
@ftp:ServiceConfig {
    path: "/incoming/config",
    fileNamePattern: ".*\\.json"
}
service on ftpListener {
    remote function onFileJson(json content, ftp:FileInfo fileInfo, ftp:Caller caller) returns error? {
        log:printInfo("Processing JSON config from /incoming/config: " + fileInfo.name);
        // Process JSON config
        check caller->move(fileInfo.path, "/processed/config/" + fileInfo.name);
    }
}
```

### Example 2: Service with File Dependencies

```ballerina
@ftp:ServiceConfig {
    path: "/incoming/orders",
    fileNamePattern: "order_.*\\.csv",
    fileDependencyConditions: [
        {
            targetPattern: "order_(\\d+)\\.csv",
            requiredFiles: ["order_$1.marker"],
            matchingMode: ALL
        }
    ]
}
service on ftpListener {
    remote function onFileCsv(record {}[] content, ftp:FileInfo fileInfo) returns error? {
        // This is only triggered when both order_XXX.csv and order_XXX.marker exist
        log:printInfo("Processing order file with marker: " + fileInfo.name);
    }
}
```

### Example 3: Backward Compatible Usage (No Annotation)

Existing code continues to work without modification:

```ballerina
// Old style - still works, but deprecated
listener ftp:Listener ftpListener = check new({
    host: "ftp.example.com",
    path: "/incoming",                    // Deprecated but functional
    fileNamePattern: ".*\\.txt"           // Deprecated but functional
});

service on ftpListener {
    remote function onFileText(string content, ftp:FileInfo fileInfo) returns error? {
        // Works as before
    }
}
```

### Example 4: Invalid - Mixed Usage (Compile/Runtime Error)

```ballerina
listener ftp:Listener ftpListener = check new({
    host: "ftp.example.com"
});

@ftp:ServiceConfig {
    path: "/incoming/csv"
}
service on ftpListener {
    remote function onFileCsv(record {}[] content) { }
}

// ERROR: All services must use @ftp:ServiceConfig when any service uses it
service on ftpListener {
    remote function onFileJson(json content) { }  // Missing @ftp:ServiceConfig
}
```

## Alternatives

### Alternative 1: Service Name as Path

Use the service name/path as the monitoring directory:

```ballerina
service "/incoming/csv" on ftpListener { }
```

**Rejected because:**
- Conflates service identity with file system path
- Less explicit about the monitoring configuration
- Doesn't support `fileNamePattern` or `fileDependencyConditions`

## Testing

- Verify backward compatibility: listener-level `path` and `fileNamePattern` still work when no service has `@ftp:ServiceConfig`.
- Verify service-level configuration: multiple services on the same listener can monitor different paths and patterns.
- Verify validation: mixed usage (some services with annotation, some without) fails with the specified error.
- Verify deprecation warnings: setting deprecated listener fields while any service has `@ftp:ServiceConfig` logs a warning.
- Verify regex and path validation: invalid `fileNamePattern` or non-absolute `path` raises the correct error.

## Migration Path

### For Existing Users

1. **No immediate action required**: Existing code will continue to work with deprecation warnings
2. **Gradual migration**: Users can migrate to `@ftp:ServiceConfig` at their own pace
3. **Future release**: The deprecated fields may be removed in a future major version

### Migration Steps

1. Add `@ftp:ServiceConfig` annotation to all services attached to a listener
2. Move `path`, `fileNamePattern`, `fileAgeFilter`, and `fileDependencyConditions` from listener config to service annotation
3. Remove the deprecated fields from listener configuration

**Before:**
```ballerina
listener ftp:Listener ftpListener = check new({
    host: "ftp.example.com",
    path: "/incoming",
    fileNamePattern: ".*\\.csv"
});

service on ftpListener {
    remote function onFileCsv(record {}[] content) { }
}
```

**After:**
```ballerina
listener ftp:Listener ftpListener = check new({
    host: "ftp.example.com"
});

@ftp:ServiceConfig {
    path: "/incoming",
    fileNamePattern: ".*\\.csv"
}
service on ftpListener {
    remote function onFileCsv(record {}[] content) { }
}
```

