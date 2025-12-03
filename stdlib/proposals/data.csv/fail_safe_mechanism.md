# Fail-safe Support in the CSV Data Module

- Authors
  - @Nuvindu
- Reviewed by
  - TBD
- Created date
  - 2025-11-18
- Updated date
  - 2025-11-26
- Issue
  - [#8465](https://github.com/ballerina-platform/ballerina-library/issues/8465)
- State
  - Pending

## Summary

This proposal introduces an optional fail-safe parsing mode for the Ballerina CSV Data module. Currently, the module uses a fail-fast approach where any parsing error terminates the entire operation. The fail-safe mode will allow the parser to skip problematic rows, log detailed diagnostics, and continue processing and returning all successfully parsed records.

## Goals

- Introduce the fail-safe mechanism for CSV parsing operations.
- Provide detailed row-level diagnostics including error messages, row indices, and column information.
- Support both fail-fast and fail-safe parsing modes with a configurable option to switch.

## Motivation

The current fail-fast behaviour presents several limitations in real-world scenarios. When processing large files with many rows, a single malformed row causes the entire operation to fail, discarding all previously parsed valid data. Users often need to extract as much valid data as possible from imperfect sources such as legacy systems, manual exports, or third-party data feeds where complete data accuracy cannot be guaranteed. Additionally, fail-safe mode improves debugging efficiency by identifying all parsing issues in a single pass rather than forcing developers to discover and fix errors iteratively through repeated processing attempts.

## Description

The proposed fail-safe mechanism operates by attempting to parse each row of a CSV file independently rather than terminating at the first encountered error. When fail-safe mode is enabled, the parser records any row that fails to parse—together with diagnostic information including the row number, error message, and optionally the source data itself using the user-specified output mode. Valid rows continue to be parsed and accumulated into the final result set.

The fail-safe mechanism will be available in the following parsing functions.

- `parseString()`
- `parseBytes()`
- `parseStream()`
- `parseList()`

In above APIs there is a parameter as `csv:Options` and the new fail-safe configurations will be added to the `Options` record as an optional field. The parser will operate in fail-fast mode by default, and will switch to fail-safe mode when the `failSafe` field is configured.

```ballerina
public type Options record {
    .
    .
    .
    # Specifies the fail-safe options for handling errors during processing
    FailSafeOptions failSafe?;
};
```

The `FailSafeOptions` record provides configuration for the fail-safe mechanism, including console logging and file output configurations.

```ballerina
# Represents the options for fail-safe mechanism during parsing.
public type FailSafeOptions record {|
    # Specifies enabling logging errors to the console
    boolean enableConsoleLogs = true;
    # Excludes logging source data to the console
    boolean excludeSourceDataInConsole = true;
    # Specifies the output mode for logging errors encountered during parsing
    FileOutputMode fileOutputMode?;
|};
```

### Console logging

When `enableConsoleLogs` is set to `true` (default), errors encountered during parsing are displayed in the console. The `excludeSourceDataInConsole` flag controls whether the source data row is included in the console output. When set to `true` (default), the error log will not include the source data row that caused the error. When set to `false`, the source data row will be included in the error output.

### File output mode

In file output mode, error details encountered during CSV parsing are written as structured logs to a user-specified file path. This allows users to persist error diagnostics for review. This is an optional configuration in `FailSafeOptions`.

```ballerina
# Represents the file output mode for logging errors.
public type FileOutputMode record {|
    # The file path where errors will be logged
    string filePath;
    # Controls the level of detail included in the error logs.
    ErrorLogContentType contentType = METADATA;
    # Configuration for writing to the log file
    FileWriteOption fileWriteOption = APPEND;
|};
```

### Error log content type

The `csv:ErrorLogContentType` enumeration determines the type and amount of information included in error logs when writing to a file.

```ballerina
# Represents the content type for error logging.
public enum ErrorLogContentType {
    # Logs only the metadata (timestamp, location, message) without source data rows
    METADATA,
    # Logs the source data rows along with error messages
    RAW,
    # Logs both source data rows and metadata along with error messages
    RAW_AND_METADATA
};
```

**Values:**

- `csv:METADATA`: The implementation will log only error metadata including timestamp, location, and error message. The source data row will not be included. This will be the default behaviour.

- `csv:RAW`: The implementation will log the offending source data row along with the error message. Additional metadata will be excluded.

- `csv:RAW_AND_METADATA`: The implementation will log both the complete source data row and all error metadata.

### File write option

The `csv:FileWriteOption` enumeration defines the file write behaviour. It specifies how error logs are persisted to the log file during CSV parsing. Users can choose whether new logs should be appended to an existing file or if the file should be overwritten at the start of processing.

```ballerina
# Represents the options for writing data.
public enum FileWriteOption {
    # If the file already exists, new logs will be appended to the existing file
    APPEND,
    # When the error logging starts, if the file already exists, the file will be overwritten
    OVERWRITE
};
```

**Values:**

- `csv:APPEND`: New error log entries will be appended to the existing file content. If the file does not exist, new file will be created. This will be the default behaviour.

- `csv:OVERWRITE`: The file will be truncated and overwritten at the start of each parsing operation. Any existing content will be discarded in the file.

### Error log format

Error log entries provide users with rich context to understand and address CSV parsing issues efficiently. The output format and information included in each log are governed by the configured output mode and content type.

#### Console log format

Console error logs use the standard Ballerina logging output format as defined by the `ballerina/log` module. If `excludeSourceDataInConsole` is set to `false`, the log entry will include the offending row to present the problematic input data for context.

#### File log format

File error logs SHALL be written as newline-delimited JSON objects. Each error log entry MUST be a valid JSON object conforming to the `LogOutput` record type:

```ballerina
# Represents an error log entry.
public type LogOutput record {|
    # The timestamp of the error occurrence
    string time?;
    # The location where the error occurred
    Location location?;
    # The error message
    string message?;
    # The source data row related to the error
    string offendingRow?;
|};

# Represents the location of an error.
public type Location record {|
    # The row number where the error occurred
    int row;
    # The column number where the error occurred
    int column;
|};
```

**Field descriptions:**

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `time` | string | Yes | Timestamp when the error was encountered, formatted according to ISO 8601. |
| `location` | object | Yes | Object specifying the exact position of the error within the CSV file. |
| &nbsp;&nbsp;&nbsp;&nbsp;`row` | int | Yes | One-indexed row number where the error occurred, as per implementation convention. |
| &nbsp;&nbsp;&nbsp;&nbsp;`column` | int | Yes | One-indexed column number where the error occurred, as per implementation convention. |
| `message` | string | Yes | Human-readable description of the error. |
| `offendingRow` | string | Conditional | The complete row data from the CSV file that caused the error. This field will be included when `contentType` is set to `csv:RAW` or `csv:RAW_AND_METADATA`. |
