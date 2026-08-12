# Introduce Azure Files Connector

- Authors
  - Yasan Punchihewa
- Reviewed by
- Created date
  - 2026-07-13
- Updated date
  - 2026-08-12
- Issue
  - [#1457](https://github.com/ballerina-platform/ballerina-spec/issues/1457)
- State
  - Submitted

## Summary

Ballerina's current support for Azure Files lives inside `ballerinax/azure_storage_service`, a combined package that re-implements the Azure Storage REST protocol (Shared Key signing, chunked transfer, error handling) by hand and is pinned to the 2019-12-12 API version. This proposal introduces **ballerinax/azure.storage.files**, a standalone connector for [Azure Files](https://learn.microsoft.com/en-us/azure/storage/files/storage-files-introduction) built on Microsoft's official `com.azure:azure-storage-file-share` Java SDK. It provides a two-tier client (`AdminClient` for account-level operations, `Client` bound to one share) covering the full Azure Files surface — share lifecycle and service configuration, directory and file CRUD, transfers, copies, byte ranges, share snapshots, leases, SMB handles, stored access policies, SDDL permissions, SAS generation, and NFS links — a polling `Listener` for event-driven services, a union-typed authentication model spanning Shared Key, SAS, connection strings, and Microsoft Entra ID, and a consistent error hierarchy. It is the sibling of `ballerinax/azure.storage.blob` and shares its design conventions.

## Motivation

The existing `azure_storage_service.files` module has accumulated several problems:

1. **Hand-written protocol layer:** Shared Key signing, chunked upload, and response parsing are implemented in Ballerina and pinned to the 2019-12-12 REST API version. Every protocol fix and every new service capability must be re-implemented by hand.
2. **Fully in-memory transfers:** `getFile` buffers the entire file before writing to disk, and the hand-rolled chunked upload both swallows failures in a logging side effect and carries a chunk-size discrepancy between its two size constants.
3. **Ambiguous configuration:** the auth record makes every field optional (`accessKeyOrSAS?`, `accountName?`), so misconfiguration surfaces as a runtime failure instead of a compile error.
4. **Inconsistent error handling:** error subtypes are defined but applied inconsistently, and an empty directory listing is raised as an error even though it is a valid state.
5. **No event-driven support:** there is no listener, so applications that react to files arriving in a share must hand-roll polling.
6. **No tests in CI:** the legacy tests are live-only and CI skips them entirely.
7. **Combined packaging:** file support is a submodule of a package that also covers Blob, so users pull one large artifact for one service, against the prevailing one-package-per-service pattern of the Azure ecosystem.

Microsoft's own SDKs solve the protocol problems once, centrally: `azure-storage-file-share` encapsulates signing, SAS construction, retry policies, parallel chunked transfer, connection-string parsing, and parity with new REST API versions. Wrapping the SDK instead of the REST API means the connector inherits all of this and Microsoft remains responsible for maintaining it.

## Goals

* Provide an idiomatic Ballerina API for the full Azure Files surface: share lifecycle and service configuration, directory and file CRUD, upload/download (disk, in-memory, stream), listing, properties and metadata, rename/move, copy, byte ranges, share snapshots, leases, SMB handles, stored access policies, SDDL permissions, SAS generation, and NFS links.
* Match Microsoft's two-tier mental model: `AdminClient` for account-level operations and `Client(shareName)` for everything inside one share.
* Provide a polling `Listener` (there is no Event Grid source for Azure Files) with a `Caller` so handlers can act on the event's file without constructing a separate client.
* Provide a union-typed authentication model where each member is exactly one real-world credential artifact and misconfiguration is a compile error.
* Provide a consistent, pattern-matchable error hierarchy keyed on the Azure error code.
* Be a strict superset of the file surface of the existing `azure_storage_service` connector, so existing users can migrate with no loss of functionality.

## Non-Goals

- **No Blob, Queue, or Table support.** Blob is the sibling package `azure.storage.blob`; Queue and Table would be their own future packages.
- **No re-implementation of the wire protocol.** Authentication, signing, retry, and chunked transfer are delegated to the official SDK.

## Design

### 1. Module overview

The module is `ballerinax/azure.storage.files`. The hierarchical name groups it with its sibling `azure.storage.blob`, following the pattern of `azure.openai.chat` and `azure.openai.responses`. The package has two parts: a `ballerina/` module holding the public API and a `native/` Java subproject that adapts it onto `com.azure:azure-storage-file-share`.

Microsoft's SDK is structured as a chain of four clients (`ShareServiceClient` account scope, `ShareClient` share scope, `ShareDirectoryClient`, `ShareFileClient`). The connector exposes the two scopes users actually think in, plus two types for event-driven services:

- **`AdminClient`**: account level. List, create, delete, and restore shares. Used by admin tooling and applications that work with multiple shares.
- **`Client`**: bound to one share at `init`. All directory, file, transfer, copy, and range operations, plus share-level properties and metadata. This is the client most applications instantiate.
- **`Listener`**: polls one watched path on a share and dispatches each present file to the matching content handler of its attached service.
- **`Caller`**: passed to each listener handler. It forwards a curated share-scoped subset of `Client`, so a handler can act on the event's file without constructing a separate client.

The lower SDK levels are not surfaced as classes. Directory and file operations are methods on `Client` taking a single slash-delimited, share-relative `path` (for example `"/reports/2026/q4.pdf"`); the Java adaptor splits the path into the segments the SDK requires. Where two paths co-occur they are named `sourcePath` and `destinationPath` in logical source-first order.

`AdminClient`, `Client`, and `Caller` are isolated client classes holding only immutable configuration, and the `Listener` is an isolated class, so a single instance of any of them can be used safely from concurrent strands. Every operation that calls the service is a `remote` method, invoked with `->`. Methods that make no service call are ordinary methods, invoked with `.`: the `Listener`'s lifecycle methods and the SAS generation methods, which sign tokens locally with the credential the client already holds. The clients hold no releasable resources, so there is no close method; a client that is no longer needed is simply discarded. The `isolated` qualifier is omitted from the signatures below for brevity.

Because `azure-storage-blob` and `azure-storage-file-share` depend on the same `azure-storage-common` artifact, splitting Blob and Files into two Ballerina packages duplicates nothing at the JVM level: the auth, signing, and retry layer is shared by Microsoft's own packaging.

### 2. Authentication

#### 2.1 The `AuthConfig` union

Each union member is exactly one real-world credential artifact, the thing the portal, CLI, or IaC tooling actually hands the user:

```ballerina
# The authentication configuration: exactly one credential-artifact record.
public type AuthConfig SharedKeyConfig|SasConfig|SasUrlConfig|ConnectionStringConfig|EntraIdConfig;
```

Every member has a unique required field or field combination, so both the compiler and `Config.toml` select the right member by structural matching, with no discriminator field. The two Microsoft Entra ID chain records (`DefaultEntraIdConfig` and `ManagedIdentityConfig`), which would otherwise share the same field shape, are the exception: they carry a `kind` discriminator.

```toml
# The fields present select the union member:
[myapp.filesConfig]
auth = {accountName = "myacct", accountKey = "..."}               # SharedKeyConfig
# auth = {accountName = "myacct", sasToken = "sv=..."}            # SasConfig
# auth = {sasUrl = "https://myacct.file.core.windows.net/?sv=..."}# SasUrlConfig
# auth = {connectionString = "..."}                               # ConnectionStringConfig
# auth = {kind = "default", accountName = "myacct"}               # DefaultEntraIdConfig
# auth = {kind = "managed-identity", accountName = "myacct"}      # ManagedIdentityConfig
# auth = {accountName = "myacct", tenantId = "...", clientId = "...", clientSecret = "..."}                # ClientSecretConfig
# auth = {accountName = "myacct", tenantId = "...", clientId = "...", certificatePath = "/path/cert.pem"}  # ClientCertificateConfig
# auth = {accountName = "myacct", tenantId = "...", clientId = "...", tokenFilePath = "/path/token"}       # WorkloadIdentityConfig
```

Every auth mode is validated at `init` with local computation and no call to Azure: connection strings run the SDK's own strict parser plus a file-endpoint check, and the explicit records get non-empty, base64, and URL-scheme checks. A malformed credential surfaces a specific error at `init` rather than an opaque failure at first use.

#### 2.2 Credential records

```ballerina
# Authenticates with the storage account name and key (Shared Key).
public type SharedKeyConfig record {|
    # Storage account name, the signing identity
    string accountName;
    # Storage account access key (base64)
    string accountKey;
    # Overrides where requests are sent (sovereign clouds, private endpoints,
    # local test endpoints); defaults to `https://{accountName}.file.core.windows.net`
    string serviceUrl?;
|};

