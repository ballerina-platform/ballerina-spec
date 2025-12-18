# 1410: Log file rotation support for ballerina/log

- Authors - @daneshk
- Reviewed by - @TharmiganK
- Created date - 2025-12-16
- Updated date - 2025-12-16
- Issue - https://github.com/ballerina-platform/ballerina-spec/issues/1410
- State - Submitted

## Summary

This proposal introduces native log rotation capability to the `ballerina/log` module, enabling automatic rotation of log files based on size, time, or both. Log rotation prevents unbounded growth of log files in long-running applications, reducing disk space consumption and improving operational manageability in production environments.

## Motivation

Currently, Ballerina writes logs continuously without built-in rotation, causing log files to grow indefinitely in long-running deployments. This can lead to:

- **Disk space exhaustion**: Log files consume increasing amounts of disk space over time
- **Performance degradation**: Large log files can slow down log analysis and troubleshooting
- **Operational overhead**: Users must implement custom scripts or external tools (logrotate, cron jobs) to manage log growth
- **Production readiness concerns**: Lack of native rotation is a blocker for enterprise production deployments

Log rotation is a standard feature in enterprise integration platforms and application servers:
- **Log4j/Logback**: RollingFileAppender with size and time-based policies
- **Winston (Node.js)**: DailyRotateFile transport
- **Python logging**: RotatingFileHandler and TimedRotatingFileHandler
- **WSO2 products**: Built-in log rotation with configurable policies

Providing native log rotation aligns Ballerina with industry standards and reduces barriers to production adoption.

## Goals

- Provide built-in log rotation functionality without requiring external tools or scripts
- Support multiple rotation policies: size-based, time-based, and combined (both)
- Enable automatic cleanup of old backup files with configurable retention limits
- Maintain backward compatibility with existing logging API
- Ensure thread-safe rotation operations in concurrent logging scenarios
- Deliver production-ready rotation with minimal performance overhead

## Non-Goals

- Log compression (e.g., gzip) of rotated files - can be added in future releases
- Remote log shipping or integration with external log management systems
- Custom rotation triggers beyond size and time
- Rotation for non-file destinations (stdout, stderr)
- Asynchronous/background rotation (rotation happens synchronously before writes)

## Design

### API Design

#### 1. Rotation Policy Enum

```ballerina
# Log rotation policies.
public enum RotationPolicy {
    # Rotate logs based on file size only
    SIZE_BASED = "SIZE_BASED",
    # Rotate logs based on time only
    TIME_BASED = "TIME_BASED",
    # Rotate logs based on both file size and time (whichever condition is met first)
    BOTH = "BOTH"
};
```

#### 2. Rotation Configuration

```ballerina
# Log rotation configuration for file destinations.
public type RotationConfig record {|
    # Rotation policy to use
    RotationPolicy policy = BOTH;
    # Maximum file size in bytes before rotation (used with SIZE_BASED or BOTH policies)
    # Default: 10MB (10 * 1024 * 1024 bytes)
    int maxFileSize = 10485760;
    # Maximum age in milliseconds before rotation (used with TIME_BASED or BOTH policies)
    # Default: 24 hours (24 * 60 * 60 s)
    int maxAge = 86400;
    # Maximum number of backup files to retain. Older files are deleted.
    # Default: 10 backup files
    int maxBackupFiles = 10;
|};
```

#### 3. Enhanced FileOutputDestination

```ballerina
# File output destination.
public type FileOutputDestination record {
    # Type of the file destination. Allowed value is "file".
    readonly FILE 'type = FILE;
    # File path (only files with .log extension are supported)
    string path;
    # File output mode
    FileOutputMode mode = APPEND;
    # Log rotation configuration
    RotationConfig rotation?;
};
```

### Usage Examples

#### Example 1: Size-Based Rotation (Most Common)

```ballerina
import ballerina/log;

public function main() returns error? {
    log:Logger logger = check log:fromConfig(
        destinations = [
            {
                'type: log:FILE,
                path: "./logs/app.log",
                rotation: {
                    policy: log:SIZE_BASED,
                    maxFileSize: 52428800,  // 50MB
                    maxBackupFiles: 5
                }
            }
        ]
    );

    logger.printInfo("Application started");
}
```

#### Example 2: Time-Based Rotation (Daily Logs)

```ballerina
import ballerina/log;

public function main() returns error? {
    log:Logger logger = check log:fromConfig(
        destinations = [
            {
                'type: log:FILE,
                path: "./logs/daily.log",
                rotation: {
                    policy: log:TIME_BASED,
                    maxAge: 86400,  // 24 hours
                    maxBackupFiles: 7   // Keep one week
                }
            }
        ]
    );

    logger.printInfo("Daily batch job started");
}
```

#### Example 3: Combined Policy (Production Recommended)

