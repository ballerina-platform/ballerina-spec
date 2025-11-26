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

The `FailSafeOptions` record includes an `outputMode` field that specifies how error logs should be output.

```ballerina
# Represents the options for fail-safe mechanism during parsing.
public type FailSafeOptions record {|
    # Specifies the output mode for logging errors encountered during parsing
    ConsoleOutputMode|FileOutputMode outputMode = {};
|};
```

The `failSafe` configuration supports two distinct output modes for error reporting: the console output mode and the file output mode.

### Console output mode

In console output mode, any errors encountered during parsing are displayed directly in the console. This option is to allow users to review parsing issues as they are detected.

```ballerina
# Represents the console output mode for logging errors.
public type ConsoleOutputMode record {|
    # Specifies enabling logging errors to the console
    boolean excludeSourceData = true;
|};
```

When `excludeSourceData` is set to `true`, the error log must not include the source data row that caused the error. When set to `false`, the source data row also will be included in the error output.

### File output mode

In file output mode, error details encountered during CSV parsing are written as structured logs to a user-specified file path. This allows users to persist error diagnostics for review, independent of the console output.

```ballerina
# Represents the file output mode for logging errors.
public type FileOutputMode record {|
    # Specifies whether to enable logging errors to the console in addition to the file
    boolean enableConsoleLogs = false;
    # The file path where errors will be logged
    string filePath;
    # Controls the level of detail included in the error logs.
    ErrorLogContentType contentType = METADATA;
    # Configuration for writing to the log file
    FileWriteOption fileWriteOption = APPEND;
|};
```

When `enableConsoleLogs` is set to `true`, errors will be logged to both the specified file and the console. When set to `false`, errors will only be written to the specified file.

### Error log content type

The `csv:ErrorLogContentType` enumeration determines the type and amount of information included in error logs.

**Fields:**

- `csv:METADATA`: The implementation will log only error metadata including timestamp, location, and error message. The source data row will not be included. This will be the default behaviour.

- `csv:RAW`: The implementation will log the offending source data row along with the error message. Additional metadata will be excluded.

- `csv:RAW_AND_METADATA`: The implementation will log both the complete source data row and all error metadata.

### File write option

The `csv:FileWriteOption` enumeration defines the file write behaviour. It specifies how error logs are persisted to the log file during CSV parsing. Users can choose whether new logs should be appended to an existing file or if the file should be overwritten at the start of processing.

- `csv:APPEND`: New error log entries will be appended to the existing file content. If the file does not exist, new file will be created. This will be the default behaviour.

- `csv:OVERWRITE`: The file will be truncated and overwritten at the start of each parsing operation. Any existing content will be discarded in the file.

### Error log format

Error log entries provide users with rich context to understand and address CSV parsing issues efficiently. The output format and information included in each log are governed by the configured output mode and content type.

#### Console log format

Console error logs use the standard Ballerina logging output format as defined by the `ballerina/log` module. If `excludeSourceData` is set to `false`, the log entry will  include the `offendingRow` field to present the problematic input data for context.

#### File log format

File error logs SHALL be written as newline-delimited JSON objects. Each error log entry MUST be a valid JSON object with the following schema:

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `time` | string | Yes | Timestamp when the error was encountered, formatted according to ISO 8601. |
| `location` | object | Yes | Object specifying the exact position of the error within the CSV file. |
| &nbsp;&nbsp;&nbsp;&nbsp;`row` | int | Yes | One-indexed row number where the error occurred, as per implementation convention. |
| &nbsp;&nbsp;&nbsp;&nbsp;`column` | int | Yes | One-indexed column number where the error occurred, as per implementation convention. |
| `message` | string | Yes | Human-readable description of the error. |
| `offendingRow` | string | Conditional | The complete row data from the CSV file that caused the error. This field will be included when `contentType` is set to `csv:RAW` or `csv:RAW_AND_METADATA`. |