# Authenticates with a bare shared access signature (SAS) token.
public type SasConfig record {|
    # Storage account name, used to derive the service URL
    string accountName;
    # The SAS token, e.g. `sv=...&sig=...`
    string sasToken;
|};

# Authenticates with a fused SAS URL as generated by the Azure portal
# (endpoint and token in one string).
public type SasUrlConfig record {|
    # The full File service SAS URL
    string sasUrl;
|};

# Authenticates with a storage account connection string. The endpoint is
# part of the string, so no separate account name is needed.
public type ConnectionStringConfig record {|
    # The connection string as shown in the portal
    string connectionString;
|};
```

#### 2.3 Microsoft Entra ID

`EntraIdConfig` is itself a union of five records, one per Entra ID credential kind:

```ballerina
public type EntraIdConfig DefaultEntraIdConfig|ManagedIdentityConfig|ClientSecretConfig|
    ClientCertificateConfig|WorkloadIdentityConfig;
```

Azure Files honors OAuth tokens only on requests carrying the backup intent, which the connector sets automatically. The intent bypasses file and directory ACLs and requires the identity to hold the `Storage File Data Privileged Reader` or `Storage File Data Privileged Contributor` role. Those roles cover the file and directory data operations; share-level and account-level management operations (the `AdminClient` surface, and the `Client` operations on the share itself) authorize against the storage account's management role actions instead (`Microsoft.Storage/storageAccounts/fileServices/shares/` read, write, and delete, carried by roles such as `Contributor`), so an identity covering the full surface holds both a privileged data role and a management role.

```ballerina
# The credential-kind discriminator value selecting `DefaultEntraIdConfig`.
public const DEFAULT_AZURE_CREDENTIAL = "default";

# The credential-kind discriminator value selecting `ManagedIdentityConfig`.
public const MANAGED_IDENTITY = "managed-identity";

# Authentication through the default credential chain, which tries the environment,
# a managed identity, and developer sign-ins in turn.
public type DefaultEntraIdConfig record {|
    # Selects the default credential chain
    DEFAULT_AZURE_CREDENTIAL kind;
    # The storage account name (determines the service URL unless `serviceUrl` overrides it)
    string accountName;
    # The file service endpoint URL; omit for `https://{accountName}.file.core.windows.net`
    string serviceUrl?;
|};

# Authentication as an Azure managed identity, for workloads running on Azure compute.
public type ManagedIdentityConfig record {|
    # Selects the managed-identity credential
    MANAGED_IDENTITY kind;
    # The storage account name (determines the service URL unless `serviceUrl` overrides it)
    string accountName;
    # The client id of a user-assigned managed identity; omit for the system-assigned identity
    string clientId?;
    # The file service endpoint URL; omit for `https://{accountName}.file.core.windows.net`
    string serviceUrl?;
|};

# Authentication as a service principal with a client secret.
public type ClientSecretConfig record {|
    # The storage account name (determines the service URL unless `serviceUrl` overrides it)
    string accountName;
    # The Entra ID tenant (directory) id
    string tenantId;
    # The application (client) id of the service principal
    string clientId;
    # The client secret of the service principal
    string clientSecret;
    # The file service endpoint URL; omit for `https://{accountName}.file.core.windows.net`
    string serviceUrl?;
|};

