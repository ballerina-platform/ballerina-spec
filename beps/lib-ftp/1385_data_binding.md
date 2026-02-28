# Enhanced Data Binding for File Retrieval and Upload

- Authors
  - Niveathika
- Reviewed by
    - TBD
- Created date
    - 2025-09-30
- Issue
    - [1385](https://github.com/ballerina-platform/ballerina-spec/issues/1385)
- State
    - Submitted

## Summary

The current implementation of the `get()` method in the Ballerina FTP client allows fetching and uploading file contents only as streams of bytes. This proposal suggests introducing a set of new APIs to support direct data binding to common data formats such as text, JSON, XML, byte arrays and CSV, reducing the need for manual conversions and stream handling.

## Goals

1. Introduce new APIs to support direct data binding, allowing it to return and upload file contents directly as text, JSON, XML, byte arrays, CSV, and streams.
2. Introduce new APIs that support direct data binding from and to Ballerina record types.

## Non-Goals

1. This proposal does not aim to remove the existing `get()` and `put()` methods that return and upload file contents as streams of bytes. The existing methods will remain for backward compatibility and, expected to be removed in a future release.

## Motivation

Currently, fetching, converting, and uploading file contents using the FTP connector involves multiple steps and explicit stream handling, which can be cumbersome. By enabling direct data binding through specific APIs, we aim to provide a more streamlined and efficient way to handle file contents.

## Design

The proposed changes will introduce new methods in the FTP connector, each tailored to fetch and bind file contents to specific data types directly. Similarly, new methods for uploading contents directly as various data types will be introduced.

### Proposed New APIs to replace `get()` method

1. **Fetch content as plain text**

    ```ballerina
    # Fetches file content from the FTP server as plain text.
    # + path - The path to the file on the FTP server
    # + return - The file content as a string or, an `ftp:Error`
    remote isolated function getText(string path) returns string|Error;
    ```

2. **Fetch content as JSON**

    ```ballerina
    # Fetches file content from the FTP server as JSON.
    # + path - The path to the file on the FTP server
    # + targetType - The type descriptor for the expected return type. Supported types are `json` and Ballerina record types (e.g., `typedesc<Person>`).
    # + return - The file content as the specified type or, an `ftp:Error`
    # + example - `ftpClient->getJson("/path/to/file.json", typedesc<Person>)`
    remote isolated function getJson(string path, typedesc<json|record{}> targetType) returns targetType|Error;
    ```

3. **Fetch content as XML**

    ```ballerina
    # Fetches file content from the FTP server as XML.
    # + path - The path to the file on the FTP server
    # + return - The file content as XML or, an `ftp:Error`
    remote isolated function getXml(string path, typedesc<xml|record{}> targetType) returns targetType|Error;
    ```

4. **Fetch content as a byte array**

    ```ballerina
    # Fetches file content from the FTP server as a byte array.
    # + path - The path to the file on the FTP server
    # + return - The file content as a byte array or, an `ftp:Error`
    remote isolated function getBytes(string path) returns byte[]|Error;
    ```

5. **Fetch content as CSV**

    ```ballerina
    # Fetches file content from the FTP server as CSV.
    # + path - The path to the file on the FTP server
    # + targetType - The target type for binding CSV rows, either `string[]` for raw CSV rows or a Ballerina record type for structured mapping.
    # + return - The file content as an array of `string[]` (for raw CSV) or an array of Ballerina records (for structured mapping), or an `ftp:Error`
    remote isolated function getCsv(string path, typedesc<string[]|record{}> targetType) returns targetType[]|Error;
    ```

6. **Fetch content as a stream of byte arrays**

    ```ballerina
    # Fetches file content from the FTP server as a stream of byte arrays.
    # + path - The path to the file on the FTP server
    # + blockSize - size of a single block to be fetched
    # + return - The file content as a stream of byte arrays or, an `ftp:Error`
    remote isolated function getBytesAsStream(string path, int blockSize) returns stream<readonly & byte[], Error?>|Error;
    ```

7. **Fetch content as a CSV stream**

    ```ballerina
    # Fetches file content from the FTP server as a stream of CSV entries(i.e., rows).
    # + path - The path to the file on the FTP server
    # + return - The file content as a stream of string arrays or, an `ftp:Error`
    remote isolated function getCsvAsStream(string path, typedesc<string[]|record{}> targetType) returns stream<targetType, Error?>|Error;
    ```


### Proposed New APIs to replace `put()` method

1. **Upload content as text**

    ```ballerina
    # Uploads file content to the FTP server directly as plain text.
    # + path - The path to the file on the FTP server
    # + content - The file content as a string
    # + return - An `ftp:Error` if an error occurs, otherwise nil
    remote isolated function putText(string path, string content, FileWriteOption option) returns Error?;
    ```
 
2. **Upload content as JSON or Ballerina record**

    ```ballerina
    # Uploads file content to the FTP server directly as JSON or, the counterpart Ballerina record representation.
    # + path - The path to the file on the FTP server
    # + content - The file content as JSON or a Ballerina record
    # + return - An `ftp:Error` if an error occurs, otherwise nil
    remote isolated function putJson(string path, json|record {|anydata...;|}  content, FileWriteOption option) returns Error?;
    ```

3. **Upload content as XML or Ballerina record**

    ```ballerina
    # Uploads file content to the FTP server directly as XML or, the counterpart Ballerina record representation.
    # + path - The path to the file on the FTP server
    # + content - The file content as XML or a Ballerina record
    # + return - An `ftp:Error` if an error occurs, otherwise nil
    remote isolated function putXml(string path, xml|record {|anydata...;|}  content, FileWriteOption option) returns Error?;
    ```

4. **Upload content as CSV**

    ```ballerina
    # Uploads file content to the FTP server as CSV or, the counterpart Ballerina record representation.
    # + path - The path to the file on the FTP server
    # + content - The file content as a 2D string array (CSV)
    # + return - An `ftp:Error` if an error occurs, otherwise nil
    remote isolated function putCsv(string path, string[][]|record {|anydata...;|}[]  content, FileWriteOption option) returns Error?;
    ```

5. **Upload content as a byte array**

    ```ballerina
    # Uploads file content to the FTP server as a byte array.
    # + path - The path to the file on the FTP server
    # + content - The file content as a byte array
    # + return - An `ftp:Error` if an error occurs, otherwise nil
    remote isolated function putBytes(string path, byte[] content, FileWriteOption option) returns Error?;
    ```

6. **Upload content as a stream of byte arrays**

    ```ballerina
    # Uploads file content to the FTP server as a stream of byte arrays.
    # + path - The path to the file on the FTP server
    # + content - The file content as a stream of byte arrays
    # + return - An `ftp:Error` if an error occurs, otherwise nil
    remote isolated function putBytesFromStream(string path, stream<byte[], Error?> content, FileWriteOption option) returns Error?;
    ```

7. **Upload content as a CSV stream**

    ```ballerina
    # Uploads file content to the FTP server as a stream of string[].
    # + path - The path to the file on the FTP server
    # + content - The file content as a stream of string arrays
    # + return - An `ftp:Error` if an error occurs, otherwise nil
    remote isolated function putCsvFromStream(string path, stream<string[]|record{}, Error?> content, FileWriteOption option) returns Error?;
    ```

### Examples

1. **Fetching content**
    - Fetching content directly as plain text:
        ```ballerina
        string stringContent = check ftpClient->getText("/path/to/file.txt");
        ```
    - Fetching content directly as JSON:
        ```ballerina
        json jsonContent = check ftpClient->getJson("/path/to/file.json");

        Person person = check ftpClient->getJson("/path/to/file.json");
        ```
    - Fetching content directly as XML:
        ```ballerina
        xml xmlContent = check ftpClient->getXml("/path/to/file.xml");

        Person person = check ftpClient->getXml("/path/to/file.xml", Person);
        ```
    - Fetching content directly as a byte array:
        ```ballerina
        byte[] byteContent = check ftpClient->getBytes("/path/to/file");
        ```
    - Fetching content as a stream of byte arrays:
        ```ballerina
        stream<byte[], ftp:Error?> byteStream = check ftpClient->getBytesAsStream("/path/to/file", 1024);
        ```
    - Fetching content directly as CSV:
        ```ballerina
        // Fetch as array of string arrays (raw CSV rows)
        string[][] csvContent = check ftpClient->getCsv("/path/to/file.csv", string[]);

        // Fetch as array of Ballerina records (structured mapping)
        Person[] person = check ftpClient->getCsv("/path/to/file.csv", Person);
        ```

2. **Uploading content**
    - Uploading content directly as a byte array:
        ```ballerina
        check ftpClient->putText("/path/to/file", "{ \"name\": \"John\", \"age: 30 }");
        ```
    - Uploading content directly as JSON:
        ```ballerina
        // 1. direct JSON content
        check ftpClient->putJson("/path/to/file.json", { "name": "John", "age: 30 });
        
        // 2. counterpart Ballerina record
        Person person = { name: "John", age: 30 };
        check ftpClient->putJson("/path/to/file.json", person);
        ```
    - Uploading content directly as XML:
        ```ballerina
        // 1. direct XML content
        check ftpClient->putXml("/path/to/file.xml", xml `<person><name>John</name><age>30</age></person>`);
      
        // 2. counterpart Ballerina record
        Person person = { name: "John", age: 30 };
        check ftpClient->putXml("/path/to/file.xml", person);
        ```
    - Uploading content directly as a byte array:
        ```ballerina
        check ftpClient->putBytes("/path/to/file", [104, 101, 108, 108, 111]);
        ```
    - Uploading content as a stream of byte arrays:
        ```ballerina
        stream<Block, ftp:Error?> byteStream = ... // define the stream
        check ftpClient->putBytesFromStream("/path/to/file", byteStream);
        ```
    - Uploading content directly as CSV:
        ```ballerina
        // 1. direct CSV content
        check ftpClient->putCsv("/path/to/file.csv", [["name", "age"], ["John", "30"]]);
      
        // 2. counterpart Ballerina record
        Person person = { name: "John", age: 30 };
        check ftpClient->putCsv("/path/to/file.csv", person);
        ```

### Compatibility and Migration

1. Existing code using the `get()` and `put()` methods with the default behavior (stream of bytes) will continue to work without modifications.
2. New code can take advantage of the new APIs for enhanced capabilities.

## Alternatives

An alternative involving a single, generalised databinding method was evaluated:
```ballerina
get() -> byte[]|string|json|xml
```

However, this approach was rejected due to significant drawbacks:

1. Unreliable Format Inference: Unlike protocols such as HTTP, which provide content-type headers, file formats cannot be reliably inferred from content or extensions alone. This makes it impossible to guarantee the correct return type for a generic get() method.

2. Ambiguous CSV Representation: To support CSV within this single method, it would likely be returned as string[][]. This is not a first-class type in the same way as json or xml, leading to an inconsistent and potentially confusing developer experience.


## Risks and Assumptions

1. The correct format of the file content is assumed based on the API used. Incorrect assumptions may lead to runtime errors.
2. Adequate error handling should be implemented to manage data conversion errors effectively.