```ballerina
import ballerina/log;

public function main() returns error? {
    log:Logger logger = check log:fromConfig(
        format: log:JSON_FORMAT,
        destinations = [
            {'type: log:STDERR},  // Console for immediate feedback
            {
                'type: log:FILE,
                path: "./logs/production.log",
                rotation: {
                    policy: log:BOTH,
                    maxFileSize: 104857600,  // 100MB
                    maxAge: 43200,        // 12 hours
                    maxBackupFiles: 14       // Two weeks
                }
            }
        ]
    );

    logger.printInfo("Production service initialized");
}
```

#### Example 4: Configuration via Config.toml

```toml
[[ballerina.log.destinations]]
type = "file"
path = "./logs/app.log"
mode = "APPEND"

[ballerina.log.destinations.rotation]
policy = "BOTH"
maxFileSize = 52428800   # 50MB
maxAge = 86400           # 24 hours
maxBackupFiles = 7
```

### Implementation Details

#### Rotation Check Flow

```
Log Write Request
    │
    ▼
Check Rotation Needed?
    │
    ├─► NO ──► Write to file
    │
    └─► YES
        │
        ▼
    Acquire Lock (thread-safe)
        │
        ▼
    Double-check condition
        │
        ▼
    Rename: app.log → app-20251209-143022.log
        │
        ▼
    Create new empty app.log
        │
        ▼
    Cleanup old backups (if count > maxBackupFiles)
        │
        ▼
    Release Lock
        │
        ▼
    Write to file
```

1. Log Write Request: A log write operation is initiated.
2. Check Rotation Needed: Before writing the log, the system checks if rotation is required based on the configured thresholds (file size, time, or both).
   * If NO, proceed to write the log to the current file.
   * If YES, proceed to the next step.
3. Acquire Lock: A thread-safe lock is acquired to ensure only one thread performs the rotation at a time.
4. Double-Check Condition: After acquiring the lock, the rotation condition is re-evaluated to avoid unnecessary rotation in case another thread already performed it.
5. Perform Rotation:
   * Rename the current log file (e.g., app.log → app-<timestamp>.log).
   * Create a new empty log file (app.log).
6. Cleanup Old Backups: Check the number of backup files. If the count exceeds the maxBackupFiles limit, delete the oldest backups.
7. Release Lock: The lock is released after the rotation is complete.
8. Write to File: The log message is written to the new or existing file.


### Performance Considerations

1. **Minimal Overhead**: Rotation checks use file metadata (O(1) operation)
2. **Synchronous Rotation**: Rotation blocks the logging thread briefly (typically < 50ms)
3. **Lock Contention**: ReentrantLock prevents thundering herd; only one thread performs rotation
4. **No Background Threads**: Simple design, no thread pool management overhead

## Alternatives

### Alternative 1: External Log Rotation (Status Quo)

**Approach**: Continue relying on external tools like `logrotate` (Linux) or custom scripts.

**Pros**:
- No changes to Ballerina
- Flexible for advanced scenarios

**Cons**:
- Requires additional setup and maintenance
- Platform-specific (logrotate on Linux, custom scripts on Windows)
- Not integrated with application lifecycle
- Increases operational complexity

**Decision**: Native solution provides better developer experience and reduces operational overhead.

### Alternative 2: Async/Background Rotation

**Approach**: Perform rotation in a background thread/worker.

**Pros**:
- No blocking of logging calls
- Better for high-throughput scenarios

**Cons**:
- Significantly more complex implementation
- Requires queue management and thread coordination
- Risk of log loss during rotation if not carefully designed
- Higher memory footprint

**Decision**: Deferred to future work. Synchronous rotation is simpler and sufficient for most use cases.

### Alternative 3: Fixed File Set (app.log.1, app.log.2, ...)

**Approach**: Use numbered backup files instead of timestamps.

**Pros**:
- Simpler file discovery
- Common pattern in some systems

**Cons**:
- Requires renaming all backups on each rotation (app.log.2 → app.log.3, etc.)
- No timestamp information for when rotation occurred
- More I/O operations

**Decision**: Timestamp-based naming is more informative and requires less I/O.

### Alternative 4: Compression of Rotated Files

**Approach**: Automatically compress rotated files (gzip, zip).

**Pros**:
- Significant disk space savings
- Common in enterprise logging

**Cons**:
- Adds complexity to implementation
- Requires additional dependencies or native compression APIs
- Compressed logs harder to inspect quickly

**Decision**: Deferred to future work. Can be added as enhancement without breaking changes.

## Testing

### Unit Tests