# Authentication as a service principal with a client certificate.
public type ClientCertificateConfig record {|
    # The storage account name (determines the service URL unless `serviceUrl` overrides it)
    string accountName;
    # The Entra ID tenant (directory) id
    string tenantId;
    # The application (client) id of the service principal
    string clientId;
    # The path to the certificate file (PEM, or PFX when `certificatePassword` is set)
    string certificatePath;
    # The password protecting the certificate file, when it has one
    string certificatePassword?;
    # The file service endpoint URL; omit for `https://{accountName}.file.core.windows.net`
    string serviceUrl?;
|};

# Workload-identity authentication, for Kubernetes workloads federated with Entra ID.
public type WorkloadIdentityConfig record {|
    # The storage account name (determines the service URL unless `serviceUrl` overrides it)
    string accountName;
    # The Entra ID tenant (directory) id
    string tenantId;
    # The application (client) id federated with the workload
    string clientId;
    # The path to the file holding the federated service-account token
    string tokenFilePath;
    # The file service endpoint URL; omit for `https://{accountName}.file.core.windows.net`
    string serviceUrl?;
|};
```

#### 2.4 Client configuration

Both clients take the same configuration record. `config` is an included record parameter on both `init` methods, so callers pass its fields as named arguments, e.g. `new (auth = {accountName, accountKey})`.

```ballerina
public type ClientConfiguration record {|
    # The authentication configuration (see `AuthConfig`)
    AuthConfig auth;
    # Retry behaviour for service requests; omit for the service defaults
    RetryConfig retryConfig?;
    # HTTP transport settings (proxy, connection pool, TLS); omit for the defaults
    TransportConfig transportConfig?;
|};
```

#### 2.5 Retry configuration

Retry behaviour for service requests. Omitting the record leaves the default retry behaviour in place.

```ballerina
public type RetryConfig record {|
    # How the delay between tries grows (`EXPONENTIAL` or `FIXED`)
    RetryPolicyType retryPolicyType = EXPONENTIAL;
    # The maximum number of tries (the first attempt plus retries)
    int maxTries = 4;
    # The timeout applied to each individual try, in seconds
    decimal tryTimeoutSeconds = 60;
    # The base delay between tries, in seconds
    decimal retryDelaySeconds = 4;
    # The upper bound on the delay between tries, in seconds
    decimal maxRetryDelaySeconds = 120;
    # A secondary endpoint to retry reads against (geo-redundant accounts)
    string secondaryHostUrl?;
|};
```

#### 2.6 Transport configuration

HTTP transport settings: proxying, connection pooling, and TLS.

```ballerina
public type TransportConfig record {|
    # Route traffic through this proxy
    ProxyConfig proxy?;
    # Connection-pool tuning
    ConnectionPoolConfig connectionPool = {};
    # Custom TLS settings (trust and key material, verification)
    SecureSocket secureSocket?;
|};
```

`ProxyConfig` routes the connector's traffic through an HTTP, SOCKS4, or SOCKS5 proxy, with optional credentials and a bypass list. `ConnectionPoolConfig` tunes the maximum number of concurrent connections and the idle, connect, and read timeouts. `SecureSocket` configures custom trust material (a truststore or a PEM certificate path), a client identity for mutual TLS (a keystore or a `CertKey` certificate and key pair), the offered TLS versions and cipher suites, host-name verification, session reuse, revocation checking, an SNI host name, and handshake and session timeouts.

### 3. The `AdminClient`

The `AdminClient` manages the shares within a storage account: the share lifecycle, the account's file-service configuration, and account-level SAS tokens. For operations scoped to a single share, use `Client`.

```ballerina
public function init(*ClientConfiguration config) returns Error?;

# Returns false only when Azure confirms absence (404); an Error means the
# check itself could not complete, so an auth problem is never misreported
# as a missing share.
remote function hasShare(string shareName) returns boolean|Error;

# createShare accepts a quota, an access tier, the protocols to enable (SMB
# and/or NFS), the NFS root-squash setting, and metadata. deleteShare is soft
# under the account's soft-delete retention policy; find restorable shares
# and their versions with listShares({includeDeleted: true}) and restore them
# with undeleteShare.
remote function listShares(ShareListOptions? options = ()) returns ShareInfo[]|Error;
remote function createShare(string shareName, ShareCreateOptions? options = ()) returns Error?;
remote function deleteShare(string shareName, ShareDeleteOptions? options = ()) returns Error?;
remote function undeleteShare(string shareName, string version) returns Error?;

# ServiceProperties covers the account's request-metrics collection, CORS
# rules, and protocol settings. The service applies the record as a whole,
# so read the current configuration, modify it, and pass the result back.
remote function getServiceProperties() returns ServiceProperties|Error;
remote function setServiceProperties(ServiceProperties properties) returns Error?;

# Requires a client authenticated with Microsoft Entra ID whose identity
# holds the Storage File Delegator role; the key is valid at most 7 days and
# signs user-delegation SAS tokens (see 4.13).
remote function getUserDelegationKey(time:Utc startTime, time:Utc expiryTime) returns UserDelegationKey|Error;

# Ordinary method (invoked with `.`): signs the token locally with the
# account key, no service call. Requires SharedKeyConfig (or a connection
# string carrying an account key); rotating the account key revokes every
# SAS minted from it.
function generateAccountSas(AccountSasSignatureValues values) returns string|Error;
```

### 4. The `Client`

```ballerina
public function init(string shareName, *ClientConfiguration config) returns Error?;
```

Binding is lazy: `init` makes no call to Azure, so the first operation against a nonexistent share fails with `NotFoundError`; the up-front check is `AdminClient.hasShare`.

A method name carries the `File` token either to disambiguate a verb that also exists for directories (`createFile` next to `createDirectory`) or to keep a bare verb from implying it handles directories when it is file-only (`uploadFile`, `downloadFile`, `copyFile`). Verbs whose object is already explicit stay bare (`uploadContent`, `uploadRange`, `setContentHeaders`), and `list` is deliberately tier-neutral because it returns files and directories in one stream.

#### 4.1 Share-level operations

```ballerina
# Metadata is free-form, user-defined annotation; Azure stores and returns it
# verbatim. setShareMetadata replaces the complete metadata set, and metadata
# is read back through getShareProperties.
remote function getShareProperties() returns ShareProperties|Error;
remote function setShareMetadata(map<string> metadata) returns Error?;
remote function getShareUsage() returns int|Error;   // approximate stored bytes
```

#### 4.2 Directory operations

```ballerina
# deleteDirectory requires the directory to be empty. hasDirectory follows
# the same semantics as hasShare: false only on a confirmed 404, an Error
# when the check itself fails.
remote function createDirectory(string directoryPath, DirectoryCreateOptions? options = ()) returns Error?;
remote function deleteDirectory(string directoryPath) returns Error?;
remote function hasDirectory(string directoryPath) returns boolean|Error;
remote function getDirectoryProperties(string directoryPath) returns DirectoryProperties|Error;
remote function setDirectoryMetadata(string directoryPath, map<string> metadata) returns Error?;

