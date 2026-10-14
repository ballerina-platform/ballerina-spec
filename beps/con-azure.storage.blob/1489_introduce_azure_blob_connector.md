# Introduce Azure Blob Storage Connector

- Authors
  - Yasan Punchihewa
- Reviewed by
- Created date
  - 2026-08-20
- Updated date
  - 2026-09-27
- Issue
  - [#1489](https://github.com/ballerina-platform/ballerina-spec/issues/1489)
- State
  - Submitted

## Summary

Ballerina's current support for Azure Blob Storage lives inside `ballerinax/azure_storage_service`, a combined package that re-implements the Azure Storage REST protocol by hand and is pinned to the 2019-12-12 API version. This proposal introduces **ballerinax/azure.storage.blob**, a standalone connector for [Azure Blob Storage](https://learn.microsoft.com/en-us/azure/storage/blobs/storage-blobs-introduction) built on Microsoft's official `com.azure:azure-storage-blob` Java SDK. It provides a two-tier client (`AdminClient` for account-level operations, `Client` bound to one container) covering container lifecycle and service configuration, blob listing, transfers with caller-directed data binding, copies, access tiers, index tags, snapshots, leases, and the append-blob, page-blob, and block surfaces; a `Listener` that consumes blob lifecycle events through Azure Event Grid and binds blob content for its handlers, with a `Caller` for acting on the event's blob; the family's union-typed authentication model; and an error hierarchy keyed on the Azure error code. It is the sibling of `ballerinax/azure.storage.files`.

## Motivation

The existing `azure_storage_service.blobs` module has accumulated several problems:

1. **Hand-written protocol layer:** Shared Key signing, block-list composition, and response parsing are implemented in Ballerina against the 2019-12-12 REST API version. Every protocol fix and every new service capability must be re-implemented by hand.
2. **A hard ceiling on uploads, and a defect past it:** `putBlob` refuses content over 50 MiB outright, and the chunked path meant to get past it derives block identifiers as `blobName:index`, whose base64 forms stop being equal in length from the eleventh block. Azure requires all block identifiers in one blob to be equal in length, so uploads needing eleven or more blocks fail.
3. **Fragile response decoding:** every XML response is passed through a regular expression that strips double quotes before parsing, so any stored value containing one is silently corrupted.
4. **A narrow authentication model:** only Shared Key and a bare SAS token are supported, with no connection string, no SAS URL, and no Microsoft Entra ID, so managed identities and workload identities cannot be used at all.
5. **No event-driven support:** there is no listener, so applications reacting to blobs arriving in a container must hand-roll polling, which on blob storage means re-listing a container that routinely holds millions of entries.
6. **No tests in CI:** the legacy tests are live-only and every workflow passes `-x test`.
7. **Combined packaging:** blob support is a submodule of a package that also covers Files, so users pull one large artifact for one service, against the prevailing one-package-per-service pattern of the Azure ecosystem.

Microsoft's own SDK solves the protocol problems once, centrally: `azure-storage-blob` encapsulates signing, SAS construction, retry policies, parallel chunked transfer, connection-string parsing, and parity with new REST API versions. Wrapping the SDK instead of the REST API means the connector inherits all of this and Microsoft remains responsible for maintaining it.

## Goals

* Provide an idiomatic Ballerina API for the everyday Azure Blob Storage surface: container lifecycle and service configuration, blob listing, transfers (disk, value, stream), properties and metadata, copies, access tiers, index tags, snapshots, leases, stored access policies, and SAS generation.
* Match Microsoft's two-tier mental model: `AdminClient` for account-level operations and `Client(containerName)` for everything inside one container.
* Provide a `Listener` over the service's native eventing path, Event Grid delivering to a storage queue, that binds each new blob's content to a typed handler, with a `Caller` so handlers can act on the blob without constructing a separate client.
* Carry content across the boundary as Ballerina values, through one dependently-typed read and one union write whose serialization format is resolved from the blob's own path.
* Provide a union-typed authentication model where each member is exactly one real-world credential artifact and misconfiguration is a compile error.
* Provide a consistent, pattern-matchable error hierarchy keyed on the Azure error code.
* Be a complete replacement for the blob surface of the existing `azure_storage_service` connector, so that its deprecation strands no user: every capability that module exposed has a path here. This is why the surface includes append blobs, page blobs, the block operations, and account information.

## Non-Goals

- **No Files, Queue, or Table support.** Files is the sibling package `azure.storage.files`; Queue and Table would be their own future packages. The storage queue this connector's listener consumes is an internal detail of the event path, not a queue API.
- **No re-implementation of the wire protocol.** Authentication, signing, retry, and chunked transfer are delegated to the official SDK.
- **No Data Lake Storage Gen2 semantics.** Hierarchical-namespace accounts expose real directories, atomic renames, and POSIX access control through a separate endpoint. The connector reports whether an account has that namespace and otherwise treats every account as flat.
- **No compliance or infrastructure surfaces in the first version:** blob versioning, immutability policies and legal holds, encryption scopes and customer-provided keys, object replication, batch operations, blob expiry, the change feed, container leases, and Blob Query.

## Design

### 1. Module overview

The module is `ballerinax/azure.storage.blob`. The hierarchical name groups it with its sibling `azure.storage.files`, following the pattern of `azure.openai.chat` and `azure.openai.responses`; the leaf is Microsoft's own product noun, lowercased.

| Type | Scope | Role |
|---|---|---|
| `AdminClient` | the storage account | Container lifecycle, the account's blob service configuration, account information, user delegation keys, account-level SAS tokens |
| `Client` | one container, bound at `init` | Every operation inside that container. The client most applications instantiate |
| `Listener` | one storage queue | Consumes the blob events an Event Grid subscription delivers, and dispatches each to the service attached for its container |
| `Caller` | one container, passed to each handler | A curated subset of `Client`, so a handler acts on the event's blob without constructing a client |

**A blob is addressed by a single slash-delimited, container-relative `path`** (for example `"2026/07/invoice.pdf"`). Blob storage has no directories: the slashes are part of the blob's name, and the hierarchical listing mode groups names by their slash segments. A leading slash is stripped. Where two paths co-occur they are named `sourcePath` and `destinationPath`, source first.

| Blob type | Created by | Grows by | Serves |
|---|---|---|---|
| Block blob | every transfer operation, `commitBlockList` | replacing the whole blob, or committing a block list | ordinary content |
| Append blob | `createAppendBlob` | `appendBlock`, `appendBlockFromUrl` | log-style accumulation |
| Page blob | `createPageBlob` | `uploadPages`, `clearPages` at 512-byte alignment | virtual disks and random access |

**A blob's type is fixed for its lifetime.** It is reported in the blob's properties; a type-specific operation applied to a blob of another type fails with `InvalidBlobTypeError`, and so does an upload over an existing append or page blob. Changing a blob's type means deleting it and writing a new one.

`AdminClient`, `Client`, and `Caller` are isolated client classes holding only immutable configuration, and `Listener` is an isolated class, so one instance of any of them is safe to use from concurrent strands. Every operation that calls the service is a `remote` method, invoked with `->`. The SAS generation methods and the `Listener` lifecycle methods make no service call and are ordinary methods, invoked with `.`. The clients hold no releasable resources and have no close method. The `isolated` qualifier is omitted from the signatures below.

### 2. Authentication

The authentication model is the sibling connector's: the credential artifacts are the storage account's, and a key, SAS, or Entra identity issued for an account authenticates against blob and file endpoints alike.

#### 2.1 The `AuthConfig` union

```ballerina
public type AuthConfig SharedKeyConfig|SasConfig|SasUrlConfig|ConnectionStringConfig|EntraIdConfig;
```

Every member has a unique required field or field combination, so the compiler and `Config.toml` select the member by structural matching, with no discriminator field. Misconfiguration between modes is a compile error.

| `Config.toml` | Member |
|---|---|
| `auth = {accountName = "myacct", accountKey = "..."}` | `SharedKeyConfig` |
| `auth = {accountName = "myacct", sasToken = "sv=..."}` | `SasConfig` |
| `auth = {sasUrl = "https://myacct.blob.core.windows.net/?sv=..."}` | `SasUrlConfig` |
| `auth = {connectionString = "..."}` | `ConnectionStringConfig` |
| `auth = {kind = "default", accountName = "myacct"}` | `EntraIdChainConfig` |
| `auth = {kind = "managed-identity", accountName = "myacct", clientId = "..."}` | `EntraIdChainConfig` |
| `auth = {accountName = "myacct", tenantId = "...", clientId = "...", clientSecret = "..."}` | `ClientSecretConfig` |
| `auth = {accountName = "myacct", tenantId = "...", clientId = "...", certificatePath = "/path/cert.pem"}` | `ClientCertificateConfig` |
| `auth = {accountName = "myacct", tenantId = "...", clientId = "...", tokenFilePath = "/path/token"}` | `WorkloadIdentityConfig` |

#### 2.2 Credential records

```ballerina
public type SharedKeyConfig record {|
    string accountName;
    string accountKey;
    string serviceUrl?;   // default https://{accountName}.blob.core.windows.net
|};

public type SasConfig record {|
    string accountName;
    string sasToken;
|};

public type SasUrlConfig record {|
    string sasUrl;
|};

public type ConnectionStringConfig record {|
    string connectionString;
|};
```

`accountName` is the signing identity, not only a URL component: `serviceUrl` overrides the endpoint alone. Every credential is validated inside `init` with no call to Azure: connection strings are parsed and checked for a blob endpoint, and the explicit records get non-empty, base64, and URL-scheme checks, so a malformed credential fails at construction with a specific error.

#### 2.3 Microsoft Entra ID

```ballerina
public enum EntraIdKind {
    DEFAULT_AZURE_CREDENTIAL = "default",
    MANAGED_IDENTITY = "managed-identity"
}

public type EntraIdChainConfig record {|
    EntraIdKind kind;
    string accountName;
    string clientId?;     // a user-assigned managed identity, under either kind
    string serviceUrl?;
|};

public type ClientSecretConfig record {|
    string accountName;
    string tenantId;
    string clientId;
    string clientSecret;
    string serviceUrl?;
|};

public type ClientCertificateConfig record {|
    string accountName;
    string tenantId;
    string clientId;
    string certificatePath;         // PEM, or PFX when certificatePassword is set
    string certificatePassword?;
    string serviceUrl?;
|};

public type WorkloadIdentityConfig record {|
    string accountName;
    string tenantId;
    string clientId;
    string tokenFilePath;           // the projected service-account token of a Kubernetes workload
    string serviceUrl?;
|};

public type EntraIdConfig EntraIdChainConfig|ClientSecretConfig|ClientCertificateConfig|WorkloadIdentityConfig;
```

`DEFAULT_AZURE_CREDENTIAL` tries the environment, a managed identity, and developer sign-ins in turn; `MANAGED_IDENTITY` uses the managed identity alone. `clientId` selects a user-assigned identity under either kind; omitted, the system-assigned identity is used. The three service-principal records are told apart by their unique required field.

An Entra identity authorizes through Azure RBAC:

| Operations | Role | Scope |
|---|---|---|
| Reads and listings | `Storage Blob Data Reader` | container or above |
| Writes and deletes | `Storage Blob Data Contributor` | container or above |
| Access policies, index tags, tag queries | `Storage Blob Data Owner` | container or above |
| `getUserDelegationKey` | `Storage Blob Delegator` | storage account or above; a container-scoped assignment does not grant it |
| Container lifecycle and service configuration (`AdminClient`) | a management-plane role such as `Contributor` | these grant no blob *data* access; an identity driving both surfaces needs a role from each plane |
| `Listener` | `Storage Queue Data Contributor` in addition to its blob roles | it receives, updates and deletes messages and creates the poison queue; `Storage Queue Data Message Processor` cannot create a queue |

#### 2.4 Client configuration

```ballerina
public type ClientConfiguration record {|
    AuthConfig auth;
    RetryConfig retryConfig?;
    TransportConfig transportConfig = {};
|};
```

The configuration is an included record parameter on both clients' `init`, so callers pass its fields as named arguments. `retryConfig` omitted keeps the service's own retry policy; `transportConfig` always applies, with the defaults in 2.6 when nothing is set.

#### 2.5 Retry configuration

```ballerina
public type RetryConfig record {|
    RetryPolicyType retryPolicyType = EXPONENTIAL;   // EXPONENTIAL | FIXED_INTERVAL
    int maxTries = 4;
    decimal tryTimeoutSeconds = 60;
    decimal retryDelaySeconds = 4;
    decimal maxRetryDelaySeconds = 120;
    string secondaryHostUrl?;                        // geo-redundant read retries
|};
```

The defaults are shared with the sibling connector. Each try is bounded by `tryTimeoutSeconds`, so a stalled request fails rather than hanging a strand, and `retryDelaySeconds` is the base delay under both policy types.

#### 2.6 Transport configuration

```ballerina
public type TransportConfig record {|
    ProxyConfig proxy?;
    ConnectionPoolConfig connectionPool = {};
    SecureSocket secureSocket?;
|};

public type ConnectionPoolConfig record {|
    decimal connectTimeoutSeconds = 10;
    decimal readTimeoutSeconds = 60;
|};
```

`proxy` routes traffic through an HTTP proxy with optional credentials and a bypass list. `secureSocket` configures TLS: trust material, a client identity for mutual TLS, offered versions and cipher suites, revocation checking, an SNI host name for endpoints addressed by IP, and the session timeout; the server's host name is always verified. The timeouts above apply to every client unless overridden. `ProxyConfig`, `SecureSocket`, and `CertKey` are defined in 8.7. The transport is the Java platform's HTTP client, so the connector carries no networking library of its own.

### 3. The `AdminClient`

```ballerina
public function init(*ClientConfiguration config) returns Error?;

remote function hasContainer(string containerName) returns boolean|Error;
remote function listContainers(ContainerListOptions? options = ()) returns ContainerList|Error;
remote function createContainer(string containerName, ContainerCreateOptions? options = ()) returns Error?;
remote function deleteContainer(string containerName, DeleteContainerOptions? options = ()) returns Error?;
remote function undeleteContainer(string containerName, string deletedContainerVersion) returns Error?;
remote function getServiceProperties() returns ServiceProperties|Error;
remote function setServiceProperties(ServiceProperties properties) returns Error?;
remote function getAccountInfo() returns AccountInfo|Error;
remote function getUserDelegationKey(time:Utc startTime, time:Utc expiryTime) returns UserDelegationKey|Error;

public function generateAccountSas(AccountSasSignatureValues values) returns string|Error;
```

`hasContainer` returns `false` only when Azure confirms absence (404); a failed check is an `Error`, so an auth problem is never reported as a missing container.

`listContainers` returns a `ContainerList`. With no `'limit` it returns every container and `nextMarker` is absent; with one, it returns up to that many and `nextMarker` when more remain, to be passed back as `marker`. `createContainer` accepts metadata and a public access level. `deleteContainer` takes a lease id for a container leased elsewhere and is soft under the account's container soft-delete retention policy; `undeleteContainer` restores a soft-deleted container, whose `deletedContainerVersion` comes from `listContainers({includeDeleted: true})` as `ContainerInfo.deletedVersion`.

`ServiceProperties` models the whole configuration document: request metrics, classic logging, CORS rules, the blob soft-delete retention policy, the static website settings, and the default service version. Each group is an optional field; a group present in the record replaces that group whole, a group absent is left untouched. The blob retention policy is the prerequisite for `undeleteBlob`; container soft delete is a storage account setting, enabled on the account rather than through the service properties, and is the prerequisite for `undeleteContainer`.

`getAccountInfo` reports the SKU, the account kind, and whether the account has a hierarchical namespace. `getUserDelegationKey` requires an Entra ID credential holding `Storage Blob Delegator`; the key is valid at most 7 days and signs user-delegation SAS tokens (4.10). `generateAccountSas` signs locally with the account key and makes no service call; the signature values select the services (blob, queue), resource types, permissions, and window, and covering both the blob and the queue services produces the account SAS a `Listener` needs.

### 4. The `Client`

```ballerina
public function init(string containerName, *ClientConfiguration config) returns Error?;
```

Binding is lazy: `init` makes no call to Azure, so the first operation against a nonexistent container fails with `NotFoundError`; the up-front check is `AdminClient.hasContainer`. The surface is 41 remote operations plus four ordinary SAS generators. A method name carries a tier token only to disambiguate a verb that exists at another tier or to keep a bare verb honest: `listBlobs` carries its token because the flat listing returns blobs only; `upload`, `setContentHeaders`, `createSnapshot` stay bare.

#### 4.1 Container-level operations

```ballerina
remote function getContainerProperties() returns ContainerProperties|Error;
remote function setContainerMetadata(map<string> metadata, ContainerMetadataOptions? options = ()) returns Error?;
remote function getContainerAccessPolicy() returns ContainerAccessPolicy|Error;
remote function setPublicAccess(PublicAccess access, AccessPolicyOptions? options = ()) returns Error?;
remote function setContainerAccessPolicy(SignedIdentifier[] identifiers, AccessPolicyOptions? options = ()) returns Error?;
```

Metadata is free-form, user-defined annotation that Azure stores and returns verbatim; `setContainerMetadata` replaces the complete set, and it is read back through `getContainerProperties`.

The anonymous access level and the stored access policies are read together and written separately. `setPublicAccess` changes the level and leaves the policies as they are; `setContainerAccessPolicy` replaces the policies (at most five; `[]` removes them all) and leaves the level as it is. Each of the two reads the current access control list first and resends the half it does not own, so each call is two requests.

#### 4.2 Blob operations

```ballerina
remote function listBlobs(BlobListOptions? options = ()) returns stream<BlobEntry, Error?>|Error;
remote function listBlobsPage(BlobPageOptions? options = ()) returns BlobList|Error;
remote function hasBlob(string path) returns boolean|Error;
remote function deleteBlob(string path, DeleteBlobOptions? options = ()) returns Error?;
remote function undeleteBlob(string path) returns Error?;
remote function getBlobProperties(string path) returns BlobProperties|Error;
remote function setBlobMetadata(string path, map<string> metadata, BlobMetadataOptions? options = ()) returns Error?;
remote function setContentHeaders(string path, ContentHeaders headers, ContentHeaderOptions? options = ()) returns Error?;
```

`listBlobs` returns one lazy stream, so memory stays bounded on a container of millions of blobs. Without a delimiter every blob is listed whatever the slashes in its name; with one, names extending past the next delimiter collapse into a single entry whose `isPrefix` is set, which is fed back as the next call's `prefix` to descend a level. `listBlobsPage` returns one page and the `nextMarker` to resume from, for a listing checkpointed and resumed across process restarts.

`hasBlob` follows `hasContainer`'s rule. `deleteBlob` refuses a blob that has snapshots unless `DeleteBlobOptions` says what to do with them; its options also delete one snapshot instead of the blob, and pass a lease id. `undeleteBlob` restores a soft-deleted blob together with its soft-deleted snapshots.

A blob's properties are read whole and written through three narrower operations, because the wire has no whole-properties setter:

| Group | Read | Written by | Semantics |
|---|---|---|---|
| System properties: timestamps, entity tag, size, blob type, lease state, copy state | `getBlobProperties` | the service | never written directly |
| Content headers: `Content-Type`, `Cache-Control`, encoding, language, disposition, MD5 | `getBlobProperties` | `setContentHeaders` | replaces the whole set; a header omitted from the record is cleared |
| Metadata: user key/value pairs | `getBlobProperties` | `setBlobMetadata` | replaces the whole set |
| Access tier | `getBlobProperties` | `setAccessTier` (4.5) | |

The access tier is read as the wire's string, since the service's tier set is open-ended; it is written through the closed `AccessTier` enum. Type-specific fields (a page blob's sequence number, an append blob's committed block count) are present only for their type.

There is no rename operation. Azure Blob Storage has no rename on flat-namespace accounts; relocating a blob is a copy followed by a delete, and the two steps are individually observable.

#### 4.3 Transfer operations and data binding

```ballerina
remote function uploadFromFile(string sourcePath, string destinationPath, UploadOptions? options = ()) returns Error?;
remote function download(string sourcePath, string destinationPath, DownloadOptions? options = ()) returns Error?;
remote function upload(UploadContent content, string destinationPath, UploadContentOptions? options = ()) returns Error?;
remote function getBlob(string path, GetBlobOptions? options = (),
        typedesc<RetrievableType> targetType = <>) returns targetType|Error;

public type UploadContent byte[]|string|json|xml|record {}|record {}[]|
                          stream<byte[], error?>|stream<record {}, error?>;

public type RetrievableType byte[]|string|json|xml|record {}|record {}[]|
                            stream<byte[], error?>|stream<record {}, error?>;
```

The disk transfers do no format detection and no conversion. Both take full paths including the file name, the local path first for the upload; neither deletes its source. `download` fails with a client-side `Error` when a local file already exists at the destination.

The value transfers use identical unions in both directions, so anything written is readable back in the same type. The union is listed rather than `anydata` because the format resolves from the path and the value's type, and it carries no list-of-lists member because a `string[][]` is simultaneously `json` and a list. Positional or headerless CSV is written as a `string` or `byte[]` and parsed with `ballerina/data.csv`.

**The format resolves first — from the operation's `fileFormat` option, else from the path's extension — and the value is then checked against it.**

| Format | Selected by | Members serialized | Members bound on read |
|---|---|---|---|
| none | no `fileFormat`, no `.json`/`.xml`/`.csv` extension | `byte[]`, `string`, byte stream | `byte[]`, `string`, byte stream |
| JSON | `JSON` or `.json` | `json`, `record {}` | `json`, a record, a record array |
| XML | `XML` or `.xml` | `xml`, `record {}` (one element; a record array has no wrapper name) | `xml`, a record |
| CSV | `CSV` or `.csv` | `record {}[]`, `stream<record {}>` | a record array, a record stream |

`byte[]`, byte streams and `string` pass through untouched under every format, so content the caller already serialized is never re-encoded. Under XML a record becomes a single-element document whose root element is named `root`; `@xmldata:Name` renames member elements, not the root. Under CSV a record array is written with a header row that is the union of every record's field names in first-seen order, with nil or absent members as empty cells; a record stream is written row by row as it is pulled, so its header is the first record's field names. An empty array or an exhausted stream writes an empty blob with no header row.

| Destination | `upload` / `uploadFromFile` |
|---|---|
| no blob | creates a block blob |
| block blob | replaces it; its snapshots are retained |
| append or page blob | `InvalidBlobTypeError` — delete it first |
| archived blob | `ArchivedBlobError` |

There is no `overwrite` option. Content over the single-request threshold is chunked and transferred in parallel in both directions, so memory stays bounded. A byte stream is staged as blocks and committed at the end, with no content length needed up front; until that commit the destination blob does not exist, so a failed stream upload leaves no partial blob.

When the connector chose the serialization and the caller set no explicit content type, the uploaded blob's content type is set to match the format applied. An explicit content type always wins, and content passed through untouched gets no automatic type.

#### 4.4 Copy operations

```ballerina
remote function copyBlob(string sourcePath, string destinationPath, CopyOptions? options = ()) returns CopyInfo|Error;
remote function copyBlobFromUrl(string sourceUrl, string destinationPath, CopyOptions? options = ()) returns CopyInfo|Error;
remote function abortCopy(string path, string copyId, AbortCopyOptions? options = ()) returns Error?;
```

Copies are asynchronous: the service accepts the request and copies in the background, and `CopyInfo` reports the copy's identifier and its status at acceptance. A pending copy is watched through `getBlobProperties`, whose result carries the state of the blob's most recent copy, and cancelled with `abortCopy`. `copyBlob` copies within the bound container under the client's credentials. `copyBlobFromUrl` copies from any Azure Storage URL the service can read: a source in the same account is authorized by the client's credential; a source that is not publicly readable elsewhere carries its own authorization in the URL.

#### 4.5 Access tiers, index tags, and snapshots

```ballerina
remote function setAccessTier(string path, AccessTier accessTier, SetAccessTierOptions? options = ()) returns Error?;
remote function setTags(string path, map<string> tags, TagOptions? options = ()) returns Error?;
remote function getTags(string path) returns map<string>|Error;
remote function findBlobsByTags(string query) returns stream<TaggedBlobEntry, Error?>|Error;
remote function createSnapshot(string path, CreateSnapshotOptions? options = ()) returns string|Error;
```

`setAccessTier` changes the tier and, for an archived blob, starts rehydration with the priority the options carry. An archived blob's content can be neither read nor replaced until rehydration completes, which takes hours; its properties, metadata, and tags stay available, and copying it to an online-tier destination rehydrates without disturbing the original.

Index tags differ from metadata: the service indexes them, so they answer queries without a listing, and they carry their own SAS permission (`t`, and `f` for queries). Tags are set and read whole. The index is eventually consistent, so `findBlobsByTags` may briefly lag a `setTags` write; `getTags` always reads the blob's current tags.

| Tag rule | Value |
|---|---|
| Tags per blob | at most 10 |
| Key length | 1 to 128 characters |
| Value length | 0 to 256 characters |
| Characters, keys and values | `a-z`, `A-Z`, `0-9`, and ` +-.:=_/` |
| Case | sensitive |

`setTags` checks these rules locally before the request. `findBlobsByTags` takes the service's filter expression — keys double-quoted, values single-quoted, operators `=`, `>`, `>=`, `<`, `<=`, joined by `AND` — for example `"status" = 'done' AND "priority" >= '05'`. The connector checks the expression locally before the request (balanced quotes, listed operators, the tag character set) and adds the `@container` clause for the bound container; an expression supplying its own `@container` is refused. A quote cannot appear in a key or a value, so there is no escaping.

`createSnapshot` returns the snapshot's identifier, which selects a snapshot in the read options, in `deleteBlob`, and in a page-range listing. Snapshots are listed through `listBlobs`.

#### 4.6 Lease operations

```ballerina
remote function acquireLease(string path, int leaseDurationSeconds, string? proposedLeaseId = ()) returns string|Error;
remote function renewLease(string path, string leaseId) returns Error?;
remote function releaseLease(string path, string leaseId) returns Error?;
remote function breakLease(string path, int? breakPeriodSeconds = ()) returns int|Error;
remote function changeLease(string path, string leaseId, string proposedLeaseId) returns string|Error;
```

A blob lease locks the blob against writes and deletion by anyone not holding the lease id; reads stay open to all. `leaseDurationSeconds` is 15 to 60, or -1 for infinite, validated locally. The proposed lease id is optional; the service generates one. `breakLease` reclaims a lease without holding its id: with no break period a fixed lease runs out its remaining time and an infinite lease breaks immediately, and the call returns the seconds until the blob is free. `changeLease` hands a lease over with no window in which another client could take it.

**While a blob or container is leased, every write operation passes the lease id through its options record; reads never need one.** The rule is uniform across the surface.

#### 4.7 Append blob operations

```ballerina
remote function createAppendBlob(string path, CreateBlobOptions? options = ()) returns Error?;
remote function appendBlock(string path, byte[] content, AppendBlockOptions? options = ()) returns Error?;
remote function appendBlockFromUrl(string path, string sourceUrl, AppendBlockOptions? options = ()) returns Error?;
```

Blocks append in arrival order, each at most 4 MiB, up to 50,000 per blob.

#### 4.8 Page blob operations

```ballerina
remote function createPageBlob(string path, int sizeInBytes, CreateBlobOptions? options = ()) returns Error?;
remote function uploadPages(string path, int offset, byte[] content, PageOptions? options = ()) returns Error?;
remote function clearPages(string path, int offset, int length, PageOptions? options = ()) returns Error?;
remote function listPageRanges(string path, PageRangeOptions? options = ()) returns PageRange[]|Error;
```

A page blob has a fixed capacity, reserved sparsely: unwritten pages read as zeros and only written pages are billed. Offsets and lengths are 512-byte aligned. Writing and clearing are two operations.

#### 4.9 Block operations

```ballerina
remote function stageBlock(string path, string blockId, byte[] content, StageBlockOptions? options = ()) returns Error?;
remote function stageBlockFromUrl(string path, string blockId, string sourceUrl,
        StageBlockFromUrlOptions? options = ()) returns Error?;
remote function commitBlockList(string path, string[] blockIds, UploadOptions? options = ()) returns Error?;
remote function listBlocks(string path) returns BlockList|Error;
```

Staged blocks are invisible until committed. `commitBlockList` creates or replaces the blob in one atomic step from the ordered `blockIds`. Staged blocks expire seven days after the blob's most recent successful staging.

`blockId` is supplied already base64-encoded, and both operations validate before any request: `stageBlock` rejects an id that is not valid base64, and `commitBlockList` rejects a set whose ids are not all equal in length.

These are not the path for ordinary large uploads, which the transfer operations chunk internally. They exist for composing a blob from remote pieces and for staging content across process restarts.

#### 4.10 SAS generation

```ballerina
public function generateContainerSas(ContainerSasSignatureValues values) returns string|Error;
public function generateSas(string path, BlobSasSignatureValues values) returns string|Error;
public function generateContainerUserDelegationSas(ContainerSasSignatureValues values, UserDelegationKey key) returns string|Error;
public function generateUserDelegationSas(string path, BlobSasSignatureValues values, UserDelegationKey key) returns string|Error;
```

Signing happens locally with the credential the client holds; no call is made to Azure. The account-key variants require a shared-key credential (or a connection string carrying an account key) and are revoked wholesale when the account key rotates. The user-delegation variants sign with a key from `AdminClient.getUserDelegationKey`, so no storage key is handled; they are valid at most 7 days, and stored access policies do not apply to them, so they reject an identifier.

The signature values carry the validity window and the permissions, and optionally a start time, an HTTPS-only restriction, an IP range, and a stored access policy identifier. A parameter may live in the stored policy or in the token but not both; the connector checks what is knowable at signing time and refuses generation when no identifier is supplied and the expiry or the permissions are missing. The signature values and their permission record come in two shapes, one per scope, so a token cannot ask for a permission its scope does not carry: `ContainerSasSignatureValues` with `ContainerSasPermissions` (`read`, `add`, `create`, `write`, `delete`, `list`, `tag`, `filter`) for the container-scoped methods, and `BlobSasSignatureValues` with `BlobSasPermissions` (the same set without `list` and `filter`) for the blob-scoped ones. Each permission is a boolean whose operation this module offers: `add` for appending, `tag` for index tags, `filter` for tag queries.

### 5. The `Listener` and `Caller`

Azure Blob Storage publishes lifecycle events through Azure Event Grid, and Event Grid delivers to an Azure Storage queue. The listener consumes that queue: delivery is near real time, deletions are observable, and the container is never listed. The queue and the Event Grid subscription are created once outside the application; the subscription's filters choose which event types and which containers reach the queue.

```ballerina
public type ListenerConfiguration record {|
    AuthConfig auth;                             // must span the queue and blob services
    decimal maxPollingIntervalSeconds = 60;      // ceiling of the empty-queue backoff
    int batchSize = 16;                          // messages per receive, 1 to 32
    int newBatchThreshold?;                      // refill trigger; defaults to half the batch size
    decimal redeliveryDelaySeconds = 0;          // invisibility after a handler failure
    int maxDeliveryCount = 5;                    // deliveries before the poison queue
    RetryConfig retryConfig?;
    TransportConfig transportConfig = {};
    boolean laxDataBinding = false;
    string queueServiceUrl?;
|};

public isolated class Listener {
    public function init(string queueName, *ListenerConfiguration config) returns Error?;
    public function attach(Service serviceRef, string[]|string? name = ()) returns error?;
    public function detach(Service serviceRef) returns error?;
    public function 'start() returns error?;
    public function gracefulStop() returns error?;
    public function immediateStop() returns error?;
}
```

#### 5.1 Services and the container attach point

```ballerina
service /invoices on eventListener {
    remote function onBlobJson(Invoice invoice, blob:BlobEvent event, blob:Caller caller) returns error?;
    remote function onBlobDeleted(blob:BlobEvent event, blob:Caller caller) returns error?;
    remote function onError(blob:Error err, blob:Caller caller) returns error?;
}
```

**The container is the service's attach point.** One listener consumes one queue, and several services attach to it, one per container. The name is one segment satisfying Azure's container-name rule (or `$root` / `$logs`); a leading slash is stripped. Routing is an exact match on the event's container: a service with no attach point receives the events of every container no named service claims, and an event for a container no service claims is acknowledged and logged at debug level. Attaching a second service for the same container, or a second service with no attach point, fails.

#### 5.2 Handlers

| Handler | First parameter | Fires on |
|---|---|---|
| `onBlob` | `byte[]` or `stream<byte[], error?>` | a created blob no typed handler takes |
| `onBlobText` | `string` | a created `.txt` blob |
| `onBlobJson` | `json`, or a record | a created `.json` blob |
| `onBlobXml` | `xml`, or a record | a created `.xml` blob |
| `onBlobCsv` | `string[][]`, a record array, `stream<string[], error?>`, or `stream<record {}, error?>` | a created `.csv` blob |
| `onBlobDeleted` | `BlobEvent` | a deleted blob |
| `onError` | `Error` | a poll failure (every attached service is notified; a catch-all `onError` that takes a `Caller` is skipped, since no container binds one), an unparseable message, or a fetch or binding failure |

A content handler takes `(content, BlobEvent?, Caller?)`, `onBlobDeleted` takes `(BlobEvent, Caller?)`, and `onError` takes `(Error, Caller?)`; the listener passes only what is declared. A service declares at least one of the six dispatchable handlers; `onError` does not count. The handler set, the parameter types and the `error?` return are validated at compile time by the module's compiler plugin.

**Routing** resolves on the blob name's extension; a name with no extension resolves on the event's content type; else to `onBlob`; `@blob:FunctionConfig { namePattern?, contentTypePattern? }` overrides it. When more than one handler matches, precedence is fixed: `onBlobText`, `onBlobJson`, `onBlobXml`, `onBlobCsv`, then `onBlob`. A created event whose routing finds no declared handler is acknowledged and logged at debug level.

```ballerina
public type FunctionConfiguration record {|
    string namePattern?;          // matched against the blob name, the last path segment
    string contentTypePattern?;   // matched against the event's content type
|};

public annotation FunctionConfiguration FunctionConfig on object function;
```

**Content is the blob's state at fetch time**, not at event time; `event.eTag` lets a handler detect that the blob changed in between. A content handler receives content only for `BlobCreated` events. Binding is strict; `laxDataBinding` relaxes JSON, XML and CSV record binding as in `azure.storage.files`.

| Fetch outcome | Disposition |
|---|---|
| bound | handler runs; a normal return acknowledges the message |
| blob not found (404) | `onError`, message acknowledged |
| archived blob (`ArchivedBlobError`) | `onError`, message acknowledged |
| content fails to bind to the handler's parameter type | `onError` with a client-side `Error`, message acknowledged |
| any other failure | `onError`, message redelivered |

#### 5.3 Events

| Event Grid type | Dispatched to | Note |
|---|---|---|
| `Microsoft.Storage.BlobCreated` | the content handlers | fires for creation **and** replacement; the two are indistinguishable |
| `Microsoft.Storage.BlobDeleted` | `onBlobDeleted` | |
| `Microsoft.Storage.BlobTierChanged` | not dispatched; acknowledged | Future Work |
| `Microsoft.Storage.AsyncOperationInitiated` | not dispatched; acknowledged | Future Work |

Metadata, property, and index-tag changes fire nothing, and on a flat-namespace account neither does an append. Both the Event Grid and the CloudEvents delivery schemas are accepted, detected per message.

```ballerina
public type BlobEvent record {|
    BlobEventType eventType;
    string containerName;
    string path;
    string url;               // the source for Caller.copyBlobFromUrl
    time:Utc eventTime;
    string api;
    string contentType?;
    int contentLength?;
    string blobType?;
    string eTag?;
    string sequencer;         // opaque; comparable per blob path
|};
```

#### 5.4 Delivery

Delivery is at-least-once, so handlers are idempotent. A handler returning normally acknowledges its event and the message is deleted; a handler returning an error or panicking makes the message visible again after `redeliveryDelaySeconds`. A message reaching `maxDeliveryCount` deliveries moves to a queue named `{queueName}-poison`, created on demand; poison messages never expire.

A received message is hidden for a fixed window that the listener extends in the background for as long as the handler runs, so a handler may run arbitrarily long without losing its message. A process that dies mid-handling leaves its messages hidden until the window expires, within ten minutes.

An empty queue is re-polled on a randomized exponential backoff rising to `maxPollingIntervalSeconds`. One receive fetches `batchSize` messages, and the next batch is fetched once the number of events still being handled falls to `newBatchThreshold`.

The queue endpoint derives from the account name as `https://{accountName}.queue.core.windows.net`; for a SAS URL credential it is the SAS URL's host with its blob service label replaced by the queue one. `queueServiceUrl` overrides it, and is required when a SAS URL's host carries no blob label; a connection string derives it from its queue endpoint or its account name.

| Time bound | Value | Where set |
|---|---|---|
| Queue message time to live | 7 days by default; longer on the subscription | Event Grid subscription |
| Event Grid retry | 30 attempts or 1,440 minutes (24 hours), whichever first; 1,440 is the ceiling | Event Grid subscription |
| Event Grid dead-letter | off by default; a dead-letter container recovers undelivered events | Event Grid subscription |

The two bounds are independent: a queue unreachable for a day loses its events whatever the queue-side setting is.

#### 5.5 The `Caller`

The `Caller` is bound to the service's container and forwards seven operations of `Client` with identical signatures: `getBlob`, `getBlobProperties`, `download`, `upload`, `deleteBlob`, `copyBlobFromUrl`, and `setTags`. Handler code and client code are interchangeable. `copyBlobFromUrl` copies into the service's own container; copying to another container from a handler uses a `Client`. The `Caller` cannot be constructed by user code.

#### Why the container is the attach point, and many services attach

One Event Grid subscription spans the storage account, so one queue carries events for every container it admits, and a storage queue is a competing-consumer transport: two listeners on one queue take messages from each other. A listener therefore serves every container in its queue, and the container is where a handler's scope lives. `azure.storage.files` attaches one service per listener because its listener watches one path; a queue consumer is a transport, for which `http:Listener` and `ftp` are the precedents.

#### Why content is bound by handler type only

A files listener has already read the file to detect it; this listener has read nothing, and a fetch is a download per event. An archived blob cannot be read at all. Declaring a content handler is therefore the request for content, and `onBlobDeleted` never carries any.

### 6. Errors

```ballerina
public type Error distinct error;

public type ServiceErrorDetail record {| int httpStatus; string errorCode; |};
public type ServiceError distinct (Error & error<ServiceErrorDetail>);

public type NotFoundError distinct ServiceError;
public type ConflictError distinct ServiceError;
public type AuthorizationError distinct ServiceError;
public type PreconditionFailedError distinct ServiceError;
public type RangeNotSatisfiableError distinct ServiceError;
public type ArchivedBlobError distinct ServiceError;
public type InvalidBlobTypeError distinct ServiceError;
```

A client-side failure is the root `Error` and carries no detail. An error the Azure service raised is a `ServiceError` carrying the HTTP status and the service's error code. **The mapping keys on the error-code string, never on the status alone**; a code that maps to no subtype stays `ServiceError` with its status and code intact.

| Type | Status | Azure error codes |
|---|---|---|
| `NotFoundError` | 404 | `BlobNotFound`, `ContainerNotFound`; for the listener's queue, `QueueNotFound`, `MessageNotFound` |
| `ConflictError` | 409 | state conflicts: `ContainerAlreadyExists`, `BlobAlreadyExists`, `SnapshotsPresent`, `PendingCopyOperation`, and the lease-operation codes `LeaseAlreadyPresent`, `LeaseNotPresentWithLeaseOperation`, `LeaseIdMismatchWithLeaseOperation` |
| `AuthorizationError` | 403 | `AuthenticationFailed`, `AuthorizationPermissionMismatch`, and the index-tag operations' missing lease id |
| `PreconditionFailedError` | 412 | `LeaseIdMissing`, `LeaseIdMismatchWithBlobOperation`, `LeaseNotPresentWithBlobOperation`, `LeaseLost`, `TargetConditionNotMet` |
| `RangeNotSatisfiableError` | 416 | `InvalidRange`, `InvalidPageRange` |
| `ArchivedBlobError` | 409 | `BlobArchived`, `BlobBeingRehydrated` |
| `InvalidBlobTypeError` | 409 | `InvalidBlobType` |

A data write against a leased blob without the lease id is `PreconditionFailedError`; a lease operation against a stale id or the wrong state is `ConflictError`.

### 7. Usage

```ballerina
import ballerina/io;
import ballerinax/azure.storage.blob;

type Reading record {|
    string sensorId;
    decimal celsius;
|};

public function main() returns error? {
    blob:Client readings = check new ("readings",
        auth = {accountName: "mystorageaccount", accountKey: "..."}
    );

    Reading[] batch = [{sensorId: "s-1", celsius: 21.4}, {sensorId: "s-2", celsius: 19.8}];

    // The .csv extension selects CSV; field names become the header row.
    check readings->upload(batch, "2026/08/20.csv");

    // The same extension drives the binding on the way back.
    Reading[] stored = check readings->getBlob("2026/08/20.csv");
    io:println(stored.length());
}
```

```ballerina
import ballerina/io;
import ballerinax/azure.storage.blob;

type Reading record {|
    string sensorId;
    decimal celsius;
|};

listener blob:Listener eventListener = check new ("blob-events",
    auth = {accountName: "mystorageaccount", accountKey: "..."}
);

// The container is the attach point; a .csv blob created in it is bound to the record array.
service /readings on eventListener {
    remote function onBlobCsv(Reading[] rows, blob:BlobEvent event, blob:Caller caller) returns error? {
        io:println(string `${event.path}: ${rows.length()} readings`);
        check caller->setTags(event.path, {status: "processed"});
    }

    remote function onBlobDeleted(blob:BlobEvent event) returns error? {
        io:println(string `${event.path} deleted`);
    }
}
```

### 8. Type definitions

The types the design sections name without defining. The configuration, content, listener, and error types are defined where they are introduced. Properties are read whole and written through `setBlobMetadata`, `setContentHeaders`, and `setAccessTier`; there is no `setBlobProperties`, because the wire has no whole-properties setter.

#### 8.1 Enumerations

```ballerina
# How the delay between retries grows.
public enum RetryPolicyType {
    # The delay grows exponentially with each try
    EXPONENTIAL = "exponential",
    # The delay is the same before every try
    FIXED_INTERVAL = "fixed"
}

# The access tiers this module sets on a blob. The tier a blob reports is a plain `string`,
# because the service's tier set is open-ended.
public enum AccessTier {
    # Optimised for frequent access
    HOT = "Hot",
    # Optimised for infrequent access, held at least 30 days
    COOL = "Cool",
    # Optimised for rare access, held at least 90 days
    COLD = "Cold",
    # Offline storage, cheapest to hold; content must be rehydrated before it can be read
    ARCHIVE = "Archive"
}

# How quickly an archived blob is rehydrated.
public enum RehydratePriority {
    # Standard priority, documented at up to fifteen hours
    STANDARD = "Standard",
    # High priority, typically under one hour
    HIGH = "High"
}

# A container's anonymous access level.
public enum PublicAccess {
    # No anonymous access
    PRIVATE = "private",
    # Anonymous read access to blobs
    BLOB = "blob",
    # Anonymous read access to blobs, and anonymous listing of the container
    CONTAINER = "container"
}

# What happens to a blob's snapshots when the blob is deleted.
public enum DeleteSnapshotsOption {
    # Delete the blob together with its snapshots
    INCLUDE = "include",
    # Delete only the snapshots, keeping the blob
    ONLY_SNAPSHOTS = "only"
}

# The serialization format applied to structured content.
public enum FileFormat {
    # A JSON document
    JSON,
    # An XML document
    XML,
    # CSV rows
    CSV
}

# The blob lifecycle event types this module dispatches.
public enum BlobEventType {
    # A blob's content was fully committed, on creation or on replacement
    BLOB_CREATED,
    # A blob was deleted
    BLOB_DELETED
}

# The state of a copy operation.
public enum CopyStatus {
    # The copy is in progress
    PENDING = "pending",
    # The copy completed
    SUCCESS = "success",
    # The copy was aborted
    ABORTED = "aborted",
    # The copy failed
    FAILED = "failed"
}

# The lease state of a container or blob.
public enum LeaseState {
    # No lease is held
    AVAILABLE = "available",
    # A lease is held
    LEASED = "leased",
    # A fixed-duration lease ran out
    EXPIRED = "expired",
    # The lease is breaking
    BREAKING = "breaking",
    # The lease was broken
    BROKEN = "broken"
}

# Whether a container or blob is locked by a lease.
public enum LeaseStatus {
    # A lease is held
    LOCKED = "locked",
    # No lease is held
    UNLOCKED = "unlocked"
}

# Whether a lease runs for a fixed time or indefinitely.
public enum LeaseDuration {
    # The lease never expires until released or broken
    INFINITE = "infinite",
    # The lease expires after its duration unless renewed
    FIXED = "fixed"
}

# The protocols a request presenting a SAS token may use.
public enum SasProtocol {
    # HTTPS only
    HTTPS = "https",
    # HTTPS or HTTP
    HTTPS_HTTP = "https,http"
}
```

#### 8.2 Container types

```ballerina
# A container as returned by the account-level listings.
public type ContainerInfo record {|
    # The container name
    string name;
    # When the container was last modified
    time:Utc lastModified;
    # The container's entity tag
    string eTag;
    # The anonymous access level
    PublicAccess publicAccess;
    # The lease state
    LeaseState leaseState;
    # Whether the container is locked by a lease
    LeaseStatus leaseStatus;
    # Whether a held lease is fixed-duration or infinite, or `()` when no lease is held
    LeaseDuration? leaseDuration;
    # The container's metadata; present only when the listing requested it
    map<string> metadata?;
    # Whether the container is soft-deleted; present only on soft-deleted entries
    boolean isDeleted?;
    # The restore version of a soft-deleted container; pass to `AdminClient.undeleteContainer`
    string deletedVersion?;
    # When the container was deleted; present only on soft-deleted entries
    time:Utc deletedTime?;
    # Days remaining before the soft-deleted container is purged
    int remainingRetentionDays?;
|};

# The result of a container listing.
public type ContainerList record {|
    # The containers returned
    ContainerInfo[] containers;
    # The marker to resume the listing from; present only when more containers remain
    string nextMarker?;
|};

# The bound container's properties and metadata.
public type ContainerProperties record {|
    # When the container was last modified
    time:Utc lastModified;
    # The container's entity tag
    string eTag;
    # The anonymous access level
    PublicAccess publicAccess;
    # The container's complete metadata set
    map<string> metadata;
    # The lease state
    LeaseState leaseState;
    # Whether the container is locked by a lease
    LeaseStatus leaseStatus;
    # Whether a held lease is fixed-duration or infinite, or `()` when no lease is held
    LeaseDuration? leaseDuration;
    # Whether an immutability policy is set on the container
    boolean hasImmutabilityPolicy;
    # Whether a legal hold is set on the container
    boolean hasLegalHold;
|};

# A container's anonymous access level and its stored access policies, as the wire carries
# them: together.
public type ContainerAccessPolicy record {|
    # The anonymous access level
    PublicAccess access;
    # The stored access policies, at most five
    SignedIdentifier[] identifiers;
|};

# One stored access policy: a validity window and a permission string under an identifier.
public type SignedIdentifier record {|
    # The identifier a SAS token references to inherit this policy
    string id;
    # When the policy becomes valid
    time:Utc startTime?;
    # When the policy expires
    time:Utc expiryTime?;
    # The permissions the policy grants, as the wire's permission string
    string permissions?;
|};
```

#### 8.3 Blob types

```ballerina
# One entry of a blob listing. In the hierarchical mode an entry whose `isPrefix` is set is a
# collapsed group of names rather than a blob.
public type BlobEntry record {|
    # The blob's container-relative path, which feeds the path-taking operations directly
    string path;
    # Whether this entry is a collapsed prefix rather than a blob
    boolean isPrefix = false;
    # The blob's size in bytes; absent on prefix entries
    int contentLength?;
    # When the blob was last modified
    time:Utc lastModified?;
    # The blob's entity tag
    string eTag?;
    # The blob type (`BlockBlob`, `AppendBlob`, or `PageBlob`)
    string blobType?;
    # The blob's access tier, as the wire's string
    string accessTier?;
    # The blob's metadata; present only when the listing requested it
    map<string> metadata?;
    # The blob's index tags; present only when the listing requested it
    map<string> tags?;
    # The snapshot identifier; present on snapshot entries
    string snapshotId?;
    # Whether the blob is soft-deleted; present on soft-deleted entries
    boolean isDeleted?;
|};

# One page of a blob listing.
public type BlobList record {|
    # The blobs returned
    BlobEntry[] blobs;
    # The marker to resume the listing from; present only when more blobs remain
    string nextMarker?;
|};

# A blob's properties, metadata, and the state of its most recent copy.
public type BlobProperties record {|
    # When the blob was last modified
    time:Utc lastModified;
    # When the blob was created
    time:Utc createdTime;
    # The blob's entity tag
    string eTag;
    # The blob's size in bytes
    int contentLength;
    # The blob's content headers
    ContentHeaders contentHeaders;
    # The blob's complete metadata set
    map<string> metadata;
    # The blob type (`BlockBlob`, `AppendBlob`, or `PageBlob`)
    string blobType;
    # The access tier, as the wire's string, since the service's tier set is open-ended
    string accessTier?;
    # Whether the tier was inferred rather than set explicitly
    boolean accessTierInferred?;
    # The rehydration state, set while a rehydration from the archive tier is pending
    string archiveStatus?;
    # The lease state
    LeaseState leaseState;
    # Whether the blob is locked by a lease
    LeaseStatus leaseStatus;
    # Whether a held lease is fixed-duration or infinite, or `()` when no lease is held
    LeaseDuration? leaseDuration;
    # The most recent copy operation; absent when the blob was never a copy destination
    CopyStatusInfo copyStatus?;
    # The page blob's write sequence marker; present only on page blobs
    int blobSequenceNumber?;
    # The append blob's committed block count; present only on append blobs
    int committedBlockCount?;
|};

# A blob's standard content headers. Written as a whole set: a field omitted from the record is
# cleared on the blob.
public type ContentHeaders record {|
    # The media type of the blob's content
    string contentType?;
    # The content encoding applied to the blob
    string contentEncoding?;
    # The natural language of the blob's content
    string contentLanguage?;
    # How a user agent should present the content
    string contentDisposition?;
    # The caching directives for the blob
    string cacheControl?;
    # The MD5 hash of the blob's content
    string contentMd5?;
|};

# A byte range, with inclusive start and end offsets.
public type ByteRange record {|
    # The first byte of the range
    int startByte;
    # The last byte of the range
    int endByte;
|};

# The identifier and state of a copy at the moment the service accepted it.
public type CopyInfo record {|
    # The identifier of the copy operation, which `abortCopy` cancels
    string copyId;
    # The copy's state at acceptance, which may already be `SUCCESS` for a small copy
    CopyStatus copyStatus;
|};

# The state of a blob's most recent copy operation.
public type CopyStatusInfo record {|
    # The identifier of the copy operation
    string copyId;
    # The copy's state
    CopyStatus copyStatus;
    # The URL the content was copied from
    string copySource;
    # The bytes copied so far, as `copied/total`
    string copyProgress?;
    # When the copy completed
    time:Utc copyCompletionTime?;
    # The service's description of a failed or aborted copy
    string copyStatusDescription?;
|};

# One blob matched by an index-tag query.
public type TaggedBlobEntry record {|
    # The blob's container-relative path
    string path;
    # The blob's index tags
    map<string> tags;
|};

# One written byte range of a page blob.
public type PageRange record {|
    # The range's start offset in bytes
    int offset;
    # The range's length in bytes
    int length;
|};

# One block of a block blob.
public type BlockInfo record {|
    # The block's base64 identifier
    string blockId;
    # The block's size in bytes
    int sizeBytes;
|};

# A block blob's committed and staged blocks.
public type BlockList record {|
    # The blocks that make up the blob's current content
    BlockInfo[] committedBlocks;
    # The blocks staged but not yet committed
    BlockInfo[] uncommittedBlocks;
|};
```

#### 8.4 Account types

```ballerina
# The account's blob service configuration. A group present in the record replaces that group
# whole; a group absent is left unchanged.
public type ServiceProperties record {|
    # Hourly request-metrics collection
    MetricsProperties hourMetrics?;
    # Per-minute request-metrics collection
    MetricsProperties minuteMetrics?;
    # Classic request logging
    LoggingProperties logging?;
    # The CORS rules; an empty array deletes every rule
    CorsRule[] cors?;
    # The blob soft-delete retention policy, the prerequisite for `undeleteBlob`
    RetentionPolicy deleteRetentionPolicy?;
    # The static website settings
    StaticWebsiteProperties staticWebsite?;
    # The service version applied to requests that do not name one
    string defaultServiceVersion?;
|};

# How long soft-deleted blobs, or metrics and log data, are retained.
public type RetentionPolicy record {|
    # Whether the retention policy is enabled
    boolean enabled;
    # The number of days a deleted resource is retained
    int days?;
|};

# Request-metrics collection for the blob service.
public type MetricsProperties record {|
    # The metrics configuration version
    string version;
    # Whether metrics collection is enabled
    boolean enabled;
    # Whether per-API metrics are collected
    boolean includeApis?;
    # How long the metrics data is retained
    RetentionPolicy retentionPolicy?;
|};

# Classic request logging for the blob service.
public type LoggingProperties record {|
    # The logging configuration version
    string version;
    # Whether read requests are logged
    boolean read;
    # Whether write requests are logged
    boolean write;
    # Whether delete requests are logged
    boolean delete;
    # How long the log data is retained
    RetentionPolicy retentionPolicy?;
|};

# One cross-origin resource sharing rule.
public type CorsRule record {|
    # The origins allowed to make cross-origin requests
    string[] allowedOrigins;
    # The HTTP methods allowed in cross-origin requests
    string[] allowedMethods;
    # The request headers the origin may specify
    string[] allowedHeaders;
    # The response headers exposed to the client
    string[] exposedHeaders;
    # How long a browser may cache the preflight response, in seconds
    int maxAgeInSeconds;
|};

# The account's static website settings.
public type StaticWebsiteProperties record {|
    # Whether static website hosting is enabled
    boolean enabled;
    # The blob served for a directory request
    string indexDocument?;
    # The blob served when a request matches nothing
    string errorDocument404Path?;
    # The default index document path
    string defaultIndexDocumentPath?;
|};

# The storage account's SKU, kind, and namespace type.
public type AccountInfo record {|
    # The account's SKU name (e.g. `Standard_LRS`)
    string skuName;
    # The account kind (e.g. `StorageV2`)
    string accountKind;
    # Whether the account has a hierarchical namespace (Azure Data Lake Storage Gen2), on which
    # directories are real and renames exist through a different endpoint
    boolean isHierarchicalNamespaceEnabled;
|};

# A key for signing user-delegation SAS tokens, obtained from `AdminClient.getUserDelegationKey`.
public type UserDelegationKey record {|
    # The object ID of the Entra ID identity the key was issued to
    string signedObjectId;
    # The tenant the identity belongs to
    string signedTenantId;
    # When the key becomes valid
    time:Utc signedStart;
    # When the key expires; tokens signed with it cannot outlive this
    time:Utc signedExpiry;
    # The service the key applies to
    string signedService;
    # The service version that issued the key
    string signedVersion;
    # The key value used to sign tokens
    string value;
|};
```

#### 8.5 SAS types

```ballerina
# The permissions granted by a blob SAS. Every permission is off unless enabled.
public type BlobSasPermissions record {|
    # Read the blob's content, properties, and metadata
    boolean read = false;
    # Append a block to the append blob
    boolean add = false;
    # Create the blob
    boolean create = false;
    # Write the blob's content, properties, and metadata
    boolean write = false;
    # Delete the blob
    boolean delete = false;
    # Read and write the blob's index tags
    boolean tag = false;
|};

# The permissions granted by a container SAS: the blob permissions, plus listing and tag queries.
public type ContainerSasPermissions record {|
    *BlobSasPermissions;
    # List the container's blobs
    boolean list = false;
    # Run an index-tag query
    boolean filter = false;
|};

# The values shared by the container and blob SAS tokens. A parameter may be carried by the
# stored access policy or by the token, but not both.
public type ServiceSasSignatureValues record {|
    # When the token expires. May be omitted only when `identifier` supplies it
    time:Utc expiryTime?;
    # A stored access policy on the container whose window and permissions the token inherits
    string identifier?;
    # When the token becomes valid; omit for immediately valid
    time:Utc startTime?;
    # The protocols a request presenting the token may use
    SasProtocol protocol?;
    # An IP address or range the requests must come from (e.g. `168.1.5.60-168.1.5.70`)
    string ipRange?;
|};

# The values signed into a container SAS token.
public type ContainerSasSignatureValues record {|
    *ServiceSasSignatureValues;
    # The permissions granted. May be omitted only when `identifier` supplies them
    ContainerSasPermissions permissions?;
|};

# The values signed into a blob SAS token.
public type BlobSasSignatureValues record {|
    *ServiceSasSignatureValues;
    # The permissions granted. May be omitted only when `identifier` supplies them
    BlobSasPermissions permissions?;
|};

# The permissions granted by an account-level SAS. Every permission is off unless enabled.
public type AccountSasPermissions record {|
    # Read content, properties, and metadata
    boolean read = false;
    # Write content, properties, and metadata
    boolean write = false;
    # Delete resources
    boolean delete = false;
    # List containers and their blobs
    boolean list = false;
    # Add content (append-style operations)
    boolean add = false;
    # Create new resources
    boolean create = false;
    # Update a queued message; required by the `Listener`
    boolean update = false;
    # Get and delete queued messages; required by the `Listener`
    boolean process = false;
    # Read and write blob index tags
    boolean tag = false;
    # Query blobs by their index tags
    boolean filter = false;
|};

# The storage services an account SAS covers.
public type AccountSasServices record {|
    # The blob service
    boolean blob = false;
    # The queue service; enable it for a `Listener` credential
    boolean queue = false;
|};

# The resource types an account SAS covers.
public type AccountSasResourceTypes record {|
    # Service-level operations, such as reading the service properties
    boolean 'service = false;
    # Container-level operations, such as creating or listing containers
    boolean container = false;
    # Object-level operations on a blob
    boolean 'object = false;
|};

# The values signed into an account-level SAS token.
public type AccountSasSignatureValues record {|
    # When the token expires
    time:Utc expiryTime;
    # The permissions granted
    AccountSasPermissions permissions;
    # The services the token covers
    AccountSasServices services;
    # The resource types the token covers
    AccountSasResourceTypes resourceTypes;
    # When the token becomes valid; omit for immediately valid
    time:Utc startTime?;
    # The protocols a request presenting the token may use
    SasProtocol protocol?;
    # An IP address or range the requests must come from (e.g. `168.1.5.60-168.1.5.70`)
    string ipRange?;
|};
```

#### 8.6 Options records

```ballerina
# Options for `abortCopy`.
public type AbortCopyOptions record {|
    *LeaseOptions;
|};

# Options for `setContainerAccessPolicy`.
public type AccessPolicyOptions record {|
    *LeaseOptions;
|};

# Options for the append-block operations.
public type AppendBlockOptions record {|
    *LeaseOptions;
|};

# Options for `Client.listBlobs`.
public type BlobListOptions record {|
    # Return only blobs whose name begins with this prefix
    string prefix?;
    # Group names that extend past this delimiter into a single prefix entry
    string delimiter?;
    # Include each blob's metadata
    boolean includeMetadata = false;
    # Include each blob's index tags
    boolean includeTags = false;
    # Include blob snapshots
    boolean includeSnapshots = false;
    # Include soft-deleted blobs
    boolean includeDeleted = false;
|};

# Options for `setBlobMetadata`.
public type BlobMetadataOptions record {|
    *LeaseOptions;
|};

# Options for `Client.listBlobsPage`.
public type BlobPageOptions record {|
    *BlobListOptions;
    # The maximum number of blobs in the page, up to the service maximum of 5,000
    int pageSize?;
    # Resume from a previous `BlobList.nextMarker`
    string marker?;
|};

# Options for `createContainer`.
public type ContainerCreateOptions record {|
    # The container's initial metadata
    map<string> metadata?;
    # The anonymous access level. Omit to create a private container. Anonymous access also
    # requires the storage account to permit it
    PublicAccess publicAccess?;
|};

# Options for `AdminClient.listContainers`.
public type ContainerListOptions record {|
    # Return only containers whose name begins with this prefix
    string prefix?;
    # Include each container's metadata
    boolean includeMetadata = false;
    # Include soft-deleted containers
    boolean includeDeleted = false;
    # The maximum number of containers to return; omit for all
    int 'limit?;
    # Resume from a previous `ContainerList.nextMarker`
    string marker?;
|};

# Options for `setContainerMetadata`.
public type ContainerMetadataOptions record {|
    *LeaseOptions;
|};

# Options for `setContentHeaders`.
public type ContentHeaderOptions record {|
    *LeaseOptions;
|};

# Options for the copies. An asynchronous copy over a leased destination requires that lease to
# be infinite.
public type CopyOptions record {|
    *LeaseOptions;
    # The metadata stored with the destination blob; when omitted, the destination inherits
    # the source's metadata
    map<string> metadata?;
    # The index tags stored with the destination blob
    map<string> tags?;
    # The access tier the destination blob starts in
    AccessTier accessTier?;
|};

# Options for creating an append blob or a page blob.
public type CreateBlobOptions record {|
    *LeaseOptions;
    # The content headers stored with the new blob
    ContentHeaders contentHeaders?;
    # The metadata stored with the new blob
    map<string> metadata?;
    # The index tags stored with the new blob
    map<string> tags?;
|};

# Options for `createSnapshot`.
public type CreateSnapshotOptions record {|
    *LeaseOptions;
    # The snapshot's own metadata; when omitted, the snapshot inherits the blob's metadata
    map<string> metadata?;
|};

# Options for `deleteBlob`.
public type DeleteBlobOptions record {|
    *LeaseOptions;
    # What happens to the blob's snapshots. Required when the blob has snapshots
    DeleteSnapshotsOption deleteSnapshots?;
    # Deletes this snapshot instead of the blob
    string snapshotId?;
|};

# Options for `deleteContainer`.
public type DeleteContainerOptions record {|
    *LeaseOptions;
|};

# Options for `download`.
public type DownloadOptions record {|
    # Reads only this byte range of the blob
    ByteRange range?;
    # Reads this snapshot instead of the live blob
    string snapshotId?;
|};

# Options for `getBlob`, extending the download options with the binding format.
public type GetBlobOptions record {|
    *DownloadOptions;
    # The binding format for record targets; when absent, the format is inferred from the
    # path's extension (`.json`, `.xml`, `.csv`)
    FileFormat fileFormat?;
|};

# The lease a write must carry. Included by every option record of a lease-guarded write.
public type LeaseOptions record {|
    # The active lease id, required when the target is leased
    string leaseId?;
|};

# Options for the page write operations.
public type PageOptions record {|
    *LeaseOptions;
|};

# Options for `listPageRanges`.
public type PageRangeOptions record {|
    # Restricts the listing to this byte range
    ByteRange range?;
    # Lists the ranges of this snapshot instead of the live blob
    string snapshotId?;
|};

# Options for `setAccessTier`.
public type SetAccessTierOptions record {|
    *LeaseOptions;
    # How quickly an archived blob is rehydrated; meaningful when leaving the archive tier
    RehydratePriority rehydratePriority?;
|};

# Options for `stageBlockFromUrl`.
public type StageBlockFromUrlOptions record {|
    *LeaseOptions;
    # Stages only this byte range of the source instead of its whole content
    ByteRange sourceRange?;
|};

# Options for `stageBlock`.
public type StageBlockOptions record {|
    *LeaseOptions;
|};

# Options for the index-tag writes.
public type TagOptions record {|
    *LeaseOptions;
|};

# Options for `upload`, extending the upload options with the serialization format.
public type UploadContentOptions record {|
    *UploadOptions;
    # The serialization format for structured content; when absent, the format is inferred
    # from the destination path's extension (`.json`, `.xml`, `.csv`)
    FileFormat fileFormat?;
|};

# Options for the uploads.
public type UploadOptions record {|
    *LeaseOptions;
    # The content headers stored with the new blob
    ContentHeaders contentHeaders?;
    # The metadata stored with the new blob
    map<string> metadata?;
    # The index tags stored with the new blob
    map<string> tags?;
    # The access tier the new blob starts in
    AccessTier accessTier?;
|};
```

#### 8.7 Transport types

```ballerina
# Settings of the HTTP proxy the connector's traffic goes through.
public type ProxyConfig record {|
    # The proxy host name or address
    string host;
    # The proxy port
    int port;
    # The user name, when the proxy requires authentication
    string username?;
    # The password, when the proxy requires authentication
    string password?;
    # Host names that bypass the proxy
    string[] nonProxyHosts?;
|};

# A PKCS12 or JKS certificate store and the password that opens it.
public type CertStore record {|
    # Path to the store file
    string path;
    # The store password
    string password;
|};

# TLS configuration for the connector's HTTPS traffic.
public type SecureSocket record {|
    # The trusted CA certificates: a PEM file path, or a truststore with its password
    CertStore|string cert?;
    # The client identity for mutual TLS: a certificate and key pair, or a keystore with its
    # password
    CertKey|CertStore key?;
    # The TLS protocol versions offered during the handshake (e.g. `["TLSv1.3", "TLSv1.2"]`)
    string[] protocolVersions?;
    # The cipher suites offered during the handshake
    string[] ciphers?;
    # Whether the server certificate's revocation status is checked
    boolean validateRevocation?;
    # The Server Name Indication host name sent during the handshake when the endpoint is an IP
    # address; for a host name endpoint, that host name is sent
    string sniHostName?;
    # The TLS session timeout, in seconds
    decimal sessionTimeoutSeconds?;
|};

# A certificate and private key pair identifying the client for mutual TLS.
public type CertKey record {|
    # Path to the client certificate file
    string certFile;
    # Path to the client private key file, in PKCS#8 form (plain or encrypted)
    string keyFile;
    # The password protecting the private key, when it is encrypted
    string keyPassword?;
|};
```

## Alternatives

* **Revamp `azure_storage_service` in place.** Rejected: the hand-written protocol layer remains the maintenance burden, and the combined Blob-plus-Files packaging contradicts the one-package-per-service pattern of the rest of the Azure ecosystem.
* **Generate a client from the REST/OpenAPI definition.** Rejected: the generated client would still leave Shared Key signing, SAS construction, retry, and chunked transfer to be implemented and maintained by hand; the official SDK already encapsulates all of it and tracks new API versions.
* **One flat account-scoped client** taking `(containerName, path)` on every operation, as `ballerinax/aws.s3` does. Rejected: the wrapped SDK has a container-scoped client class carrying the container surface, so the two-tier split mirrors it. s3's flat client mirrors *its* SDK, which has no bucket-scoped client.
* **A polling listener over the container**, the shape the sibling connector uses. Rejected: each tick would re-list the watched prefix, so cost grows with container size; deletions are invisible to a stateless poll; and because blob storage has no rename, the claim-by-move pattern that makes a polling consumer safe is not atomic. The sibling polls because Azure Files is not an Event Grid source.
* **The change feed as the event source.** Rejected: it is a replay and audit log rather than an event source. Its documented latency is on the order of minutes, its own documentation redirects latency-sensitive consumers to events, and its Java reader has never shipped a stable release.
* **Offering both an Event Grid listener and a polling listener.** Rejected: it doubles the listener surface, the compiler plugin, and the delivery-semantics story for no clear gain.
* **One service per listener**, the sibling's rule. Rejected: one queue carries every container's events and a queue is competing-consumer, so a listener must serve many containers (5.1).
* **An account-scoped `Caller`** taking a leading `containerName` on every operation. Rejected: its signatures diverged from `Client`'s, so handler code could not be shared with client code.
* **A content-free created handler** beside the content handlers. Rejected: with two event types the only content-free event is deletion, and `ftp` and `smb` ship the six-handler shape; a handler that wants a created event without its content declares a stream form and does not read it.
* **Auto-consume actions (`afterProcess` / `afterError`)** as in the sibling. Rejected: acknowledging the queue message already consumes the event, and a blob "move" is an asynchronous copy plus a delete that cannot carry the sibling's atomic-rename guarantee under the same name.
* **A row-level CSV fail-safe on the listener.** Rejected: the sibling removed the same option in its own review.
* **A conditional content fetch on `event.eTag`.** Rejected: a rapidly replaced blob's first event would then deliver no content, and its second event covers the case; `event.eTag` is exposed for handlers that need to detect the race.
* **A configurable message-visibility window on the listener.** Rejected: a fixed window with background extension means a slow handler cannot lose its message, whereas an exposed value can be set too low and silently duplicate work.
* **One container listing operation returning an array and one returning a page.** Rejected: the two justified themselves contradictorily. One operation carries the marker in and out. Blobs keep `listBlobsPage` beside the stream because a stream cannot carry a marker.
* **`ContainerPage` / `BlobPage`, or s3's `ListObjectsResponse` / `nextContinuationToken`, as the paged-return names.** Rejected: `<Resource>List` with the service's own token name (`nextMarker`) describes both the whole-list and the partial-list case, without importing another service's vocabulary.
* **Two Entra chain records with singleton `kind` types.** Rejected in review: one record with an `EntraIdKind` enum selects structurally just as well, and `clientId` is meaningful under both kinds.
* **`transportConfig?`**, absent meaning the SDK's stock client. Rejected in review: the documented timeout values then applied only when some other transport field was set.
* **The SDK's default Netty transport.** Rejected: its Netty line collides with the one the `http` module ships on newer distributions, and a Ballerina program keeps one copy of each library, so a program importing both hangs on every request. The JDK HTTP client transport brings no networking library; the pool-size, idle-timeout, SOCKS, handshake-timeout, and session-resumption settings it cannot honour are not offered.
* **One access-policy operation with both halves optional.** Rejected: one verb for two concepts. Two operations, each reading the current list and resending the other half.
* **A typed tag-filter record for `findBlobsByTags`.** Rejected: the SDK and the ecosystem take the expression string, and local validation gives the same guarantee.
* **An `overwrite` option on the uploads.** Rejected: the deprecated module's `putBlob` replaced unconditionally, the sibling and `aws.s3` replace without one, and the type rule already refuses the destructive cases.
* **A dedicated copy-status operation.** Rejected: `getBlobProperties` is the wire's way of watching a copy.
* **A single page-write operation with a mode enum**, mirroring the wire's Put Page. Rejected: content is required in one mode and forbidden in the other.
* **Leaving block-id validation to the service.** Rejected: an id derived from a counter changes encoded length as it crosses a power of ten, which is how the deprecated connector failed past ten blocks; the equal-length rule is checked before the request.

## Testing

One suite, two backends, a run uses exactly one. With no credentials configured the suite runs against [Azurite](https://github.com/Azure/Azurite), which emulates the Blob and Queue services; that is the run on every pull request. With `liveAccountName` and `liveAccountKey` configured, the same suite runs against a live storage account, and a live run never silently falls back to the emulator.

Azurite covers the surface under Shared Key over HTTP, including leases, snapshots, same-instance copies, index tags and tag queries, access tiers, append blobs, and the block operations. The Azurite version is pinned for reproducibility, with its API-version check bypassed. Four behaviours run only live: soft delete and undelete of blobs and containers, the two from-URL block operations (which Azurite answers with 501), the queue endpoint a listener derives from a SAS URL, and user-delegation SAS; the Event Grid subscription itself is verified by a manual live probe outside the suite — the last because `Get User Delegation Key` is authorized by Entra ID only, and Azurite accepts a bearer token without checking its signature or permissions. The listener's queue-consumption half is tested against Azurite's queue endpoint by enqueuing synthetic Event Grid-shaped messages.

## Risks and Assumptions

- **A crashed process holds its messages for up to ten minutes.** The listener's fixed visibility window has no configuration; this is the bound every Azure Functions queue consumer lives with.
- **Azurite is not Azure.** A green emulator run is necessary but not sufficient; the four live-only behaviours above exist for exactly what it cannot show.
- **The access tier a blob reports is an open string.** A preview tier already exists beyond the enum this module writes, and the service documents that more may be added. Callers comparing against the enum's values are unaffected.
- **Blob events do not distinguish creation from replacement**, and no event fires for metadata, property, or tag changes. The event fields describe the blob as of the moment the event fired.

## Dependencies

* Azure SDK for Java: `com.azure:azure-storage-blob`, `com.azure:azure-storage-queue` (the listener's event path), and `com.azure:azure-identity` (Entra ID support)

## Future Work

- `BlobTierChanged` and `AsyncOperationInitiated` handlers, for observing rehydration without polling.
- Blob versioning, once the version-scoped reads, version listing, and promote and delete operations that make it minimally complete can be justified together.
- Conditional requests (entity-tag and date preconditions) on reads and writes, for optimistic concurrency.
- Batch operations for bulk delete and bulk tier changes.
- Container leases, and an account-level tag query alongside the container-scoped one.
- Immutability policies and legal holds, encryption scopes, and customer-provided keys.

## References

* [Azure Blob Storage documentation](https://learn.microsoft.com/en-us/azure/storage/blobs/storage-blobs-introduction)
* [Azure Blob Storage REST API](https://learn.microsoft.com/en-us/rest/api/storageservices/blob-service-rest-api)
* [Azure SDK for Java, Blob client library](https://learn.microsoft.com/en-us/java/api/overview/azure/storage-blob-readme)
* [Azure Event Grid, Blob Storage event schema](https://learn.microsoft.com/en-us/azure/event-grid/event-schema-blob-storage)
* [Blob index tags](https://learn.microsoft.com/en-us/azure/storage/blobs/storage-manage-find-blobs)
* [Existing connector: `ballerinax/azure_storage_service`](https://central.ballerina.io/ballerinax/azure_storage_service/latest)
* [Sibling connector: `ballerinax/azure.storage.files`](https://github.com/ballerina-platform/ballerina-spec/issues/1457)
* [Azurite, the Azure Storage emulator](https://github.com/Azure/Azurite)
