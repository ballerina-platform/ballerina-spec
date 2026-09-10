# 1501: Post-Processing Actions for the File Listener

- Authors - @YasanPunch
- Reviewed by -
- Created date - 2026/09/10
- Updated date - 2026/09/10
- Issue - [#1501](https://github.com/ballerina-platform/ballerina-spec/issues/1501)
- State - Submitted

## Summary

Add a `@file:FunctionConfig` annotation to the `ballerina/file` module. A remote function of a file service uses it to declare what happens to the file after the function completes: delete it, or move it to another directory. Separate actions can be set for success and for error. The annotation has the same shape as the `afterProcess` and `afterError` fields of `@ftp:FunctionConfig`.

## Motivation

A `file:Listener` invokes `onCreate`, `onModify`, and `onDelete` for changes in a watched directory. After a remote function has processed a file, the file stays where it is. Users move or delete it themselves at the end of each remote function, and again on the error path.

The `ftp:Listener` already provides this through `@ftp:FunctionConfig`. Users who build integrations with both listeners, including through the WSO2 Integrator low-code editor, expect the same options in both.

## Goals

- Run an action after a remote function returns successfully.
- Run a separate action after a remote function returns an error or panics.
- Support `DELETE` and `MOVE` actions.
- Use the same annotation name as `@ftp:FunctionConfig`, and the same names and value shapes for its `afterProcess` and `afterError` fields.
- Keep listeners whose services carry no annotation unchanged.

## Non-Goals

- File name filtering on the listener or on the annotation.
- Age-based file filtering, as offered by the FTP listener's `fileAgeFilter`.
- An `onError` remote function for the file service.
- Content-binding remote functions such as `onFileJson` for the file listener.
- Chained or conditional actions.

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

The annotation is valid on `onCreate` and `onModify` only. Attaching it to `onDelete` is a compile-time error. Attaching such a service to a listener at runtime fails with an error.

### 3. Behavior

When the remote function returns `()`, the `afterProcess` action runs. When it returns an error or panics, the error is printed and the `afterError` action runs. At most one action runs per invocation. If the relevant field is not set, the file is left in place.

The action runs as soon as the remote function returns.

`DELETE` removes the file.

`MOVE` moves the file into the `moveTo` directory. With `preserveSubDirs` set to `true`, the default, the file keeps its path relative to the listener's `path`. With `false`, the file is placed directly in `moveTo` under its own name. Missing directories on the destination path are created. If a file with the same name already exists at the destination, the move fails, the failure is logged, and the source file stays in place.

For example, the listener watches `/data/in` with `recursive: true`, and `/data/in/orders/2026/a.csv` is handled with `afterProcess: {moveTo: "/data/archive"}`. With `preserveSubDirs: true` the file ends at `/data/archive/orders/2026/a.csv`. With `preserveSubDirs: false` it ends at `/data/archive/a.csv`.

The listener's `path`, the event's file path, and `moveTo` are resolved to absolute paths against the working directory, with symbolic links resolved. `moveTo` is not relative to the watched directory.

Attaching a service fails with an error when `moveTo` is empty, when `moveTo` is the watched directory, or when the listener is recursive and `moveTo` is inside the watched directory. With `recursive: false`, a subdirectory of the watched directory such as `in/processed` is a valid destination.

Only regular files are acted on. A create event for a new subdirectory invokes the remote function but skips the action.

A failure of the action itself is logged and is not reported to the service. The file stays in place. If the file is no longer present when the action runs, the action is skipped.

Moving or deleting the file emits a delete event for the source path. Every service attached to the listener receives it, and `onDelete` is invoked where declared.

When several services are attached to the same listener, a remote function of one service may run after an action of another service has already moved or deleted the file. The first action to run acts on the file and the others are skipped.

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

#### Example 4: Different actions for create and modify

```ballerina
service on fileListener {
    @file:FunctionConfig {
        afterProcess: {moveTo: "/data/archive"}
    }
    remote function onCreate(file:FileEvent event) returns error? {
        check importNew(event.name);
    }

    @file:FunctionConfig {
        afterError: {moveTo: "/data/failed"}
    }
    remote function onModify(file:FileEvent event) returns error? {
        check reimport(event.name);
    }
}
```

## Alternatives

- Manual handling in each remote function. Rejected: this is the boilerplate the feature removes.
- Options on `file:ListenerConfig`. Rejected: actions differ per remote function, and a listener can host several services.

## Testing

1. `DELETE` after a successful `onCreate` removes the file.
2. `MOVE` after a successful `onCreate` places the file under `moveTo`, creating missing directories.
3. `MOVE` with `preserveSubDirs: true` on a recursive listener keeps the subdirectory path; with `false` it does not.
4. `DELETE` and `MOVE` after `onCreate` returns an error, and after it panics.
5. Only one of `afterProcess` and `afterError` runs when both are set.
6. A destination file that already exists causes the move to fail and leaves the source in place.
7. A directory create event runs the remote function but skips the action.
8. The action is skipped without error when the remote function has already moved the file.
9. `onDelete` is invoked for the delete event caused by an action, both in the service that configured the action and in a second service on the same listener that carries no annotation.
10. Attach fails for an empty `moveTo`, for `moveTo` equal to the watched directory, and for `moveTo` inside a recursively watched directory. Attach succeeds for a subdirectory of a non-recursive watched directory.
11. Two services with actions on the same event: the file is acted on once and neither service fails.
12. A listener whose services carry no annotation behaves as before.
13. Compiler plugin: the annotation is accepted on `onCreate` and `onModify`, rejected on `onDelete`, recognised through an import alias, and a user-defined annotation with the same name is not flagged.

## Risks and Assumptions

- A create event is emitted when a file is created, before the writer has finished. An action on `onCreate` or `onModify` can act on an incomplete file. This proposal assumes a single producer that writes each file completely before it is handled. Producers should write to a temporary name and rename on completion.
- A move across file systems is a copy followed by a delete and is not atomic. If the copy fails, no partial destination is left and the source stays in place. On Windows, if the copy succeeds but the source cannot be deleted, both files remain.
- The process needs permission to move or delete files in the watched directory and to create files in `moveTo`.
- A listener whose services carry no annotation is unaffected.

## Dependencies

None. The low-code trigger metadata shipped with the module is updated in the same change.

## Future Work

- File name filtering on the listener, tracked in [ballerina-library#8748](https://github.com/ballerina-platform/ballerina-library/issues/8748).
- Age-based file filtering, matching the FTP listener's `fileAgeFilter`.
- Content-binding remote functions for the file listener. The annotation applies to them without change.

## References

- Tracking issue: [ballerina-library#9146](https://github.com/ballerina-platform/ballerina-library/issues/9146)
- FTP post-processing actions: [ballerina-library#8604](https://github.com/ballerina-platform/ballerina-library/issues/8604) and the FTP library specification, section "Post-Processing Actions"
- FTP proposal for the same feature: [ballerina-spec#1432](https://github.com/ballerina-platform/ballerina-spec/issues/1432)