# Lists a directory's entries, files and subdirectories, as one lazy stream,
# so memory stays bounded on large directories. Every Entry carries its full
# share-relative path and an isDirectory flag, so entries feed directly into
# the path-taking operations. ListOptions offers a name prefix, recursion,
# page sizing, extended info (ETag and timestamps), and a snapshotId to list
# from a share snapshot.
remote function list(string directoryPath, ListOptions? options = ()) returns stream<Entry, Error?>|Error;

# Rename doubles as move: the destination is a full share-relative path, so
# "/X/A" to "/Y/A" re-parents within the same share. A directory can never
# overwrite an existing directory; with RenameOptions.replaceIfExists it may
# overwrite an existing file at the destination. Moving across shares is not
# possible.
remote function renameDirectory(string sourcePath, string destinationPath, RenameOptions? options = ()) returns Error?;
```

#### 4.3 File operations

```ballerina
# createFile provisions an empty file of a fixed size; content is written
# separately via the transfer or range operations. Metadata is read via
# `getFileProperties().metadata`; only a setter is exposed.
remote function createFile(string path, int sizeInBytes, CreateOptions? options = ()) returns Error?;
remote function deleteFile(string path) returns Error?;
remote function hasFile(string path) returns boolean|Error;
remote function getFileProperties(string path) returns FileProperties|Error;
remote function setFileMetadata(string path, map<string> metadata) returns Error?;
# Replaces the complete content-header set (Content-Type, Cache-Control, and
# the other standard headers): any header omitted is cleared.
remote function setContentHeaders(string path, ContentHeaders headers) returns Error?;
# Overwrites an existing destination file only when
# RenameOptions.replaceIfExists is set; an existing destination directory
# always fails the operation.
remote function renameFile(string sourcePath, string destinationPath, RenameOptions? options = ()) returns Error?;
```

#### 4.4 Transfer operations

```ballerina
# uploadFile copies a local file to the share and downloadFile copies a share
# file to a local path; neither deletes its source. Both take full paths
# including the file name, in source-first order. uploadContent takes in-memory
# content (byte[]/string written as-is, xml in its textual form, map<json> as a
# JSON document, string[][] as CSV rows in the dialect getFileCsv reads back).
# uploadFromStream requires contentLength because Azure Files pre-allocates a
# file at a fixed size before content is written into its ranges; a
# source-stream failure, or a stream whose length does not match contentLength,
# surfaces as a client-side Error, and the pre-allocated file, holding whatever
# ranges were written before the failure, stays at the destination for the
# caller to inspect, overwrite, or delete. The transfer methods chunk
# internally (small source chunks coalesce into range writes of the service's
# maximum range size), and getFileContent reads lazily, so memory stays bounded
# for any file size. downloadFile fails with a client-side Error when a local
# file already exists at destinationPath. DownloadOptions offers a byte range
# and a snapshotId to read from a share snapshot.
remote function uploadFile(string sourcePath, string destinationPath, UploadOptions? options = ()) returns Error?;
remote function uploadContent(byte[]|string|xml|map<json>|string[][] content, string destinationPath, UploadOptions? options = ()) returns Error?;
remote function uploadFromStream(stream<byte[], error?> content, int contentLength, string destinationPath, UploadOptions? options = ()) returns Error?;
remote function downloadFile(string sourcePath, string destinationPath, DownloadOptions? options = ()) returns Error?;
remote function getFileContent(string path, DownloadOptions? options = ()) returns stream<byte[], Error?>|Error;

# The typed reads materialize the file's full content and bind it to the
# caller-directed target type: getFileText decodes UTF-8 text, getFileJson
# binds a JSON document to a json form or a record, getFileXml binds to an xml
# value or a record projected from the document, and getFileCsv binds to
# string[][] rows or to a record array whose field names come from the file's
# header row (the string-matrix form keeps every row, including the first).
# Binding is strict: content that does not match the target type fails with a
# client-side Error.
remote function getFileText(string path, DownloadOptions? options = ()) returns string|Error;
remote function getFileJson(string path, DownloadOptions? options = (), typedesc<json|record {}> targetType = <>) returns targetType|Error;
remote function getFileXml(string path, DownloadOptions? options = (), typedesc<xml|record {}> targetType = <>) returns targetType|Error;
remote function getFileCsv(string path, DownloadOptions? options = (), typedesc<string[][]|record {}[]> targetType = <>) returns targetType|Error;
```

#### 4.5 Copy operations

```ballerina
# Copies are asynchronous: inspect the returned CopyInfo.copyStatus and, if
# pending, observe progress with checkCopyStatus (which returns () when the
# file has never been a copy destination) or cancel with abortCopy. copyFile
# copies within the bound share under this client's credentials.
# copyFileFromUrl copies from an external URL: a source in a different
# storage account, or any blob source, must carry its own authorization in
# the URL (typically a SAS token).
remote function copyFile(string sourcePath, string destinationPath, CopyOptions? options = ()) returns CopyInfo|Error;
remote function copyFileFromUrl(string sourceUrl, string destinationPath, CopyOptions? options = ()) returns CopyInfo|Error;
remote function checkCopyStatus(string path) returns CopyStatusInfo?|Error;
remote function abortCopy(string path, string copyId) returns Error?;
```

#### 4.6 Range operations

```ballerina
# uploadRange is a single Put Range (at most 4 MiB) with no chunking; for
# content of arbitrary size, use the transfer operations. clearRange frees
# the underlying storage; storage deallocates in 512-byte units, so a smaller
# cleared span is zeroed but may still appear in listRanges until the whole
# unit is cleared. listRanges returns the valid (written) byte ranges of a
# file, each with inclusive start and end offsets.
remote function uploadRange(string path, int offset, byte[] content) returns Error?;
remote function clearRange(string path, int offset, int length) returns Error?;
remote function listRanges(string path, RangeListOptions? options = ()) returns Range[]|Error;
```

#### 4.7 Share snapshot operations

A share snapshot is a point-in-time, read-only copy of the whole share. Snapshot contents are read through the regular read operations: pass the returned `snapshotId` in `DownloadOptions` (`downloadFile`, `getFileContent`) or `ListOptions` (`list`) to resolve the same paths inside the snapshot instead of the live share.

```ballerina
# The snapshot operations are account-scoped: createShareSnapshot,
# listShareSnapshots, and deleteShareSnapshot all need account-level
# credentials (an account key, a connection string carrying one, or an
# account SAS; a share-scoped SAS is not sufficient).
remote function createShareSnapshot(map<string>? metadata = ()) returns ShareSnapshotInfo|Error;
remote function listShareSnapshots() returns ShareSnapshotInfo[]|Error;
remote function deleteShareSnapshot(string snapshotId) returns Error?;

