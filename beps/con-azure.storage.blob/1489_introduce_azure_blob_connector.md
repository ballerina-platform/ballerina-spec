# Introduce Azure Blob Storage Connector

- Authors
  - Yasan Punchihewa
- Reviewed by
- Created date
  - 2026-08-20
- Updated date
  - 2026-08-24
- Issue
  - [#1489](https://github.com/ballerina-platform/ballerina-spec/issues/1489)
- State
  - Submitted

## Summary

Ballerina's current support for Azure Blob Storage lives inside `ballerinax/azure_storage_service`, a combined package that re-implements the Azure Storage REST protocol by hand and is pinned to the 2019-12-12 API version. This proposal introduces **ballerinax/azure.storage.blob**, a standalone connector for [Azure Blob Storage](https://learn.microsoft.com/en-us/azure/storage/blobs/storage-blobs-introduction) built on Microsoft's official `com.azure:azure-storage-blob` Java SDK. It provides a two-tier client (`AdminClient` for account-level operations, `Client` bound to one container) covering container lifecycle and service configuration, blob listing, transfers with caller-directed data binding, copies, access tiers, index tags, snapshots, leases, and the append-blob, page-blob, and block surfaces; a `Listener` that consumes blob lifecycle events through Azure Event Grid, with a `Caller` for handlers; the family's union-typed authentication model; and an error hierarchy keyed on the Azure error code. It is the sibling of `ballerinax/azure.storage.files` and follows its design conventions, diverging only where the blob service's wire contract genuinely differs.

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
* Provide a `Listener` over the service's native eventing path, Event Grid delivering to a storage queue, with a `Caller` so handlers can act on the event's blob without constructing a separate client.
* Carry content across the boundary as Ballerina values, through one dependently-typed read and one union write whose serialization format is resolved from the blob's own path.
* Provide a union-typed authentication model where each member is exactly one real-world credential artifact and misconfiguration is a compile error.
* Provide a consistent, pattern-matchable error hierarchy keyed on the Azure error code.
* **Be a complete replacement for the blob surface of the existing `azure_storage_service` connector**, so that its deprecation strands no user: every capability that module exposed has a path here.

## Non-Goals

- **No Files, Queue, or Table support.** Files is the sibling package `azure.storage.files`; Queue and Table would be their own future packages. The storage queue this connector's listener consumes is an internal detail of the event path, not a queue API.
- **No re-implementation of the wire protocol.** Authentication, signing, retry, and chunked transfer are delegated to the official SDK.
- **No Data Lake Storage Gen2 semantics.** Hierarchical-namespace accounts expose real directories, atomic renames, and POSIX access control through a separate endpoint. The connector reports whether an account has that namespace and otherwise treats every account as flat.
- **No compliance or infrastructure surfaces in the first version:** blob versioning, immutability policies and legal holds, encryption scopes and customer-provided keys, object replication, batch operations, blob expiry, the change feed, container leases, and Blob Query.

## Design

### 1. Module overview

The module is `ballerinax/azure.storage.blob`. The hierarchical name groups it with its sibling `azure.storage.files`, following the pattern of `azure.openai.chat` and `azure.openai.responses`; the leaf is Microsoft's own product noun, lowercased, which is singular here ("Azure Blob Storage") and plural in the sibling ("Azure Files"). The package has two parts: a `ballerina/` module holding the public API and a `native/` Java subproject that adapts it onto `com.azure:azure-storage-blob`.

Microsoft's SDK is structured as a chain of three clients (`BlobServiceClient` account scope, `BlobContainerClient` container scope, `BlobClient` blob scope). The connector exposes the two scopes users actually think in, plus two types for event-driven services:

- **`AdminClient`**: account level. Create, list, delete, and restore containers, read and write the account's blob service configuration, read account information, obtain user delegation keys, and mint account-level SAS tokens.
- **`Client`**: bound to one container at `init`. Every operation inside that container. This is the client most applications instantiate.
- **`Listener`**: consumes blob lifecycle events that an Event Grid subscription delivers to an Azure Storage queue, and dispatches each to the matching handler of its attached service.
- **`Caller`**: passed to each listener handler. It forwards a curated account-scoped subset of `Client`, so a handler can act on the event's blob without constructing a separate client.

The blob level of the SDK chain is not surfaced as a class. Blob operations are methods on `Client` taking a single slash-delimited, container-relative `path` (for example `"2026/07/invoice.pdf"`). Blob storage has no directories: the slashes are part of the blob's name, and the hierarchical listing mode merely groups names by their slash segments. A leading slash is tolerated and stripped, because the wire carries none and every Azure surface the user sees elsewhere shows bare names. Where two paths co-occur they are named `sourcePath` and `destinationPath` in logical source-first order.

Blobs come in three types. Block blobs hold ordinary content and are what every transfer operation creates; append blobs grow by appending blocks and serve log-style accumulation; page blobs are fixed-capacity, 512-byte-aligned random-access blobs that back virtual disks. A blob's type is fixed for its lifetime and is reported in the blob's properties, and a type-specific operation applied to a blob of another type fails with `InvalidBlobTypeError`. Replacing a blob is not an exception: an upload cannot convert the blob at a path, so uploading over an existing append or page blob fails with `InvalidBlobTypeError`. Changing a blob's type means deleting it and writing a new one, which is the wire's own rule — `Put Blob` states that after a blob is created its type cannot be changed unless it is deleted and re-created.

`AdminClient`, `Client`, and `Caller` are isolated client classes holding only immutable configuration, and the `Listener` is an isolated class, so a single instance of any of them can be used safely from concurrent strands. Every operation that calls the service is a `remote` method, invoked with `->`. Methods that make no service call are ordinary methods, invoked with `.`: the `Listener`'s lifecycle methods and the SAS generation methods, which sign tokens locally with the credential the client already holds. The clients hold no releasable resources, so there is no close method; a client that is no longer needed is simply discarded. The `isolated` qualifier is omitted from the signatures below for brevity.

Because `azure-storage-blob` and `azure-storage-file-share` depend on the same `azure-storage-common` artifact, splitting Blob and Files into two Ballerina packages duplicates nothing at the JVM level: the auth, signing, and retry layer is shared by Microsoft's own packaging.

### 2. Authentication

The authentication model is identical to the sibling connector's, because the credential artifacts are the storage account's rather than any one service's: a key, SAS, or Entra identity issued for an account authenticates against blob and file endpoints alike.

#### 2.1 The `AuthConfig` union

```ballerina
# The authentication configuration: exactly one credential-artifact record.
public type AuthConfig SharedKeyConfig|SasConfig|SasUrlConfig|ConnectionStringConfig|EntraIdConfig;
```

```toml
# The fields present select the union member:
# auth = {accountName = "myacct", accountKey = "..."}             # SharedKeyConfig
# auth = {accountName = "myacct", sasToken = "sv=..."}            # SasConfig
# auth = {sasUrl = "https://myacct.blob.core.windows.net/?sv=..."}# SasUrlConfig
# auth = {connectionString = "..."}                               # ConnectionStringConfig
# auth = {kind = "default", accountName = "myacct"}               # DefaultEntraIdConfig
# auth = {kind = "managed-identity", accountName = "myacct"}      # ManagedIdentityConfig
# auth = {accountName = "myacct", tenantId = "...", clientId = "...", clientSecret = "..."}                # ClientSecretConfig
# auth = {accountName = "myacct", tenantId = "...", clientId = "...", certificatePath = "/path/cert.pem"}  # ClientCertificateConfig
# auth = {accountName = "myacct", tenantId = "...", clientId = "...", tokenFilePath = "/path/token"}       # WorkloadIdentityConfig
```

Every member has a unique required field or field combination, so both the compiler and `Config.toml` select the right member by structural matching, with no discriminator field. The two Entra ID chain records, which would otherwise share a field shape, are the exception and carry a `kind` discriminator. Misconfiguration between modes is a compile error.

#### 2.2 Credential records

```ballerina
# Authenticates with the storage account name and key (Shared Key). accountName
# is the signing identity, not merely a URL component, so serviceUrl overrides
# only the endpoint and defaults to https://{accountName}.blob.core.windows.net.
public type SharedKeyConfig record {| string accountName; string accountKey; string serviceUrl?; |};

# Authenticates with a bare shared access signature (SAS) token.
public type SasConfig record {| string accountName; string sasToken; |};

# Authenticates with a fused SAS URL as generated by the Azure portal
# (endpoint and token in one string).
public type SasUrlConfig record {| string sasUrl; |};

# Authenticates with a storage account connection string. The endpoint is
# part of the string, so no separate account name is needed.
public type ConnectionStringConfig record {| string connectionString; |};
```

Every auth mode is validated inside `init` with local computation and no call to Azure: connection strings are parsed strictly and checked for a blob endpoint, and the explicit records get non-empty, base64, and URL-scheme checks. A malformed credential therefore surfaces a specific error at construction rather than an opaque failure at first use.

#### 2.3 Microsoft Entra ID

`EntraIdConfig` is itself a union of five records, one per credential kind: `DefaultEntraIdConfig` (`kind = "default"`, trying the environment, a managed identity, and developer sign-ins in turn), `ManagedIdentityConfig` (`kind = "managed-identity"`, with an optional `clientId` selecting a user-assigned identity), and the three service-principal records distinguished by their unique required field, `ClientSecretConfig` (`clientSecret`), `ClientCertificateConfig` (`certificatePath`, plus an optional `certificatePassword` when the certificate is a PFX rather than a PEM), and `WorkloadIdentityConfig` (`tokenFilePath`, the federated service-account token of a Kubernetes workload). All five require `accountName` and accept a `serviceUrl` override; the service-principal records also require `tenantId` and `clientId`.

The two chain records are told apart by a `kind` field typed as a singleton, not as a `string`, so an ambiguous or unknown value is a compile error rather than a runtime one:

```ballerina
public const DEFAULT_AZURE_CREDENTIAL = "default";
public const MANAGED_IDENTITY = "managed-identity";

public type DefaultEntraIdConfig record {| DEFAULT_AZURE_CREDENTIAL kind; string accountName; string serviceUrl?; |};
public type ManagedIdentityConfig record {| MANAGED_IDENTITY kind; string accountName; string clientId?; string serviceUrl?; |};
```

An Entra identity authorizes data operations through Azure RBAC: `Storage Blob Data Reader` covers reads and listings, and `Storage Blob Data Contributor` adds writes and deletes. `Storage Blob Delegator` permits obtaining a user delegation key; because that operation acts on the whole account, it must be assigned at storage-account, resource-group, or subscription scope, and a container-scoped assignment does not grant it. Container lifecycle and service configuration, the `AdminClient` surface, authorize against the storage account's management actions instead, carried by roles such as `Contributor` — which grant no blob *data* access on their own, so an identity driving both surfaces needs a role from each plane. A `Listener` needs `Storage Queue Data Contributor` in addition to its blob roles: it receives, updates and deletes queue messages and creates the poison queue, and the narrower `Storage Queue Data Message Processor` cannot create a queue.

#### 2.4 Client configuration

```ballerina
public type ClientConfiguration record {|
    AuthConfig auth;
    RetryConfig retryConfig?;          // advanced tier
    TransportConfig transportConfig?;  // advanced tier
|};
```

The configuration is an included record parameter on both clients' `init`, so callers pass its fields as named arguments.

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

These are the Azure Storage family's reviewed defaults, shared with the sibling connector so the two behave alike when the record is omitted. Two deliberately differ from the SDK's own: a per-try timeout of 60 seconds is applied where the SDK ships effectively unbounded, so a stalled request fails rather than hanging a strand, and one base delay applies to both policy types where the SDK varies it per policy.

#### 2.6 Transport configuration

`TransportConfig` covers the HTTP transport: `proxy` routes traffic through an HTTP, SOCKS4, or SOCKS5 proxy with optional credentials and a bypass list; `connectionPool` tunes the maximum number of concurrent connections and the idle, connect, and read timeouts; `secureSocket` configures custom TLS (trust material, a client identity for mutual TLS, offered versions and cipher suites, host-name verification, session reuse, revocation checking, an SNI host name, and handshake and session timeouts). The transport is Netty, chosen over the JDK HTTP client for authenticated proxy support, finer timeouts, and being the SDK's most-tested path.

### 3. The `AdminClient`

The `AdminClient` manages the containers within a storage account: the container lifecycle, the account's blob service configuration, account information, and account-level SAS tokens. For operations scoped to a single container, use `Client`.

```ballerina
public function init(*ClientConfiguration config) returns Error?;

# Returns false only when Azure confirms absence (404); an Error means the
# check itself could not complete, so an auth problem is never misreported
# as a missing container.
remote function hasContainer(string containerName) returns boolean|Error;

# listContainers returns an array, since an account's container count is
# bounded in practice. listContainersPage returns one page plus an opaque
# nextMarker, for a listing checkpointed to durable storage and resumed in a
# later process. createContainer accepts metadata and a public access level;
# deleteContainer takes a leaseId for a container leased elsewhere, and is
# soft under the account's container soft-delete retention policy.
remote function listContainers(ContainerListOptions? options = ()) returns ContainerInfo[]|Error;
remote function listContainersPage(ContainerPageOptions? options = ()) returns ContainerPage|Error;
remote function createContainer(string containerName, ContainerCreateOptions? options = ()) returns Error?;
remote function deleteContainer(string containerName, DeleteContainerOptions? options = ()) returns Error?;
remote function undeleteContainer(string containerName, string 'version) returns Error?;

# ServiceProperties models the whole configuration document: request metrics,
# classic logging, CORS rules, both soft-delete retention policies, the static
# website settings, and the default service version. Each group is an optional
# field and the wire treats them independently, so a group present in the
# record replaces that group whole while a group absent is left untouched.
# Enabling the retention policies here is the prerequisite for undeleteBlob
# and undeleteContainer.
remote function getServiceProperties() returns ServiceProperties|Error;
remote function setServiceProperties(ServiceProperties properties) returns Error?;

# SKU, account kind, and whether the account has a hierarchical namespace.
# The last matters: on such accounts directories are real and renames exist
# through a different endpoint, neither of which this module models.
remote function getAccountInfo() returns AccountInfo|Error;

# Requires a client authenticated with Microsoft Entra ID whose identity
# holds the Storage Blob Delegator role; the key is valid at most 7 days and
# signs user-delegation SAS tokens (see 4.10).
remote function getUserDelegationKey(time:Utc startTime, time:Utc expiryTime) returns UserDelegationKey|Error;

# Ordinary method (invoked with `.`): signs the token locally with the
# account key, no service call. The signature values select the covered
# services (blob, queue), the resource types, the permissions, and the
# window; covering both the blob and the queue services produces the account
# SAS a Listener needs (see 5).
public function generateAccountSas(AccountSasSignatureValues values) returns string|Error;
```

### 4. The `Client`

```ballerina
public function init(string containerName, *ClientConfiguration config) returns Error?;
```

Binding is lazy: `init` makes no call to Azure, so the first operation against a nonexistent container fails with `NotFoundError`; the up-front check is `AdminClient.hasContainer`.

The surface is 40 remote operations plus four ordinary SAS generators. A method name carries a tier token only to disambiguate a verb that exists at another tier, or to keep a bare verb from implying more than it does: `listBlobs` carries its token because blob's flat listing returns blobs only, unlike the sibling's tier-neutral `list`, which genuinely returns two kinds of entry. Verbs whose object is already explicit stay bare (`upload`, `setContentHeaders`, `createSnapshot`).

#### 4.1 Container-level operations

```ballerina
# Metadata is free-form, user-defined annotation; Azure stores and returns it
# verbatim. setContainerMetadata replaces the complete metadata set, and
# metadata is read back through getContainerProperties.
remote function getContainerProperties() returns ContainerProperties|Error;
remote function setContainerMetadata(map<string> metadata, ContainerMetadataOptions? options = ()) returns Error?;

# The wire's Set Container ACL sets the public access level and the stored
# policies together, and resets access to private whenever the header is
# omitted. The access level is therefore a required parameter rather than an
# option: a policy write can never silently strip public access, and this is
# also how the level is changed after creation. At most five policies.
remote function getContainerAccessPolicy() returns ContainerAccessPolicy|Error;
remote function setContainerAccessPolicy(PublicAccess access, SignedIdentifier[] identifiers,
        AccessPolicyOptions? options = ()) returns Error?;
```

#### 4.2 Blob operations

```ballerina
# listBlobs returns one lazy stream, so memory stays bounded on a container of
# millions of blobs. Without a delimiter every blob is listed whatever its
# slashes; with one, names extending past the next delimiter collapse into a
# single entry whose isPrefix flag is set, which is fed back as the next
# call's prefix to descend a level. listBlobsPage returns one page plus an
# opaque nextMarker, for a listing resumed across process restarts.
remote function listBlobs(ListOptions? options = ()) returns stream<BlobEntry, Error?>|Error;
remote function listBlobsPage(BlobPageOptions? options = ()) returns BlobPage|Error;

# hasBlob follows the same semantics as hasContainer. deleteBlob refuses a
# blob that has snapshots unless told what to do with them, which is the
# wire's own rule; its options also delete one snapshot instead of the blob,
# and pass a lease id. undeleteBlob restores a soft-deleted blob together
# with any soft-deleted snapshots it had.
remote function hasBlob(string path) returns boolean|Error;
remote function deleteBlob(string path, DeleteBlobOptions? options = ()) returns Error?;
remote function undeleteBlob(string path) returns Error?;

# BlobProperties carries timestamps and the entity tag, content length and
# content headers, metadata, the blob type, the access tier and any pending
# rehydration, the lease state, the state of the most recent copy operation,
# and the type-specific fields present only for their type (a page blob's
# sequence number, an append blob's committed block count). The access tier
# is reported as the wire's string, because the service's tier set is open
# ended and a closed type would turn a future service change into a binding
# failure. setContentHeaders replaces the complete header set: any header
# omitted from the record is cleared on the blob, as the wire specifies.
remote function getBlobProperties(string path) returns BlobProperties|Error;
remote function setBlobMetadata(string path, map<string> metadata, BlobMetadataOptions? options = ()) returns Error?;
remote function setContentHeaders(string path, ContentHeaders headers, ContentHeaderOptions? options = ()) returns Error?;
```

There is no rename operation. Azure Blob Storage has no rename on flat-namespace accounts, so relocating a blob is a copy to the new name followed by a delete of the old one, and the two steps are individually observable. No idiom in this design depends on an atomic move.

#### 4.3 Transfer operations and data binding

```ballerina
# Disk transfers: no format detection, no type conversion. Both take full
# paths including the file name, the local path first for the upload, and
# neither deletes its source. download fails with a client-side Error when a
# local file already exists at the destination, so it never destroys local
# data.
remote function uploadFromFile(string sourcePath, string destinationPath, UploadOptions? options = ()) returns Error?;
remote function download(string sourcePath, string destinationPath, DownloadOptions? options = ()) returns Error?;

# Value transfers. The unions are identical in both directions, so anything
# written is readable back in the same type.
remote function upload(UploadContent content, string destinationPath, UploadContentOptions? options = ()) returns Error?;
remote function getBlob(string path, GetBlobOptions? options = (),
        typedesc<RetrievableType> targetType = <>) returns targetType|Error;
```

```ballerina
public type UploadContent byte[]|string|json|xml|record {}|record {}[]|
                          stream<byte[], error?>|stream<record {}, error?>;

public type RetrievableType byte[]|string|json|xml|record {}|record {}[]|
                            stream<byte[], error?>|stream<record {}, error?>;
```

The format resolves **first**, from the operation's `fileFormat` option when set, else from the path's extension (`.json`, `.xml`, `.csv`), else not at all; the value is then checked against the resolved format. `byte[]`, byte streams, and `string` pass through untouched under every format, so content the caller already serialized is never re-encoded. Under JSON a `json` value or a record becomes a JSON document; under XML an `xml` value is written in its textual form and a record becomes a single-element document whose root element `data.xmldata` names `root` (the `@xmldata:Name` annotation renames member elements, not that root), never an array, because no wrapper element name exists for one; under CSV a record array becomes rows headed by the union of every record's field names in first-seen order, with nil or absent members as empty cells. A record stream is written row by row as it is pulled, so its header can only be the first record's field names and a later record's extra field cannot join a header already written; an empty array or an exhausted stream writes an empty blob with no header row. Specifically defined records are the encouraged shape among the structured members: their fields are checked at compile time and drive the serialization directly. Lists of lists are deliberately absent from both unions, because a value such as `string[][]` is simultaneously `json` and a list of lists, so its treatment would depend on which branch matched first; positional or headerless CSV is written as a `string` or `byte[]` and parsed with `ballerina/data.csv`.

Every upload creates a block blob and replaces an existing **block** blob at the destination, which is the wire's own Put Blob behaviour, and the replaced blob's snapshots are retained. Two destinations cannot be replaced: an existing append or page blob, because a blob's type cannot change (`InvalidBlobTypeError` — delete it first, then upload), and an archived blob (`ArchivedBlobError`). There is deliberately no `overwrite` option. A guard would change the behaviour of every user migrating from the deprecated module, whose `putBlob` replaced unconditionally, and the sibling connector and `aws.s3` both replace without one; the type rule already refuses the destructive cases, which is a stronger guarantee than a flag a caller must remember to set. Content over the single-request threshold is chunked and transferred in parallel by the SDK in both directions, so the request count tracks content size and memory stays bounded. A byte stream truly streams: its chunks are staged as blocks and committed at the end, with no content length needed up front, because block blobs are created by committing what was written rather than by pre-allocating a size. Until that commit the destination blob does not exist, so a failed stream upload leaves no partial blob. This is where blob's wire departs from the sibling's, whose stream upload requires a length because Azure Files pre-allocates the file.

When the connector itself chose the serialization and the caller set no explicit content type, the uploaded blob's content type is set to match the format applied. This describes a serialization the connector performed and fabricates nothing; an explicit content type always wins, and content the connector passed through untouched gets no automatic type. Blobs are routinely served over HTTP through SAS links, where a missing content type is a real defect rather than a cosmetic one.

#### 4.4 Copy operations

```ballerina
# Copies are asynchronous: the service accepts the request and copies in the
# background, so CopyInfo reports the copy's identifier and its status at
# acceptance. A pending copy is watched through getBlobProperties, whose
# result carries the state of the blob's most recent copy, and cancelled with
# abortCopy. copyBlob copies within the bound container under this client's
# credentials; copyBlobFromUrl copies from any Azure Storage URL the service
# can read, where a source that is not publicly readable carries its own
# authorization in the URL and a source in the same account is authorized by
# this client's credential.
remote function copyBlob(string sourcePath, string destinationPath, CopyOptions? options = ()) returns CopyInfo|Error;
remote function copyBlobFromUrl(string sourceUrl, string destinationPath, CopyOptions? options = ()) returns CopyInfo|Error;
remote function abortCopy(string path, string copyId, AbortCopyOptions? options = ()) returns Error?;
```

A dedicated copy-status operation is deliberately absent: Get Blob Properties *is* the wire's way of watching a copy, and a second name for one wire call would be a second thing to keep consistent.

#### 4.5 Access tiers, index tags, and snapshots

```ballerina
# Tier changes and rehydration are one operation because they are one wire
# call, distinguished only by a rehydrate priority the options carry. An
# archived blob's content can be neither read nor overwritten until it is
# rehydrated, which takes hours, while its properties, metadata, and tags
# stay available; copying to a new online-tier destination rehydrates
# without disturbing the original.
remote function setAccessTier(string path, AccessTier accessTier, SetAccessTierOptions? options = ()) returns Error?;

# Index tags differ from metadata: the service indexes them, so they answer
# queries without a listing, and they carry their own SAS permission. Tags
# are set and read whole, matching the wire. The index is eventually
# consistent, so findBlobsByTags may briefly lag a setTags write while
# getTags always reads the blob's current tags.
remote function setTags(string path, map<string> tags, TagOptions? options = ()) returns Error?;
remote function getTags(string path) returns map<string>|Error;
remote function findBlobsByTags(string query) returns stream<TaggedBlobEntry, Error?>|Error;

# Returns the snapshot's identifier, which is what every later operation
# needs: it selects a snapshot in the read options, in deleteBlob, and in a
# page-range listing. Snapshots are listed through listBlobs.
remote function createSnapshot(string path, CreateSnapshotOptions? options = ()) returns string|Error;
```

#### 4.6 Lease operations

```ballerina
# Blob leases lock a blob against writes and deletion by anyone not holding
# the lease id; reads stay open to all. The duration is a required parameter
# rather than a defaulted option, because the wire header is mandatory and
# omitting it means nothing: 15 to 60 seconds, or -1 for infinite. It is
# validated locally, so a value outside the range fails without a round trip.
# The proposed lease id is genuinely optional; the service generates one.
remote function acquireLease(string path, int leaseDurationSeconds, string? proposedLeaseId = ()) returns string|Error;
remote function renewLease(string path, string leaseId) returns Error?;
remote function releaseLease(string path, string leaseId) returns Error?;

# breakLease reclaims a lease without holding its id, the recovery path when
# the holder is gone; without it an orphaned infinite lease would block a
# blob permanently. With no break period a fixed lease runs out its remaining
# time and an infinite lease breaks immediately, and the call returns the
# seconds until the blob is actually free. changeLease hands a lease over
# without a window in which another client could take it.
remote function breakLease(string path, int? breakPeriodSeconds = ()) returns int|Error;
remote function changeLease(string path, string leaseId, string proposedLeaseId) returns string|Error;
```

While a blob is leased, every write operation passes the lease id through its options record. The rule is uniform across the surface, blob writes and container writes alike, so it is stated once rather than per operation: writes take the lease id, reads never need one.

#### 4.7 Append blob operations

```ballerina
# Append blobs serve log-style accumulation. They are in the surface because
# the deprecated connector could create them and append to them, locally and
# from a URL, and nothing else here covers that: the transfer operations
# always create block blobs, so writing one over an append blob leaves a
# block blob at that path. Blocks append in arrival order, each at most 4 MiB,
# up to 50,000 per blob.
remote function createAppendBlob(string path, CreateBlobOptions? options = ()) returns Error?;
remote function appendBlock(string path, byte[] content, AppendBlockOptions? options = ()) returns Error?;
remote function appendBlockFromUrl(string path, string sourceUrl, AppendBlockOptions? options = ()) returns Error?;
```

#### 4.8 Page blob operations

```ballerina
# Page blobs are fixed-capacity, 512-byte-aligned random-access blobs backing
# virtual disks; capacity is reserved sparsely, so unwritten pages read as
# zeros and only written pages are billed.
remote function createPageBlob(string path, int sizeInBytes, CreateBlobOptions? options = ()) returns Error?;

# The wire exposes writing and clearing as one operation distinguished by a
# mode header, and this surface splits them: a single operation would take
# content that is required in one mode and forbidden in the other, so two
# invalid combinations would be representable and could fail only at run
# time. The SDK draws the same split, and so does the sibling connector for
# the identical wire shape on file ranges.
remote function uploadPages(string path, int offset, byte[] content, PageOptions? options = ()) returns Error?;
remote function clearPages(string path, int offset, int length, PageOptions? options = ()) returns Error?;
remote function listPageRanges(string path, PageRangeOptions? options = ()) returns PageRange[]|Error;
```

#### 4.9 Block operations

These expose block-blob composition directly. **They are not the path for ordinary large uploads**, which the transfer operations chunk and parallelize internally. They exist for the two things only they can do: composing a blob from remote pieces without the content passing through the caller, and staging content across process restarts before committing it.

```ballerina
# Staged blocks are invisible until committed: the visible blob, if any, is
# unchanged, and commitBlockList creates or replaces it in one atomic step
# from an ordered list of block ids. A crashed producer resumes by listing
# its uncommitted blocks and continuing. The caller supplies the block id
# already base64 encoded, and both operations validate locally before any
# request: stageBlock rejects an id that is not valid base64, and
# commitBlockList rejects a set whose ids are not all equal in length. That
# equal-length rule is the wire's, and it is checked here rather than left to
# the service because an id derived from a counter silently changes encoded
# length as it crosses a power of ten — exactly how the deprecated connector
# failed for uploads past ten blocks.
# Staged blocks live for seven days from the blob's most recent successful
# staging.
remote function stageBlock(string path, string blockId, byte[] content, StageBlockOptions? options = ()) returns Error?;
remote function stageBlockFromUrl(string path, string blockId, string sourceUrl,
        StageBlockFromUrlOptions? options = ()) returns Error?;
remote function commitBlockList(string path, string[] blockIds, CommitBlockListOptions? options = ()) returns Error?;
remote function listBlocks(string path) returns BlockList|Error;
```

#### 4.10 SAS generation

```ballerina
# Ordinary methods (invoked with `.`): signing happens locally with the
# credential the client already holds and no call is made to Azure. The
# account-key variants require a shared-key credential and are revoked
# wholesale when the account key rotates. The user-delegation variants sign
# with a key from AdminClient.getUserDelegationKey, so no storage key is
# ever handled; they are valid at most 7 days, and stored access policies do
# not apply to them, so they reject an identifier.
public function generateContainerSas(BlobSasSignatureValues values) returns string|Error;
public function generateSas(string path, BlobSasSignatureValues values) returns string|Error;
public function generateContainerUserDelegationSas(BlobSasSignatureValues values, UserDelegationKey key) returns string|Error;
public function generateUserDelegationSas(string path, BlobSasSignatureValues values, UserDelegationKey key) returns string|Error;
```

The signature values carry the validity window and the permissions, and optionally a start time, an HTTPS-only protocol restriction, an IP range, and a stored access policy identifier. The wire permits **splitting** those parameters between a stored policy and the token: the policy may carry the window while the token carries the permissions, or any other split, and only specifying one parameter in both places fails. Local validation therefore checks only what is knowable at signing time, since the policy's contents are not, and refuses generation when neither an identifier nor an expiry is supplied. The permission record carries one boolean per wire permission whose operation this module offers, including `add` for appending, `tag` for index tags, and `filter` for tag queries.

### 5. The `Listener` and `Caller`

Azure Blob Storage publishes lifecycle events through Azure Event Grid, and Event Grid delivers to an Azure Storage queue as a pull destination. The listener consumes that queue. This is the service's native eventing path: delivery is near real time, deletions are observable, and the container is never listed. The wiring is created once outside the application, a queue and an Event Grid subscription targeting it, and the subscription's filters choose which event types and which containers reach the queue.

```ballerina
public type ListenerConfiguration record {|
    AuthConfig auth;                             // must span the queue and blob services
    decimal maxPollingIntervalSeconds = 60;      // ceiling of the empty-queue backoff
    int batchSize = 16;                          // messages per receive, 1 to 32
    int newBatchThreshold?;                      // refill trigger; defaults to half the batch size
    decimal redeliveryDelaySeconds = 0;          // invisibility after a handler failure
    int maxDeliveryCount = 5;                    // deliveries before the poison queue
    // -- advanced --
    RetryConfig retryConfig?;
    TransportConfig transportConfig?;
    string queueServiceUrl?;
|};

public isolated class Listener {
    public function init(string queueName, *ListenerConfiguration config) returns Error?;
    public function attach(Service serviceRef, string[]|string? name = ()) returns error?;
    public function 'start() returns error?;
    public function gracefulStop() returns error?;
    public function immediateStop() returns error?;
    public function detach(Service serviceRef) returns error?;
}
```

```ballerina
# A bare distinct service object; the handler set is validated at compile time
# by the module's compiler plugin (at least one event handler, parameter types
# and error? returns, no resource functions, no unknown remote methods).
service on <a Listener> {
    remote function onBlobCreated(BlobEvent event, Caller caller) returns error?;
    remote function onBlobDeleted(BlobEvent event, Caller caller) returns error?;
    remote function onError(Error err) returns error?;   // optional; not an event handler
}
```

The polling and delivery mechanics follow the storage-queue consumer that Azure Functions itself runs, verified against its source rather than chosen by taste. An empty queue is re-polled on a randomized exponential backoff rising to `maxPollingIntervalSeconds`, so a busy queue is drained continuously while an idle one is probed sparsely. One receive fetches `batchSize` messages, and the next batch is fetched only once the number of events still being handled falls to `newBatchThreshold`, which bounds concurrent handling at the sum of the two and ensures a message is never received before it can run.

**Message visibility is not configuration.** A received message is hidden for a fixed internal window that the listener extends in the background for as long as the handler runs, so a handler may run arbitrarily long without losing its message to redelivery. Exposing that window as a knob, as an earlier draft did, hands the user a setting whose wrong value silently duplicates work. The accepted cost is that a process which dies mid-handling leaves its messages hidden until the window expires, within ten minutes, and no configuration shortens it.

Delivery is at-least-once. A handler returning normally acknowledges its event and the message is deleted; a handler returning an error or panicking makes the message visible again after `redeliveryDelaySeconds`. A message reaching `maxDeliveryCount` deliveries moves to a queue named `{queueName}-poison`, created on demand — Storage queues have no native dead-letter facility, so this is the convention Azure Functions established — and poison messages are enqueued without an expiry, because a parking lot for human inspection that empties itself is not one. Delivery has two independent time bounds and raising one does not extend the other. An event that reaches the queue is subject to the queue service's message time to live, seven days by default, so events waiting for a listener down longer than that are lost; the subscription can be configured with a longer one. An event that never reaches the queue is subject to Event Grid's own retry policy, which stops at whichever limit is hit first — thirty delivery attempts, or an event time to live whose value may be 1 to 1,440 minutes and whose default *is* that 1,440-minute (24-hour) ceiling. It cannot be raised, so a queue unreachable for a day loses those events whatever the queue-side setting is. Event Grid then drops the event unless the subscription names a dead-letter storage container, which is off by default and is the only way to recover events that were never delivered. Both are subscription-level setup, outside this module's configuration.

Creation and replacement are the same event: overwriting a blob fires `onBlobCreated` again and the event does not distinguish the two, since the service publishes no modification event. Metadata, property, and index-tag changes fire nothing, and on a flat-namespace account neither does an append. `onError` is notified when a poll fails and when a message cannot be parsed as a storage event; it takes no `Caller`, because neither condition has a subject blob to act on.

```ballerina
# Carries what the storage event provides, in both the Event Grid and the
# CloudEvents delivery schemas, detected per message. The url feeds
# Caller.copyBlobFromUrl directly; the sequencer is opaque and comparable per
# blob path, which is what makes a stale duplicate detectable.
public type BlobEvent record {|
    BlobEventType eventType;
    string containerName;
    string path;
    string url;
    time:Utc eventTime;
    string api;
    string contentType?;
    int contentLength?;
    string blobType?;
    string eTag?;
    string sequencer;
|};
```

The `Caller` is **account-scoped**, and this is the one place the family's listener frame is adapted rather than copied: an Event Grid subscription spans the storage account, so one queue can carry events from every container it admits, and there is no single container to bind a caller to. Its operations therefore take a container name as their leading parameter — the event's own container for the operations that act on the event's blob, and a destination the handler chooses for `copyBlobFromUrl`. It forwards seven operations: `getBlob`, `getBlobProperties`, `download`, `upload`, `deleteBlob`, `copyBlobFromUrl`, and `setTags` — read the event's blob, write a result, consume it, archive it, and mark it. The copy is the from-URL form specifically, so the event's URL feeds it directly and archiving to another container is one call. Everything else requires a full `Client`; the trim is what keeps the handler surface legible.

### 6. Errors

```ballerina
public type Error distinct error;

public type ServiceErrorDetail record {| int httpStatus; string errorCode; |};
public type ServiceError distinct (Error & error<ServiceErrorDetail>);

public type NotFoundError distinct ServiceError;             // 404
public type ConflictError distinct ServiceError;             // 409, state conflicts
public type AuthorizationError distinct ServiceError;        // 403
public type PreconditionFailedError distinct ServiceError;   // 412
public type RangeNotSatisfiableError distinct ServiceError;  // 416
public type ArchivedBlobError distinct ServiceError;         // 409, BlobArchived/BlobBeingRehydrated
public type InvalidBlobTypeError distinct ServiceError;      // 409, InvalidBlobType
```

An error the Azure service raised is a `ServiceError` carrying both the HTTP status and the service's error code. A client-side failure is the root `Error` and carries no detail: no server exchange produced a status or a code, and the connector never fabricates them.

The mapping keys on the **error-code string, never the status alone**. Blob storage returns HTTP 409 for state conflicts, for archive-tier refusals, and for blob-type mismatches alike, so a status-based mapping would collapse three unrelated failures into one type. A code that maps to no subtype stays the generic `ServiceError` with its status and code intact, so an unmapped failure is still fully diagnosable. The two service-specific leaves earn their place: `ArchivedBlobError` names a condition with a distinct remedy that no other conflict shares, and `InvalidBlobTypeError` exists because this connector exposes type-specific write operations for all three blob types, which makes applying one to the wrong type a likely mistake rather than an exotic one.

Lease failures divide by operation kind, which is worth stating because a reader will otherwise check the wrong type: a data write against a leased blob without the lease id is 412 and surfaces as `PreconditionFailedError`, while a failure of a lease operation itself against a stale id or the wrong state is 409 and surfaces as `ConflictError`. The index-tag operations are the wire's exception, reporting a missing lease id as 403.

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

listener blob:Listener blobListener = check new ("blob-events",
    auth = {accountName: "mystorageaccount", accountKey: "..."}
);

service on blobListener {
    remote function onBlobCreated(blob:BlobEvent event, blob:Caller caller) returns error? {
        byte[] content = check caller->getBlob(event.containerName, event.path);
        io:println(content.length());

        // The event's URL feeds the copy source directly.
        _ = check caller->copyBlobFromUrl("processed", event.url, event.path);
        check caller->deleteBlob(event.containerName, event.path);
    }
}
```

## Alternatives

* **Revamp `azure_storage_service` in place.** Rejected: the hand-written protocol layer remains the maintenance burden, and the combined Blob-plus-Files packaging contradicts the one-package-per-service pattern of the rest of the Azure ecosystem.
* **Generate a client from the REST/OpenAPI definition.** Rejected: the generated client would still leave Shared Key signing, SAS construction, retry, and chunked transfer to be implemented and maintained by hand; the official SDK already encapsulates all of it and tracks new API versions.
* **One flat account-scoped client** taking `(containerName, path)` on every operation, as `ballerinax/aws.s3` does. Rejected: the wrapped SDK has a real container-scoped client class carrying the container surface, so the two-tier split mirrors it while the flat shape would be the divergence. s3's flat client mirrors *its* SDK, which has no bucket-scoped client, so it corroborates mirroring one's own SDK rather than departing from it.
* **A polling listener over the container**, the shape the sibling connector uses. Rejected on the wire: each tick would re-list the watched prefix, so cost grows with container size and containers routinely hold millions of blobs; deletions are invisible to a stateless poll; and because blob storage has no rename, the claim-by-move pattern that makes a polling consumer safe is not atomic. The sibling polls because Azure Files is not exposed as an Event Grid source, not because polling was preferred.
* **The change feed as the event source.** Rejected: it is a replay and audit log rather than an event source. Its documented latency is on the order of minutes, its own documentation redirects latency-sensitive consumers to events, and its Java reader has never shipped a stable release.
* **A configurable message-visibility window on the listener.** Rejected after verifying the reference consumer: a fixed internal window with background extension means a slow handler cannot lose its message, whereas any exposed value can be set too low and silently duplicates work.
* **A single page-write operation with a mode enum**, mirroring the wire's own Put Page. Rejected: content is required in one mode and forbidden in the other, so the signature would represent two invalid states that could fail only at run time.
* **Offering both an Event Grid listener and a polling listener.** Rejected: it doubles the listener surface, the compiler plugin, and the delivery-semantics story for no clear gain, against a bias toward one whole mechanism rather than two partial ones.

## Testing

Unlike Azure Files, Blob Storage has a real local emulator: Azurite covers both the Blob and Queue services. The suite is **dual-mode** on the same principle as the sibling's, but with the emulator in the cheap backend's role: every test runs against Azurite when no credentials are configured, and against a real storage account when they are, with no separate test groups. CI therefore runs credential-free and every PR exercises the surface, including leases, snapshots, same-instance copies, index tags and tag queries, access tiers, append blobs, and the block operations, all of which Azurite implements against Shared Key over HTTP. The Azurite version is pinned in CI, because a request carrying a newer `x-ms-version` than the emulator's baseline fails with `InvalidHeaderValue` rather than degrading. A residue pins live: soft delete and undelete of blobs and containers, archive-rehydration realism, the Event Grid wiring itself, and user-delegation SAS. That last one is not a gap in Azurite's coverage so much as in what an emulator can prove: `Get User Delegation Key` is authorized by Microsoft Entra ID only, so exercising it needs Azurite started with `--oauth basic` *and* HTTPS certificates, and even then Azurite validates a bearer token's issuer, audience and expiry without checking its signature or the permissions behind it. The mechanics would pass locally while the authorization semantics went untested, so this path is verified against a real account. The listener's queue-consumption half is tested against Azurite's queue endpoint by enqueuing synthetic Event Grid-shaped messages, which is the only local path since Event Grid is not emulated. Correctness remains live-first: an emulator can mask a defect exactly as a hand-built mock can, so behaviour verified only against Azurite is confirmed against live Azure before release.

## Risks and Assumptions

- **Replacement parity is a hard floor.** The deprecation of `azure_storage_service` must strand no user, so the surface includes append blobs, page blobs, the block operations, page-wise listings, and account information — capabilities that would otherwise fail an 80% test — because nothing else in the design covers what they do. The assumption is that a larger surface is cheaper than a stranded user.
- **A crashed process holds its messages for up to ten minutes.** The listener's fixed visibility window is the price of removing a knob that could silently duplicate work, and no configuration shortens it. This is the same bound every Azure Functions queue consumer lives with.
- **Azurite is not Azure.** Its fidelity gaps around signing and newer service versions mean a green emulator run is necessary but not sufficient; the live pins above exist for exactly the behaviour it cannot show.
- **The access tier a blob reports is an open string.** A preview tier already exists beyond the enum this module writes, and the service documents that more may be added, so the read path is typed as a string to keep a future service change from becoming a binding failure. Callers comparing against the enum's values are unaffected.
- **Blob events do not distinguish creation from replacement**, and no event fires for metadata, property, or tag changes. An application needing those must poll the corresponding read operation; the event fields are advisory, describing the blob as of the moment the event fired.

## Dependencies

* Azure SDK for Java: `com.azure:azure-storage-blob`, `com.azure:azure-storage-queue` (the listener's event path), and `com.azure:azure-identity` (Entra ID support)

## Future Work

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
* [Existing connector: `ballerinax/azure_storage_service`](https://central.ballerina.io/ballerinax/azure_storage_service/latest)
* [Sibling connector: `ballerinax/azure.storage.files`](https://github.com/ballerina-platform/ballerina-spec/issues/1457)
* [Azurite, the Azure Storage emulator](https://github.com/Azure/Azurite)
