# 1501: Post-Processing Actions for the File Listener

- Authors - @YasanPunch
- Reviewed by -
- Created date - 2026/09/10
- Updated date - 2026/09/11
- Issue - [#1501](https://github.com/ballerina-platform/ballerina-spec/issues/1501)
- State - Submitted

## Summary

Add a `@file:FunctionConfig` annotation to the `ballerina/file` module. A remote function of a file service uses it to declare what happens to the file after the function completes: delete it, or move it to another directory, with separate actions for success and for error. The fields match `afterProcess` and `afterError` of `@ftp:FunctionConfig`.

## Motivation

A `file:Listener` invokes `onCreate`, `onModify`, and `onDelete` for changes in a watched directory. After a remote function has processed a file, the file stays where it is. Users move or delete it themselves in every remote function, and again on the error path.

The `ftp:Listener` already provides this through `@ftp:FunctionConfig`. Users who build integrations with both listeners, including through the WSO2 Integrator low-code editor, expect the same options in both.

## Goals

- Run an action after a remote function returns successfully, and a separate action after it returns an error or panics.
- Support `DELETE` and `MOVE`.
- Use the same annotation name and the same `afterProcess` and `afterError` shapes as `@ftp:FunctionConfig`.
- Leave services without the annotation unchanged.

## Non-Goals

- File name filtering.
- Age-based file filtering, as offered by the FTP listener's `fileAgeFilter`.
- An `onError` remote function or content-binding remote functions for the file listener.

## Design

### 1. Action types

```ballerina
# Delete action for file processing. When specified, the file is deleted after processing.
public const DELETE = "DELETE";

# Configuration for moving a file after processing.
public type Move record {|
    # Destination directory the file is moved into
    string moveTo;
    # If `true`, keeps the subdirectory path relative to the listener's `path` under `moveTo`
    boolean preserveSubDirs = true;
|};

# Type alias for the `Move` record, used in the action unions.
public type MOVE Move;
```

### 2. Annotation

```ballerina
# Configuration for the remote functions of a file service.
public type FunctionConfiguration record {|
    # Action to perform after the remote function returns successfully. Can be `DELETE` or `MOVE`.
    # If not specified, no action is taken and the file remains in place
    MOVE|DELETE afterProcess?;
    # Action to perform after the remote function returns an error or panics. Can be `DELETE` or `MOVE`.
    # If not specified, no action is taken and the file remains in place
    MOVE|DELETE afterError?;
|};

# Annotation to configure the remote functions of a file service.
public annotation FunctionConfiguration FunctionConfig on service remote function;
```

The annotation is valid on `onCreate` and `onModify`. On `onDelete` it is a compile-time error. On one listener, only one service may configure an action for a given remote function; a second one is a compile-time error. Both rules are also checked when a service is attached at runtime.

### 3. Behavior

**After a successful return:** the `afterProcess` action runs.

**After an error or panic:** the error is printed, then the `afterError` action runs.

If the relevant field is not set, the file stays in place. The action runs after the remote function returns. When several services are attached to the listener, it runs after every service has handled the event.

- `DELETE`: the file is removed.
- `MOVE`: the file is moved into the `moveTo` directory. With `preserveSubDirs` set to `true`, the default, it keeps its path relative to the listener's `path`; with `false`, it is placed directly in `moveTo`. Missing directories are created. If an entry with the destination name already exists, the move fails and the source stays in place.

Paths are resolved to absolute paths against the working directory; `moveTo` is not relative to the watched directory. Attaching a service fails when `moveTo` is empty, is the watched directory, or, on a recursive listener, is inside it. A move whose computed destination is inside a recursively watched directory fails. With `recursive: false`, a subdirectory such as `/data/in/processed` is a valid destination.

Only regular files are acted on; directories and symbolic links are skipped. A failure of the action is logged and is not reported to the service; the file stays in place. If the file is no longer present when the action runs, the action is skipped. Removing the file produces a delete event like any other removal, and `onDelete` runs in every attached service that declares it.

**Example:** the listener watches `/data/in` with `recursive: true`, and `/data/in/orders/2026/a.csv` is handled with `afterProcess: {moveTo: "/data/archive"}`. With `preserveSubDirs: true` the file ends at `/data/archive/orders/2026/a.csv`; with `false`, at `/data/archive/a.csv`.

### 4. Usage examples

#### Example 1: Delete after processing

```ballerina
service on fileListener {
    @file:FunctionConfig {
        afterProcess: file:DELETE
    }
    remote function onCreate(file:FileEvent event) returns error? {
        check process(event.name);
    }
}
```

#### Example 2: Archive on success, quarantine on error

```ballerina
service on fileListener {
    @file:FunctionConfig {
        afterProcess: {moveTo: "/data/archive"},
        afterError: {moveTo: "/data/failed"}
    }
    remote function onCreate(file:FileEvent event) returns error? {
        check process(event.name);
    }
}
```

#### Example 3: Flatten into one directory

```ballerina
listener file:Listener fileListener = new (path = "/data/in", recursive = true);

service on fileListener {
    @file:FunctionConfig {
        afterProcess: {moveTo: "/data/archive", preserveSubDirs: false}
    }
    remote function onCreate(file:FileEvent event) returns error? {
        check process(event.name);
    }
}
```

## Alternatives

- Manual handling in each remote function. Rejected: this is the boilerplate the feature removes.
- Options on `file:ListenerConfig`. Rejected: actions differ per remote function, and a listener can host several services.

## Testing

1. `DELETE` and `MOVE` after success, error, and panic, on `onCreate` and on `onModify`.
2. `preserveSubDirs` `true` and `false` on a recursive listener; missing directories created; an existing destination fails the move.
3. Directory and symbolic-link events, and a file already gone, skip the action; an action failure is logged and leaves the file in place.
4. `onDelete` runs in every attached service for the delete event caused by an action.
5. Attach rejections: annotation on `onDelete`, empty `moveTo`, `moveTo` equal to or inside the watched directory, a second service on the same remote function; success for a subdirectory of a non-recursive watched directory.
6. Two services on one listener, one with an action; a create followed by a modify event on one file.
7. A listener without annotations behaves as before.
8. Compiler plugin: accepted on `onCreate` and `onModify`, rejected on `onDelete` and on a second service, recognized through an import alias, and a user-defined annotation with the same name is not flagged.

## Risks and Assumptions

- A create event can arrive before the writer has finished. The proposal assumes each file is complete when its event is delivered: producers write outside the watched directory on the same file system and move the finished file in.
- The action acts on whatever regular file is at the path when it runs.
- A move across file systems is a copy followed by a delete and is not atomic; a failed step leaves the source in place, and on Windows can also leave the copy. On Windows an open file cannot be moved or deleted.
- Services without the annotation are unaffected.

## Dependencies

None. The low-code trigger metadata shipped with the module is updated in the same change.

## Future Work

- File name filtering on the listener, tracked in [ballerina-library#8748](https://github.com/ballerina-platform/ballerina-library/issues/8748).
- Age-based file filtering, matching the FTP listener's `fileAgeFilter`.
- Content-binding remote functions for the file listener. Extending the annotation to them extends the list of remote functions it is valid on.

## References

- Tracking issue: [ballerina-library#9146](https://github.com/ballerina-platform/ballerina-library/issues/9146)
- FTP post-processing actions: [ballerina-library#8604](https://github.com/ballerina-platform/ballerina-library/issues/8604) and the FTP library specification, section "Post-Processing Actions"
- FTP proposal for the same feature: [ballerina-spec#1432](https://github.com/ballerina-platform/ballerina-spec/issues/1432)