# Reports which of a file's ranges were written and which were cleared since
# a baseline snapshot, for incremental backup on top of snapshots.
remote function listRangesDiff(string path, string previousSnapshotId, RangeListOptions? options = ()) returns RangeDiff|Error;
```

#### 4.8 Lease operations

A share lease locks the share against deletion by anyone not holding the lease id; it is fixed-duration (15 to 60 seconds) or infinite (-1) and is kept alive with `renewShareLease`. A file lease locks the file against writes and deletion; it is always infinite, so it takes no duration and has no renew. The break operations reclaim a lease without needing its id, for when the holder is gone: a share lease keeps running for `breakPeriodSeconds` (or its own remaining time) before breaking, while a file lease breaks immediately.

```ballerina
// Share leases
remote function acquireShareLease(int leaseDurationSeconds, string? proposedLeaseId = ()) returns string|Error;
remote function renewShareLease(string leaseId) returns Error?;
remote function releaseShareLease(string leaseId) returns Error?;
remote function breakShareLease(int? breakPeriodSeconds = ()) returns int|Error;
remote function changeShareLease(string leaseId, string proposedLeaseId) returns string|Error;

// File leases
remote function acquireLease(string path, string? proposedLeaseId = ()) returns string|Error;
remote function releaseLease(string path, string leaseId) returns Error?;
remote function breakLease(string path) returns Error?;
remote function changeLease(string path, string leaseId, string proposedLeaseId) returns string|Error;
```

#### 4.9 SMB handle operations

Handles are opened by SMB clients (mounted drives); REST operations through this connector do not hold handles. The force-close operations release locks whose holders are gone or unresponsive, closing one handle by id or, when `handleId` is absent, all handles on the target; the affected SMB clients receive an error on their next operation.

```ballerina
remote function listFileHandles(string path) returns HandleInfo[]|Error;
remote function forceCloseFileHandles(string path, string? handleId = ()) returns CloseHandlesInfo|Error;
remote function listDirectoryHandles(string directoryPath) returns HandleInfo[]|Error;
# recursive additionally closes handles throughout the directory's subtree.
remote function forceCloseDirectoryHandles(string directoryPath, string? handleId = (), boolean recursive = false) returns CloseHandlesInfo|Error;
```

#### 4.10 Property update operations

These update properties after creation; only what is set is changed, and every omitted field keeps the current value.

```ballerina
# Changes the share's quota or access tier; administrative, needs
# account-level credentials, and fails with an AuthorizationError on a
# share-scoped SAS.
remote function setShareProperties(ShareSetPropertiesOptions options) returns Error?;
# Covers content headers, SMB properties, an SDDL permission, a new file size
# (growing pre-allocates, shrinking truncates), and POSIX attributes.
remote function setFileProperties(string path, FileSetPropertiesOptions options) returns Error?;
# Covers SMB properties, an SDDL permission, and POSIX attributes.
remote function setDirectoryProperties(string directoryPath, DirectorySetPropertiesOptions options) returns Error?;
```

#### 4.11 Access policy operations

A stored access policy carries a validity window and a permission string under an identifier. Share SAS tokens minted against a policy (via the `identifier` field of the signature values) inherit its window and permissions, so removing or editing a policy immediately revokes or changes every SAS minted against it.

```ballerina
remote function getShareAccessPolicy() returns SignedIdentifier[]|Error;
# Replaces the complete set, at most five per share.
remote function setShareAccessPolicy(SignedIdentifier[] identifiers) returns Error?;
```

#### 4.12 Permission operations

The share carries a permission store of security descriptors (SDDL strings). `createSharePermission` stores a descriptor and returns its key, so the same permission can be applied to many files via `SmbProperties.filePermissionKey` without repeating the descriptor; `getSharePermission` reads a stored descriptor back by key.

```ballerina
remote function getSharePermission(string permissionKey) returns string|Error;
remote function createSharePermission(string sddlPermission) returns string|Error;
```

#### 4.13 SAS generation

The SAS generation methods are ordinary methods, invoked with `.`: signing happens locally with the credential the client holds, and no call is made to Azure.

```ballerina
function generateShareSas(ShareSasSignatureValues values) returns string|Error;
function generateSas(string path, FileSasSignatureValues values) returns string|Error;
function generateShareUserDelegationSas(ShareSasSignatureValues values, UserDelegationKey key) returns string|Error;
function generateUserDelegationSas(string path, FileSasSignatureValues values, UserDelegationKey key) returns string|Error;
```

`generateShareSas` and `generateSas` sign with the account key, so the client must be authenticated with `SharedKeyConfig` (or a connection string carrying an account key); rotating the account key revokes every SAS minted from it. The signature values carry the validity window, the permissions, and optionally a protocol restriction, an IP range, or a stored access policy `identifier` in place of an explicit expiry and permissions; generation fails with an `Error` when neither the identifier nor both `expiryTime` and `permissions` are supplied. The user-delegation variants sign with a `UserDelegationKey` (from `AdminClient.getUserDelegationKey`) instead of the account key, so no storage key is ever handled; they are valid at most 7 days (the key's lifetime), and stored access policies do not apply to them: the user-delegation variants reject an `identifier` and require an explicit `expiryTime` and `permissions`.

#### 4.14 NFS link operations

These operate on NFS shares only. A hard link makes both paths refer to the same underlying file, and the file's `PosixProperties.linkCount` grows by one. A symbolic link stores its target as a path, resolved by the NFS client at access time; the target need not exist.

```ballerina
remote function createHardLink(string path, string targetPath) returns Error?;
remote function createSymbolicLink(string path, string linkTarget) returns Error?;
remote function getSymbolicLink(string path) returns string|Error;
```

### 5. The `Listener` and `Caller`

Azure Files is not exposed as an Event Grid source, so the listener polls, following the model of `ballerina/ftp`. It uses **stateless dispatch**: each polling tick lists the watched path and reads each present file, invoking the content handler that matches it. No per-file state is kept, so the contract is that handlers consume files by processing them and then deleting or moving them out of the watched path; an unprocessed file fires again on a later poll. This mode is trivially restart-safe. Delivery is at-least-once.

Polling runs on the platform task scheduler at a fixed `pollingInterval`, whose waiting policy makes a tick that fires during a still-running scan wait for it; each matching file is dispatched to its handler on its own thread, so handlers run concurrently beyond the scan. An in-progress guard keyed on the file's path ensures one file is never dispatched to two invocations at once, so a file re-fires only after its previous handling has finished and it is still present; a file overwritten while its previous version is still being handled is dispatched with its new content on a later poll, once that handling completes. To keep that promise under auto-consume, a configured `afterProcess` or `afterError` action first checks that the file's entity tag still matches the dispatched version and leaves a changed file for the next poll; the instant between that check and the action stays unguarded, since Azure Files offers no conditional deletes or renames. A file overwritten in the short window between a poll's listing and its content read is delivered with the new content while the accompanying `FileInfo` still describes the listed version; Azure Files offers no conditional reads to close that window. Handlers should be idempotent, or claim a file by renaming it out of the watched path before processing.

One listener watches exactly one service and one path. The listener configuration carries the share-level concerns (credentials, polling cadence, transport, content-binding behaviour). What to watch is the service's attach point: `service /invoices on lsn` (a resource path, whose segments join with `/`) or `service "/dir one/reports" on lsn` (a string, for names a resource path cannot express). The path normalizes by trimming whitespace, collapsing repeated slashes, ensuring a leading slash, and stripping a trailing one; a service with no attach point watches the share root. The optional `@ServiceConfig` annotation configures recursion and file-name filtering; no annotation is needed for a service to work.

```ballerina
public type ListenerConfiguration record {|
    # The authentication configuration
    AuthConfig auth;
    # Polling interval in seconds; must be greater than zero
    decimal pollingInterval = 60;
    # Retry configuration for the underlying client
    RetryConfig retryConfig?;
    # HTTP transport configuration for the underlying client
    TransportConfig transportConfig?;
    # Relaxed data binding for the typed content handlers
    boolean laxDataBinding = false;
    # Fail-safe CSV processing; skipped records go to an error log file
    FailSafeOptions csvFailSafe?;
|};

