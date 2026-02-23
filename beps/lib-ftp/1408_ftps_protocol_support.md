# Specification: FTPS Protocol Support

- **Owners:** @YasanPunch
- **Created date:** 2025-12-11
- **Updated date:** 2025-12-11
- **Issue:** [#1408](https://github.com/ballerina-platform/ballerina-spec/issues/1408)
- **State:** Submitted

## Summary
This specification documents the FTPS (FTP over SSL/TLS) protocol support in the Ballerina FTP library. FTPS extends the standard FTP protocol with SSL/TLS encryption to provide secure file transfer capabilities. This specification covers the configuration, initialization, and usage of FTPS clients and listeners, ensuring industry-standard security practices such as proper Protection Buffer Size (PBSZ) handling and secure data channel negotiation.

## Goals
- To provide comprehensive FTPS protocol support for secure file transfers.
- To support both **IMPLICIT** and **EXPLICIT** FTPS connection modes.
- To enable configurable data channel protection levels (PROT C, P, etc.).
- To ensure connection stability by enforcing required FTPS commands (e.g., `PBSZ 0`).
- To support SSL/TLS certificate management through Ballerina `crypto:KeyStore` and `crypto:TrustStore`.
- To maintain consistency with existing FTP and SFTP implementations.

## Motivation
While the library currently supports FTP (unsecured) and SFTP (SSH-based), enterprise environments widely use FTPS (FTP over SSL/TLS) for legacy compliance and secure integration. FTPS provides encryption for both control and data channels using SSL/TLS certificates, bridging the gap between legacy FTP infrastructure and modern security requirements.

## Description

### 1. Protocol Overview

FTPS uses SSL/TLS encryption layers over standard FTP. The library supports the two standard connection modes:

- **EXPLICIT FTPS (Standard)**: The client connects to the standard FTP port (typically 21). The client explicitly requests security by sending an `AUTH TLS` command immediately after the connection is established.

- **IMPLICIT FTPS (Legacy)**: The client connects to a dedicated SSL-enabled port (typically 990). The SSL/TLS handshake occurs immediately upon connection, before any FTP commands are sent.

### 2. Type Definitions

#### 2.1. Protocol Enum
The `Protocol` enum includes `FTPS` as a supported protocol:
```ballerina
public enum Protocol {
    FTP = "ftp",
    FTPS = "ftps",
    SFTP = "sftp"
}
```

#### 2.2. FTPS Mode Enum
Defines the connection negotiation strategy.

```ballerina
# FTPS connection mode.
# IMPLICIT - SSL/TLS connection is established immediately upon connection (typically port 990).
# EXPLICIT - Starts as regular FTP (typically port 21), then upgrades to SSL/TLS using AUTH TLS command.
public enum FtpsMode {
    IMPLICIT,
    EXPLICIT
}
```

#### 2.3. Data Channel Protection Enum
Controls the security of the actual file transfer stream.

```ballerina
# FTPS data channel protection level.
# Controls whether the data channel (file transfers) is encrypted.
# CLEAR - Data channel is not encrypted (PROT C). Authentication is secure, but file content is visible.
# PRIVATE - Data channel is encrypted (PROT P). Recommended for secure transfers.
# SAFE - Data channel has integrity protection only (PROT S). Rarely used.
# CONFIDENTIAL - Data channel is encrypted (PROT E). Treated similarly to PRIVATE.
public enum FtpsDataChannelProtection {
    CLEAR,
    PRIVATE,
    SAFE,
    CONFIDENTIAL
}
```

#### 2.4. SecureSocket Record
Configuration for SSL/TLS settings.

> **Note:** While `verifyHostname` is included in the API design for future compatibility and security best practices, the current implementation **does not enforce** hostname verification due to limitations in the underlying connector (Apache Commons VFS2).

```ballerina
# Secure socket configuration for FTPS (FTP over SSL/TLS).
# Used for configuring SSL/TLS certificates and keystores for FTPS connections.
#
# + key - Keystore configuration for client authentication (Mutual TLS).
# + trustStore - Truststore configuration for server certificate validation.
# + mode - FTPS connection mode (IMPLICIT or EXPLICIT). Defaults to EXPLICIT.
# + dataChannelProtection - Data channel protection level. Defaults to PRIVATE (encrypted).
# + verifyHostname - Whether to verify that the server certificate hostname matches the connection hostname.
#                    Defaults to `true`.
#                    Note: In the current version, this setting is not enforced by the underlying transport.
public type SecureSocket record {|
    crypto:KeyStore key?;
    crypto:TrustStore trustStore?;
    FtpsMode mode = EXPLICIT;
    FtpsDataChannelProtection dataChannelProtection = PRIVATE;
    boolean verifyHostname = true;
|};
```

#### 2.5. Updated AuthConfiguration Record
The `AuthConfiguration` record allows for protocol-specific security configurations.

```ballerina
public type AuthConfiguration record {|
    Credentials credentials?;
    PrivateKey privateKey?;
    SecureSocket secureSocket?;
    PreferredMethod[] preferredMethods = [PUBLICKEY, PASSWORD];
|};
```

**Important**: 
- `privateKey` can only be used with `SFTP` protocol.
- `secureSocket` can only be used with `FTPS` protocol.
- The library validates these combinations and returns an error if misconfigured.

### 3. Client Configuration

#### 3.1. FTPS Client Initialization

An FTPS client can be initialized by providing `ftp:FTPS` as the protocol and configuring the `secureSocket` in `auth`:

```ballerina
import ballerina/ftp;
import ballerina/crypto;

// FTPS client configuration
ftp:ClientConfiguration ftpsConfig = {
    protocol: ftp:FTPS,
    host: "ftps.example.com",
    port: 21, 
    auth: {
        credentials: {
            username: "ftpsuser",
            password: "ftpspassword"
        },
        secureSocket: {
            mode: ftp:EXPLICIT,
            dataChannelProtection: ftp:PRIVATE,
            trustStore: {
                path: "resources/truststore.p12",
                password: "truststorepassword"
            }
        }
    }
};

ftp:Client|ftp:Error ftpsClient = new(ftpsConfig);
```

#### 3.2. Configuration Options

**Mode Configuration:**
- `EXPLICIT` (default): Uses port 21, starts as regular FTP then upgrades to SSL/TLS.
- `IMPLICIT`: Uses port 990, SSL/TLS connection established immediately.

**Data Channel Protection:**
- `PRIVATE` (default): Encrypts data channel (PROT P) - Recommended.
- `CLEAR`: No encryption on data channel (PROT C) - Not recommended.
- `SAFE`: Integrity protection only (PROT S) - Rarely used.
- `CONFIDENTIAL`: Encrypts data channel (PROT E) - Similar to PRIVATE.

**Certificate Configuration:**
- `key`: KeyStore for client authentication (optional).
- `trustStore`: TrustStore for server certificate validation (optional but recommended).
- `verifyHostname`: Enable/disable hostname verification (default: true).

### 4. Listener Configuration

#### 4.1. FTPS Listener Initialization

An FTPS listener monitors a remote directory securely.

```ballerina
listener ftp:Listener ftpsListener = check new({
    protocol: ftp:FTPS,
    host: "ftps.example.com",
    port: 990, // Example for IMPLICIT mode
    path: "/remote/directory",
    auth: {
        credentials: {
            username: "ftpsuser",
            password: "ftpspassword"
        },
        secureSocket: {
            mode: ftp:IMPLICIT,
            dataChannelProtection: ftp:PRIVATE,
            trustStore: {
                path: "resources/truststore.p12",
                password: "truststorepassword"
            }
        }
    }
});
```

### 5. Implementation Details

#### 5.1. Connection Logic & Defaults

To ensure stability and security, the implementation adheres to the following logic:

1. **Port Selection:**
   If the user does not specify a port:
   - If mode is `IMPLICIT`, default to 990.
   - If mode is `EXPLICIT`, default to 21.

2. **Protocol Handshake (PBSZ/PROT):**
   When `dataChannelProtection` is set to `PRIVATE` (or anything other than `CLEAR`), the implementation **must** execute the `PBSZ 0` command immediately after authentication and before the `PROT` command. This is required by RFC 4217 and most FTP servers (e.g., vsftpd) to accept the protection level.

3. **NAT Workaround:**
   The implementation should enable passive mode NAT workarounds by default where supported, as FTPS encrypts the IP information in the PASV response, making it difficult for firewalls to rewrite addresses.

#### 5.2. Protocol Validation Rules
The `init` functions validate the configuration map:
- **Error:** `privateKey` provided with `FTPS` protocol.
- **Error:** `secureSocket` provided with `SFTP` or `FTP` protocol.

#### 5.3. VFS2 Integration
The implementation wraps Apache Commons VFS2:
- Uses `FtpsFileSystemConfigBuilder` for SSL context setup.
- Loads certificates from the Ballerina `crypto` module types into Java `KeyStore` objects before passing them to the VFS2 configuration.

### 6. Usage Examples

#### 6.1. Explicit FTPS (Most Common)

Explicit mode allows the server to support both standard FTP and FTPS on the same port.

```ballerina
ftp:ClientConfiguration config = {
    protocol: ftp:FTPS,
    host: "files.example.com",
    port: 21,
    auth: {
        credentials: { username: "user", password: "123" },
        secureSocket: {
            mode: ftp:EXPLICIT,
            dataChannelProtection: ftp:PRIVATE,
            verifyHostname: true, // Note: Not enforced in current version
            trustStore: { path: "certs/server-trust.p12", password: "pass" }
        }
    }
};
```

#### 6.2. Implicit FTPS (Legacy/Strict)

Forces SSL immediately. Usually requires port 990.

```ballerina
ftp:ClientConfiguration config = {
    protocol: ftp:FTPS,
    host: "files.example.com",
    port: 990, // Default for Implicit, but good to be explicit
    auth: {
        credentials: { username: "user", password: "123" },
        secureSocket: {
            mode: ftp:IMPLICIT,
            dataChannelProtection: ftp:PRIVATE,
            trustStore: { path: "certs/server-trust.p12", password: "pass" }
        }
    }
};
```

#### 6.3. Mutual TLS (Client Authentication)
Used when the server requires the client to present a certificate.

```ballerina
ftp:ClientConfiguration config = {
    protocol: ftp:FTPS,
    host: "secure.bank.com",
    auth: {
        credentials: { username: "user", password: "123" },
        secureSocket: {
            // Identity of the client
            key: { path: "certs/client-identity.p12", password: "keypass" },
            // Trusted CAs
            trustStore: { path: "certs/ca-trust.p12", password: "trustpass" }
        }
    }
};
```

### 7. Security Considerations

#### 7.1. Hostname Verification Limitation
**Critical Note:** In the initial release of this feature, **Hostname Verification is not implemented**. The implementation validates the certificate chain against the `trustStore` (verifying it was signed by a trusted CA), but it does not currently verify that the certificate's Common Name (CN) or Subject Alternative Name (SAN) matches the server's hostname. 
*Mitigation:* Use strictly controlled TrustStores containing only the specific certificates required for the target server, rather than generic public TrustStores.

#### 7.2. Data Channel Encryption
Users are strongly advised to leave `dataChannelProtection` at its default (`PRIVATE`). Setting this to `CLEAR` encrypts the password but transfers file contents in plain text, negating most benefits of FTPS.

#### 7.3. Certificate Management
-   Support is provided for PKCS12 and JKS formats via the Ballerina `crypto` module.
-   If `trustStore` is omitted, the connection may fail if the server uses a self-signed certificate, or it might default to the JVM's default trust store depending on the deployment environment. Explicit configuration is recommended.

### 8. Testing Scenarios

1.  **Implicit Mode**: Connect to a server on port 990. Verify handshake occurs immediately.
2.  **Explicit Mode**: Connect to port 21. Verify `AUTH TLS` is sent.
3.  **Data Protection**:
    -   Set to `PRIVATE`: Verify file transfer succeeds. (Requires `PBSZ 0` internal fix).
    -   Set to `CLEAR`: Verify file transfer succeeds (PROT C).
4.  **Mutual TLS**: Configure a server requiring client auth. Verify connection fails without `key` config and succeeds with it.
5.  **Invalid Certs**:
    -   Expired certificate (Should fail validation).
    -   Untrusted CA (Should fail validation if TrustStore is restrictive).

### 9. Limitations and Known Issues

-   **Hostname Verification**: Not enforced in VFS2 integration (as detailed in section 7.1).
-   **TLS Version Control**: The current API does not expose specific TLS version selection (e.g., forcing TLS 1.3 vs 1.2). The implementation relies on the JVM defaults and VFS2 negotiation.
-   **Proxy Support**: While the `Proxy` record exists, complex proxying (e.g., SOCKS5) combined with FTPS (Implicit mode) can be unstable due to strict timing in SSL handshakes.

### 10. Future Enhancements

-   Implement a custom `TrustManager` wrapper to enforce Hostname Verification.
-   Expose `protocols` and `ciphers` configuration in `SecureSocket` to allow users to enforce specific security standards (e.g., Custom SSL/TLS protocol versions, Disable TLS 1.1, etc.).
-   Support for Certificate Pinning.
- Advanced cipher suite configuration

## References

- [RFC 4217 - Securing FTP with TLS](https://tools.ietf.org/html/rfc4217)
- [Apache Commons VFS2 FTPS Provider](https://commons.apache.org/proper/commons-vfs/)
- [Ballerina Crypto Module](https://lib.ballerina.io/ballerina/crypto/latest)