1. **Size-based rotation**: Generate logs exceeding maxFileSize, verify rotation occurs
2. **Time-based rotation**: Use short maxAge (5 seconds), verify rotation after timeout
3. **Combined policy**: Verify rotation happens when either condition met
4. **Backup cleanup**: Verify old backups deleted when exceeding maxBackupFiles
5. **No rotation**: Verify NONE policy doesn't create backups
6. **Multiple log levels**: Verify rotation works with DEBUG, INFO, WARN, ERROR
7. **Error handling**: Verify graceful handling of rotation failures (permissions, disk full)

### Integration Tests

1. **Production scenario**: High-volume logging with BOTH policy
2. **Concurrent logging**: Multiple workers logging simultaneously
3. **Context loggers**: Verify rotation with withContext() derived loggers
4. **Mixed destinations**: STDERR + FILE with rotation
5. **Config.toml**: Verify rotation configuration via Config.toml

### Performance Tests

1. **Baseline**: Log write performance without rotation
2. **With rotation**: Measure overhead of rotation checks
3. **During rotation**: Measure time taken for actual rotation operation
4. **Concurrent**: Performance under high concurrency

### Manual/Exploratory Tests

1. **Disk space handling**: Behavior when disk is nearly full
2. **File permissions**: Behavior with read-only directories
3. **Long-running**: Verify stability over extended periods (24+ hours)
4. **Rotation at boundary**: Edge cases (exactly at threshold, slightly over)

## Risks and Assumptions

### Risks

1. **File System Limitations**
   - Risk: File rename operations may not be atomic on all file systems
   - Mitigation: Use Java NIO atomic move where available; document limitations

2. **Disk Space Exhaustion**
   - Risk: Backups might still consume excessive space if not cleaned up properly
   - Mitigation: Strict enforcement of maxBackupFiles; clear documentation on sizing

3. **Lock Contention**
   - Risk: High-frequency logging might experience contention during rotation
   - Mitigation: Rotation operations are fast (<50ms); happens infrequently

4. **Log Loss During Rotation**
   - Risk: Logs written during rotation window might be lost
   - Mitigation: Rotation is synchronized; new file created immediately

### Assumptions

1. File system supports atomic rename operations (true for most modern systems)
2. Users have write permissions for log directory
3. System clock is reasonably accurate for time-based rotation
4. Rotation thresholds are set to reasonable values (not micro-rotations every second)
5. Backup files are not modified by external processes

## Dependencies

### Internal Dependencies
- `ballerina/io`: File I/O operations
- `ballerina/jballerina.java`: Java interop for native rotation logic

### External Dependencies
- Java NIO (java.nio.file): File operations, atomic moves
- Java concurrency utilities (java.util.concurrent.locks): Thread safety

### Build Dependencies
- No additional Gradle dependencies required (Java standard library only)

## Future Work

### Phase 2 Enhancements

1. **Log Compression**
   - Automatically compress rotated files (gzip format)
   - Configurable: `compressionEnabled: true`

2. **Asynchronous Rotation**
   - Perform rotation in background worker
   - Queue log writes during rotation
   - Better for ultra-high-throughput scenarios

3. **Custom Rotation Triggers**
   - Cron-like expressions for scheduled rotation
   - Event-based rotation (e.g., on application restart)

4. **Rotation Hooks/Callbacks**
   - Execute custom logic before/after rotation
   - Useful for log shipping, notifications

5. **Rotation Metrics**
   - Expose metrics: rotation count, last rotation time, backup count
   - Integration with observability features

6. **Advanced Cleanup Policies**
   - Retention based on age (delete backups older than N days)
   - Retention based on total size (delete oldest when total exceeds limit)

7. **Remote Log Archival**
   - Automatically upload rotated logs to cloud storage (S3, Azure Blob)
   - Integration with log management platforms

### Backward Compatibility

All future enhancements will maintain backward compatibility with this initial design. New fields added to `RotationConfig` will have sensible defaults.

### For Existing Applications

Applications using file destinations without rotation will continue to work unchanged. Rotation is opt-in via the `rotation` field in `FileOutputDestination`.

## References

### Industry Standards
- [RFC 5424](https://tools.ietf.org/html/rfc5424): The Syslog Protocol
- [Twelve-Factor App - Logs](https://12factor.net/logs): Treat logs as event streams

### Similar Implementations
- [Log4j RollingFileAppender](https://logging.apache.org/log4j/2.x/manual/appenders.html#RollingFileAppender)
- [Logback RollingPolicy](https://logback.qos.ch/manual/appenders.html#RollingFileAppender)
- [Python RotatingFileHandler](https://docs.python.org/3/library/logging.handlers.html#rotatingfilehandler)
- [Winston Daily Rotate File](https://github.com/winstonjs/winston-daily-rotate-file)

### Related Proposals
- [Contextual Logging](https://github.com/ballerina-platform/ballerina-spec/blob/master/beps/lib-log/1322_contextual_logging.md)
