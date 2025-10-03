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

### 1. New listener class

```ballerina
public isolated class ContentListener {
    public isolated function init(*ListenerConfiguration cfg) returns Error?;
}
```

- Takes the same `ftp:ListenerConfiguration` you use today.
- Users route by `path` and/or `fileNamePattern` to target specific formats.

### 2. Service callbacks

#### 2.1. Generic

```ballerina
remote function onFile(stream<byte[], error> content, ftp:FileInfo fileInfo?, ftp:Caller caller?) returns error?;

remote function onFile(byte[] content, ftp:FileInfo fileInfo?, ftp:Caller caller?) returns error?;
```

#### 2.2. Data-friendly

```ballerina
# UTF-8 (simple default)
remote function onFileText(string content, ftp:FileInfo fileInfo?, ftp:Caller caller?) returns error?;

# Delivered as json
remote function onFileJson(json content, ftp:FileInfo fileInfo?, ftp:Caller caller?) returns error?;
remote function onFileJson(record{} content, ftp:FileInfo fileInfo?, ftp:Caller caller?) returns error?;

# Delivered as xml
remote function onFileXml(xml content, ftp:FileInfo fileInfo?, ftp:Caller caller?) returns error?;
remote function onFileXml(record{} content, ftp:FileInfo fileInfo?, ftp:Caller caller?) returns error?;

# RFC4180 defaults
remote function onFileCsv(string[][] content, ftp:FileInfo fileInfo?, ftp:Caller caller?) returns error?;
remote function onFileCsv(record{}[] content, ftp:FileInfo fileInfo?, ftp:Caller caller?) returns error?;
remote function onFileCsv(stream<byte[], content> rows, ftp:FileInfo fileInfo?, ftp:Caller caller?) returns error?;
```

- If a format-specific method is implemented and the file matches your `fileNamePattern`, that method is invoked (`onFileJson` / `onFileXml` / `onFileCsv` / `onFileText`).
- Else, if `onFile` is implemented, it is invoked (stream). 
- Else, if `onFileBytes` is implemented, it is invoked (bytes). 
- Else, no callback is made (use the legacy listener if you only need metadata).

> The legacy `onFileChange(WatchEvent, Caller)` remain available and unchanged.

### Usage Examples

1. Stream big files, then delete via `Caller`

```ballerina
import ballerina/ftp;

listener ftp:ContentListener ContentListener = check new ({
    protocol: ftp:SFTP,
    host: "sftp.example.com",
    path: "/drop/in",
    fileNamePattern: ".*\\.(bin|gz|zip)$",
    pollingInterval: 2
});

service on ContentListener {
    remote function onFile(stream<byte[] & readonly, io:Error?> stream,
                                  ftp:FileInfo fileInfo,
                                  ftp:Caller caller) returns error? {
        // Consume the stream…
        check stream.close();
        if caller is ftp:Caller {
            check caller->delete(fileInfo.path);
        }
    }
}
```

2. Text (UTF-8)

```ballerina
import ballerina/ftp;

listener ftp:ContentListener ContentListener = check new ({
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

### Compatibility and migration

- Existing `ftp:Listener` and `onFileChange` continue to work as-is.
- Services can adopt the new content callbacks incrementally by adding one of the allowed signatures for the formats they need.

## Risks and Assumptions

- **Partial uploads:** The listener will see a file as soon as the provider reports it. Use filename conventions (e.g., upload with `.part` then rename) and `fileNamePattern` to avoid premature processing.
- **Large files / memory:** Prefer `onFile` (stream) for large payloads; avoid buffering with `onFileBytes`.
- **Dispatch clarity:** It’s the user’s responsibility to set an appropriate `fileNamePattern` so the right callback is chosen for the format they expect.
