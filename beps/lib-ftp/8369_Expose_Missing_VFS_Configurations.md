# Expose Missing Commons VFS Configuration Parameters in FTP Module

- Authors
    - SachinAkash01
- Reviewed by
    - TBD
- Created date
    - 2025-10-20
- Issue
    - [8369](https://github.com/ballerina-platform/ballerina-library/issues/8369)
- State
    - Submitted

## Summary

The current Ballerina FTP module exposes minimal Apache Commons VFS configurations. For FTP, only `userDirIsRoot` is user-configurable (with `passiveMode` used internally but not exposed). For SFTP, only `userDirIsRoot`, `preferredAuthentications`, `identityInfo`, and `strictHostKeyChecking` are exposed, while `connectTimeout` is hardcoded to 10 seconds.

This proposal exposes **13 essential VFS configurations** across both `ClientConfiguration` and `ListenerConfiguration` to enable production-grade deployments with proper timeout handling, international character support, corporate network compatibility, performance optimization, and enhanced security.

## Goals

1. **Enable Production Deployments**: Expose timeout configurations to prevent indefinite hangs and handle unreliable network conditions.
2. **Support International Usage**: Expose encoding configurations for proper handling of file names with non-ASCII characters.
3. **Improve Corporate Network Compatibility**: Make `passiveMode` user-configurable and add SFTP proxy support for firewall-restricted environments.
4. **Enhance Performance**: Allow SFTP compression for bandwidth optimization.
5. **Strengthen Security**: Support SSH known hosts verification for SFTP connections.
6. **Maintain Backward Compatibility**: All new configurations must be optional with defaults matching current behavior.

## Non-Goals

1. **Low-Level VFS Configurations**: This proposal will not expose specialized configurations like `entryParser`, `entryParserFactory`, `defaultDateFormat`, `recentDateFormat`, `activePortRange`, `transferAbortedOkReplyCodes`, or `mdtmLastModifiedTime`. These are too specialized, error-prone, or have suitable defaults handled by VFS.

2. **Java API-Dependent Configurations**: Will not expose configurations requiring Java implementations such as `identityProvider`, `identityRepositoryFactory`, `userInfo`, or `configRepository`. Existing Ballerina abstractions (`privateKey`, `credentials`) are sufficient.

3. **Behavioral Changes**: Will not change existing default behaviors or modify error handling mechanisms unless explicitly configured by users.

## Motivation

Currently, the Ballerina FTP and SFTP modules expose only a minimal subset of Apache Commons VFS configurations. This limits users’ ability to tune connection behavior for real-world production environments. Developers have no control over timeouts, encoding, proxies, or transfer parameters — all of which are critical for enterprise reliability and security.

In production, connections may hang indefinitely when servers are unreachable, large file transfers fail silently over slow networks, and file names with non-Latin characters often appear corrupted. Likewise, security teams require known host verification and proxy routing through corporate firewalls, which are not supported today.

By exposing these essential VFS configurations, developers gain precise control over connection reliability, security policies, and international compatibility. This enhancement aligns Ballerina’s FTP/SFTP modules with industry-standard behavior in libraries such as Apache Commons VFS, Paramiko, and WinSCP — making it truly production-ready for enterprise deployments.

## Design

### New Type Definitions

```ballerina
# FTP file transfer type
#
# + BINARY - Binary mode (no conversion, suitable for all file types)
# + ASCII - ASCII mode (CRLF conversion for text files)
public enum FtpFileType {
    BINARY,
    ASCII
}

# Proxy type for SFTP connections
#
# + HTTP - HTTP CONNECT proxy
# + SOCKS5 - SOCKS version 5 proxy
# + STREAM - Stream proxy (advanced usage)
public enum ProxyType {
    HTTP,
    SOCKS5,
    STREAM
}

# Proxy authentication credentials
#
# + username - Proxy username
# + password - Proxy password
public type ProxyCredentials record {|
    string username;
    string password;
|};

# Proxy configuration for SFTP connections
#
# + host - Proxy server hostname or IP address
# + port - Proxy server port number
# + type - Type of proxy (HTTP, SOCKS5, or STREAM)
# + auth - Optional proxy authentication credentials
public type ProxyConfiguration record {|
    string host;
    int port;
    ProxyType 'type = HTTP;
    ProxyCredentials auth?;
|};
```

### Updated ClientConfiguration

```ballerina
# Configuration for FTP client
#
# + protocol - Supported FTP protocols (FTP or SFTP)
# + host - Target service hostname or IP address
# + port - Port number of the remote service
# + auth - Authentication configuration
# + userDirIsRoot - If `true`, treats the user's home directory as root (/)
# + connectTimeout - Connection timeout in seconds (default: 30.0 for FTP, 10.0 for SFTP)
# + dataTimeout - Data transfer timeout in seconds (FTP only, default: 120.0)
# + soTimeout - Socket operation timeout in seconds (FTP only, default: 60.0)
# + controlEncoding - Character encoding for FTP control connection (FTP only, default: "UTF-8")
# + passiveMode - Use passive mode for data connections (FTP only, default: true)
# + autodetectUtf8 - Auto-detect UTF-8 encoding support (FTP only, default: true)
# + serverTimeZoneId - Server timezone identifier (FTP only, e.g., "America/New_York", "UTC")
# + fileType - File transfer type: BINARY or ASCII (FTP only, default: BINARY)
# + sessionTimeout - SSH session timeout in seconds (SFTP only, default: 300.0)
# + fileNameEncoding - Character encoding for file names (SFTP only, default: "UTF-8")
# + compression - Compression algorithms (SFTP only, default: "none")
# + knownHosts - Path to SSH known_hosts file (SFTP only)
# + proxy - Proxy configuration for SFTP connections (SFTP only)
public type ClientConfiguration record {|
    Protocol protocol = FTP;
    string host = "127.0.0.1";
    int port = 21;
    AuthConfiguration auth?;
    boolean userDirIsRoot = false;

    # Common configurations (both FTP and SFTP)
    decimal connectTimeout = 30.0;  // Seconds

    # FTP-specific configurations
    decimal dataTimeout = 120.0;           // Seconds
    decimal soTimeout = 60.0;              // Seconds
    string controlEncoding = "UTF-8";
    boolean passiveMode = true;
    boolean autodetectUtf8 = true;
    string serverTimeZoneId?;              // Optional, e.g., "America/New_York"
    FtpFileType fileType = BINARY;

    # SFTP-specific configurations
    decimal sessionTimeout = 300.0;        // Seconds
    string fileNameEncoding = "UTF-8";
    string compression = "none";           // e.g., "zlib,none" to prefer compression
    string knownHosts?;                    // Optional, path to known_hosts file
    ProxyConfiguration proxy?;             // Optional proxy settings
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
# + pollingInterval - Polling interval in seconds (default: 60)
# + userDirIsRoot - If `true`, treats the user's home directory as root (/)
# + connectTimeout - Connection timeout in seconds (default: 30.0 for FTP, 10.0 for SFTP)
# + dataTimeout - Data transfer timeout in seconds (FTP only, default: 120.0)
# + soTimeout - Socket operation timeout in seconds (FTP only, default: 60.0)
# + controlEncoding - Character encoding for FTP control connection (FTP only, default: "UTF-8")
# + passiveMode - Use passive mode for data connections (FTP only, default: true)
# + autodetectUtf8 - Auto-detect UTF-8 encoding support (FTP only, default: true)
# + serverTimeZoneId - Server timezone identifier (FTP only, e.g., "America/New_York")
# + fileType - File transfer type: BINARY or ASCII (FTP only, default: BINARY)
# + sessionTimeout - SSH session timeout in seconds (SFTP only, default: 300.0)
# + fileNameEncoding - Character encoding for file names (SFTP only, default: "UTF-8")
# + compression - Compression algorithms (SFTP only, default: "none")
# + knownHosts - Path to SSH known_hosts file (SFTP only)
# + proxy - Proxy configuration for SFTP connections (SFTP only)
public type ListenerConfiguration record {|
    Protocol protocol = FTP;
    string host = "127.0.0.1";
    int port = 21;
    AuthConfiguration auth?;
    string path = "/";
    string fileNamePattern?;
    decimal pollingInterval = 60;
    boolean userDirIsRoot = false;

    # Common configurations (both FTP and SFTP)
    decimal connectTimeout = 30.0;  // Seconds

    # FTP-specific configurations
    decimal dataTimeout = 120.0;           // Seconds
    decimal soTimeout = 60.0;              // Seconds
    string controlEncoding = "UTF-8";
    boolean passiveMode = true;
    boolean autodetectUtf8 = true;
    string serverTimeZoneId?;              // Optional
    FtpFileType fileType = BINARY;

    # SFTP-specific configurations
    decimal sessionTimeout = 300.0;        // Seconds
    string fileNameEncoding = "UTF-8";
    string compression = "none";
    string knownHosts?;                    // Optional
    ProxyConfiguration proxy?;             // Optional
|};
```

### Configuration Summary

| Configuration | Protocol | Type | Default | Description |
|--------------|----------|------|---------|-------------|
| `connectTimeout` | Both | decimal | 30.0 (FTP), 10.0 (SFTP) | Connection timeout in seconds |
| `dataTimeout` | FTP | decimal | 120.0 | Data transfer timeout in seconds |
| `soTimeout` | FTP | decimal | 60.0 | Socket operation timeout in seconds |
| `controlEncoding` | FTP | string | "UTF-8" | Character encoding for FTP commands |
| `passiveMode` | FTP | boolean | true | Use passive mode for data connections |
| `autodetectUtf8` | FTP | boolean | true | Auto-detect UTF-8 support |
| `serverTimeZoneId` | FTP | string? | (none) | Server timezone ID (e.g., "America/New_York") |
| `fileType` | FTP | enum | BINARY | File transfer type (BINARY or ASCII) |
| `sessionTimeout` | SFTP | decimal | 300.0 | SSH session timeout in seconds |
| `fileNameEncoding` | SFTP | string | "UTF-8" | Character encoding for file names |
| `compression` | SFTP | string | "none" | Compression algorithms (e.g., "zlib,none") |
| `knownHosts` | SFTP | string? | (none) | Path to SSH known_hosts file |
| `proxy` | SFTP | record? | (none) | Proxy configuration for SFTP |

### Default Values Rationale

- **connectTimeout**: 30s for FTP (standard), 10s for SFTP (maintains current hardcoded value)
- **dataTimeout**: 120s allows large files over slow connections
- **soTimeout**: 60s balances responsiveness and reliability
- **controlEncoding**: "UTF-8" is modern standard with widest compatibility
- **passiveMode**: `true` required for most firewalls/NAT, modern standard
- **autodetectUtf8**: `true` improves compatibility with legacy servers
- **serverTimeZoneId**: Optional, uses system timezone by default
- **fileType**: BINARY is safe for all file types, modern standard
- **sessionTimeout**: 300s (5 minutes) prevents premature disconnection
- **fileNameEncoding**: "UTF-8" modern standard for file names
- **compression**: "none" avoids CPU overhead unless explicitly needed
- **knownHosts**: Optional security feature
- **proxy**: Optional, direct connection by default

### Protocol-Specific Behavior

**FTP-only configurations** (ignored for SFTP):
- `dataTimeout`, `soTimeout`, `controlEncoding`, `passiveMode`, `autodetectUtf8`, `serverTimeZoneId`, `fileType`

**SFTP-only configurations** (ignored for FTP):
- `sessionTimeout`, `fileNameEncoding`, `compression`, `knownHosts`, `proxy`

**Common configurations** (both FTP and SFTP):
- `connectTimeout`

Configurations are silently ignored when not applicable to maintain flexibility and allow configuration reuse.

### Value Validation

Runtime validation enforces:

1. **Timeout values**: Must be positive decimals (> 0); maximum 600 seconds (10 minutes). Zero (0.0) means no timeout (not recommended).

2. **Encoding values**: Must be valid charset names validated by Java `Charset.isSupported()`. Common values: "UTF-8", "ISO-8859-1", "Shift_JIS", "GB2312", "Windows-1252". Invalid charset throws `ftp:Error` during initialization.

3. **Timezone values**: Must be valid timezone IDs validated by Java `ZoneId.of()`. Examples: "UTC", "America/New_York", "Europe/London", "Asia/Tokyo". Invalid timezone throws `ftp:Error` during initialization.

4. **Compression values**: Comma-separated algorithm list. Valid: "none", "zlib", "zlib@openssh.com", or combinations like "zlib,none". Invalid format logs warning and defaults to "none".

5. **Known hosts file**: Must be valid file path. Supports tilde expansion (`~/.ssh/known_hosts`). Logs warning if file not found but doesn't fail connection.

6. **Proxy configuration**: Host must not be empty; port must be in range 1-65535. Invalid proxy throws `ftp:Error` during connection.

## Usage Examples

### Example 1: FTP with Timeout Configuration

Connect to an unreliable FTP server with custom timeouts:

```ballerina
import ballerina/ftp;
import ballerina/io;

public function main() returns error? {
    ftp:ClientConfiguration config = {
        protocol: ftp:FTP,
        host: "ftp.example.com",
        port: 21,
        auth: {credentials: {username: "user", password: "pass"}},
        connectTimeout: 15.0,    // 15 seconds to connect
        dataTimeout: 300.0,      // 5 minutes for large file transfers
        soTimeout: 60.0          // 1 minute for socket operations
    };

    ftp:Client ftpClient = check new(config);
    stream<byte[], io:Error?> fileStream = check ftpClient->get("/reports/large-report.pdf");
    check io:fileWriteBlocksFromStream("./local-report.pdf", fileStream);
    io:println("File downloaded successfully");
}
```

### Example 2: FTP with Passive Mode for Corporate Firewall

Connect through corporate firewall requiring passive mode:

```ballerina
import ballerina/ftp;
import ballerina/io;

public function main() returns error? {
    ftp:ClientConfiguration config = {
        protocol: ftp:FTP,
        host: "external-ftp.partner.com",
        port: 21,
        auth: {credentials: {username: "partner_user", password: "secure_pass"}},
        passiveMode: true,       // Explicit passive mode for firewall
        connectTimeout: 30.0,
        dataTimeout: 180.0
    };

    ftp:Client ftpClient = check new(config);
    stream<byte[], io:Error?> inputStream = check io:fileReadBlocksAsStream("./invoice.pdf");
    check ftpClient->put("/invoices/invoice-2024-001.pdf", inputStream);
    io:println("File uploaded through corporate firewall");
}
```

### Example 3: FTP with International File Names

Work with FTP server using non-UTF-8 encoding:

```ballerina
import ballerina/ftp;
import ballerina/io;

public function main() returns error? {
    ftp:ClientConfiguration config = {
        protocol: ftp:FTP,
        host: "ftp.jp.example.com",
        port: 21,
        auth: {credentials: {username: "user", password: "pass"}},
        controlEncoding: "UTF-8",         // UTF-8 for Japanese characters
        autodetectUtf8: true,              // Auto-detect UTF-8 support
        serverTimeZoneId: "Asia/Tokyo"     // Server in JST timezone
    };

    ftp:Client ftpClient = check new(config);
    ftp:FileInfo[] files = check ftpClient->list("/レポート");  // /reports in Japanese

    foreach ftp:FileInfo file in files {
        io:println(string `File: ${file.name}, Size: ${file.size} bytes`);
    }
}
```

### Example 4: SFTP with Compression

Transfer large text files with compression:

```ballerina
import ballerina/ftp;
import ballerina/io;

public function main() returns error? {
    ftp:ClientConfiguration config = {
        protocol: ftp:SFTP,
        host: "sftp.remote.example.com",
        port: 22,
        auth: {
            credentials: {username: "user", password: "pass"},
            privateKey: {path: "~/.ssh/id_rsa"}
        },
        connectTimeout: 45.0,           // Slow connection
        sessionTimeout: 600.0,          // 10 minutes for large transfers
        compression: "zlib,none",       // Prefer zlib compression
        fileNameEncoding: "UTF-8"
    };

    ftp:Client sftpClient = check new(config);
    stream<byte[], io:Error?> logStream = check io:fileReadBlocksAsStream("./app-logs.txt");
    check sftpClient->put("/logs/app-logs-2024-01-15.txt", logStream);
    io:println("Log file uploaded with compression");
}
```

### Example 5: SFTP with Known Hosts Verification

Secure SFTP connection with host key verification:

```ballerina
import ballerina/ftp;
import ballerina/io;

public function main() returns error? {
    ftp:ClientConfiguration config = {
        protocol: ftp:SFTP,
        host: "sftp.secure.example.com",
        port: 22,
        auth: {
            credentials: {username: "secure_user", password: "secure_pass"},
            privateKey: {path: "/etc/keys/id_rsa"}
        },
        knownHosts: "/etc/ssh/known_hosts",  // Verify host key
        connectTimeout: 20.0,
        sessionTimeout: 300.0
    };

    ftp:Client sftpClient = check new(config);
    stream<byte[], io:Error?> fileStream = check sftpClient->get("/confidential/report.pdf");
    check io:fileWriteBlocksFromStream("./report.pdf", fileStream);
    io:println("Secure download completed");
}
```

### Example 6: SFTP through Corporate HTTP Proxy

Connect to external SFTP server through corporate proxy:

```ballerina
import ballerina/ftp;
import ballerina/io;

public function main() returns error? {
    ftp:ClientConfiguration config = {
        protocol: ftp:SFTP,
        host: "external-sftp.partner.com",
        port: 22,
        auth: {credentials: {username: "partner_user", password: "partner_pass"}},
        connectTimeout: 30.0,
        sessionTimeout: 300.0,
        proxy: {
            host: "proxy.corporate.com",
            port: 8080,
            'type: ftp:HTTP,
            auth: {username: "proxy_user", password: "proxy_pass"}
        }
    };

    ftp:Client sftpClient = check new(config);
    stream<byte[], io:Error?> dataStream = check io:fileReadBlocksAsStream("./data.csv");
    check sftpClient->put("/uploads/data.csv", dataStream);
    io:println("File uploaded through corporate proxy");
}
```

### Example 7: FTP Listener with Timeout and Encoding

Monitor FTP server with custom timeouts and encoding:

```ballerina
import ballerina/ftp;
import ballerina/io;

listener ftp:Listener ftpListener = check new({
    protocol: ftp:FTP,
    host: "ftp.example.com",
    port: 21,
    auth: {credentials: {username: "monitor_user", password: "monitor_pass"}},
    path: "/uploads",
    fileNamePattern: ".*\\.csv$",
    pollingInterval: 30,
    connectTimeout: 20.0,
    dataTimeout: 180.0,
    soTimeout: 60.0,
    controlEncoding: "UTF-8",
    passiveMode: true
});

service on ftpListener {
    remote function onFileChange(ftp:WatchEvent event) returns error? {
        foreach ftp:FileInfo fileInfo in event.addedFiles {
            io:println(string `New CSV file: ${fileInfo.name}`);
        }
    }
}
```

### Example 8: SFTP Listener with Compression and Security

Monitor SFTP server with compression and known hosts:

```ballerina
import ballerina/ftp;
import ballerina/io;

listener ftp:Listener sftpListener = check new({
    protocol: ftp:SFTP,
    host: "sftp.secure.example.com",
    port: 22,
    auth: {
        credentials: {username: "monitor_user", password: "monitor_pass"},
        privateKey: {path: "~/.ssh/id_rsa"}
    },
    path: "/drop/zone",
    fileNamePattern: ".*\\.(json|xml)$",
    pollingInterval: 60,
    connectTimeout: 15.0,
    sessionTimeout: 600.0,
    compression: "zlib,none",
    knownHosts: "~/.ssh/known_hosts",
    fileNameEncoding: "UTF-8"
});

service on sftpListener {
    remote function onFileChange(ftp:WatchEvent event, ftp:Caller caller) returns error? {
        foreach ftp:FileInfo fileInfo in event.addedFiles {
            io:println(string `New file: ${fileInfo.name}`);
            stream<byte[], io:Error?> content = check caller->get(fileInfo.path);
            // Process content...
            check caller->delete(fileInfo.path);
        }
    }
}
```

### Example 9: Environment-Specific Configuration

Different configurations for development and production:

```ballerina
import ballerina/ftp;
import ballerina/os;

type Environment "dev"|"prod";

function getClientConfig(Environment env) returns ftp:ClientConfiguration {
    if env == "dev" {
        return {
            protocol: ftp:SFTP,
            host: "dev-sftp.example.com",
            port: 22,
            auth: {credentials: {username: "dev_user", password: "dev_pass"}},
            connectTimeout: 60.0,        // Longer timeout for debugging
            sessionTimeout: 600.0,
            compression: "none"
        };
    } else {
        return {
            protocol: ftp:SFTP,
            host: "prod-sftp.example.com",
            port: 22,
            auth: {
                credentials: {username: "prod_user", password: "prod_pass"},
                privateKey: {path: "/etc/keys/prod_id_rsa"}
            },
            connectTimeout: 20.0,        // Fast fail in production
            sessionTimeout: 300.0,
            compression: "zlib,none",
            knownHosts: "/etc/ssh/known_hosts",
            proxy: {
                host: "proxy.corporate.com",
                port: 8080,
                'type: ftp:HTTP,
                auth: {username: "proxy_user", password: "proxy_pass"}
            }
        };
    }
}

public function main() returns error? {
    Environment env = <Environment>os:getEnv("ENVIRONMENT");
    ftp:ClientConfiguration config = getClientConfig(env);
    ftp:Client client = check new(config);
    // Use client...
}
```

## Compatibility and Migration

- Existing `ftp:Client` and `sftp:Client` usage continues to work as-is.
- All new configurations are optional with safe defaults.
- Users can incrementally enable additional properties (timeouts, encoding, proxies, etc.) based on deployment needs.
- No migration or code changes are required unless a user explicitly opts in to new configurations.

## Risks and Assumptions

- **Timeouts**: Setting very low timeout values may cause premature failures. Defaults are tuned for typical production usage (connect: 30 s, data: 120 s, socket: 60 s).
- **Encoding**: Wrong `controlEncoding` or `fileNameEncoding` can lead to garbled file names. UTF-8 is default and works for most servers.
- **Passive mode**: Passive mode remains the default and is compatible with most modern FTP servers. It can be disabled if active mode is required.
- **Proxy credentials**: Proxy usernames and passwords are stored like standard FTP credentials. Sensitive values should be externalized via environment variables.
- **Known hosts**: If `knownHosts` is configured with an invalid path, the connection will log a warning and continue gracefully.
- **Compression**: Compression is disabled by default. Enabling it may reduce performance for binary files but helps with text-based transfers on slow networks.
- **Timezone**: Wrong `serverTimeZoneId` values may affect modification timestamps. Defaults to system timezone.
- **File type**: ASCII mode should only be used for legacy text servers. BINARY mode remains the safe default.
- **Configuration complexity**: Documentation will distinguish “Basic” and “Advanced” usage, with clear examples and recommended defaults.
- **Partial uploads**: Detection of incomplete or partially written files remains a listener-level responsibility, not part of this configuration set.
- **Large files**: For high-volume transfers, users are encouraged to use streaming APIs (`stream<byte[]>`) instead of buffering entire files.
- **Library stability**: Apache Commons VFS is a mature dependency; no breaking API changes are anticipated.
