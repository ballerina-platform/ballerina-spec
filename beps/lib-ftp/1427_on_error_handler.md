# 1427: Error Handler for FTP Listener

- Authors - @niveathika
- Reviewed by - 
- Created date - 2026/02/02
- Updated date - 2026/02/05
- Issue - [#1427](https://github.com/ballerina-platform/ballerina-standard-library/issues/1427)
- State - Draft

## Summary

Add an `onError` remote function to the FTP listener service that handles data binding errors occurring during file content conversion. This provides a centralized error handling mechanism for content-related failures.

## Motivation

Currently, when a file fails to bind to the expected type (e.g., invalid JSON, malformed CSV, XML parsing errors), the error is logged and the file is skipped. Users have no visibility or control over these failures. This leads to:

1. **Silent data loss** - Files that fail conversion are not processed and users are unaware
2. **No recovery mechanism** - Users cannot implement custom error handling logic (e.g., move to error folder, notify, retry with different type)
3. **Debugging difficulty** - Errors are only visible in logs, not programmatically accessible

## Goals

- Provide a dedicated error handler (`onError`) for data binding and content conversion failures
- Introduce `ContentBindingError` error type for data binding failures (applicable to both Client and Listener)
- Allow users to handle errors gracefully without losing file context
- Maintain consistency with other Ballerina connectors (e.g., Kafka module)

## Non-Goals

- Handling connection-level errors (these should be handled by retry mechanisms)
- Replacing existing error handling within content handler methods

## Design

### 1. New Error Type: `ContentBindingError`

A new error type will be introduced to represent data binding failures:

```ballerina
# Represents an error that occurs when file content cannot be converted to the expected type.
# This includes JSON/XML parsing errors, CSV format errors, and record type binding failures.
# This error type is applicable to both Client operations and Listener callbacks.
public type ContentBindingError distinct Error<ContentBindingErrorDetail>;

# Detail record for ContentBindingError providing additional context about the binding failure.
#
# + filePath - The file path that caused the error
# + content - The raw file content as bytes that failed to bind
public type ContentBindingErrorDetail record {|
    string filePath?;
    byte[] content?;
|};
```

### 2. New Remote Function: `onError`

The `onError` remote function will be invoked when a content binding error occurs during file processing:

```ballerina
# Called when an error occurs during file content binding.
#
# + err - The error that occurred during content binding (will be ContentBindingError for binding failures)
# + caller - FTP caller for performing recovery operations (optional)
# + return - Error to indicate handler failure, or nil on success
remote function onError(ftp:Error err, ftp:Caller caller) returns error? {
    // Handle the error - check error type and access details
    if err is ftp:ContentBindingError {
        string? filePath = err.detail().filePath;
        byte[]? content = err.detail().content;
        // Move to error folder, log, notify, etc.
    }
}
```

**Parameter Options:**
- `(ftp:Error)` - Error only (can also use `error` keyword)
- `(ftp:Error, ftp:Caller)` - Error with FTP caller for recovery operations

**Note:** The first parameter accepts the base `ftp:Error` type (or Ballerina's `error` keyword). Inside the handler, users should type-check for `ContentBindingError` to access the error detail record containing `filePath` and `content`.

### 3. Error Routing Behavior

When content binding fails:

1. If `onError` is defined in the service, invoke it with the error
2. If `onError` is NOT defined, log the error and continue processing other files (current behavior)
3. The original content handler (e.g., `onFileJson`) is NOT called for the failed file

### 4. Error Context

The `ContentBindingError` will include:
- **message**: Human-readable description of the binding failure
- **cause**: The underlying parsing/conversion error
- **detail**: File path and raw content bytes for recovery

## Usage Examples

### Example 1: Basic Error Handling

```ballerina
import ballerina/ftp;
import ballerina/log;

listener ftp:Listener ftpListener = check new ({
    host: "ftp.example.com",
    auth: {credentials: {username: "user", password: "pass"}},
    path: "/incoming"
});

service on ftpListener {
    remote function onFileJson(json content, ftp:FileInfo fileInfo) returns error? {
        // Process valid JSON files
        log:printInfo("Processing: " + fileInfo.name);
    }

    remote function onError(ftp:Error err, ftp:Caller caller) returns error? {
        // Check if it's a content binding error
        if err is ftp:ContentBindingError {
            string filePath = err.detail().filePath ?: "unknown";
            log:printError("Failed to process file: " + filePath, err);
            // Move to error folder
            check caller->move(filePath, "/error/failed_file");
        } else {
            log:printError("Unexpected error", err);
        }
    }
}
```

### Example 2: Error Handler with Raw Content Access

```ballerina
service on ftpListener {
    remote function onFileJson(MyRecord content, ftp:FileInfo fileInfo) returns error? {
        // Process type-bound content
    }

    remote function onError(ftp:Error err, ftp:Caller caller) returns error? {
        // Check if it's a content binding error to access raw content
        if err is ftp:ContentBindingError {
            byte[]? rawContent = err.detail().content;
            string? filePath = err.detail().filePath;

            if rawContent is byte[] {
                // Log raw content for debugging
                string contentStr = check string:fromBytes(rawContent);
                log:printError(string `Failed to bind content: ${contentStr.substring(0, 100)}...`);
            }

            if filePath is string {
                // Move to dead letter folder
                check caller->move(filePath, "/dead-letter/");
            }
        }
    }
}
```

### Example 3: Minimal Error Handler

```ballerina
service on ftpListener {
    @ftp:FunctionConfig {fileNamePattern: ".*\\.json"}
    remote function onFileJson(json content, ftp:FileInfo fileInfo) returns error? {
        // Process JSON files
    }

    remote function onError(ftp:Error err) returns error? {
        // Minimal error handling - just log
        log:printError("Content binding failed", err);
    }
}
```

## API Changes

### New Types in `error.bal`

```ballerina
# Represents an error that occurs when file content cannot be converted to the expected type.
# This includes JSON/XML parsing errors, CSV format errors, and record type binding failures.
# This error type is applicable to both Client operations and Listener callbacks.
public type ContentBindingError distinct Error<ContentBindingErrorDetail>;

# Detail record for ContentBindingError providing additional context.
public type ContentBindingErrorDetail record {|
    # The file path that caused the error
    string filePath?;
    # The raw file content as bytes that failed to bind
    byte[] content?;
|};
```

### Compiler Plugin Updates

Add validation for `onError` remote function:
- Must be a remote function
- First parameter must be an error type - either:
  - Ballerina's `error` type descriptor
  - `ftp:Error` (qualified reference to the FTP module's Error type)
- Optional second parameter: `ftp:Caller`
- Return type must be `error?`
- At most 2 parameters allowed

**Note:** The first parameter accepts the base error type to allow flexibility. Users should type-check for `ContentBindingError` inside the handler to access the detail record.

## Compatibility

- **Backward Compatible**: Services without `onError` will behave as before (log and skip)
- **New Services**: Can optionally implement `onError` for custom error handling

## References

- [Kafka Module onError Pattern](https://github.com/ballerina-platform/module-ballerinax-kafka)
- [Current FTP Listener Implementation](../spec/spec.md)
