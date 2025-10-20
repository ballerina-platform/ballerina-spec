# Improve Auth Configuration in FTP Client and Listener

- Authors
    - niveathika
- Reviewed by
    - TBD
- Created date
    - 2025-10-20
- Issue
    - [1393](https://github.com/ballerina-platform/ballerina-spec/issues/1393)
- State
    - Submitted

## Summary

This proposal restructures the authentication configuration model of the Ballerina FTP client to improve clarity and maintainability. The existing auth field in `ClientConfiguration`, which currently uses a single `AuthConfiguration` record, will be reorganized into distinct configuration records: `Credentials`, `SSLConfig`, and `SSHConfig`. This change makes the configuration model more expressive and easier to understand while preserving existing functionality and backward compatibility.

## Motivation

The current FTP client configuration in Ballerina defines authentication through a single `AuthConfiguration` record. While functional, this approach combines multiple concerns—credentials, secure socket options, and SFTP-specific configurations—into one field. This makes the configuration less intuitive, particularly for developers working with different authentication modes or secure transfer protocols.

By reorganizing the configuration to separate these concerns into `Credentials`, `SSLConfig`, and `SSHConfig`, the design becomes more readable and maintainable. It also aligns with configuration patterns used across other Ballerina standard library modules such as `HTTP` and `Email`, promoting a consistent developer experience. Furthermore, this clearer separation improves long-term extensibility, allowing future enhancements (for example, new key exchange methods or TLS extensions) without disrupting existing configurations.

## Goals

1. Simplify and clarify the authentication configuration structure of the FTP client.

2. Separate credentials, TLS/SSL, and SSH configuration concerns into distinct records.

3. Align the FTP client configuration model with patterns used in other Ballerina standard library modules (e.g., HTTP, Email).

4. Improve maintainability and readability of the configuration schema.

5. Enable easier future extensions (e.g., support for additional secure connection options) without introducing breaking changes.

## Non-Goals

1. Introducing new authentication mechanisms or protocols beyond those currently supported by the FTP client (e.g., no new SFTP or FTPS features are added).

2. Modifying existing runtime behavior or connection logic of the FTP client.

3. Deprecating or removing existing configuration options; instead, this proposal focuses solely on reorganizing them for clarity.

4. Changing server-side behavior or the way credentials are validated.

>> Note: The intent of this BEP is strictly structural — to improve the configuration schema for better readability, modularity, and future extensibility.

## Design

### Current Configuration

The current `ClientConfiguration` record defines authentication using a single auth field of type `AuthConfiguration`. This record encapsulates all authentication-related data, which makes it less expressive when handling different secure connection types such as SFTP or FTPS.

```ballerina
public type ClientConfiguration record {|
    Protocol protocol = FTP;
    string host = "127.0.0.1";
    int port = 21;
    AuthConfiguration auth?;
    boolean userDirIsRoot = false;
|};

public type AuthConfiguration record {|
    Credentials credentials?;
    PrivateKey privateKey?;
    PreferredMethod[] preferredMethods = [PUBLICKEY, PASSWORD];
|};
```

This structure provides a basic authentication model but lacks clear separation between credential-based, secure-socket, and SSH-specific configurations.

### Proposed configuration

This proposal introduces a reorganized configuration structure that separates authentication concerns into distinct fields within the FTP client configuration.

```ballerina
public type ClientConfiguration record {|
    Protocol protocol = FTP;
    string host = "127.0.0.1";
    int port = 21;

    # User name and password authentication details
    Credentials auth?;
    # SSL/TLS configuration for FTPS connections
    SSLConfig sslConfig?;
    # SSH configuration for SFTP connections
    SSHConfig sftpConfig?;

    boolean userDirIsRoot = false;
|};

# User name and password authentication details
# 
# + username - User name
# + password - Password
type Credentials record {|
    string username;
    string password?;
|};

# SSL/TLS configuration for FTPS connections
# 
# + cert - Trust store configuration
# + key - Key store configuration
type SSLConfig record {|
    crypto:TrustStore cert;
    crypto:KeyStore key?;
|};

# SSH configuration for SFTP connections
# 
# + privateKey - Private key authentication details
# + strictHostKeyChecking - If `true`, enables strict host key checking
# + preferredMethod - Preferred authentication methods
# + knownHosts - Path to known_hosts file
type SSHConfig record {|
    ftp:PrivateKey privateKey?;
    boolean strictHostKeyChecking = true;
    ftp:PreferredMethod[] preferredMethod = [ftp:PUBLICKEY, ftp:PASSWORD];
    string knownHosts?;                    
|};
```

## Usage Examples

### Example 1: Connecting to Annoymous FTP

```ballerina
ClientConfiguration anonConfig = {
    protocol: ftp:FTP,
    host: "127.0.0.1",
    port: 21210
};
```

### Example 2: Connecting to Annoymous FTPs

```ballerina
ClientConfiguration anonConfigWithFTPs = {
    protocol: ftp:FTP,
    host: "127.0.0.1",
    port: 21210,
    secureSocket: {
      cert: {
        path: "/path/to/cert",
        password: "passphrase"
    }}
};

```

### Example 3: Connecting to FTPs with credentials

```ballerina
ClientConfiguration ftpsConfig = {
    protocol: ftp:FTP,
    host: "127.0.0.1",
    port: 21210,
    auth: {
        username: "user",
        password: "pass"
    },
    secureSocket: {
      cert: {
        path: "/path/to/cert",
        password: "passphrase"
    }}
};
```

### Example 4: SFTP (Self signed cert) with credentials

```ballerina
ClientConfiguration sftpConfig = {
    protocol: ftp:SFTP,
    host: "127.0.0.1",
    port: 2222,
    auth: {
        username: "user",
        password: "pass"
    }
};
```

### Example 5: SFTP with credentials

```ballerina
ClientConfiguration sftpConfigWithPrivateKey = {
    protocol: ftp:SFTP,
    host: "127.0.0.1",
    port: 2222,
    auth: {
        username: "user"
    },
    sftpConfig: {
        privateKey: {
            path: "/path/to/private/key",
            password: "privateKeyPassword"
        }
    }
};
```

## Compatibility and Migration

- The existing AuthConfiguration type will be refactored into Credentials.
- The ClientConfiguration.auth field will change its type accordingly.
- Internal validation and connection logic will map Credentials, SecureSocket, and SSHConfig fields to the corresponding transport initialization routines.
- Documentation and examples will be updated to reflect the new configuration structure.

>> Note: Existing user code may require minimal updates to rename or restructure configuration fields. The runtime behavior of the FTP client remains unchanged.

## Risks and Assumptions

- The existing `AuthConfiguration` type will be refactored into Credentials.
- The `ClientConfiguration.auth` field will change its type accordingly.
- Internal validation and connection logic will map `Credentials`, `SSLConfig`, and `SSHConfig` fields to the corresponding transport initialization routines.

>> Note: Existing user code may require minimal updates to rename or restructure configuration fields. The runtime behavior of the FTP client remains unchanged.