public type FailSafeOptions record {|
    # What each skipped CSV record's error log entry carries
    ErrorLogContentType contentType = METADATA;
|};

public enum ErrorLogContentType {
    METADATA,
    RAW,
    RAW_AND_METADATA
}

public type ServiceConfiguration record {|
    # Whether the service watches subdirectories under the watched path
    boolean recursive = true;
    # Regex on the file name; non-matching files are never dispatched to this service
    string fileNamePattern?;
    # Skip files younger than this many seconds, guarding against partial writes
    decimal minFileAgeSeconds?;
|};

public annotation ServiceConfiguration ServiceConfig on service;
```

A listener already bound to a service rejects a second `attach` at runtime, so to watch several paths, run several independent listeners. Overlap can still arise across separate listeners (a file under a path watched by two of them reaches each), so handling races there are the user's responsibility (idempotent handlers, or claim a file by renaming it out of the watched path).

The `attach` `name` argument carries the service's attach point, which is the watched path. Attaching a service with an invalid `fileNamePattern` fails; a credential that cannot list the watched path does not fail `attach`, the first poll surfaces the authorization error instead. Calling `start` on a listener that is already running fails, and `detach` of a service that is not attached fails. `gracefulStop` and `immediateStop` both stop the polling schedule; in either case, handler invocations already running complete on their own threads.

```ballerina
public isolated class Listener {
    public isolated function init(string shareName, *ListenerConfiguration config) returns Error?;
    public isolated function attach(Service serviceRef, string[]|string? name = ()) returns error?;
    public isolated function 'start() returns error?;
    public isolated function gracefulStop() returns error?;
    public isolated function immediateStop() returns error?;
    public isolated function detach(Service serviceRef) returns error?;
}

# A bare distinct service object; the handler set is validated at compile time.
public type Service distinct service object {
};

