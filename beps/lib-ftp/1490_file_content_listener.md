# Add a File Content Listener to the FTP Module

- Authors
    - SachinAkash01
- Reviewed by
    - TBD
- Created date
    - 2025-10-02
- Issue
    - [1490](https://github.com/ballerina-platform/ballerina-library/issues/1490)
- State
    - Submitted

## Summary

The current `ftp:Listener` reports file add/delete events via `onFileChange`, exposing metadata only. To process content, developers must invoke a client (`Caller->get`) inside the handler.
This proposal adds content-first callbacks to the existing listener, so services can receive file content directly (stream, bytes, text, JSON, XML, CSV) as soon as a file is detected

## Goals

1. Extend the current `ftp:Listener` service contract to provide file content directly upon detection of a new file.

## Non-Goals

1. This proposal will not remove the existing `onFileChange` method that provides `ftp:WatchEvent`. This will be maintained for backward compatibility and for use cases where only file metadata is required.

## Motivation

Currently, the listener only reports metadata and processing a new file requires significant boilerplate code. The developer must handle the event, instantiate a client, fetch the content as a stream, and then perform data conversion. Many real-world flows need the file’s content the moment it lands. A content-first callback lets your service start processing immediately, and if needed, use the provided `Caller` to move or delete the file afterward.

## Design

### 1. Service callbacks

#### 1.1. Generic

```ballerina
remote function onFile(stream<byte[], error> content, ftp:FileInfo fileInfo, ftp:Caller caller) returns error?;

remote function onFile(byte[] content, ftp:FileInfo fileInfo, ftp:Caller caller) returns error?;
```

#### 1.2. Data-friendly

```ballerina
# UTF-8 (simple default)
remote function onFileText(string content, ftp:FileInfo fileInfo, ftp:Caller caller) returns error?;

# Delivered as json
remote function onFileJson(json content, ftp:FileInfo fileInfo, ftp:Caller caller) returns error?;
remote function onFileJson(record{} content, ftp:FileInfo fileInfo, ftp:Caller caller) returns error?;

# Delivered as xml
remote function onFileXml(xml content, ftp:FileInfo fileInfo, ftp:Caller caller) returns error?;
remote function onFileXml(record{} content, ftp:FileInfo fileInfo, ftp:Caller caller) returns error?;

# RFC4180 defaults
remote function onFileCsv(string[][] content, ftp:FileInfo fileInfo, ftp:Caller caller) returns error?;
remote function onFileCsv(record{}[] content, ftp:FileInfo fileInfo, ftp:Caller caller) returns error?;
remote function onFileCsv(stream<byte[], error> content, ftp:FileInfo fileInfo, ftp:Caller caller) returns error?;
```

> Note: 
> - `fileInfo` and `caller` parameters are optional and user can skip them if needed.
> - The legacy `onFileChange(WatchEvent, Caller)` remain available and unchanged.

### 2. Service Dispatching Logic

The listener employs an intelligent dispatching mechanism to route incoming files to the appropriate service method based on file extensions, method availability, and user-defined overrides.

#### 2.1. Method Routing Priority

When a file is detected, the listener determines which method to invoke using the following priority order:

1. **Annotation-Based Override** (Highest Priority):
   - If a method is annotated with `@ftp:FileConfig { pattern: "..." }` and the file matches the specified pattern, that method is invoked regardless of the file extension's default mapping.
   - See [Section 4: Method Override via Annotation](#4-method-override-via-annotation) for details.

2. **Default Extension Mapping**:
   - If no annotation override applies, the listener uses the file extension to determine the appropriate content method based on default mappings (e.g., `.json` → `onFileJson`, `.txt` → `onFileText`).
   - See [Section 3: Default File Extension to Content Method Mapping](#3-default-file-extension-to-content-method-mapping) for the full mapping table.

3. **Fallback to Generic or Metadata Methods**:
   - If no format-specific method is available for the detected file, the listener falls back to `onFile` (generic byte stream handling) or `onFileChange` (metadata-only handling).
   - See [Section 5: Fallback Behavior](#5-fallback-behavior-for-unmatched-content-methods) for fallback chain details.

#### 2.2. Method Handling Strategies

A developer can choose one of the following strategies for handling file content within a single service:

1. **Format-Specific Handling**: The service can implement one or more format-specific methods (e.g., `onFileJson`, `onFileXml`, `onFileText`).
    - **Behavior**: The listener attempts to parse the content into the required type based on file extension or annotation override.
    - **Failure Case**: A content parsing failure is treated as a terminal error for that file event. The error will be logged, and no other methods will be invoked.

2. **Generic Content Handling**: If no format-specific methods are used, the service can implement a single generic method.
    - Either `onFile(stream<byte[], error> ...)` for efficient stream processing.
    - Or `onFile(byte[] ...)` for in-memory byte array processing.

3. **Metadata-Only Handling (Legacy)**: For backward compatibility, a service can implement only the `onFileChange(ftp:WatchEvent ...)` method if no content-handling methods are present.

### 3. Default File Extension to Content Method Mapping

When multiple file extension patterns are configured in the listener and multiple content methods are available in the service, the listener will automatically route files to the appropriate content method based on the file extension.

#### 3.1. Default Mapping Rules

The listener applies the following default mappings between file extensions and content methods:

| File Extensions | Content Method | Content Type |
|----------------|----------------|--------------|
| `.json` | `onFileJson` | `json` or `record{}` |
| `.xml` | `onFileXml` | `xml` or `record{}` |
| `.csv` | `onFileCsv` | `string[][]`, `record{}[]`, or `stream<byte[], error>` |
| `.txt` | `onFileText` | `string` |
| All other extensions | `onFile` | `byte[]` or `stream<byte[], error>` |

#### 3.2. Multiple Pattern Handling

When the listener configuration includes multiple file patterns, the listener will:
1. Match the incoming file against the configured `fileNamePattern`
2. Extract the file extension from the matched file
3. Route to the corresponding content method based on the mapping table above

**Example:**

```ballerina
listener ftp:Listener ContentListener = check new ({
    protocol: ftp:FTP,
    host: "ftp.example.com",
    path: "/data",
    fileNamePattern: ".*\\.(txt|json|csv)$"
});

service on ContentListener {
    // Handles .txt files
    remote function onFileText(string content, ftp:FileInfo fileInfo) returns error? {
        // Process text content
    }

    // Handles .json files
    remote function onFileJson(json content, ftp:FileInfo fileInfo) returns error? {
        // Process JSON content
    }

    // Handles .csv files
    remote function onFileCsv(string[][] content, ftp:FileInfo fileInfo) returns error? {
        // Process CSV content
    }
}
```

In this example, when a file with `.txt` extension arrives, `onFileText` is invoked; `.json` files trigger `onFileJson`, and `.csv` files trigger `onFileCsv`.

### 4. Method Override via Annotation

While the default extension-to-method mapping covers common use cases, there are scenarios where a user may want to process a file using a different content method than the default. The `@ftp:FileConfig` annotation allows users to override the default behavior on a per-method basis.

#### 4.1. Annotation Definition

```ballerina
public type FileConfig record {|
    string pattern;
|};

public annotation FileConfig FileConfig on function;
```

#### 4.2. Override Behavior

The `pattern` field in `@ftp:FileConfig` specifies a file name pattern that should be routed to the annotated method, overriding the default extension mapping. The pattern must be a subset (or more specific version) of the listener-level `fileNamePattern`.

**Example: Processing `.txt` files as JSON**

```ballerina
listener ftp:Listener ContentListener = check new ({
    protocol: ftp:FTP,
    host: "ftp.example.com",
    path: "/data",
    fileNamePattern: ".*\\.(txt|json)$"
});

service on ContentListener {
    // Override: treat .txt files as JSON instead of text
    @ftp:FileConfig { pattern: ".*\\.txt$" }
    remote function onFileJson(json content, ftp:FileInfo fileInfo) returns error? {
        // Process .txt files as JSON
        // .txt files will be parsed as JSON due to annotation
    }
}
```

In this scenario, when a `.txt` file arrives, it will be parsed as JSON and routed to the annotated `onFileJson` method instead of the default `onFileText` method. Similarly, `.json` files will also be routed to `onFileJson` by default.

#### 4.3. Annotation Constraints

- The annotation pattern must be a subset of the listener's `fileNamePattern`.
- If the annotation pattern does not match the listener pattern, a compilation error will be raised.
- Multiple methods cannot have overlapping annotation patterns—this will result in a compilation error.

### 5. Fallback Behavior for Unmatched Content Methods

When the listener detects a file but no appropriate content method exists in the service, a fallback mechanism is triggered to handle the file gracefully.

#### 5.1. Fallback Chain

The fallback operates in the following order:

1. **Primary Fallback - `onFile` (Generic Content Method)**:
   - If a format-specific content method (e.g., `onFileJson`, `onFileText`) is not available for the detected file extension, the listener will attempt to invoke the generic `onFile` method with the file content as a stream of bytes or byte array.
   - This allows the service to handle the file content in a generic manner.

   ```ballerina
   remote function onFile(stream<byte[], error> content, ftp:FileInfo fileInfo, ftp:Caller caller) returns error? {
       // Process file as raw bytes
   }
   ```

2. **Secondary Fallback - `onFileChange` (Metadata-Only)**:
   - If neither a format-specific method nor a generic `onFile` method is available, the listener will fall back to invoking the `onFileChange` method, if present.
   - This method receives only the file metadata (`ftp:WatchEvent`), allowing the service to know a file was added without reading its content.

   ```ballerina
   remote function onFileChange(ftp:WatchEvent event, ftp:Caller caller) returns error? {
       // Handle file addition event without reading content
   }
   ```

3. **Tertiary Fallback - Compilation Error**:
   - If none of the above methods are available, the service will fail at compile time with an error message indicating that at least one content handling method (`onFile`, format-specific methods, or `onFileChange`) must be implemented.

#### 5.2. Example Scenarios

**Scenario 1: Missing format-specific method, fallback to `onFile`**

```ballerina
listener ftp:Listener ContentListener = check new ({
    protocol: ftp:FTP,
    host: "ftp.example.com",
    path: "/data",
    fileNamePattern: ".*\\.(txt|json)$"
});

service on ContentListener {
    // No onFileText or onFileJson
    // Fallback: handles all files as byte streams
    remote function onFile(stream<byte[], error> content, ftp:FileInfo fileInfo) returns error? {
        // Process all files as raw bytes
    }
}
```

**Scenario 2: No content methods, fallback to `onFileChange`**

```ballerina
listener ftp:Listener ContentListener = check new ({
    protocol: ftp:FTP,
    host: "ftp.example.com",
    path: "/data",
    fileNamePattern: ".*\\.(txt|json)$"
});

service on ContentListener {
    // No onFile or format-specific methods
    // Fallback: only metadata is processed
    remote function onFileChange(ftp:WatchEvent event) returns error? {
        // Only file metadata is available here
        // User must fetch content manually if needed
    }
}
```

**Scenario 3: No methods implemented - Compilation Error**

```ballerina
listener ftp:Listener ContentListener = check new ({
    protocol: ftp:FTP,
    host: "ftp.example.com",
    path: "/data",
    fileNamePattern: ".*\\.(txt|json)$"
});

service on ContentListener {
    // No methods implemented
    // Compilation error: "Service must implement at least one of: onFile, onFileText, onFileJson, onFileXml, onFileCsv, or onFileChange"
}
```

### 6. Usage Examples

#### 6.1. Multiple File Extensions with Default Routing

```ballerina
import ballerina/ftp;
import ballerina/log;

listener ftp:Listener ContentListener = check new ({
    protocol: ftp:FTP,
    host: "ftp.example.com",
    path: "/data",
    fileNamePattern: ".*\\.(txt|json|csv)$",
    pollingInterval: 5
});

service on ContentListener {
    // Automatically handles .txt files
    remote function onFileText(string content, ftp:FileInfo fileInfo, ftp:Caller caller) returns error? {
        log:printInfo(string `Processing text file: ${fileInfo.name}`);
        // Process text content
        check caller->delete(fileInfo.path);
    }

    // Automatically handles .json files
    remote function onFileJson(json content, ftp:FileInfo fileInfo, ftp:Caller caller) returns error? {
        log:printInfo(string `Processing JSON file: ${fileInfo.name}`);
        // Process JSON content
        check caller->delete(fileInfo.path);
    }

    // Automatically handles .csv files
    remote function onFileCsv(string[][] content, ftp:FileInfo fileInfo, ftp:Caller caller) returns error? {
        log:printInfo(string `Processing CSV file: ${fileInfo.name}`);
        // Process CSV content
        check caller->delete(fileInfo.path);
    }
}
```

#### 6.2. Annotation Override - Processing Text Files as JSON

```ballerina
import ballerina/ftp;
import ballerina/log;

listener ftp:Listener ContentListener = check new ({
    protocol: ftp:SFTP,
    host: "sftp.example.com",
    path: "/config",
    fileNamePattern: ".*\\.(txt|json)$"
});

service on ContentListener {
    // Override: treat .txt files as JSON (e.g., .txt files contain JSON data)
    @ftp:FileConfig { pattern: ".*\\.txt$" }
    remote function onFileJson(json content, ftp:FileInfo fileInfo) returns error? {
        log:printInfo(string `Processing ${fileInfo.name} as JSON`);
        // Process .txt files as JSON
    }
}
```

#### 6.3. Fallback to Generic `onFile` Method

```ballerina
import ballerina/ftp;
import ballerina/io;

listener ftp:Listener ContentListener = check new ({
    protocol: ftp:FTP,
    host: "ftp.example.com",
    path: "/uploads",
    fileNamePattern: ".*\\.(txt|json|pdf|docx)$"
});

service on ContentListener {
    // Only onFileJson is implemented
    remote function onFileJson(json content, ftp:FileInfo fileInfo) returns error? {
        // Handles .json files
    }

    // Fallback: handles .txt, .pdf, .docx files as byte streams
    remote function onFile(stream<byte[], error> content, ftp:FileInfo fileInfo, ftp:Caller caller) returns error? {
        string localPath = string `./downloads/${fileInfo.name}`;
        check io:fileWriteBlocksFromStream(localPath, content);
        check caller->delete(fileInfo.path);
    }
}
```

#### 6.4. Fallback to Metadata-Only `onFileChange`

```ballerina
import ballerina/ftp;
import ballerina/log;

listener ftp:Listener ContentListener = check new ({
    protocol: ftp:FTP,
    host: "ftp.example.com",
    path: "/notifications",
    fileNamePattern: ".*\\.(txt|json)$"
});

service on ContentListener {
    // No content methods implemented
    // Fallback: only file metadata is received
    remote function onFileChange(ftp:WatchEvent event) returns error? {
        foreach ftp:FileInfo fileInfo in event.addedFiles {
            log:printInfo(string `New file detected: ${fileInfo.name}, size: ${fileInfo.size}`);
            // User can manually fetch content if needed using a client
        }
    }
}
```

#### 6.5. Mixed Strategy - Some Extensions with Specific Handlers, Others with Fallback

```ballerina
import ballerina/ftp;
import ballerina/log;

listener ftp:Listener ContentListener = check new ({
    protocol: ftp:SFTP,
    host: "sftp.example.com",
    path: "/mixed",
    fileNamePattern: ".*\\.(json|xml|txt|log)$"
});

service on ContentListener {
    // Specific handler for JSON files
    remote function onFileJson(json content, ftp:FileInfo fileInfo) returns error? {
        log:printInfo(string `Processing JSON: ${fileInfo.name}`);
        // Process JSON content
    }

    // Specific handler for XML files
    remote function onFileXml(xml content, ftp:FileInfo fileInfo) returns error? {
        log:printInfo(string `Processing XML: ${fileInfo.name}`);
        // Process XML content
    }

    // Fallback: handles .txt and .log files (no onFileText implemented)
    remote function onFile(stream<byte[], error> content, ftp:FileInfo fileInfo) returns error? {
        log:printInfo(string `Processing ${fileInfo.name} as byte stream`);
        // Generic processing for .txt and .log files
    }
}
```

### 7. Additional Usage Examples

#### 7.1. Consume a binary file

```ballerina
import ballerina/ftp;
import ballerina/io;

listener ftp:Listener ContentListener = check new ({
    protocol: ftp:SFTP,
    host: "sftp.example.com",
    path: "/drop/in",
    fileNamePattern: ".*\\.(bin|gz|zip)$",
    pollingInterval: 2
});

service on ContentListener {
    remote function onFile(byte[] content,
                                  ftp:FileInfo fileInfo,
                                  ftp:Caller caller) returns error? {
        string localFilePath = string `./downloads/${fileInfo.name}`;
        check io:fileWriteBytes(localFilePath, content);
        if caller is ftp:Caller {
            check caller->delete(fileInfo.path);
        }
    }
}
```

#### 7.2. Text (UTF-8)

```ballerina
import ballerina/ftp;

listener ftp:Listener ContentListener = check new ({
    protocol: ftp:FTP,
    host: "ftp.example.com",
    path: "/notes",
    fileNamePattern: ".*\\.txt$"
});

service on ContentListener {
    remote function onFileText(string content, ftp:FileInfo fileInfo, ftp:Caller caller) returns error? {
        // … process text
    }
}
```

### 8. Compatibility and Migration

- Existing `ftp:Listener` and `onFileChange` continue to work as-is.
- Services can adopt the new content callbacks incrementally by adding one of the allowed signatures for the formats they need.

## Risks and Assumptions

- **Partial uploads:** The listener will see a file as soon as the provider reports it. Use filename conventions (e.g., upload with `.part` then rename) and `fileNamePattern` to avoid premature processing.
- **Large files / memory:** Prefer `onFile` (stream) for large payloads; avoid buffering with `onFileBytes`.
- **Dispatch clarity:** It’s the user’s responsibility to set an appropriate `fileNamePattern` so the right callback is chosen for the format they expect.
