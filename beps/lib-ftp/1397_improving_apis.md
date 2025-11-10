# Enhanced Data Binding for File Retrieval and Upload

- Authors
  - Ravindu
- Reviewed by
    - TBD
- Created date
    - 2025-11-06
- Issue
    - [1397](https://github.com/ballerina-platform/ballerina-spec/issues/1397)
- State
    - Submitted

## Summary

The Ballerina FTP client already delivers the core primitives required for basic file transfer. However, common modern integration usage patterns frequently rely on a few essential file manipulation primitives that eliminate the need for custom orchestration logic. This proposal introduces such base-level convenience APIs (move, copy and existence checking) which are widely expected in integration runtimes.

## Goals

1. Introduce new key APIs that most File Integration Solutions offer in the world, however is not yet available directly in the Ballerina FTP Client.

## Non-Goals

1. This proposal does not aim to any changes to existing APIs. It will only add a few new APIs to the current stack.
2. More advanced file processing capabilities (such as compression/decompression, file pattern matching, file age filters, multi-file aggregation/splitting etc.) are explicitly out of scope here and will be handled as separate future proposals if needed.

## Motivation

This aims to improve the FTP Client of Ballerina, hence improving File Integration capabilities of BI, which would create more opportunities for marketing BI for advanced file related integrations

## Design

The proposed changes will introduce 3 new APIs, identified as essential to provide a minimal File Integration experience for the user.

### Proposed New APIs

1. **Move a File or Folder within the FTP Server**

    ```ballerina
    # Moves a file or folder to a new location within the same FTP server.
    #
    # + sourcePath - The path of the file or directory to move
    # + destinationPath - The new target path including the new name if renaming is required
    # + return - `()` or an `ftp:Error` if the move operation fails
    remote isolated function move(string sourcePath, string destinationPath) returns Error?;
    ```

2. **Copy a File or Folder within the FTP Server**

    ```ballerina
    # Copies a file or folder to a new location within the same FTP server.
    #
    # + sourcePath - The path of the file or directory to copy
    # + destinationPath - The target location where the copied content should be written
    # + return - `()` on success, or an `ftp:Error` on failure
    remote isolated function copy(string sourcePath, string destinationPath) returns Error?;
    ```

3. **Check if a specified File or Folder exists**

    ```ballerina
    # Checks whether a given file or directory exists on the FTP server.
    #
    # + path - The file or folder path to check for existence
    # + return - `true` if exists, `false` if does not exist, or an `ftp:Error` on failure
    remote isolated function checkExists(string path) returns boolean|Error;
    ```

### Examples

1. **Moving content**
    - Moving a file:
        ```ballerina
        check ftpClient->move("/input/data.csv", "/archive/data.csv");
        ```
    - Moving a directory:
        ```ballerina
        check ftpClient->move("/inbox/reports", "/processed/reports");
        ```
    - Moving and renaming in one go:
        ```ballerina
        check ftpClient->move("/input/data.csv", "/archive/data_2024_01.csv");
        ```

2. **Copying content**
    - Copying a file:
        ```ballerina
        check ftpClient->copy("/input/jan.csv", "/backup/jan.csv");
        ```
    - Copying a folder:
        ```ballerina
        check ftpClient->copy("/incoming/photos", "/backup/photos");
        ```
    - Copying while renaming:
        ```ballerina
        check ftpClient->copy("/input/report.pdf", "/backup/report_backup.pdf");
        ```

3. **Checking existence**
    - Simple existence check:
        ```ballerina
        boolean exists = check ftpClient->checkExists("/archive/data.csv");
        ```
    - Checking for a directory:
        ```ballerina
        boolean exists = check ftpClient->checkExists("/archive/reports/");
        ```
    - Conditional usage:
        ```ballerina
        if check ftpClient->checkExists("/archive/data.csv") {
            io:println("Exists!");
        } else {
            io:println("Does not exist!");
        }
        ```


### Compatibility and Migration

These new operations are additive. They do not modify any existing APIs or runtime behaviours.

1. Existing code using the current FTP client continues to function exactly as before.
2. These 3 new operations can simply be imported and used where required.
3. Return type patterns are aligned with current FTP API conventions (`Error?` / `boolean|Error`), so developers do not need to learn new error handling styles.


### Alternatives Considered

In certain cases, some degree of these operations can be technically simulated with existing functionality:

- A **move** can sometimes be achieved by a `rename()` call.
- A **copy** can be simulated by a `get()` + `put()` sequence in user code.
- A **check exists** can be approximated through `list()` and then checking returned values.

However, these are not ideal because:

1. they require more lines of user code,
2. they require manual orchestration / branching logic,
3. they introduce more network round trips and therefore more latency and more failure points, and
4. they reduce readability and maintainability of integration code.

Therefore, first-class explicit support for move / copy / checkExists provides significantly higher developer ergonomics, fewer opportunities for error, and a more idiomatic integration experience.


### Risks and Assumptions

1. Servers may impose restrictions on move or copy operations — these are surfaced as `ftp:Error` as per current error model.
2. These new APIs assume the existing connector layer is capable of supporting native FTP commands or equivalent behaviour for these operations.
3. Developers must still implement retry logic where required, as these operations do not implicitly implement retry semantics.