# Carries what a directory listing provides, the Listener's data source.
public type FileInfo record {|
    # The name of the share the file lives on
    string shareName;
    # Share-relative path, e.g. "/dir1/dir2/file.ext"
    string path;
    # File name only
    string name;
    # Size in bytes
    int sizeBytes;
    # Entity tag of the file
    string eTag;
    # Last-modified time
    time:Utc lastModified;
|};
```

A service declares at least one content handler. `onFile` is the raw-bytes catch-all, taking its content as `byte[]` or as `stream<byte[], error?>`, and the typed variants receive a matching file's content already deserialised: `onFileText` takes a `string`, `onFileJson` takes a `map<json>`, a record, a `map<json>[]`, or a record array, `onFileXml` takes an `xml` document or a record, and `onFileCsv` takes a `string[][]`, a record array, a `stream<string[], error?>`, or a `stream<record {}, error?>`.

An object root binds the `onFileJson` map and record forms (a record binds by projection), and an array root binds the array forms element by element. The `string[][]` and `stream<string[]>` CSV forms yield every row of the file; the CSV record forms map each row's fields through the file's first row, the header. An XML record target binds the document's elements to the record's fields. A root that does not match the declared form is a content-binding error.

The `FileInfo` and `Caller` parameters are optional trailing parameters: a handler declares its content parameter first, then either, both, or neither of `FileInfo` and `Caller` (with `FileInfo` before `Caller` when both are present), so the accepted shapes are `(content)`, `(content, FileInfo)`, `(content, Caller)`, and `(content, FileInfo, Caller)`, and the listener passes only what the handler declares.

Routing is by file extension (`txt` to `onFileText`, `json` to `onFileJson`, `xml` to `onFileXml`, `csv` to `onFileCsv`), and a per-handler `@FunctionConfig` pattern overrides it. When more than one routing pattern matches a file name, the winner is fixed: patterns are checked in the order `onFileText`, `onFileJson`, `onFileXml`, `onFileCsv`, then `onFile`, so a typed handler's pattern always beats the catch-all's. A file routed to a typed variant whose content is malformed raises a content-binding error rather than falling through to `onFile`.

Binding is strict by default; setting `laxDataBinding` on the listener relaxes it, so JSON and CSV record binding treat a null value as an optional field and an absent member as a nilable field, and XML record binding tolerates elements the record does not declare. With `csvFailSafe` set, a malformed record in a materialized CSV binding is skipped instead of failing the whole binding, and is appended to an error log file named `<sourceBaseName>_error.log` in the process working directory; the `contentType` field selects what each entry carries. Fail-safe mode applies to the materialized CSV forms only, not the stream forms.

The stream content forms read the file from the service in chunks as the handler drains the stream, instead of downloading it up front. A stream closes its underlying source at the end of the file, and a handler that abandons a stream early should call its `close()`. A CSV stream row that fails to bind surfaces as the error entry of that `next()` call, after which the stream is closed. The consume actions run on the handler's return exactly as for materialized content, so a handler that deletes or moves the file (or declares `afterProcess`) while its stream is not fully drained loses access to the remaining content.

A service may also declare an `onError` handler, `remote function onError(Error err, Caller caller?) returns error?` (the first parameter may equally be typed as the bare `error`, and the `Caller` parameter is optional), which is notified when a poll fails (with the mapped typed error, for example an `AuthorizationError` when the credential lacks access) and when a typed handler's content binding fails (with a client-side `Error`). It is not a content handler: it does not satisfy the at-least-one-handler requirement, takes no annotation, and does not change what happens to the file, so a declared `afterError` still applies to a binding failure. An error returned by `onError` itself is swallowed. Errors returned by content handlers do not notify `onError`, and neither does a CSV stream row that fails to bind lazily (that error belongs to the handler draining the stream).

A compiler plugin validates the service at compile time: at least one content handler, each handler's parameter types and `error?` return (including the accepted parameter shapes and the `onError` signature), and no resource functions or unknown remote methods.

A handler can consume a file by declaring `@FunctionConfig`, which moves or deletes the file after the handler runs:

```ballerina
public const DELETE = "DELETE";

public type Move record {|
    # Target directory; the file keeps its name and the directory is created if absent
    string moveTo;
    # Recreate the file's sub-path under the watched root on recursive watches
    boolean preserveSubDirs = true;
|};

public type MOVE Move;

public type FunctionConfiguration record {|
    # Per-handler routing override (regex on the file name)
    string fileNamePattern?;
    # Auto-consume after the handler succeeds
    DELETE|MOVE afterProcess?;
    # Auto-consume after the handler errors or content-binding fails
    DELETE|MOVE afterError?;
|};

public annotation FunctionConfiguration FunctionConfig on object function;
```

`afterProcess` runs when the handler returns normally, and `afterError` when it errors or content-binding fails; when neither is set the file stays and re-fires. A `Move` onto an existing same-named file replaces it, so a recurring file name moves cleanly every time; with `preserveSubDirs: false`, same-named files from different subdirectories land on one destination name and the last move wins, so flattened moves should only be used where names are unique.

A `Caller` is passed to each handler so it can act on the event's file without constructing a separate client. The listener's own polling uses the same share-scoped client that backs the `Caller`, so one listener holds exactly one connection stack. The `Caller` forwards a curated share-scoped subset of `Client` (`downloadFile`, `getFileContent`, `getFileText`, `getFileJson`, `getFileXml`, `getFileCsv`, `uploadFile`, `uploadContent`, `deleteFile`, `copyFile`, `checkCopyStatus`, `abortCopy`, `renameFile`, `createDirectory`, `deleteDirectory`, `list`). Handlers pass the event's path explicitly, e.g. `caller->deleteFile(file.path)`, and read the share's name from `FileInfo.shareName`.

A failed poll surfaces its error: the listener logs it on every poll, and a declared `onError` receives it. Polling keeps its configured interval, so the next scheduled poll scans again.

### 6. Errors

Every error raised by an operation of the module is a subtype of the distinct `Error` type. The hierarchy splits by origin: an error the Azure service raised is a `ServiceError` and carries a `ServiceErrorDetail` with the HTTP status and the Azure error code of the failed request, while a client-side failure is the generic `Error` and carries no detail (no server exchange produced a status or a code, and the connector never fabricates them). Callers can pattern-match on specific failures:

```ballerina
public type ServiceErrorDetail record {|
    # The HTTP status code returned by Azure
    int httpStatus;
    # The Azure error code (e.g. `ShareNotFound`)
    string errorCode;
|};

