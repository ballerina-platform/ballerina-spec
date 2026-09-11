# 1501: Post-Processing Actions for the File Listener

- Authors - @YasanPunch
- Reviewed by -
- Created date - 2026/09/10
- Updated date - 2026/09/11
- Issue - [#1501](https://github.com/ballerina-platform/ballerina-spec/issues/1501)
- State - Submitted

## Summary

Add a `@file:FunctionConfig` annotation to the `ballerina/file` module. A remote function of a file service uses it to declare what happens to the file after the function completes: delete it, or move it to another directory. Separate actions can be set for success and for error. Its `afterProcess` and `afterError` fields have the same shape as those of `@ftp:FunctionConfig`.

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

On one listener, only one service may configure an action for a given remote function. A second service declaring an action for the same remote function on the same listener is a compile-time error. Attaching such a service at runtime fails with an error.

Different services on one listener may configure different remote functions. An annotation with either field set configures its remote function. An annotation with neither field set is allowed and configures nothing. After a service is detached, another service may configure that remote function. The compile-time check covers services declared on the same listener in one module; other services are checked when they are attached.

### 3. Behavior

**Outcome.** When the remote function returns `()`, the `afterProcess` action runs. When it returns an error or panics, the error is printed and the `afterError` action runs. At most one action runs per invocation. If the relevant field is not set, the file is left in place. Only the outcome of the remote function that carries the annotation selects the action.

**When the action runs.** The action runs after the remote function returns. When several services are attached to the listener, it runs after every service has handled the event. Actions for events already dispatched run to completion after the listener stops.

**`DELETE`.** The file is removed.

**`MOVE`.** The file is moved into the `moveTo` directory. With `preserveSubDirs` set to `true`, the default, the file keeps its path relative to the listener's `path`. With `false`, the file is placed directly in `moveTo` under its own name, and files with the same name from different subdirectories collide there. On a non-recursive listener, `preserveSubDirs` has no effect. Directories missing on the destination path are created when the action runs; if they cannot be created, the action fails and is logged. If an entry with the destination name already exists, the move fails, the failure is logged, and the source file stays in place. If the computed destination is inside a recursively watched directory, the move fails and is logged.

For example, the listener watches `/data/in` with `recursive: true`, and `/data/in/orders/2026/a.csv` is handled with `afterProcess: {moveTo: "/data/archive"}`. With `preserveSubDirs: true` the file ends at `/data/archive/orders/2026/a.csv`. With `preserveSubDirs: false` it ends at `/data/archive/a.csv`.

**Paths.** The listener's `path`, the event's file path, and `moveTo` are resolved to absolute paths against the working directory. `moveTo` is not relative to the watched directory. For the attach-time checks, symbolic links in the listener's `path` and in `moveTo` are resolved first. The action uses the event's file path as delivered: links in parent directories are traversed, and a link as the final path component is skipped.

**Attach-time checks.** Attaching a service fails with an error when the annotation is present on `onDelete`, when `moveTo` is empty, when `moveTo` exists and is not a directory, when `moveTo` is the watched directory, when the listener is recursive and `moveTo` is inside the watched directory, or when another service on the listener already configures an action for the same remote function. With `recursive: false`, a subdirectory of the watched directory such as `/data/in/processed` is a valid destination; creating it produces a create event for the directory, which invokes the remote function and skips the action.

**What is acted on.** Only regular files are acted on. Directories and symbolic links are skipped: a create event for a new subdirectory or for a link invokes the remote function but skips the action. The action acts on the regular file at the path when it runs, whether or not it is the file that produced the event.

**Failures.** A failure of the action itself is logged and is not reported to the service. The file stays in place. If the file is no longer present when the action runs, the action is skipped. On Windows, a file still open by another process cannot be moved or deleted; the action fails and is logged.

**Events produced.** Removing the file from the watched directory, by `DELETE` or by `MOVE`, produces a delete event from the file system like any other removal. The listener generates no events of its own. Every service attached to the listener receives that event, and `onDelete` is invoked where declared. If the source file remains, no delete event occurs.

**Several events on one file.** Each event is a separate invocation with its own action. Events for the same file are handled independently and may run concurrently. A remote function for a later event may find the file already removed by an earlier event's action; its own action is then skipped.

**Several services on one listener.** Within one event, every service handles the event before the action runs.

**Several listeners on one directory.** Each listener acts independently. The later action finds the file gone and is skipped.

**Other services.** On a service that is not attached to a `file:Listener`, the annotation has no effect.

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
5. `DELETE` and `MOVE` on `onModify` after success, after an error, and after a panic.
6. Only one of `afterProcess` and `afterError` runs when both are set.
7. An entry that already exists at the destination causes the move to fail and leaves the source in place.
8. A create event for a directory or for a symbolic link runs the remote function but skips the action.
9. The action is skipped without error when the remote function has already moved the file.
10. `onDelete` is invoked for the delete event caused by an action, both in the service that configured the action and in a second service on the same listener that carries no annotation.
11. Attach fails for the annotation on `onDelete`, for an empty `moveTo`, for a `moveTo` that exists and is not a directory, for `moveTo` equal to the watched directory, for `moveTo` inside a recursively watched directory, for a `moveTo` symbolic link that points into a recursively watched directory, and for a second service configuring the same remote function on the same listener.
12. Attach succeeds for a subdirectory of a non-recursive watched directory. The first move creates it; the directory create event runs the remote function and skips the action.
13. A relative `moveTo` resolves against the working directory.
14. A computed destination inside a recursively watched directory fails and is logged.
15. An action failure other than a collision, such as `DELETE` in a directory without write permission, is logged and leaves the file in place.
16. A file that produces a create event and a modify event, both with actions: the first action removes the file and the second is skipped.
17. Two services on one listener, one with an action on `onCreate` and one without: both remote functions run with the file in place, then the file is acted on once.
18. An annotation with neither field set is accepted and configures nothing.
19. After a service is detached, another service can configure the same remote function.
20. A listener whose services carry no annotation behaves as before.
21. Compiler plugin: the annotation is accepted on `onCreate` and `onModify`, rejected on `onDelete`, rejected on a second service configuring the same remote function on the same listener, recognized through an import alias, and a user-defined annotation with the same name is not flagged.

Moves across file systems are not covered by automated tests.

## Risks and Assumptions

- A create event may arrive before the writer has finished, and each write may produce a further modify event. This proposal assumes each file is complete when its event is delivered. Producers write the file outside the watched directory, on the same file system, and move it into the watched directory when complete.
- A move across file systems is a copy followed by a delete and is not atomic. On Linux and macOS, if the copy fails, no partial destination is left and the source stays in place; if the copy succeeds but the source cannot be deleted, the copy is removed and the source stays in place. On Windows, if the copy succeeds but the source cannot be deleted, both files remain, and a later action on the same file follows the collision rule.
- The process needs write permission on the directory containing the file, on `moveTo`, and on any directory it creates under `moveTo`.
- A listener whose services carry no annotation is unaffected.

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
