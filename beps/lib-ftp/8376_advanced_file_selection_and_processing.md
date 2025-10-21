# Advanced File Selection and Processing Framework for Ballerina FTP Module

- Authors
    - SachinAkash01
- Reviewed by
    - TBD
- Created date
    - 2025-10-21
- Issue
    - [8376](https://github.com/ballerina-platform/ballerina-library/issues/8376)
- State
    - Submitted

## Summary

The current Ballerina FTP listener provides basic file monitoring capabilities with regex-based file name filtering and fixed-interval polling. However, it lacks enterprise-grade file selection capabilities essential for production integration scenarios. This proposal introduces a unified Advanced File Selection and Processing Framework that addresses four critical enterprise requirements through a cohesive set of enhancements:

1. **Cron Expression Scheduling** - Introduce flexible cron-based scheduling via union type support in `pollingInterval`
2. **File Stability Detection** - Prevent processing files actively being written by other processes
3. **File Age Filtering** - Process files only within specified age ranges (minimum/maximum age)
4. **Conditional File Processing** - Process files based on the existence of dependent files

## Goals

1. **Flexible Scheduling**: Enable cron-based scheduling for precise control over polling times (e.g., "every 15 minutes", "daily at 2 AM").
2. **Data Integrity**: Prevent processing incomplete files that are actively being written by external processes.
3. **Age-Based Processing**: Allow file selection based on age criteria to handle stabilization periods and archival policies.
4. **Dependency-Aware Processing**: Support complex file processing workflows where files depend on the presence of other related files.
5. **Unified Configuration**: Provide a cohesive API where all features work together naturally.
6. **Backward Compatibility**: Maintain full compatibility with existing configurations; all new features are opt-in.

## Non-Goals

1. **File Content Validation**: This proposal does not include validation of file contents, checksums, or file format verification. These remain application-level concerns.
2. **File Transformation**: This proposal does not include file transformation, conversion, or content manipulation capabilities.
3. **Distributed Locking**: This proposal does not implement distributed file locking across multiple listener instances. Lock detection is limited to local/single-instance scenarios.
4. **File Sorting/Ordering**: This proposal does not include explicit file ordering (e.g., by name, size, or modification time). Files are processed as discovered.

## Motivation

### Current Limitations

The existing FTP listener has several limitations that prevent it from being used effectively in enterprise production environments:

1. **Fixed Polling Only**: The `pollingInterval` parameter only supports fixed intervals (e.g., every 60 seconds). Enterprise workflows often require specific schedules like "every weekday at 9 AM" or "every 15 minutes during business hours," which cannot be expressed with simple intervals.

2. **No File Stability Detection**: The listener immediately processes files as soon as they appear in the monitored directory. If an external process is actively writing a large file, the listener may begin processing it prematurely, leading to:
   - Incomplete data reads
   - File corruption
   - Processing failures and retries
   - Data integrity issues

3. **No Age-Based Filtering**: Many integration scenarios require files to "settle" before processing. For example:
   - **Minimum Age**: Wait 5 minutes after a file appears to ensure the writing process has completed
   - **Maximum Age**: Process only files less than 24 hours old to avoid processing stale or archived data
   - Currently, developers must implement this logic manually in their service code

4. **No Dependency Checking**: Complex file processing workflows often involve multiple related files. For example:
   - Process `invoice_2024_01.xml` only if `invoice_2024_01.csv` and `invoice_2024_01.checksum` exist
   - Process `*.xml` files only if corresponding `*.metadata` files are present
   - Currently, there is no built-in mechanism to express these dependencies

## Design

### New Type Definitions

```ballerina
# Strategy for detecting if a file is still being written by another process
#
# + NONE - No stability checking (default, backward compatible)
# + LOCK_FILE - Check for companion .lock file (e.g., data.csv requires absence of data.csv.lock)
# + SIZE_STABILITY - Check if file size remains unchanged between 2 consecutive polling cycles
# + TIMESTAMP_STABILITY - Check if last modified timestamp remains unchanged between 2 consecutive polling cycles
# + COMBINED_STABILITY - Both size and timestamp must be stable (most reliable)
public enum FileStabilityStrategy {
    NONE,
    LOCK_FILE,
    SIZE_STABILITY,
    TIMESTAMP_STABILITY,
    COMBINED_STABILITY
}

# Mode for calculating file age
#
# + LAST_MODIFIED - Use file's last modified timestamp (default)
# + CREATION_TIME - Use file's creation timestamp (where supported by file system)
public enum AgeCalculationMode {
    LAST_MODIFIED,
    CREATION_TIME
}

# Configuration for file age filtering
#
# + minAge - Minimum age of file in seconds since last modification/creation (inclusive).
#            Files younger than this will be skipped. -1 or absence means no minimum age requirement.
# + maxAge - Maximum age of file in seconds since last modification/creation (inclusive).
#            Files older than this will be skipped. -1 or absence means no maximum age requirement.
# + ageCalculationMode - Whether to calculate age based on last modified time or creation time
public type FileAgeFilter record {|
    decimal minAge = -1;
    decimal maxAge = -1;
    AgeCalculationMode ageCalculationMode = LAST_MODIFIED;
|};

# How required dependency files should be matched
#
# + ALL - All required file patterns must have at least one matching file (default)
# + ANY - At least one required file pattern must have a matching file
# + EXACT_COUNT - Exact number of required files must match (count specified in requiredFileCount)
public enum DependencyMatchingMode {
    ALL,
    ANY,
    EXACT_COUNT
}

# Represents a dependency condition where processing of target files depends on existence of other files
#
# + targetPattern - Regex pattern for files that should be processed conditionally
# + requiredFiles - Array of file patterns that must exist. Supports capture group substitution (e.g., "$1")
# + matchingMode - How to match required files (ALL, ANY, or EXACT_COUNT)
# + requiredFileCount - For EXACT_COUNT mode, specifies the exact number of required files
public type FileDependencyCondition record {|
    string targetPattern;
    string[] requiredFiles;
    DependencyMatchingMode matchingMode = ALL;
    int requiredFileCount = 1;
|};
```

### Updated ListenerConfiguration

```ballerina
# Configuration for FTP listener
#
# + protocol - Supported FTP protocols (FTP or SFTP)
# + host - Target service hostname or IP address
# + port - Port number of the remote service
# + auth - Authentication configuration
# + path - Remote FTP directory path to monitor
# + fileNamePattern - Regex pattern for filtering files (optional)
# + pollingInterval - Polling interval in seconds (decimal, default: 60) OR cron expression (string, e.g., "0 */15 * * * *")
# + userDirIsRoot - If `true`, treats the user's home directory as root (/)
# + fileStabilityStrategy - Strategy for detecting if files are being written (default: NONE)
# + fileAgeFilter - Configuration for filtering files based on age (optional)
# + fileDependencyConditions - Array of dependency conditions for conditional file processing (default: [])
public type ListenerConfiguration record {|
    Protocol protocol = FTP;
    string host = "127.0.0.1";
    int port = 21;
    AuthConfiguration auth?;
    string path = "/";
    string fileNamePattern?;
    boolean userDirIsRoot = false;

    # Scheduling configuration
    decimal|string pollingInterval = 60;

    # File stability detection configuration
    FileStabilityStrategy fileStabilityStrategy = NONE;

    # File age filtering configuration
    FileAgeFilter fileAgeFilter?;

    # File dependency conditions
    FileDependencyCondition[] fileDependencyConditions = [];
|};
```

### Configuration Summary

| Configuration | Type | Default | Description |
|--------------|------|---------|-------------|
| **Scheduling** ||||
| `pollingInterval` | decimal\|string | 60 | Polling interval in seconds (decimal) OR cron expression (string, e.g., "0 */15 * * * *" for every 15 minutes). |
| **File Stability Detection** ||||
| `fileStabilityStrategy` | enum | NONE | Strategy to detect if files are being written: NONE, LOCK_FILE, SIZE_STABILITY, TIMESTAMP_STABILITY, COMBINED_STABILITY. Stability checks use 2 consecutive polling cycles. |
| **File Age Filtering** ||||
| `fileAgeFilter` | record? | - | Optional configuration for filtering files based on age criteria. |
| `fileAgeFilter.minAge` | decimal | -1 | Minimum age in seconds. Files younger than this are skipped. -1 means no minimum. |
| `fileAgeFilter.maxAge` | decimal | -1 | Maximum age in seconds. Files older than this are skipped. -1 means no maximum. |
| `fileAgeFilter.ageCalculationMode` | enum | LAST_MODIFIED | Use LAST_MODIFIED or CREATION_TIME to calculate age. |
| **File Dependencies** ||||
| `fileDependencyConditions` | array | [] | Array of dependency conditions. Empty array means no dependency checking. |
| `fileDependencyConditions[].targetPattern` | string | - | Regex pattern for target files that require dependencies. |
| `fileDependencyConditions[].requiredFiles` | string[] | - | Patterns for required files. Supports capture group substitution. |
| `fileDependencyConditions[].matchingMode` | enum | ALL | Match mode: ALL (all patterns must match), ANY (at least one), EXACT_COUNT (exact number). |
| `fileDependencyConditions[].requiredFileCount` | int | 1 | For EXACT_COUNT mode only: exact number of required matches. |

### Feature Behaviors

#### Feature 1: Cron Expression Scheduling

**Purpose**: Replace fixed-interval polling with flexible cron-based scheduling.

**Cron Expression Format**: Standard Unix cron format with seconds field.
```
┌─────────── second (0-59)
│ ┌───────── minute (0-59)
│ │ ┌─────── hour (0-23)
│ │ │ ┌───── day of month (1-31)
│ │ │ │ ┌─── month (1-12 or JAN-DEC)
│ │ │ │ │ ┌─ day of week (0-6 or SUN-SAT)
│ │ │ │ │ │
* * * * * *
```

**Examples**:
- `"0 */15 * * * *"` - Every 15 minutes
- `"0 0 2 * * *"` - Daily at 2:00 AM
- `"0 0 9-17 * * MON-FRI"` - Every hour from 9 AM to 5 PM on weekdays
- `"0 30 14 1 * *"` - At 2:30 PM on the 1st of every month

**Behavior**:
- If `pollingInterval` is a decimal, it represents the polling interval in seconds
- If `pollingInterval` is a string, it is treated as a cron expression
- If not specified, `pollingInterval` defaults to 60 seconds (decimal)
- Cron scheduling uses the server's local timezone
- Invalid cron expressions will cause initialization to fail with a validation error

**Implementation**: Leverage Ballerina's `task` module or implement a cron parser that calculates the next execution time and uses `task:scheduleJobRecurAtTime`.

#### Feature 2: File Stability Detection

**Purpose**: Prevent processing files actively being written by other processes.

**Strategies**:

1. **NONE (default)**: No stability checking. Files are processed immediately upon discovery. This is the current behavior.

2. **LOCK_FILE**: Check for the existence of a companion `.lock` file.
   - Example: `data.csv` is processed only if `data.csv.lock` does NOT exist
   - Useful when external writers create `.lock` files during upload
   - Low overhead, instant detection

3. **SIZE_STABILITY**: Check if file size remains unchanged between 2 consecutive polling cycles.
   - File metadata is checked in the current poll and again in the next 2 polls
   - If size changes between any of the polls, file is skipped in the current cycle
   - Useful for detecting active writes without lock files
   - Moderate overhead (adds 2 polling intervals to processing latency)

4. **TIMESTAMP_STABILITY**: Check if last modified timestamp remains unchanged between 2 consecutive polling cycles.
   - File metadata is checked in the current poll and again in the next 2 polls
   - If timestamp changes between any of the polls, file is skipped
   - Useful for systems that update timestamps during writes
   - Moderate overhead (adds 2 polling intervals to processing latency)

5. **COMBINED_STABILITY**: Both size AND timestamp must be stable across 2 consecutive polling cycles.
   - Most reliable detection method
   - Highest overhead (adds 2 polling intervals to processing latency)
   - Recommended for critical data integrity scenarios

**Behavior**:
- Stability checking occurs **after** file name pattern matching and **before** age filtering
- Files that fail stability checks are silently skipped (not reported as added)
- Stability checks require 2 polling cycles (e.g., with `pollingInterval: 30`, stability verification takes 60 seconds)
- For LOCK_FILE mode, `.lock` files themselves are automatically excluded from processing

#### Feature 3: File Age Filtering

**Purpose**: Process files only within specified age ranges.

**Age Calculation**:
- Age is calculated as: `current_time - file_timestamp`
- Timestamp source controlled by `ageCalculationMode`:
  - `LAST_MODIFIED`: Use file's last modified time (default, most reliable)
  - `CREATION_TIME`: Use file's creation time (where supported by OS/file system)

**Filtering Logic**:
- If `minAge` is set (> 0): Files younger than `minAge` are skipped
- If `maxAge` is set (> 0): Files older than `maxAge` are skipped
- If both are set: Files must satisfy both conditions
- Values of -1 or absence mean no limit

**Common Use Cases**:
- **Minimum Age Only**: Wait for files to stabilize (e.g., `minAge: 300` = 5 minutes)
- **Maximum Age Only**: Process only recent files (e.g., `maxAge: 86400` = 24 hours)
- **Both**: Process files in a specific age window (e.g., between 1 hour and 7 days old)

**Behavior**:
- Age filtering occurs **after** lock checking and **before** dependency checking
- Files that fail age requirements are silently skipped
- Age is re-evaluated on every poll (stale files eventually become too old)

#### Feature 4: Conditional File Processing (Dependencies)

**Purpose**: Process files only when required dependent files exist.

**Pattern Matching with Capture Groups**:
Dependencies support regex capture group substitution:

```ballerina
fileDependencyConditions: [
    {
        targetPattern: "(.*)\\.xml",           // Match: invoice_2024.xml
        requiredFiles: ["$1.csv", "$1.checksum"],  // Require: invoice_2024.csv, invoice_2024.checksum
        matchingMode: ALL
    }
]
```

**Matching Modes**:

1. **ALL (default)**: All patterns in `requiredFiles` must match at least one file
   - Example: `["$1.csv", "$1.txt"]` requires BOTH files to exist

2. **ANY**: At least one pattern in `requiredFiles` must match
   - Example: `["$1.csv", "$1.json"]` requires EITHER file to exist

3. **EXACT_COUNT**: Exactly `requiredFileCount` files must match (total across all patterns)
   - Example: `requiredFileCount: 3` with pattern `["backup_*"]` requires exactly 3 backup files

**Behavior**:
- Dependency checking occurs **after** age filtering
- Only the directory being monitored is scanned for dependencies (no recursive search)
- If a target file matches multiple dependency conditions, ALL conditions must be satisfied
- Files that fail dependency checks are silently skipped
- Dependent files themselves are subject to the same filtering pipeline

**Complex Example**:
```ballerina
fileDependencyConditions: [
    {
        targetPattern: "invoice_(\\d{4})_(\\d{2})\\.xml",
        requiredFiles: ["invoice_$1_$2.csv", "metadata_$1_$2.json"],
        matchingMode: ALL
    },
    {
        targetPattern: ".*\\.xml",
        requiredFiles: [".*\\.checksum"],
        matchingMode: ANY
    }
]
```

### Integration: The File Selection Pipeline

All features work together in a unified pipeline executed during each poll cycle:

```
1. Directory Scan
   ↓
2. File Name Pattern Matching (fileNamePattern)
   ↓
3. File Stability Detection (fileStabilityStrategy)
   ↓
4. File Age Filtering (fileAgeFilter)
   ↓
5. Dependency Checking (fileDependencyConditions)
   ↓
6. Fire onFileChange Event with Qualified Files
```

**Key Principles**:
- Each stage filters out non-qualifying files
- Filters are applied in order (pattern → lock → age → dependencies)
- Only files passing all stages are reported in `WatchEvent.addedFiles`
- Failed checks are silent (no errors thrown, files simply skipped)
- Performance: Early stages (pattern, lock) fail fast to minimize expensive checks

### Value Validation

Runtime validation enforces the following rules:

1. **Polling Interval Type Validation**:
   - If `pollingInterval` is a decimal, it must be positive (> 0).
     - Error: `"pollingInterval must be greater than 0"`
   - If `pollingInterval` is a string, it must be a valid cron expression.
     - Error: `"Invalid cron expression: <expression>"`

2. **Age Filter Values**: `minAge` and `maxAge` must be either -1 (disabled) or positive values.
   - Error: `"minAge/maxAge must be -1 or greater than 0"`
   - Warning: If `minAge > maxAge`, log warning (no files will ever match)

3. **Dependency Patterns**: `targetPattern` and `requiredFiles` must be valid regex patterns.
   - Error: `"Invalid regex in targetPattern/requiredFiles"`

4. **Exact Count Mode**: If `matchingMode = EXACT_COUNT`, `requiredFileCount` must be > 0.
   - Error: `"requiredFileCount must be positive for EXACT_COUNT mode"`

## Usage Examples

### Example 1: Basic File Stability Detection with Size Stability

Wait for files to finish uploading before processing:

```ballerina
import ballerina/ftp;
import ballerina/log;

listener ftp:Listener remoteServer = check new({
    protocol: ftp:FTP,
    host: "ftp.example.com",
    port: 21,
    auth: {
        credentials: {username: "user", password: "pass"}
    },
    path: "/incoming",
    fileNamePattern: ".*\\.csv",
    pollingInterval: 30,  // Check every 30 seconds

    // Only process files whose size is stable across 2 polling cycles (60 seconds)
    fileStabilityStrategy: ftp:SIZE_STABILITY
});

service on remoteServer {
    remote function onFileChange(ftp:WatchEvent event) {
        foreach ftp:FileInfo file in event.addedFiles {
            log:printInfo("Processing stable file: " + file.name);
            // File is guaranteed to not be actively written
        }
    }
}
```

### Example 2: Cron Scheduling for Business Hours

Process files every 15 minutes during business hours (9 AM - 5 PM, Monday-Friday):

```ballerina
import ballerina/ftp;
import ballerina/log;

listener ftp:Listener businessHoursListener = check new({
    protocol: ftp:SFTP,
    host: "sftp.corporate.com",
    port: 22,
    auth: {
        credentials: {username: "bot", password: "secret"},
        privateKey: {path: "~/.ssh/id_rsa"}
    },
    path: "/data/uploads",
    fileNamePattern: "report_.*\\.xml",

    // Every 15 minutes from 9 AM to 5 PM, Monday through Friday (cron expression)
    pollingInterval: "0 */15 9-17 * * MON-FRI"
});

service on businessHoursListener {
    remote function onFileChange(ftp:WatchEvent event) {
        foreach ftp:FileInfo file in event.addedFiles {
            log:printInfo("Business hours processing: " + file.name);
        }
    }
}
```

### Example 3: File Age Filtering for Stabilization Period

Wait 5 minutes after file creation before processing (prevents processing incomplete uploads):

```ballerina
import ballerina/ftp;
import ballerina/log;

listener ftp:Listener stabilizedListener = check new({
    protocol: ftp:FTP,
    host: "ftp.partner.com",
    port: 21,
    auth: {
        credentials: {username: "partner", password: "partnerpass"}
    },
    path: "/shared/drop",
    fileNamePattern: ".*\\.(xml|json)",
    pollingInterval: 60,

    // Only process files at least 5 minutes old
    fileAgeFilter: {
        minAge: 300,  // 5 minutes
        ageCalculationMode: ftp:LAST_MODIFIED
    }
});

service on stabilizedListener {
    remote function onFileChange(ftp:WatchEvent event) {
        foreach ftp:FileInfo file in event.addedFiles {
            log:printInfo("Processing stabilized file: " + file.name);
            // File has existed for at least 5 minutes
        }
    }
}
```

### Example 4: Maximum Age Filter for Fresh Files Only

Process only files less than 24 hours old (ignore stale/archived files):

```ballerina
import ballerina/ftp;
import ballerina/log;

listener ftp:Listener freshFilesListener = check new({
    protocol: ftp:SFTP,
    host: "sftp.data.com",
    port: 22,
    auth: {
        credentials: {username: "consumer", password: "secret"}
    },
    path: "/feeds/daily",
    pollingInterval: 3600,  // Check hourly

    // Only process files less than 24 hours old
    fileAgeFilter: {
        maxAge: 86400  // 24 hours in seconds
    }
});

service on freshFilesListener {
    remote function onFileChange(ftp:WatchEvent event) {
        foreach ftp:FileInfo file in event.addedFiles {
            log:printInfo("Processing fresh file: " + file.name);
            // File is less than 24 hours old
        }
    }
}
```

### Example 5: Age Range Filter (Min and Max)

Process files between 1 hour and 7 days old:

```ballerina
import ballerina/ftp;
import ballerina/log;

listener ftp:Listener ageRangeListener = check new({
    protocol: ftp:FTP,
    host: "ftp.archive.com",
    port: 21,
    auth: {
        credentials: {username: "archiver", password: "archivepass"}
    },
    path: "/staging",
    pollingInterval: 1800,  // Check every 30 minutes

    // Process files between 1 hour and 7 days old
    fileAgeFilter: {
        minAge: 3600,      // 1 hour
        maxAge: 604800     // 7 days
    }
});

service on ageRangeListener {
    remote function onFileChange(ftp:WatchEvent event) {
        foreach ftp:FileInfo file in event.addedFiles {
            log:printInfo("Processing file in age range: " + file.name);
            // File is between 1 hour and 7 days old
        }
    }
}
```

### Example 6: Simple File Dependencies (All Required)

Process XML files only if corresponding CSV and checksum files exist:

```ballerina
import ballerina/ftp;
import ballerina/log;

listener ftp:Listener dependencyListener = check new({
    protocol: ftp:SFTP,
    host: "sftp.secure.com",
    port: 22,
    auth: {
        credentials: {username: "validator", password: "validpass"}
    },
    path: "/validated",
    pollingInterval: 120,

    // Process invoice_2024_01.xml only if invoice_2024_01.csv
    // and invoice_2024_01.checksum exist
    fileDependencyConditions: [
        {
            targetPattern: "(.*)\\.xml",
            requiredFiles: ["$1.csv", "$1.checksum"],
            matchingMode: ftp:ALL
        }
    ]
});

service on dependencyListener {
    remote function onFileChange(ftp:WatchEvent event) {
        foreach ftp:FileInfo file in event.addedFiles {
            log:printInfo("Processing file with dependencies: " + file.name);
            // Both .csv and .checksum files are guaranteed to exist
        }
    }
}
```

## Compatibility and Migration

- Existing `ftp:Listener` usage continues to work as-is.
- All new configurations are optional with safe defaults.
- Users can incrementally enable additional features (cron scheduling, lock detection, age filtering, dependencies) based on deployment needs.
- No migration or code changes are required unless a user explicitly opts in to new configurations.

## Risks and Assumptions

- **Cron syntax**: Invalid expressions can break schedules. We validate at startup and fail fast with clear errors; docs include copy-pasteable examples.
- **Stability checks**: SIZE/COMBINED stability adds a delay of 2 polling cycles. For example, with `pollingInterval: 30`, this adds 60 seconds. Use LOCK_FILE for high-frequency folders, COMBINED for critical data.
- **Dependency patterns**: Complex regex across many files can slow polls. Patterns are compiled once; keep them simple where possible.
- **Age filter window**: Files can age out before pickup (e.g., processed elsewhere). Use minAge only as a short "settle" buffer (60–300s) and document behavior.
- **Stability heuristics**: SIZE stability can false-positive during brief write pauses; .lock files require writer cooperation.
- **No clustering**: No distributed coordination or shared locks; assume a single listener instance per directory.
