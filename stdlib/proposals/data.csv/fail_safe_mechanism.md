# Fail-safe support in the CSV data module

- Authors
  - @Nuvindu
- Reviewed by
    - 
- Created date
    - 2025-11-18
- Issue
    - [8465](https://github.com/ballerina-platform/ballerina-library/issues/8465)
- State
    - Pending

## Summary

This proposal introduces an optional fail-safe parsing mode for the Ballerina CSV Data module. Currently, the module uses a fail-fast approach where any parsing error terminates the entire operation. The fail-safe mode will allow the parser to skip problematic rows, log detailed diagnostics, and continue processing and returning all successfully parsed records.

## Goals

- Introduce the fail-safe mechanism for CSV parsing operations
- Provide detailed row-level diagnostics including error messages, row indices, and column information
- Support both fail-fast and fail-safe parsing modes with a configurable option to switch

## Motivation

The current fail-fast behavior presents several limitations in real-world scenarios. When processing large files with many rows, a single malformed row causes the entire operation to fail, discarding all previously parsed valid data. Users often need to extract as much valid data as possible from imperfect sources such as legacy systems, manual exports, or third-party data feeds where complete data accuracy cannot be guaranteed. Additionally, fail-safe mode improves debugging efficiency by identifying all parsing issues in a single pass rather than forcing developers to discover and fix errors iteratively through repeated processing attempts.

## Description

To support the fail-safe mode while supporting fail-fast decided to add a new field `failSafe` is introduced in the `csv:Options` record to enable a fail-safe mechanism in CSV parsing APIs.

To support both fail-fast and fail-safe behaviours, a new field `failSafe` is added to the `csv:Options` record.

```ballerina
public type Options record {
    .
    .
    .
    # Specifies whether to enable the fail-safe mechanism during parsing.
    # When `true`, rows with parsing errors are skipped and logged.
    # When `false`, the parser fails fast and returns an error at the first failure.
    boolean failSafe = true;
};
```

By default, it supports the fail-safe mode and users can explicitly enable fail-fast mode by setting `failSafe: false` in the `csv:Options` passed to parsing APIs.

This support is available in the following APIs. It can be enabled/disabled by changing the `failSafe` config from the `options` field.

```ballerina
// Parse from string
Data[] recordFromString = check csv:parseString(csvString, options = {failSafe: true});

// Parse from byte array
Data[] recordFromBytes = check csv:parseBytes(csvBytes, {failSafe: true});

// Parse from stream
Data[] recordsFromStream = check csv:parseStream(csvStream, {failSafe: true});

// Parse from list
Data[] recordsFromList = check csv:parseList(csvList, {failSafe: true});
```

When enabled, errors encountered during the parsing of individual rows are not returned to the caller. Instead, they are logged with detailed diagnostics. Each log entry includes the source line number, the column index, and a specific error message describing the parsing or type conversion failure.

```sh
time=2025-11-18T14:24:07.011+05:30 level=ERROR module=ballerina/data.csv message="CSV parse error at line 7, column 2: value \'invalid\' cannot be cast into \'boolean\'"
time=2025-11-18T14:24:07.036+05:30 level=ERROR module=ballerina/data.csv message="CSV parse error at line 10, column 7: invalid number of headers"
```

By providing a fail-safe mechanism to handle CSV data without disrupting the parsing process, the CSV Data module becomes more robust and developer-friendly. This enhancement directly supports scenarios where completeness of extracted data and comprehensive diagnostics are more valuable than strict parsing guarantees.
