# Introduce Azure Blob Storage Connector

- Authors
  - Yasan Punchihewa
- Reviewed by
- Created date
  - 2026-08-20
- Updated date
  - 2026-10-17
- Issue
  - [#1489](https://github.com/ballerina-platform/ballerina-spec/issues/1489)
- State
  - Submitted

## Summary

Ballerina's current support for Azure Blob Storage lives inside `ballerinax/azure_storage_service`, a combined package that re-implements the REST protocol by hand. This proposal introduces **ballerinax/azure.storage.blob**, a standalone connector for [Azure Blob Storage](https://learn.microsoft.com/en-us/azure/storage/blobs/storage-blobs-introduction) built on Microsoft's official `com.azure:azure-storage-blob` Java SDK. It provides a two-tier client (`AdminClient` for the account, `Client` bound to one container) with caller-directed data binding on transfers; a `Listener` that consumes blob events through Azure Event Grid and binds blob content for its handlers, with a `Caller` acting on the event's blob; the family's union-typed authentication model; and an error hierarchy keyed on the Azure error code.

## Motivation

The existing `azure_storage_service.blobs` module has accumulated several problems:

1. **Hand-written protocol layer:** Shared Key signing, block-list composition, and response parsing are implemented in Ballerina against the 2019-12-12 REST API version. Every protocol fix and new capability is hand work.
2. **A hard ceiling on uploads, and a defect past it:** `putBlob` refuses content over 50 MiB, and its chunked path derives block identifiers as `blobName:index`, whose base64 forms differ in length from the eleventh block on, which Azure rejects.
3. **Fragile response decoding:** every XML response is passed through a regular expression that strips double quotes before parsing, so any stored value containing one is silently corrupted.
4. **A narrow authentication model:** only Shared Key and a bare SAS token are supported, with no connection string, no SAS URL, and no Microsoft Entra ID, so managed and workload identities cannot be used.
5. **No event-driven support:** there is no listener, so reacting to new blobs means hand-rolled polling that re-lists whole containers.
6. **No tests in CI:** the legacy tests are live-only and every workflow passes `-x test`.
7. **Combined packaging:** blob support is a submodule of a package that also covers Files, against the Azure ecosystem's one-package-per-service pattern.

Microsoft's SDK solves the protocol problems centrally; the connector inherits its signing, SAS construction, retry, parallel chunked transfer, connection-string parsing, and new REST API versions.

## Goals

* Provide an idiomatic Ballerina API for the everyday Azure Blob Storage surface: container lifecycle and service configuration, blob listing, transfers (disk, value, stream), properties and metadata, copies, access tiers, index tags, snapshots, leases, stored access policies, and SAS generation.
* Match Microsoft's two-tier model of an account client and a container client.
* Provide a `Listener` over Event Grid delivery to a storage queue that binds each new blob's content to a typed handler.
* Carry content across the boundary as Ballerina values, through one dependently-typed read and one union write whose format resolves from the blob's path.
* Provide a union-typed authentication model where each member is exactly one real-world credential artifact and misconfiguration is a compile error.
* Provide a consistent, pattern-matchable error hierarchy keyed on the Azure error code.
* Replace the blob surface of `azure_storage_service` completely: every capability it exposed has a path here.

## Non-Goals

- **No Files, Queue, or Table support.** Files is the sibling package `azure.storage.files`; Queue and Table would be their own future packages. The listener's storage queue is an internal detail of the event path, not a queue API.
- **No re-implementation of the wire protocol.** Authentication, signing, retry, and chunked transfer are delegated to the official SDK.
- **No Data Lake Storage Gen2 semantics.** Hierarchical-namespace accounts expose real directories, atomic renames, and POSIX access control through a separate endpoint. The connector reports whether an account has that namespace and otherwise treats every account as flat.
- **No compliance or infrastructure surfaces:** blob versioning, immutability policies and legal holds, encryption scopes and customer-provided keys, object replication, batch operations, blob expiry, the change feed, container leases, and Blob Query.

## Design

### 1. Module overview

The module is `ballerinax/azure.storage.blob`. The hierarchical name groups it with its sibling `azure.storage.files`.

| Type | Scope | Role |
|---|---|---|
| `AdminClient` | the storage account | Container lifecycle, the account's blob service configuration, account information, user delegation keys, account-level SAS tokens |
| `Client` | one container, bound at `init` | Every operation inside that container. The client most applications instantiate |
| `Listener` | one storage queue per service | Consumes the blob events Event Grid subscriptions deliver, and dispatches each to the service that names its queue |
| `Caller` | the event's container, passed to each handler | A curated subset of `Client`, so a handler acts on the event's blob without constructing a client |

**A blob is addressed by a single slash-delimited, container-relative `path`** (for example `"2026/07/invoice.pdf"`). Blob storage has no directories: the slashes are part of the blob's name. A leading slash is stripped. Where two paths co-occur they are named `sourcePath` and `destinationPath`, source first.

| Blob type | Created by | Grows by | Serves |
|---|---|---|---|
| Block blob | every transfer operation, `commitBlockList` | replacing the whole blob, or committing a block list | ordinary content |
| Append blob | `createAppendBlob` | `appendBlock`, `appendBlockFromUrl` | log-style accumulation |
| Page blob | `createPageBlob` | `uploadPages`, `clearPages` at 512-byte alignment | virtual disks and random access |

**A blob's type is fixed for its lifetime.** It is reported in the blob's properties; a type-specific operation on a blob of another type fails with `InvalidBlobTypeError`.

`AdminClient`, `Client`, and `Caller` are isolated client classes holding only immutable configuration, and `Listener` is an isolated class, so each instance is safe to share across strands. Every operation that calls the service is a `remote` method; the SAS generators and the `Listener` lifecycle methods make no service call and are ordinary methods. The clients have no close method: a client holds its connections while reachable, so create it once and reuse it. The `isolated` qualifier is omitted from the signatures below.

### 2. Authentication

The authentication model is the sibling connector's: an account's key, SAS, or Entra identity authenticates against its blob and file endpoints alike.

#### 2.1 The `AuthConfig` union

```ballerina
public type AuthConfig SharedKeyConfig|SasConfig|SasUrlConfig|ConnectionStringConfig|EntraIdConfig;
```

Each member has a unique required field or combination, so the compiler and `Config.toml` select it structurally, with no discriminator; misconfiguration between modes is a compile error.

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

`accountName` is the signing identity, not only a URL component: `serviceUrl` overrides the endpoint alone. Every credential is validated inside `init` with no call to Azure: connection strings are parsed and checked for a blob endpoint, and the explicit records get non-empty, base64, and URL-scheme checks.

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

`DEFAULT_AZURE_CREDENTIAL` tries the environment, a managed identity, and developer sign-ins in turn; `MANAGED_IDENTITY` uses the managed identity alone. `clientId` selects a user-assigned identity under either kind; omitted, the system-assigned identity is used.

An Entra identity authorizes through Azure RBAC:

| Operations | Role | Scope |
|---|---|---|
| Reads and listings | `Storage Blob Data Reader` | container or above |
| Writes and deletes, containers included | `Storage Blob Data Contributor` | container or above; account or above to create a container |
| Access policies, index tags, tag queries | `Storage Blob Data Owner` | container or above |
| `getUserDelegationKey` | `generateUserDelegationKey` action: `Storage Blob Delegator` least; any blob data role | storage account or above, never container scope |
| `getServiceProperties`, `setServiceProperties` | `Storage Account Contributor` | storage account; no data access |
| `Listener` | `Storage Queue Data Contributor` in addition to its blob roles | it receives, updates, sends and deletes messages and creates a missing poison queue; `Storage Queue Data Message Processor` cannot update or send |

#### 2.4 Client configuration

```ballerina
public type ClientConfiguration record {|
    AuthConfig auth;
    RetryConfig retryConfig?;
    TransportConfig transportConfig = {};
|};
```

The configuration is an included record parameter on both clients' `init`, so callers pass its fields as named arguments. `retryConfig` omitted keeps the connector's defaults; `transportConfig` always applies, with the defaults in 2.6 when nothing is set.

#### 2.5 Retry configuration

```ballerina
public type RetryConfig record {|
    RetryPolicyType retryPolicyType = EXPONENTIAL;   // EXPONENTIAL | FIXED_INTERVAL
    int maxTries = 4;
    decimal tryTimeout = 60;
    decimal retryDelay = 4;
    decimal maxRetryDelay = 120;
    string secondaryHostUrl?;                        // geo-redundant read retries
|};
```

The defaults are shared with the sibling connector. Each try is bounded by `tryTimeout`, so a stalled request fails rather than hanging a strand, and `retryDelay` is the base delay under both policy types.

#### 2.6 Transport configuration

```ballerina
public type TransportConfig record {|
    ProxyConfig proxy?;
    ConnectionPoolConfig connectionPool = {};
    SecureSocket secureSocket?;
|};

public type ConnectionPoolConfig record {|
    int maxConnections = 50;
    decimal idleTimeout = 60;
    decimal connectTimeout = 10;
    decimal readTimeout = 60;
|};
```

`proxy` routes traffic through a proxy and `secureSocket` configures TLS, mutual TLS included, with the types of 8.7. The pool values above apply to every client unless overridden.

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

With no `'limit`, `listContainers` returns every container and `nextMarker` is absent; with one, it returns up to that many and `nextMarker` when more remain, to be passed back as `marker`. `createContainer` accepts metadata and a public access level. `deleteContainer` takes a lease id for a container leased elsewhere and is soft under the account's container soft-delete retention policy; `undeleteContainer` restores a soft-deleted container, whose `deletedContainerVersion` comes from `listContainers({includeDeleted: true})` as `ContainerInfo.deletedVersion`.

`ServiceProperties` (8.4) models the whole configuration document as optional groups, each replaced whole when present. The blob retention policy is the prerequisite for `undeleteBlob`; container soft delete, the prerequisite for `undeleteContainer`, is a storage account setting outside the service properties.

`getAccountInfo` reports the SKU, the account kind, and whether the account has a hierarchical namespace. `getUserDelegationKey` requires an Entra ID credential with an account-scope role (2.3); the key is valid at most 7 days and signs user-delegation SAS tokens (4.10). `generateAccountSas` signs locally with the account key and makes no service call; the signature values select the services (blob, queue), resource types, permissions, and window, and covering both produces the account SAS a `Listener` needs.

### 4. The `Client`

```ballerina
public function init(string containerName, *ClientConfiguration config) returns Error?;
```

Binding is lazy: `init` makes no call to Azure, so the first operation against a nonexistent container fails with `NotFoundError`; the up-front check is `AdminClient.hasContainer`. The surface is 41 remote operations plus four ordinary SAS generators. A method name carries a tier token only where a bare verb would clash or mislead, as in `listBlobs`, whose flat listing returns blobs only; `upload`, `setContentHeaders`, `createSnapshot` stay bare.

#### 4.1 Container-level operations

```ballerina
remote function getContainerProperties() returns ContainerProperties|Error;
remote function setContainerMetadata(map<string> metadata, ContainerMetadataOptions? options = ()) returns Error?;
remote function getContainerAccessPolicy() returns ContainerAccessPolicy|Error;
remote function setPublicAccess(PublicAccess access, AccessPolicyOptions? options = ()) returns Error?;
remote function setContainerAccessPolicy(SignedIdentifier[] identifiers, AccessPolicyOptions? options = ()) returns Error?;
```

Metadata is free-form annotation stored and returned verbatim; `setContainerMetadata` replaces the complete set, and it is read back through `getContainerProperties`.

The anonymous access level and the stored access policies are read together and written separately. `setPublicAccess` changes the level and leaves the policies as they are; `setContainerAccessPolicy` replaces the policies (at most five; `[]` removes them all) and leaves the level as it is. Each of the two reads the current access control list first and resends the half it does not own, so each call is two requests, and two processes updating the two halves at the same time can overwrite each other: the last writer wins, and an application that changes both concurrently serialises its own calls.

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

`listBlobs` returns one lazy stream, so memory stays bounded over millions of blobs. Without a delimiter every blob is listed whatever the slashes in its name; with one, names extending past the next delimiter collapse into a single entry whose `isPrefix` is set, which is fed back as the next call's `prefix` to descend a level. `listBlobsPage` returns one page and the `nextMarker` to resume from, for a listing checkpointed across process restarts.

`hasBlob` follows `hasContainer`'s rule. `deleteBlob` refuses a blob that has snapshots unless `DeleteBlobOptions` says what to do with them; its options also delete one snapshot instead of the blob, and pass a lease id. `undeleteBlob` restores a soft-deleted blob together with its soft-deleted snapshots.

A blob's properties are read whole and written through three narrower operations, because the wire has no whole-properties setter:

| Group | Read | Written by | Semantics |
|---|---|---|---|
| System properties: timestamps, entity tag, size, blob type, lease state, copy state | `getBlobProperties` | the service | never written directly |
| Content headers: `Content-Type`, `Cache-Control`, encoding, language, disposition, MD5 | `getBlobProperties` | `setContentHeaders` | replaces the whole set; a header omitted from the record is cleared |
| Metadata: user key/value pairs | `getBlobProperties` | `setBlobMetadata` | replaces the whole set |
| Access tier | `getBlobProperties` | `setAccessTier` (4.5) | |

There is no rename: on a flat-namespace account relocating a blob is a copy followed by a delete, each step observable.

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

The disk transfers do no format detection and no conversion. Both take full paths including the file name, the local path first for the upload; neither deletes its source. `download` fails with a client-side `Error` when the local file already exists.

The value transfers use identical unions in both directions, so anything written is readable back in the same type. The union is listed rather than `anydata`, and carries no `string[][]`, which is both `json` and a list. Positional or headerless CSV is written as a `string` or `byte[]` and parsed with `ballerina/data.csv`.

**The format resolves first — from the operation's `fileFormat` option, else from the path's extension — and the value is then checked against it.**

| Format | Selected by | Members serialized | Members bound on read |
|---|---|---|---|
| none | no `fileFormat`, no `.json`/`.xml`/`.csv` extension | `byte[]`, `string`, byte stream | `byte[]`, `string`, byte stream |
| JSON | `JSON` or `.json` | `json`, `record {}` | `json`, a record, a record array |
| XML | `XML` or `.xml` | `xml`, `record {}` (one element; a record array has no wrapper name) | `xml`, a record |
| CSV | `CSV` or `.csv` | `record {}[]`, `stream<record {}>` | a record array, a record stream |

`byte[]`, byte streams and `string` pass through untouched under every format. Under XML a record becomes a single-element document whose root element is named `root`; `@xmldata:Name` renames member elements, not the root. Under CSV a record array is written with a header row that is the union of every record's field names in first-seen order, with nil or absent members as empty cells; a record stream is written row by row as it is pulled, so its header is the first record's field names, and a later record's extra field is not added to a header already written. An empty array or an exhausted stream writes an empty blob with no header row.

| Destination | `upload` / `uploadFromFile` |
|---|---|
| no blob | creates a block blob |
| block blob | replaces it; its snapshots are retained |
| append or page blob | `InvalidBlobTypeError` — delete it first |
| archived blob | `ArchivedBlobError` |

There is no `overwrite` option. Content over the single-request threshold is chunked and transferred in parallel in both directions, so memory stays bounded. A byte stream is staged as blocks and committed at the end, with no content length needed up front; until that commit the destination blob does not exist, so a failed stream upload leaves no partial blob.

When the connector chose the serialization and the caller set no explicit content type, the blob's content type matches the format applied. An explicit content type always wins, and content passed through untouched gets no automatic type.

#### 4.4 Copy operations

```ballerina
remote function copyBlob(string sourcePath, string destinationPath, CopyOptions? options = ()) returns CopyInfo|Error;
remote function copyBlobFromUrl(string sourceUrl, string destinationPath, CopyOptions? options = ()) returns CopyInfo|Error;
remote function abortCopy(string path, string copyId, AbortCopyOptions? options = ()) returns Error?;
```

Copies are asynchronous: `CopyInfo` reports its identifier and status at acceptance. A pending copy is watched through `getBlobProperties`, whose result carries the state of the blob's most recent copy, and cancelled with `abortCopy`. `copyBlob` copies within the bound container under the client's credentials. `copyBlobFromUrl` copies from any Azure Storage URL the service can read: a source in the same account is authorized by the client's credential; a source that is not publicly readable elsewhere carries its own authorization in the URL.

#### 4.5 Access tiers, index tags, and snapshots

```ballerina
remote function setAccessTier(string path, AccessTier accessTier, SetAccessTierOptions? options = ()) returns Error?;
remote function setTags(string path, map<string> tags, TagOptions? options = ()) returns Error?;
remote function getTags(string path) returns map<string>|Error;
remote function findBlobsByTags(string query) returns stream<TaggedBlobEntry, Error?>|Error;
remote function createSnapshot(string path, CreateSnapshotOptions? options = ()) returns string|Error;
```

`setAccessTier` changes the tier and, for an archived blob, starts rehydration with the priority the options carry. An archived blob's content can be neither read nor replaced until rehydration completes, which takes hours; its properties, metadata, and tags stay available, and copying it to an online-tier destination rehydrates without disturbing the original.

Index tags differ from metadata: the service indexes them, so they answer queries without a listing, and they carry their own SAS permission (`t`, and `f` for queries). Tags are set and read whole. The service refuses index tags on an account with a hierarchical namespace, so the tag operations fail there with the service's error. The index is eventually consistent, so `findBlobsByTags` may briefly lag a `setTags` write; `getTags` always reads the blob's current tags.

| Tag rule | Value |
|---|---|
| Tags per blob | at most 10 |
| Key length | 1 to 128 characters |
| Value length | 0 to 256 characters |
| Characters, keys and values | `a-z`, `A-Z`, `0-9`, and ` +-.:=_/` |
| Case | sensitive |

`setTags` checks these rules locally. `findBlobsByTags` takes the service's filter expression — keys double-quoted, values single-quoted, operators `=`, `>`, `>=`, `<`, `<=`, joined by `AND` — for example `"status" = 'done' AND "priority" >= '05'`. The connector checks it locally first (balanced quotes, listed operators, the tag character set) and adds the `@container` clause for the bound container; an expression supplying its own `@container` is refused. A quote cannot appear in a key or a value, so there is no escaping.

`createSnapshot` returns the snapshot's identifier, which selects a snapshot in the read options, in `deleteBlob`, and in a page-range listing. Snapshots are listed through `listBlobs`.

#### 4.6 Lease operations

```ballerina
remote function acquireLease(string path, int leaseDurationSeconds, string? proposedLeaseId = ()) returns string|Error;
remote function renewLease(string path, string leaseId) returns Error?;
remote function releaseLease(string path, string leaseId) returns Error?;
remote function breakLease(string path, int? breakPeriodSeconds = ()) returns int|Error;
remote function changeLease(string path, string leaseId, string proposedLeaseId) returns string|Error;
```

A blob lease locks the blob against writes and deletion by anyone not holding the lease id. `leaseDurationSeconds` is 15 to 60, or -1 for infinite, validated locally. Without a proposed lease id the service generates one. `breakLease` reclaims a lease without holding its id: with no break period a fixed lease runs out its remaining time and an infinite lease breaks immediately; a break period only shortens that. It returns the seconds until the blob is free. `changeLease` hands a lease over atomically.

**While a blob is leased, every write passes the lease id through its options record; reads never need one.** `createSnapshot` alone needs none, but a given id is checked. A blob write's lease id is the blob's; a container lease gates only container deletion, and other container writes fail on a wrong id.

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

A page blob has a fixed capacity, reserved sparsely: unwritten pages read as zeros and only written pages are billed. Offsets and lengths are 512-byte aligned.

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

They are not the large-upload path, which the transfers chunk internally, but for composing a blob from remote pieces and staging content across process restarts.

#### 4.10 SAS generation

```ballerina
public function generateContainerSas(ContainerSasSignatureValues values) returns string|Error;
public function generateSas(string path, BlobSasSignatureValues values) returns string|Error;
public function generateContainerUserDelegationSas(ContainerSasSignatureValues values, UserDelegationKey key) returns string|Error;
public function generateUserDelegationSas(string path, BlobSasSignatureValues values, UserDelegationKey key) returns string|Error;
```

Signing is local, with the client's credential. The account-key variants require a shared-key credential (or a connection string carrying an account key) and are revoked wholesale when the account key rotates. The user-delegation variants sign with a key from `AdminClient.getUserDelegationKey`, so no storage key is handled; they are valid at most 7 days, and stored access policies do not apply to them, so they reject an identifier.

Generation is refused when no identifier is supplied and the expiry or the permissions are missing. The signature values and their permission record come in two shapes, one per scope, so a token cannot ask for a permission its scope does not carry: `ContainerSasSignatureValues` with `ContainerSasPermissions` for the container-scoped methods, and `BlobSasSignatureValues` with `BlobSasPermissions`, without `list` and `filter`, for the blob-scoped ones. Each permission is a boolean whose operation this module offers: `add` for appending, `tag` for index tags, `filter` for tag queries.

### 5. The `Listener` and `Caller`

Azure Blob Storage publishes lifecycle events through Azure Event Grid to Azure Storage queues, which the listener consumes: delivery is near real time, deletions are observable, and the container is never listed. Each queue and the Event Grid subscription feeding it are created once outside the application.

```ballerina
public type ListenerConfiguration record {|
    AuthConfig auth;                         // must span the queue and blob services
    boolean laxDataBinding = false;
    RetryConfig retryConfig?;
    TransportConfig transportConfig = {};
    string queueServiceUrl?;                 // overrides the derived queue endpoint
|};

public type ServiceConfiguration record {|
    string queueName;
    string poisonQueueName?;                 // default "{queueName}-poison"
    int batchSize = 16;                      // messages per receive, 1 to 32
    int newBatchThreshold?;                  // refill trigger, 0 to batchSize; default half, rounded down
    decimal maxPollingInterval = 60;  // ceiling of the empty-queue backoff; above 0
    decimal redeliveryDelay = 0;      // invisibility after a handler failure; 0 to 604,800
    int maxDeliveryCount = 5;                // deliveries before the poison queue; at least 1;
                                             // 1 poisons any unsettled delivery, routine shutdowns
                                             // and redeploys included, on its next receipt
|};

public annotation ServiceConfiguration ServiceConfig on service, class;

public type Service distinct service object {};

public isolated class Listener {
    public isolated function init(*ListenerConfiguration config) returns Error?;
    public isolated function attach(Service serviceRef, string[]|string? name = ()) returns error?;
    public isolated function detach(Service serviceRef) returns error?;
    public isolated function 'start() returns error?;
    public isolated function gracefulStop() returns error?;
    public isolated function immediateStop() returns error?;
}

public isolated function parseEvent(anydata message) returns BlobEvent|Error?;
```

**One credential and one transport serve every queue, poison queue and `Caller` of a listener.** The pool is per remote address (host and port), so blob and queue traffic each get `transportConfig.connectionPool.maxConnections`, shared by all services; `attach` warns, printing both, when the sum of their `batchSize + newBatchThreshold` (the most blob fetches in flight, an upper bound) exceeds it, as three default services do; raise `maxConnections` or lower `batchSize`. `retryConfig.secondaryHostUrl` applies to blob requests only. A listener SAS is an account SAS with `ss=bq`, `srt=co`, `sp=racup`, or `srt=o`, `sp=raup` with pre-created poison queues; each `Caller` operation used adds its letter (`w`, `d`, `t`, the last also for tagged writes). `init` rejects one, or a connection string's `SharedAccessSignature`, carrying `sr` or whose `ss` lacks `b` or `q`; permissions fail at first use.

#### 5.1 Each service names its queue

```ballerina
@blob:ServiceConfig {queueName: "invoice-events"}
isolated service on blobListener {
    isolated remote function onBlobJson(Invoice invoice, blob:BlobEvent event, blob:Caller caller)
            returns blob:DeadLetterError|blob:RetryError|error?;
    isolated remote function onBlobDelete(blob:BlobEvent event, blob:Caller caller) returns error?;
    isolated remote function onError(blob:Error err, blob:BlobEvent? event, blob:Caller? caller) returns error?;
}
```

**Each service names its own queue.** `@blob:ServiceConfig` is required; a non-empty attach point is rejected by the compiler plugin and by `attach`. Several services, each with its own queue, settings and poison queue, attach to one listener. The subscription feeding each queue does all filtering, by container and path (`subjectBeginsWith`, `subjectEndsWith`) and event type (`includedEventTypes`).

| Queue name case | Outcome |
|---|---|
| a name breaking Azure's rules: 3 to 63 lowercase letters, digits and single hyphens, alphanumeric at both ends | rejected |
| `queueName` over 56 characters with no `poisonQueueName` | rejected, naming `poisonQueueName` |
| `poisonQueueName` equal to `queueName` | rejected |
| two attached services of one listener naming the same queue | rejected |
| a poison queue that is another attached service's queue | allowed, for inspection and replay |
| services sharing one poison queue | allowed; replay routes by subject only while their filters share no container, else the ERROR line's source queue is the only record |
| poison queues forming a cycle among one listener's services | rejected; a cycle across listeners or processes cannot be detected |
| consuming a poison queue whose source queue's name exceeds 49 characters | `poisonQueueName` required |

The checks, and the setting ranges commented above, run at `attach`, and at compile time for literals. Several processes consuming one queue are competing consumers, a valid scale-out when they serve one account; per-account consumers need separate queues.

#### 5.2 Handlers

| Handler | First parameter | Fires on |
|---|---|---|
| `onBlob` | `byte[]` or `stream<byte[], error?>` | a created blob no typed handler takes |
| `onBlobText` | `string` | a created `.txt` blob |
| `onBlobJson` | `json`, or a record | a created `.json` blob |
| `onBlobXml` | `xml`, or a record | a created `.xml` blob |
| `onBlobCsv` | `string[][]`, a record array, `stream<string[], error?>`, or `stream<record {}, error?>` | a created `.csv` blob |
| `onBlobDelete` | `BlobEvent` | a deleted blob |
| `onError` | `Error` | a failed receive, an unparseable message, a message past `maxDeliveryCount`, a fetch, binding or `Caller` build failure, or a failed or transiently skipped poison move |

A content handler takes `(content, BlobEvent?, Caller?)` and `onBlobDelete` takes `(BlobEvent, Caller?)`; the listener passes only what is declared. A service declares at least one of the six event handlers. An event handler returns `error?`, optionally listing `blob:DeadLetterError` and `blob:RetryError` (5.4). The compiler plugin validates handlers, parameters and returns.

| `onError` form | Receives |
|---|---|
| `onError(blob:Error err)` | the error |
| `onError(blob:Error err, blob:BlobEvent? event)` | the error and the event |
| `onError(blob:Error err, blob:Caller? caller)` | the error and a `Caller` bound to the event's container |
| `onError(blob:Error err, blob:BlobEvent? event, blob:Caller? caller)` | all three |

The extra parameters are nilable and identified by type; a non-nil form is a compile error, and the error parameter may be `error` or `blob:Error`. They are `()` for a failed receive or an unparseable message, and the `Caller` is `()` when it cannot be built, after which the message settles as an ordinary handler failure (5.4). **`onError` observes and never settles.** A call for a held message, unparseable or past the limit included, runs in its slot under renewal, with the hold-window warnings, before disposal; only a failed receive's call runs before the queue's next poll, pausing it, with a WARNING at each full 10 minutes; an error it returns is logged at WARNING and changes nothing.

**Routing** first checks handlers carrying `@blob:FunctionConfig { namePattern?, contentTypePattern? }`, in the order `onBlobText`, `onBlobJson`, `onBlobXml`, `onBlobCsv`, `onBlob`; either pattern matching in full selects one. Otherwise a `txt`, `json`, `xml` or `csv` extension in any case decides, and any other extension goes to `onBlob`; a name with no extension routes by content type without parameters, JSON, XML and CSV before other `text/*`, else `onBlob`.

```ballerina
public type FunctionConfiguration record {|
    string namePattern?;          // matched against the blob name, the last path segment
    string contentTypePattern?;   // matched against the event's content type without parameters
|};

public annotation FunctionConfiguration FunctionConfig on object function;
```

**An event the service does not handle is acknowledged with a visible warning.**

| Never handled | Filter that stops it |
|---|---|
| an event type the listener does not dispatch (5.3) | `includedEventTypes` |
| a created blob whose routing finds no declared handler and no `onBlob` | an advanced `StringNotEndsWith` on `subject` with that extension, or `StringEndsWith` with the handled ones (or `subjectEndsWith`, one suffix) |
| a no-content created event (5.3) | `StringNotIn` on `data.api` with `CreateFile`, `SftpCreate`, `SftpWrite`; for append and page creates, on `data.blobType` with `AppendBlob`, `PageBlob`, also dropping their copies and deletes |
| a deleted blob on a service without `onBlobDelete` | `includedEventTypes` |

Microsoft documents that a missing key fails `StringNotEndsWith` and `StringNotBeginsWith` and passes `StringNotIn`; a live probe (custom topic, 2026-10-17) observed missing and null keys and empty data passing both `StringNotIn` and `StringNotEndsWith`; the advice relies only on `StringNotIn` for keys that can be absent. The first time each kind is seen on a queue, a WARNING names the queue and the filter, and an unrouted blob's extension; repeats log at debug with a count.

**Content is the blob's state at fetch time**, not at event time; `event.eTag` detects a change in between. An empty blob, whatever the event's `contentLength`, gives empty bytes, an empty string or an empty stream, and fails JSON, XML and CSV binding. Binding is strict; under `laxDataBinding`, JSON and CSV record binding treat null as an optional field and an absent member as a nilable field, and XML binding tolerates undeclared elements.

| Fetch outcome | Disposition |
|---|---|
| bound | the handler runs; its return settles the message (5.4) |
| `BlobNotFound`: deleted before the fetch | `onError`, then acknowledged; its deleted event follows only for an individual delete the subscription admits |
| archived blob (`ArchivedBlobError`) | `onError`, then moved to the poison queue, for replay after rehydration |
| content fails to bind (`ContentBindingError`) | `onError`, then moved to the poison queue |
| any other failure: throttling, network, authorization, any other 404 | `onError`, then settled as a handler error (5.4) |

When a listener-produced stream fails to bind an item, a returned `DeadLetterError` or `RetryError` wins, returning the stream's binding error applies the binding row (without `content`), any other error or a panic is an ordinary failure, and `()` acknowledges. Stream content is read in ranged chunks, holding no connection between them, locked to the blob's version: a blob replaced mid-read fails the next chunk with `PreconditionFailedError`; the handler's returned error retries the message, and the new content may be processed twice.

#### 5.3 Events

| Event Grid type | Dispatched to | Note |
|---|---|---|
| `Microsoft.Storage.BlobCreated` | the content handlers | fires for creation **and** replacement, indistinguishably; a no-content created event, from an operation committing no content (`CreateFile`, `SftpCreate`, `SftpWrite`) or a `PutBlob` whose `blobType` is `AppendBlob` or `PageBlob` (no written content; a `CopyBlob` of one dispatches), is never handled; an absent or unknown `blobType` dispatches |
| `Microsoft.Storage.BlobDeleted` | `onBlobDelete` | |
| `BlobTierChanged`, `AsyncOperationInitiated`, `BlobRenamed`, `DirectoryCreated`, `DirectoryRenamed`, `DirectoryDeleted`, `BlobInventoryPolicyCompleted`, `LifecyclePolicyCompleted` | not dispatched; acknowledged with a warning | the first two are Future Work |

Content is committed by a block blob's PutBlob, PutBlockList, CopyBlob, FlushWithClose and SftpCommit; `AsyncOperationInitiated` marks archive rehydration (Set Blob Tier, or Copy Blob from an archived blob) on any account, and on a hierarchical-namespace account a copy that does not finish at once, before its `BlobCreated` on commit. Metadata, property, and index-tag changes fire nothing, and on a flat-namespace account neither does an append. Event Grid and CloudEvents schemas are both accepted, detected per message.

**Every message is checked in a fixed order.**

| Step | Failure | Disposition |
|---|---|---|
| 1. delivery count | above `maxDeliveryCount` | moved to the poison queue undispatched, logged as "delivery limit exceeded on receipt"; `onError` before the move and again after a failed or transiently skipped one, each receipt, with the event and `Caller` only for a created event that is not a no-content created event, or a deleted event, from this account (routing not consulted), else `()` for both |
| 2. decode and parse the envelope | not an event in either schema | moved to the poison queue now; `onError` with `()` for event and `Caller`; the error names the queue and the message id |
| 3. event type | neither `BlobCreated` nor `BlobDeleted`, or a no-content created event | never handled: acknowledged with a warning |
| 4. account | a blob event whose `topic` or `source` names no `storageAccounts` segment | unparseable, as step 2 |
| 4. account | the event comes from another storage account | acknowledged, lost to that account's consumer; ERROR the first time each foreign account is seen, then debug with a count |
| 5. route | no handler takes the event | never handled: acknowledged with a warning |

The event's account is the last segment of its `topic` or `source`, `.../storageAccounts/{name}`, never the URL host. It is compared, ignoring case, with the `Caller`'s account, resolved in order:

| Source of the listener's account | Used when |
|---|---|
| the credential's `accountName` | the credential record has one |
| the connection string's `AccountName` | a connection string is used |
| the blob endpoint's first host label | the host carries the `.blob.` label |
| the emulator address's path segment | the endpoint is a path-style emulator address |

**The check fails open.** When no source applies, it is skipped, with a one-time warning assuming a single account. The foreign-account set holds one small entry per account seen. A custom-topic relay loses the account under the Event Grid schema, which stamps the topic, or when a CloudEvents relay rewrites `source`: such events are unparseable and `parseEvent` returns an `Error`. A CloudEvents relay keeping `source` parses normally; otherwise subscribe the system topic directly.

```ballerina
public type BlobEvent record {|
    BlobEventType eventType;
    string accountName;       // from the event's topic or source
    string containerName;
    string path;
    string url;               // blob endpoint, also for dfs events; a copyBlobFromUrl source
    time:Utc eventTime;
    string api;
    string contentType?;
    int contentLength?;
    string blobType?;         // BlockBlob, PageBlob or AppendBlob
    string eTag?;
    string sequencer;         // opaque; comparable per blob path
|};
```

**`parseEvent` reads a blob event delivered elsewhere**, such as to Service Bus. It is pure and takes bytes, a string or JSON, base64 or raw, either schema, one event or a one-element array. It returns a `BlobEvent` for a created or deleted blob, `()` for a valid event of another type or a no-content created event, and an `Error` otherwise. Webhook delivery is out of scope.

#### 5.4 Delivery

Delivery is at-least-once, so handlers are idempotent. A handler writing into a container its subscription covers re-triggers itself; an advanced `StringNotBeginsWith` filter on `subject` excludes its output prefix, or it writes elsewhere. **Settlement follows the handler's return value.**

| Handler outcome | The message |
|---|---|
| returns `()` | deleted |
| returns any other error, or panics | visible again after `redeliveryDelay`; at `maxDeliveryCount` deliveries, moved to the poison queue |
| returns `DeadLetterError` | moved to the poison queue now |
| returns `RetryError` | visible again after its `delay`; the retry counts toward `maxDeliveryCount` |
| returns `RetryError` on the final delivery | moved to the poison queue; the delay is ignored |
| any redelivery delay that would land at or within one hold window of the message's expiry | moved to the poison queue now; never under an infinite message time to live |

`delay` and `redeliveryDelay` are rounded up to whole seconds; `delay` is a requested minimum (negative is 0, capped at 604,800), while `redeliveryDelay` must lie in 0 to 604,800. The two errors count only when returned unwrapped, in any event handler; a panic is always an ordinary failure.

A poison move first checks the hold with a retry-free update, timed out at the lesser of 30 seconds and the hold remaining; its visibility is a renewal's: the ten-minute window, clamped to end 60 seconds before the message's expiry. A pop-receipt mismatch or not found skips the move, only logged; a transient failure skips it and notifies `onError`, under renewal, after which renewal stops and the message returns at its window's end. Only inside the last minute does it send unchecked, risking a rare duplicate. After the check it sends a verbatim copy, creating a missing poison queue, and deletes the original. Poison messages never expire; the dequeue count restarts there.

| Settlement step that fails | Result |
|---|---|
| acknowledge | the message is redelivered; `MessageNotFound` means it is gone |
| delay update or stop-time release | outcome unknown, a retry may have applied it; else the message returns at its hold's end |
| poison move, between the copy and the delete, or a retried send | a duplicate in the poison queue |
| poison move to a missing queue, without create permission | later deliveries repeat what led to the move: the handler when the move followed its return (a `DeadLetterError`, a returned stream binding error, a redelivery outliving the message), else the parse or fetch, binding, `onError` and move; once past `maxDeliveryCount` the move is retried on receipt without them |

A failed settlement step is logged at ERROR with the message id; a failed or transiently skipped poison move also reaches `onError`, naming the poison queue. A handler failure is logged at WARNING with the handler, path, "delivery n of max" and message, a `RetryError`'s with the delay applied after rounding and the cap, or "delay not applied: <reason>" with its poison reason, as is a failure meant for an undeclared `onError`; a returned `DeadLetterError` logs only its poison line. A poison move is logged at ERROR with the source queue, both message ids, the path, the delivery count and a `reason` field: "delivery limit reached", "dead-lettered by the handler: <message>", "retry requested on the final delivery", "would expire before redelivery", "delivery limit exceeded on receipt", "unparseable message", "archived blob" or "content binding failed". Azure Monitor cannot alert on one poison queue's depth; a periodic approximate-count check can.

A received message is hidden for 10 minutes and renewed every 5 minutes while its handler or `onError` runs; a hung one keeps the message and a concurrency slot, warning at each full hold window. Each renewal call times out at the lesser of 30 seconds and the hold remaining, without SDK retries, and is scheduled from the previous attempt's start. After a transient failure (server, network, timeout) the interval halves, to a floor of 1 minute, with a warning, and resets after a success; one hung renewal never delays another. Renewal and settlement of a message are serialised; settlement uses the newest pop receipt and, the hold check aside, keeps `retryConfig`. Renewal is clamped to 60 seconds before expiry and stops when the message is no longer ours (a pop-receipt mismatch, a message or queue not found, a queue being deleted, a refused visibility past expiry), when the expiry margin is reached (logged at ERROR), or on disposal, including after a failed or skipped settlement step. A renewal succeeding on the server but timing out on the client leaves no usable receipt; the message returns after the hold.

An empty queue is re-polled on a randomized exponential backoff rising to `maxPollingInterval`. A receive fetches `batchSize` messages, and the next is fetched once the events in hand fall to `newBatchThreshold`. Up to `batchSize + newBatchThreshold` events are in flight: an `isolated service` with isolated handlers runs them fully in parallel, a non-isolated one in turn at the runtime's lock, interleaving while one waits on I/O (every connector call), so only its Ballerina code is serialised; declare it isolated or lower its `batchSize`. A failed receive reaches only the owning service's `onError`, naming the queue, and the queue keeps retrying.

**Attaching, detaching and stopping never discard in-flight work.**

| Call | Behaviour |
|---|---|
| `attach` on a running listener | starts that service's polling at once |
| `detach` | stops polling that queue and returns at once; running handlers settle normally with a working `Caller`; detaching an unattached service fails |
| `immediateStop` | stops polling and returns at once; in-flight messages are never released |
| `gracefulStop` | stops polling and waits up to 10 minutes for in-flight handlers and running `onError` calls, poll failures' and detached services' included, then returns with a warning; in a process that keeps running the rest still settle |
| SIGTERM or SIGINT | the runtime calls each listener's `gracefulStop` in turn, then exits; handlers running at exit, after `gracefulStop` returns or at the platform's kill after its grace period (30 s by default on Kubernetes), do not settle; their messages reappear within the hold; one listener's wait delays the next |
| a receive returning after `detach` or a stop | its messages are released at once, undispatched, each spending a delivery |
| either stop | connections are released after the last in-flight handler; a second stop does nothing; a stopped listener cannot restart and rejects `attach`; stopping one never started fails |

The queue endpoint is `queueServiceUrl`, else the `serviceUrl` or SAS URL host with its `.blob.` label replaced by `.queue.`, else `https://{accountName}.queue.core.windows.net`; a connection string uses `QueueEndpoint`, else an explicit `BlobEndpoint` relabelled, else `AccountName`, `DefaultEndpointsProtocol` and `EndpointSuffix`. A blob host without that label, or nothing derivable, makes `init` fail, asking for `queueServiceUrl`.

| Time bound | Value | Where set |
|---|---|---|
| Queue message time to live | 7 days by default; longer on the subscription | Event Grid subscription |
| Event Grid retry | 30 attempts or 1,440 minutes (24 hours), whichever first; 1,440 is the ceiling | Event Grid subscription |
| Event Grid dead-letter | off by default; a dead-letter container recovers undelivered events | Event Grid subscription |

The two bounds are independent: a queue unreachable for a day loses its events.

#### 5.5 The `Caller`

**A `Caller` is bound to the event's container**, one small cached entry per container seen, kept for the listener's life, and forwards seven operations of `Client` with identical signatures: `getBlob`, `getBlobProperties`, `download`, `upload`, `deleteBlob`, `copyBlobFromUrl`, and `setTags`. `copyBlobFromUrl` copies into the event's container; copying elsewhere uses a `Client`. The `Caller` cannot be constructed by user code.

#### Why each service names its own queue

An Event Grid subscription already filters by path and event type, and an account's system topic carries up to 500 subscriptions, each with its own queue. Routing again in code was rejected because **the subscription is the one place a split is expressed, and code could split only by container**. The connectors for S3 through SQS and Cloud Storage through Pub/Sub also name the queue or subscription in the service annotation.

#### Why settlement follows the return value

The runtime marks a service method's trace span as an error when it returns one, so settling through the return keeps spans truthful, which "settle, then return `()`" would not. It needs no per-event state on `Caller`, and it ports to SQS and Pub/Sub, whose deadlines take a delay the same way; hence `delay` is a requested minimum. `DeadLetterError` saves `maxDeliveryCount − 1` blob fetches on a permanent failure; `RetryError` honours a retry-after hint.

#### Why content is bound by handler type only

A files listener has already read the file to detect it; this listener has read nothing, and a fetch is a download per event. An archived blob cannot be read at all. Declaring a content handler is therefore the request for content, and `onBlobDelete` never carries any.

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

public type ContentBindingErrorDetail record {| string containerName; string path; byte[] content?; |};
public type ContentBindingError distinct (Error & error<ContentBindingErrorDetail>);
public type DeadLetterError distinct Error;
public type RetryErrorDetail record {| decimal delay; |};
public type RetryError distinct (Error & error<RetryErrorDetail>);
```

A client-side failure is the root `Error` and carries no detail; the three listener errors below are the exception. An error the Azure service raised is a `ServiceError` carrying the HTTP status and the service's error code. **The mapping keys on the error-code string, never on the status alone**; a code that maps to no subtype, such as `AppendPositionConditionNotMet` or any 5xx, stays `ServiceError` with its status and code intact.

| Type | Status | Azure error codes |
|---|---|---|
| `NotFoundError` | 404 | `BlobNotFound`, `ContainerNotFound`, `ResourceNotFound`; for a listener's queue, `QueueNotFound`, `MessageNotFound` |
| `ConflictError` | 409 | `ContainerAlreadyExists`, `BlobAlreadyExists`, `ContainerBeingDeleted`, `SnapshotsPresent`, `PendingCopyOperation`, `NoPendingCopyOperation`, `CopyIdMismatch`, `BlockCountExceedsLimit`, `LeaseAlreadyPresent`, `LeaseAlreadyBroken`, `LeaseNotPresentWithLeaseOperation`, `LeaseIdMismatchWithLeaseOperation`, `LeaseIsBreakingAndCannotBeAcquired`, `LeaseIsBreakingAndCannotBeChanged`, `LeaseIsBrokenAndCannotBeRenewed` |
| `AuthorizationError` | 403 | `AuthenticationFailed`, `AuthorizationFailure`, `AuthorizationPermissionMismatch`, `AuthorizationSourceIPMismatch`, `AuthorizationProtocolMismatch`, `AuthorizationServiceMismatch`, `AuthorizationResourceTypeMismatch`, `InsufficientAccountPermissions`, `AccountIsDisabled`, `UnauthorizedBlobOverwrite` |
| `PreconditionFailedError` | 412 | `LeaseIdMissing`, `LeaseIdMismatchWithBlobOperation`, `LeaseIdMismatchWithContainerOperation`, `LeaseNotPresentWithBlobOperation`, `LeaseNotPresentWithContainerOperation`, `LeaseLost`, `ConditionNotMet`, `TargetConditionNotMet`, `SourceConditionNotMet`, `InfiniteLeaseDurationRequired` |
| `RangeNotSatisfiableError` | 416 | `InvalidRange`, `InvalidPageRange` |
| `ArchivedBlobError` | 409 | `BlobArchived`, `BlobBeingRehydrated` |
| `InvalidBlobTypeError` | 409 | `InvalidBlobType` |

A write other than `createSnapshot` against a leased blob without its lease id (for index tags observed as 412 `LeaseIdMissing`; Microsoft documents 403), a container delete without the container's, and a wrong lease id on any write are `PreconditionFailedError`; a lease operation against a stale id or the wrong state is `ConflictError`.

| Listener error | Raised when | Detail |
|---|---|---|
| `ContentBindingError` | a blob's content fails to bind to the handler's parameter type | `containerName`, `path`, and `content` when it was already read into memory |
| `DeadLetterError` | a handler returns it, to move the message to the poison queue now | none |
| `RetryError` | a handler returns it, to retry after `delay` | `delay`, a requested minimum |

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

    // The extension also drives the binding back.
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

listener blob:Listener blobListener = check new (
    auth = {accountName: "mystorageaccount", accountKey: "..."}
);

// This queue's subscription admits the readings container's .csv blobs.
@blob:ServiceConfig {queueName: "reading-events"}
isolated service on blobListener {
    isolated remote function onBlobCsv(Reading[] rows, blob:BlobEvent event, blob:Caller caller)
            returns blob:DeadLetterError|error? {
        if rows.length() == 0 {
            return error blob:DeadLetterError(string `${event.path} holds no readings`);
        }
        io:println(string `${event.path}: ${rows.length()} readings`);
        check caller->setTags(event.path, {status: "processed"});
    }

    isolated remote function onBlobDelete(blob:BlobEvent event) returns error? {
        io:println(string `${event.path} deleted`);
    }

    isolated remote function onError(blob:Error err, blob:BlobEvent? event) returns error? {
        io:println(string `${event?.path ?: "receive"}: ${err.message()}`);
    }
}
```

```ballerina
import ballerina/io;
import ballerinax/asb;
import ballerinax/azure.storage.blob;

type Reading record {|
    string sensorId;
    decimal celsius;
|};

listener asb:Listener eventListener = check new (
    connectionString = "...",
    entityConfig = {queueName: "blob-events"}
);

final blob:Client readings = check new ("readings",
    auth = {accountName: "mystorageaccount", accountKey: "..."}
);

// Event Grid delivers the readings container's events to a Service Bus queue.
isolated service asb:Service on eventListener {
    isolated remote function onMessage(asb:Message message, asb:Caller caller) returns error? {
        blob:BlobEvent? event = check blob:parseEvent(message.body);
        if event is () || event.eventType != blob:BLOB_CREATED || event.accountName != "mystorageaccount" {
            return;
        }
        Reading[] rows = check readings->getBlob(event.path);
        io:println(string `${event.path}: ${rows.length()} readings`);
    }
}
```

### 8. Type definitions

The types the design sections name without defining; the others are defined where introduced.

#### 8.1 Enumerations

```ballerina
# How the delay between retries grows.
public enum RetryPolicyType {
    EXPONENTIAL = "exponential",
    FIXED_INTERVAL = "fixed"
}

# The proxy protocol.
public enum ProxyType {
    HTTP,
    SOCKS4,
    SOCKS5
}

# The access tiers this module sets on a blob; a blob reports its tier as a plain `string`.
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
    JSON,
    XML,
    CSV
}

# The blob lifecycle event types this module dispatches.
public enum BlobEventType {
    # A blob's content was committed, on creation or on replacement (5.3)
    BLOB_CREATED,
    BLOB_DELETED
}

# The state of a copy operation.
public enum CopyStatus {
    PENDING = "pending",
    SUCCESS = "success",
    ABORTED = "aborted",
    FAILED = "failed"
}

# The lease state of a container or blob.
public enum LeaseState {
    AVAILABLE = "available",
    LEASED = "leased",
    # A fixed-duration lease ran out
    EXPIRED = "expired",
    BREAKING = "breaking",
    BROKEN = "broken"
}

# Whether a container or blob is locked by a lease.
public enum LeaseStatus {
    LOCKED = "locked",
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
    HTTPS = "https",
    HTTPS_HTTP = "https,http"
}
```

#### 8.2 Container types

```ballerina
# A container as returned by the account-level listings.
public type ContainerInfo record {|
    string name;
    time:Utc lastModified;
    string eTag;
    PublicAccess publicAccess;
    LeaseState leaseState;
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
    ContainerInfo[] containers;
    # The marker to resume the listing from; present only when more containers remain
    string nextMarker?;
|};

# The bound container's properties and metadata.
public type ContainerProperties record {|
    time:Utc lastModified;
    string eTag;
    PublicAccess publicAccess;
    # The container's complete metadata set
    map<string> metadata;
    LeaseState leaseState;
    LeaseStatus leaseStatus;
    # Whether a held lease is fixed-duration or infinite, or `()` when no lease is held
    LeaseDuration? leaseDuration;
    boolean hasImmutabilityPolicy;
    boolean hasLegalHold;
|};

# A container's anonymous access level and its stored access policies, carried together.
public type ContainerAccessPolicy record {|
    PublicAccess access;
    # The stored access policies, at most five
    SignedIdentifier[] identifiers;
|};

# One stored access policy: a validity window and a permission string under an identifier.
public type SignedIdentifier record {|
    # The identifier a SAS token references to inherit this policy
    string id;
    time:Utc startTime?;
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
    boolean isPrefix = false;
    # The blob's size in bytes; absent on prefix entries
    int contentLength?;
    time:Utc lastModified?;
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
    BlobEntry[] blobs;
    # The marker to resume the listing from; present only when more blobs remain
    string nextMarker?;
|};

# A blob's properties, metadata, and the state of its most recent copy.
public type BlobProperties record {|
    time:Utc lastModified;
    time:Utc createdTime;
    string eTag;
    # The blob's size in bytes
    int contentLength;
    ContentHeaders contentHeaders;
    # The blob's complete metadata set
    map<string> metadata;
    # The blob type (`BlockBlob`, `AppendBlob`, or `PageBlob`)
    string blobType;
    # The access tier, as the wire's string
    string accessTier?;
    # Whether the tier was inferred rather than set explicitly
    boolean accessTierInferred?;
    # The rehydration state, set while a rehydration from the archive tier is pending
    string archiveStatus?;
    LeaseState leaseState;
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
    string contentType?;
    string contentEncoding?;
    string contentLanguage?;
    string contentDisposition?;
    string cacheControl?;
    string contentMd5?;
|};

# A byte range, with inclusive start and end offsets.
public type ByteRange record {|
    int startByte;
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
    string copyId;
    CopyStatus copyStatus;
    string copySource;
    # The bytes copied so far, as `copied/total`
    string copyProgress?;
    time:Utc copyCompletionTime?;
    # The service's description of a failed or aborted copy
    string copyStatusDescription?;
|};

# One blob matched by an index-tag query.
public type TaggedBlobEntry record {|
    string path;
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
    MetricsProperties hourMetrics?;
    MetricsProperties minuteMetrics?;
    LoggingProperties logging?;
    # The CORS rules; an empty array deletes every rule
    CorsRule[] cors?;
    # The blob soft-delete retention policy, the prerequisite for `undeleteBlob`
    RetentionPolicy deleteRetentionPolicy?;
    StaticWebsiteProperties staticWebsite?;
    # The service version applied to requests that do not name one
    string defaultServiceVersion?;
|};

# How long soft-deleted blobs, or metrics and log data, are retained.
public type RetentionPolicy record {|
    boolean enabled;
    int days?;
|};

# Request-metrics collection for the blob service.
public type MetricsProperties record {|
    string version;
    boolean enabled;
    # Whether per-API metrics are collected
    boolean includeApis?;
    RetentionPolicy retentionPolicy?;
|};

# Classic request logging for the blob service.
public type LoggingProperties record {|
    string version;
    boolean read;
    boolean write;
    boolean delete;
    RetentionPolicy retentionPolicy?;
|};

# One cross-origin resource sharing rule.
public type CorsRule record {|
    string[] allowedOrigins;
    string[] allowedMethods;
    string[] allowedHeaders;
    string[] exposedHeaders;
    # How long a browser may cache the preflight response
    int maxAgeInSeconds;
|};

# The account's static website settings.
public type StaticWebsiteProperties record {|
    boolean enabled;
    # The blob served for a directory request
    string indexDocument?;
    # The blob served when a request matches nothing
    string errorDocument404Path?;
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
    string signedTenantId;
    time:Utc signedStart;
    # When the key expires; tokens signed with it cannot outlive this
    time:Utc signedExpiry;
    string signedService;
    # The service version that issued the key
    string signedVersion;
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
    boolean create = false;
    # Write the blob's content, properties, and metadata
    boolean write = false;
    boolean delete = false;
    # Read and write the blob's index tags
    boolean tag = false;
|};

# The permissions granted by a container SAS: the blob permissions, plus listing and tag queries.
public type ContainerSasPermissions record {|
    *BlobSasPermissions;
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
    boolean delete = false;
    # List containers and their blobs
    boolean list = false;
    # Add content (append-style operations)
    boolean add = false;
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
    time:Utc expiryTime;
    AccountSasPermissions permissions;
    AccountSasServices services;
    AccountSasResourceTypes resourceTypes;
    # When the token becomes valid; omit for immediately valid
    time:Utc startTime?;
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
    string prefix?;
    # Group names that extend past this delimiter into a single prefix entry
    string delimiter?;
    boolean includeMetadata = false;
    boolean includeTags = false;
    boolean includeSnapshots = false;
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
    map<string> metadata?;
    # The anonymous access level. Omit to create a private container. Anonymous access also
    # requires the storage account to permit it
    PublicAccess publicAccess?;
|};

# Options for `AdminClient.listContainers`.
public type ContainerListOptions record {|
    string prefix?;
    boolean includeMetadata = false;
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
    # Index tags; a copy carries none unless set here
    map<string> tags?;
    AccessTier accessTier?;
|};

# Options for creating an append blob or a page blob.
public type CreateBlobOptions record {|
    *LeaseOptions;
    ContentHeaders contentHeaders?;
    map<string> metadata?;
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

# The lease a write carries. Included by every option record of a lease-guarded write.
public type LeaseOptions record {|
    # The active lease id, where 4.6 requires one
    string leaseId?;
|};

# Options for the page write operations.
public type PageOptions record {|
    *LeaseOptions;
|};

# Options for `listPageRanges`.
public type PageRangeOptions record {|
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
    ContentHeaders contentHeaders?;
    map<string> metadata?;
    map<string> tags?;
    AccessTier accessTier?;
|};
```

#### 8.7 Transport types

```ballerina
# Proxy settings for the connector's traffic.
public type ProxyConfig record {|
    ProxyType proxyType = HTTP;
    string host;
    int port;
    string username?;
    string password?;
    string[] nonProxyHosts?;
|};

# A PKCS12 or JKS certificate store and the password that opens it.
public type CertStore record {|
    string path;
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
    string[] ciphers?;
    boolean verifyHostName = true;
    boolean sessionResumption?;
    boolean validateRevocation?;
    string sniHostName?;
    decimal handshakeTimeout?;
    decimal sessionTimeout?;
|};

# A certificate and private key pair identifying the client for mutual TLS.
public type CertKey record {|
    string certFile;
    string keyFile;
    # The password protecting the private key, when it is encrypted
    string keyPassword?;
|};
```

## Alternatives

* **Revamp `azure_storage_service` in place.** Rejected: it keeps the hand-written protocol layer and the combined packaging.
* **Generate a client from the REST/OpenAPI definition.** Rejected: signing, SAS construction, retry, and chunked transfer would stay hand-written.
* **One flat account-scoped client taking `(containerName, path)` on every operation, as `ballerinax/aws.s3` does.** Rejected: the two tiers mirror the SDK's container-scoped client, as s3's flat client mirrors its own SDK.
* **A polling listener over the container, the sibling's shape.** Rejected: each tick re-lists the prefix, so cost grows with container size; a stateless poll misses deletions; and with no rename, claim-by-move is not atomic. The sibling polls because Azure Files is not an Event Grid source.
* **The change feed as the event source.** Rejected: a replay and audit log with minutes of latency, and no stable Java reader.
* **Container routing over one queue, each service attached to a container.** Rejected: it splits only by container, strands events of unclaimed containers, and makes every stream share one batch budget and poison queue.
* **The queue as the attach name.** Rejected: an untyped string reads like a path and leaves no room for the service's consumption settings.
* **One service per listener, the sibling's rule.** Rejected: it multiplies credentials and connection pools.
* **Consumption settings on the listener, or listener defaults with a per-service override.** Rejected: each setting acts on one queue, so two retry counts would need two listeners; a whole-record override drops the listener's values, and field-level inheritance adds a precedence rule.
* **A hard 56-character queue-name cap, so the default poison name always fits.** Rejected: existing 57- to 63-character queues would be locked out.
* **Service Bus as the transport.** Rejected: despite duplicate detection and a native dead-letter queue, it adds a second service and credential, an emulator without Entra ID, and costs more than an idle storage queue's $0.02 a month. `ballerinax/asb` and `parseEvent` read such events.
* **An Event Grid namespace with pull delivery now.** Rejected: CloudEvents schema only, a managed identity to forward the events, an extra hop, and about $29 a month per throughput unit.
* **A separate Storage-queue connector under the listener.** Rejected: no demand for a general queue API.
* **A manual settlement mode with a separate settlement object, as `aws.sqs` ships.** Rejected: additive later.
* **Settlement methods on `Caller`.** Rejected: a `Caller` carries no per-event state, and no sibling mixes settlement into its caller.
* **The failure reason inside the poison message.** Rejected: replay needs the verbatim body and a storage queue message has no properties; the reason is in the correlated log line.
* **`onError(Error, Caller?)` only, the `azure.storage.files` and `ftp` shape.** Rejected: fetch failures would stay anonymous, since a service error carries no path, and a failed receive or an unparseable message has no container for a `Caller`.
* **Failing closed on the account check with a required account field, or trusting the account derived from the endpoint URL.** Rejected: both break custom-domain deployments, the first over a rare case.
* **Hand parsing in the Service Bus example.** Rejected: every user would re-implement base64 decoding, both delivery schemas and array unwrapping.
* **A fixed renewal interval.** Rejected: halving after a transient failure, as the Azure Functions queue consumer does, recovers before the hold lapses.
* **Honouring settlement errors returned from `onError`.** Rejected: a second settlement path beside the handler's return.
* **An account-scoped `Caller` taking a leading `containerName` on every operation.** Rejected: its signatures diverged from `Client`'s, so handler code could not share client code.
* **Auto-consume actions (`afterProcess` / `afterError`) as in the sibling.** Rejected: acknowledging already consumes the event, and a blob "move" is an asynchronous copy plus a delete, not an atomic rename.
* **A row-level CSV fail-safe on the listener.** Rejected: the sibling removed it in review.
* **A conditional content fetch on `event.eTag`.** Rejected: a rapidly replaced blob's first event would deliver nothing, and its second covers the case.
* **A configurable message-visibility window.** Rejected: with background extension a slow handler keeps its message while renewal succeeds; a low exposed value silently duplicates work.
* **One container listing operation returning an array and one returning a page.** Rejected: one operation carries the marker both ways; blobs keep `listBlobsPage` because a stream cannot carry one.
* **`ContainerPage` / `BlobPage`, or s3's `ListObjectsResponse` / `nextContinuationToken`, as the paged-return names.** Rejected: `<Resource>List` with the service's `nextMarker` fits whole and partial lists without another service's vocabulary.
* **Two Entra chain records with singleton `kind` types.** Rejected: one record with an `EntraIdKind` enum selects structurally as well, and `clientId` is meaningful under both kinds.
* **`transportConfig?`, absent meaning the SDK's stock client.** Rejected: the documented pool values then applied only when some other transport field was set.
* **One access-policy operation with both halves optional.** Rejected: one verb for two concepts.
* **A typed tag-filter record for `findBlobsByTags`.** Rejected: the SDK and the ecosystem take the expression string, and local validation gives the same guarantee.
* **An `overwrite` option on the uploads.** Rejected: the deprecated module's `putBlob` replaced unconditionally, the sibling and `aws.s3` replace without one, and the type rule already refuses the destructive cases.
* **A dedicated copy-status operation.** Rejected: `getBlobProperties` is the wire's way of watching a copy.
* **A single page-write operation with a mode enum.** Rejected: content is required in one mode and forbidden in the other.
* **Leaving block-id validation to the service.** Rejected: a counter-derived id changes encoded length past a power of ten, as the deprecated connector's did.

## Testing

One suite runs against one backend: [Azurite](https://github.com/Azure/Azurite), emulating the Blob and Queue services, by default and on every pull request, or a live storage account when `liveAccountName` and `liveAccountKey` are configured, never silently falling back to the emulator. The user-delegation tests also need `liveEntraTenantId`, `liveEntraClientId`, and `liveEntraClientSecret` for an identity holding Storage Blob Data Contributor and Storage Blob Delegator on the account; without them those tests are skipped.

Azurite covers the surface under Shared Key over HTTP, including leases, snapshots, same-instance copies, index tags and tag queries, access tiers, append blobs, and the block operations. The Azurite version is pinned, with its API-version check bypassed. Four behaviours run only live: soft delete and undelete of blobs and containers, the two from-URL block operations (which Azurite answers with 501), the queue endpoint a listener derives from a SAS URL, and user-delegation SAS, the last because Azurite accepts a bearer token without checking it. The Event Grid subscription is verified by a manual live probe outside the suite. The listener's queue half is tested on Azurite with synthetic Event Grid-shaped messages.

## Risks and Assumptions

- **A crashed process holds its messages for up to ten minutes.**
- **Azurite is not Azure.** A green emulator run is necessary but not sufficient; the four live-only behaviours cover what it cannot show.
- **The access tier a blob reports is an open string.** A preview tier already exists beyond the enum this module writes, and more may be added; comparisons against the enum's values are unaffected.
- **Blob events do not distinguish creation from replacement.**

## Dependencies

* Azure SDK for Java: `com.azure:azure-storage-blob`, `com.azure:azure-storage-queue` (the listener's event path), and `com.azure:azure-identity` (Entra ID support)

## Future Work

- `BlobTierChanged` and `AsyncOperationInitiated` handlers, for observing rehydration without polling.
- Blob versioning, once the version-scoped reads, listing, promote and delete that make it minimally complete are justified together.
- Conditional requests (entity-tag and date preconditions) on reads and writes, for optimistic concurrency.
- Batch operations for bulk delete and bulk tier changes.
- Container leases, and an account-level tag query alongside the container-scoped one.
- Immutability policies and legal holds, encryption scopes, and customer-provided keys.
- Event Grid namespace pull delivery.
- A content-free created-event handler, for copy, index and trigger pipelines; a stream form left unread serves today.
- `Client.getBlob` returning `ContentBindingError` on a binding failure.
- An explicit manual settlement mode.

## References

* [Azure Blob Storage documentation](https://learn.microsoft.com/en-us/azure/storage/blobs/storage-blobs-introduction)
* [Azure Blob Storage REST API](https://learn.microsoft.com/en-us/rest/api/storageservices/blob-service-rest-api)
* [Azure SDK for Java, Blob client library](https://learn.microsoft.com/en-us/java/api/overview/azure/storage-blob-readme)
* [Azure Event Grid, Blob Storage event schema](https://learn.microsoft.com/en-us/azure/event-grid/event-schema-blob-storage)
* [Blob index tags](https://learn.microsoft.com/en-us/azure/storage/blobs/storage-manage-find-blobs)
* [Existing connector: `ballerinax/azure_storage_service`](https://central.ballerina.io/ballerinax/azure_storage_service/latest)
* [Sibling connector: `ballerinax/azure.storage.files`](https://github.com/ballerina-platform/ballerina-spec/issues/1457)
* [Azurite, the Azure Storage emulator](https://github.com/Azure/Azurite)