public type Error                    distinct error;
public type ServiceError             distinct (Error & error<ServiceErrorDetail>);
public type NotFoundError            distinct ServiceError;
public type ConflictError            distinct ServiceError;
public type AuthorizationError       distinct ServiceError;
public type PreconditionFailedError  distinct ServiceError;
public type RangeNotSatisfiableError distinct ServiceError;
public type QuotaExceededError       distinct ServiceError;
```

* `ServiceError`: any error raised by the Azure service; a service failure whose Azure error code maps to none of the specific subtypes below stays this generic type.
* `NotFoundError`: the requested share, directory, or file was not found (HTTP 404).
* `ConflictError`: the operation conflicts with the current state of the resource, for example creating a share that already exists (HTTP 409).
* `AuthorizationError`: authentication or authorization failed, for example an invalid key or insufficient SAS permissions (HTTP 403).
* `PreconditionFailedError`: a precondition such as an ETag condition or a lease-id requirement was not met (HTTP 412).
* `RangeNotSatisfiableError`: the requested byte range cannot be satisfied for the target file (HTTP 416).
* `QuotaExceededError`: a write was rejected because the share's provisioned capacity is exhausted (HTTP 403).

Mapping keys on the Azure error code string, not the HTTP status alone: `ShareSizeLimitReached` (403) maps to `QuotaExceededError`, distinct from auth failures (also 403) mapping to `AuthorizationError`. The human-readable message becomes the Ballerina error's `message()` rather than being duplicated into the detail record.

### 7. Usage

Working with files in a share:

```ballerina
import ballerinax/azure.storage.files;

configurable files:ClientConfiguration filesConfig = ?;

public function main() returns error? {
    files:Client fileShare = check new ("invoices", filesConfig);

    check fileShare->uploadFile("./invoice-2026-07.pdf", "/2026/07/invoice.pdf");

    stream<files:Entry, files:Error?> entries = check fileShare->list("/2026/07");
    check entries.forEach(function(files:Entry entry) {
        // ...
    });

    check fileShare->downloadFile("/2026/07/invoice.pdf", "./copies/invoice.pdf");
}
```

Reacting to files arriving in a share:

```ballerina
import ballerinax/azure.storage.files;

listener files:Listener invoiceListener = check new ("invoices",
    auth = {accountName: "myacct", accountKey: "..."},
    pollingInterval = 30
);

service /incoming on invoiceListener {
    remote function onFile(byte[] content, files:FileInfo file, files:Caller caller) returns error? {
        check caller->downloadFile(file.path, "./processed/" + file.name);
        // Consume the file so it does not fire again on the next poll.
        check caller->deleteFile(file.path);
    }
}
```

Share administration:

```ballerina
files:AdminClient admin = check new (auth = {accountName: "myacct", accountKey: "..."});

if !(check admin->hasShare("invoices")) {
    check admin->createShare("invoices", {quotaInGb: 100});
}
```

Minting a read-only, one-hour SAS token for a single file (a local signing operation, invoked with `.`):

```ballerina
import ballerina/time;

files:Client fileShare = check new ("invoices", auth = {accountName: "myacct", accountKey: "..."});

string sasToken = check fileShare.generateSas("/2026/07/invoice.pdf", {
    expiryTime: time:utcAddSeconds(time:utcNow(), 3600),
    permissions: {read: true}
});
```

Handling a specific failure:

```ballerina
files:FileProperties|files:Error properties = fileShare->getFileProperties("/2026/07/invoice.pdf");
if properties is files:NotFoundError {
    // the file is absent; create it, or skip
} else if properties is files:Error {
    return properties;
}
```

## Alternatives

* **Revamp `azure_storage_service` in place.** Rejected: the hand-written protocol layer remains the maintenance burden, and the combined Blob-plus-Files packaging contradicts the one-package-per-service pattern of the rest of the Azure ecosystem.
* **Generate a client from the REST/OpenAPI definition.** Rejected: the generated client would still leave Shared Key signing, SAS construction, retry, and chunked transfer to be implemented and maintained by hand; the official SDK already encapsulates all of it and tracks new API versions.
* **Surface the SDK's four-client chain directly** (`ShareServiceClient`, `ShareClient`, `ShareDirectoryClient`, `ShareFileClient`). Rejected: navigating a client chain to reach a file is SDK ergonomics, not Ballerina ergonomics. Two clients plus a combined `path` parameter keeps the common case to a single object and small signatures.
* **One combined package for Blob and Files.** Rejected: users pull one artifact per service everywhere else in the ecosystem, and Microsoft's own packaging already shares the common auth/retry layer between the two SDK artifacts, so separate Ballerina packages duplicate nothing.
* **A stateful snapshot-diff listener mode** (comparing each poll against a per-poll path-to-ETag snapshot and firing `onFileAdd`, `onFileDelete`, and `onFileModify` events). Rejected: Azure Files keeps no change feed, so the connector would have to own change-tracking state it cannot keep honest (a restart re-baselines the snapshot and silently misses deletions that happened during downtime). The stateless consume contract stays restart-safe, and an application that wants diff semantics can keep the path-to-ETag snapshot itself on top of the stateless listener, choosing its own persistence.

## Testing

Azure Files has no local emulator (Azurite covers Blob, Queue, and Table only), so the suite is **dual-mode**: every test runs against an in-process localhost mock of the File REST service (wired through the `serviceUrl` override on the auth config) when no credentials are configured, and against a real storage account when they are, with no separate test groups. CI runs credential-free, so every PR exercises the full surface against the mock, including canned error responses covering the Azure error-code to typed-error mapping; the live mode runs the same tests with organization secrets. A small residue is single-mode for physical reasons: fault injection and SMB-handle fixtures exist only on the mock, while the Entra ID token flows and the NFS operations run only against live Azure.

## Dependencies

* Azure SDK for Java: `com.azure:azure-storage-file-share` (and `com.azure:azure-identity` for the Entra ID support)

## References

* [Azure Files documentation](https://learn.microsoft.com/en-us/azure/storage/files/storage-files-introduction)
* [Azure Files REST API](https://learn.microsoft.com/en-us/rest/api/storageservices/file-service-rest-api)
* [Azure SDK for Java, File Share client library](https://learn.microsoft.com/en-us/java/api/overview/azure/storage-file-share-readme)
* [Existing connector: `ballerinax/azure_storage_service`](https://central.ballerina.io/ballerinax/azure_storage_service/latest)
* [`ballerina/ftp`, the polling-listener precedent](https://central.ballerina.io/ballerina/ftp/latest)
