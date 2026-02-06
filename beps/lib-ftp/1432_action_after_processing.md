# 1432: Action After Process/Error in FunctionConfig

- Authors - @niveathika
- Reviewed by - 
- Created date - 2026/02/02
- Updated date - 2026/02/02
- Issue - [#1432](https://github.com/ballerina-platform/ballerina-standard-library/issues/1432)
- State - Submitted

## Summary

Add support for automatic file actions (move/delete) after successful processing or error handling through the `ftp:FunctionConfig` annotation. This enables declarative file lifecycle management without manual caller operations.

## Motivation

Currently, users must manually call `caller->delete()` or `caller->move()` within their handler methods to manage file lifecycle. This leads to:

1. **Boilerplate code** - Every handler needs cleanup logic
2. **Error-prone** - Forgetting cleanup leaves files unprocessed repeatedly
3. **Inconsistent handling** - Different developers implement different patterns

A declarative approach via annotations simplifies common patterns like "process and delete" or "process and archive".

## Goals

- Allow users to specify automatic actions after successful file processing
- Allow users to specify automatic actions after file processing errors
- Support `move` and `delete` actions
- Maintain backward compatibility (no action if not specified)

## Non-Goals

- Complex workflows with multiple actions
- Conditional actions based on file content

## Design

### 1. New Types for Post-Processing Actions

In `annotations.bal`:

```ballerina
# Represents the delete action for file processing.
public const DELETE = "DELETE";

# Configuration for moving a file after processing.
#
# + moveTo - Destination directory path where the file will be moved
# + preserveSubDirs - If true, preserves the subdirectory structure relative to the
#                     listener's root path. Defaults to true.
public type Move record {|
    string moveTo;
    boolean preserveSubDirs = true;
|};

# Type alias for Move record, used in union types.
public type MOVE Move;
```

### 2. Updated `FtpFunctionConfig` Record

```ballerina
# Configuration for FTP service remote functions.
#
# + fileNamePattern - File name pattern (regex) that should be routed to this method
# + afterProcess - Action to perform after successful processing (DELETE or MOVE)
# + afterError - Action to perform after processing error (DELETE or MOVE)
public type FtpFunctionConfig record {|
    string fileNamePattern?;
    MOVE|DELETE afterProcess?;
    MOVE|DELETE afterError?;
|};
```

### 3. Behavior

**After Successful Processing:**
- If `afterProcess` is `DELETE`: Delete the file
- If `afterProcess` is `MOVE` record: Move the file to `moveTo` path
  - If `preserveSubDirs` is true (default): Preserves subdirectory structure
  - If `preserveSubDirs` is false: Moves file directly to the target directory
- If `afterProcess` is not specified: No action (file remains in place)

**After Error (when `onError` handles the error):**
- If `afterError` is `DELETE`: Delete the file
- If `afterError` is `MOVE` record: Move the file to `moveTo` path
- If `afterError` is not specified: No action (file remains in place)

**SubDirectory Preservation Example:**
If the listener monitors `/input/` and a file `/input/orders/2024/invoice.csv` is processed with `preserveSubDirs: true` and `moveTo: "/archive/"`, the file will be moved to `/archive/orders/2024/invoice.csv`.

### 4. Usage Examples

#### Example 1: Delete After Processing

```ballerina
service on ftpListener {
    @ftp:FunctionConfig {
        fileNamePattern: ".*\\.json",
        afterProcess: ftp:DELETE
    }
    remote function onFileJson(json content, ftp:FileInfo fileInfo) returns error? {
        // Process JSON - file is automatically deleted after successful return
        processJson(content);
    }
}
```

#### Example 2: Move to Archive After Processing

```ballerina
service on ftpListener {
    @ftp:FunctionConfig {
        fileNamePattern: ".*\\.csv",
        afterProcess: {
            moveTo: "/archive/processed/"
        }
    }
    remote function onFileCsv(Employee[] content, ftp:FileInfo fileInfo) returns error? {
        // Process CSV - file is moved to /archive/processed/ after success
        // Subdirectory structure is preserved by default
        saveEmployees(content);
    }
}
```

#### Example 3: Move Without Preserving Subdirectories

```ballerina
service on ftpListener {
    @ftp:FunctionConfig {
        fileNamePattern: ".*\\.csv",
        afterProcess: {
            moveTo: "/archive/flat/",
            preserveSubDirs: false
        }
    }
    remote function onFileCsv(Employee[] content, ftp:FileInfo fileInfo) returns error? {
        // Process CSV - all files moved directly to /archive/flat/
        // regardless of their original subdirectory
        saveEmployees(content);
    }
}
```

#### Example 4: Different Actions for Success and Error

```ballerina
service on ftpListener {
    @ftp:FunctionConfig {
        fileNamePattern: ".*\\.xml",
        afterProcess: {
            moveTo: "/archive/success/"
        },
        afterError: {
            moveTo: "/archive/failed/"
        }
    }
    remote function onFileXml(xml content, ftp:FileInfo fileInfo) returns error? {
        // Process XML
        // On success: moved to /archive/success/
        // On error (handled by onError): moved to /archive/failed/
        processXml(content);
    }

    remote function onError(ftp:ContentBindingError err, ftp:Caller caller) returns error? {
        log:printError("Processing failed", err);
        // File will be automatically moved to afterError path after this returns
    }
}
```

#### Example 5: Delete on Error Only

```ballerina
service on ftpListener {
    @ftp:FunctionConfig {
        afterError: ftp:DELETE
    }
    remote function onFileJson(json content, ftp:FileInfo fileInfo) returns error? {
        // If processing fails and onError handles it, file is deleted
        // If processing succeeds, file remains (no afterProcess specified)
    }
}
```

## Alternatives

- **Manual Handling**: Users continue to call delete/move explicitly in the function body. This was rejected due to the boilerplate and error-prone nature described in the Motivation.

## Testing

1. Test `DELETE` action after successful processing
2. Test `MOVE` action after successful processing with `preserveSubDirs: true` (default)
3. Test `MOVE` action after successful processing with `preserveSubDirs: false`
4. Test `DELETE` action after error
5. Test `MOVE` action after error
6. Test no action when not configured (default)
7. Test compiler validation for empty `moveTo` path
8. Test action execution order with multiple handlers
9. Test subdirectory preservation with nested directory structures

## Risks and Assumptions

- **Risk**: Moving files across different filesystems (if the FTP server mount points differ) might be slower or fail depending on server configuration.
- **Assumption**: The FTP user has permissions to perform the delete or move operations on the target paths.
- **Compatibility**: This design is backward compatible. Default behavior (when no action is specified) remains unchanged (NONE). Existing services continue to work without changes.

## Future Work

- Support for more complex post-processing actions (e.g., renaming with timestamp).
- Support for calling a separate cleanup function.
