# MCP 2.0 for Ballerina: Modern Protocol Support and API Revision

- Author: @RadCod3
- Reviewers:
- Created: 2026-10-15
- Updated: 2026-10-15
- Issue: [#1511](https://github.com/ballerina-platform/ballerina-spec/issues/1511)
- Status: Submitted

## Summary

MCP `2026-07-28` replaces the `initialize` handshake and HTTP sessions with per-request negotiation. Every request carries its protocol version, client information and capabilities, and a server describes itself through `server/discover`. The revision also adds standard routing headers, tool argument headers, change notification subscriptions over `POST`, structured output with any JSON root, and caching hints on cacheable results.

This proposal defines version 2.0 of `ballerina/mcp`. It:

- adds support for MCP `2026-07-28` (the "modern" protocol) to the client and the server, while keeping interoperability with every initialize-based revision up to `2025-11-25` (the "legacy" protocol) through a configurable protocol mode;
- revises the public API around the Streamable HTTP transport, removing the aliases deprecated in 1.x and making the client connect explicitly;
- adds result caching on both sides;
- adds MCP authorization (OAuth 2.1) to the client, including Enterprise-Managed Authorization.

## Goals

- Support MCP `2026-07-28` for tools on both the client and the server.
- Let existing MCP clients and servers that only speak the legacy protocol keep working with Ballerina by default, without extra configuration.
- Report service designs that cannot work with the modern protocol, such as tools that require an HTTP session, at compile time.
- Give Streamable HTTP concepts explicit names, and remove the deprecated 1.x aliases.
- Make protocol selection an explicit client step whose result is visible to the application.
- Support the caching hints defined in `2026-07-28`, so that servers can mark results as reusable and clients reuse them.
- Let a client obtain its own access tokens from an MCP server's authorization server.

## Non-Goals

- Server-to-client requests through multi round-trip requests, such as elicitation. The `InputRequiredResult` continuation types described in this proposal are the minimal surface that the `tools/call` result shape needs. How a server asks for input and how a client answers it will be covered by a separate proposal, which may change the client's input handler API.
- Prompts, resources, completions, logging and task-augmented execution. The module implements tools only, and these capabilities are not advertised.
- Transports other than Streamable HTTP, such as stdio.
- Authorization enforcement on the server. Services continue to use the `ballerina/http` auth configuration and the HTTP request access introduced by the [transport-specific service types proposal](https://github.com/ballerina-platform/ballerina-spec/pull/1452).

## Motivation

### The modern protocol is not compatible with the 1.x module

The 1.x module starts every connection with `initialize`, negotiates the protocol version once, and relies on `Mcp-Session-Id` for state. A `2026-07-28` client sends no `initialize` request and no session ID. It sends `server/discover`, or goes straight to `tools/list` and `tools/call`, with the protocol version, client information and capabilities in `_meta` and in headers. A 1.x server rejects these requests. A 1.x client cannot talk to a server that only accepts the modern protocol.

The modern protocol also changes several message shapes that the 1.x types cannot represent:

- results carry a `resultType` discriminator (`complete` or `input_required`);
- `structuredContent` may be any JSON value, not only an object, and `outputSchema` may have any root;
- `tools/list` and `server/discover` results carry `ttlMs` and `cacheScope`;
- change notifications are delivered through a `subscriptions/listen` request instead of the session's `GET` stream.

### The ecosystem moves at different speeds

Clients and servers will support both protocols for some time. A Ballerina server must accept requests from clients that only send `initialize`, and a Ballerina client must connect to servers that do not implement `server/discover`. Neither side should need to know in advance which protocol the peer speaks.

### The 1.x API carries deprecated and misleading names

Version 1.2.0 added `mcp:StreamableHttpListener`, `mcp:StreamableHttpService` and `@mcp:StreamableHttpServiceConfig`, and deprecated `mcp:Listener` and the transport fields of `@mcp:ServiceConfig`. Version 1.x therefore has two names for most concepts. Some 1.x names also describe the legacy protocol only. `mcp:Session` is an HTTP session that the modern protocol does not have, and `initialize()` names a handshake that the modern protocol removes. A major version is the point to remove the aliases and rename these concepts.

### Clients need authorization

MCP servers are increasingly protected with OAuth. The 1.x client accepts only an existing credential through `http:ClientAuthConfig`. It cannot discover the authorization server from protected resource metadata, run an OAuth grant, or refresh tokens, so each application implements MCP authorization itself.

## Background: Current State (1.x)

- `mcp:Listener` (deprecated) and `mcp:StreamableHttpListener` serve `mcp:Service`, `mcp:AdvancedService`, `mcp:StreamableHttpService` and `mcp:StreamableHttpAdvancedService`.
- `@mcp:ServiceConfig` and `@mcp:StreamableHttpServiceConfig` configure a service, and `sessionMode` selects `STATEFUL`, `STATELESS` or `AUTO` session handling.
- A tool can bind `mcp:Session` (first parameter) and `mcp:Meta?`. Streamable HTTP tools can also bind `@http:Header` parameters, `http:Headers` and `http:Request`.
- `mcp:StreamableHttpClient` offers `initialize()`, `listTools()`, `callTool()`, `subscribeToServerMessages()` and `close()`. `initialize()` always performs the `initialize` handshake, and the other methods do not check that it was called.
- The supported protocol versions are `2025-11-25`, `2025-06-18`, `2025-03-26`, `2024-11-05` and `2024-10-07`.

## Design

### Protocol versions and modes

The supported versions are split by lifecycle. Modern versions use per-request negotiation, and legacy versions use the `initialize` handshake:

```ballerina
# Revisions that use per-request negotiation, newest first.
public const MODERN_PROTOCOL_VERSIONS = ["2026-07-28"];
# Revisions that use the `initialize` handshake, newest first.
public const LEGACY_PROTOCOL_VERSIONS = ["2025-11-25", "2025-06-18", "2025-03-26", "2024-11-05", "2024-10-07"];
# The union of the modern and legacy revisions.
public const SUPPORTED_PROTOCOL_VERSIONS = [
    "2026-07-28", "2025-11-25", "2025-06-18", "2025-03-26", "2024-11-05", "2024-10-07"
];

# The newest modern revision, sent by the client.
public const LATEST_PROTOCOL_VERSION = "2026-07-28";
# The newest legacy revision, offered in `initialize`.
public const LATEST_LEGACY_PROTOCOL_VERSION = "2025-11-25";
```

`MODERN_PROTOCOL_VERSION`, which duplicates `LATEST_PROTOCOL_VERSION`, is removed. There is only one modern revision today. A list lets the next one be added as a membership change, instead of replacing every comparison against a single constant.

Whether a request is modern or legacy is decided by its lifecycle, not by comparing versions. An `initialize` request is always legacy. A request whose `_meta` carries `io.modelcontextprotocol/protocolVersion` is modern. For any other request, an absent `MCP-Protocol-Version` header or a version in `LEGACY_PROTOCOL_VERSIONS` means legacy. Any other value is handled as a modern request, and is rejected unless it carries the required metadata.

Each list is used where its lifecycle negotiates or validates a version:

| Check | List |
|---|---|
| The server accepts a modern request's version | `MODERN_PROTOCOL_VERSIONS` |
| The client selects the modern protocol: the newest of its modern versions that `server/discover` lists | `MODERN_PROTOCOL_VERSIONS` |
| For `initialize`, the server echoes the requested version, or answers with `LATEST_LEGACY_PROTOCOL_VERSION` if the version is not supported | `LEGACY_PROTOCOL_VERSIONS` |
| The server accepts the `MCP-Protocol-Version` header of a legacy request | `LEGACY_PROTOCOL_VERSIONS` |
| The client accepts the version in an `InitializeResult` | `LEGACY_PROTOCOL_VERSIONS` |
| The client falls back to `initialize` when an `UNSUPPORTED_PROTOCOL_VERSION` error's `supported` list names a legacy version and no modern one (see [Protocol selection](#protocol-selection)) | Both |
| The server lists its versions in `server/discover` and in `UNSUPPORTED_PROTOCOL_VERSION` errors | `MODERN_PROTOCOL_VERSIONS` in `"modern"` mode, `LEGACY_PROTOCOL_VERSIONS` in `"legacy"` mode, `SUPPORTED_PROTOCOL_VERSIONS` in `"auto"` mode |

> **Implementation note:** the current implementation has a single `MODERN_PROTOCOL_VERSION` constant and compares against it directly. The request classifier also keeps its own hardcoded copy of the legacy versions instead of deriving them from `SUPPORTED_PROTOCOL_VERSIONS`. The legacy header check uses `SUPPORTED_PROTOCOL_VERSIONS`, which includes the modern version. These will be changed to use the lists above once this proposal is approved, with no change in behavior for the versions supported today.

A protocol mode selects which of these a client or service uses. It is independent of HTTP session management.

```ballerina
public type ProtocolMode "legacy"|"auto"|"modern";
```

| Mode | Client | Server |
|---|---|---|
| `"auto"` (default) | Tries modern discovery. Falls back to `initialize` only when the response shows a legacy server. | Accepts modern requests and initialize-based requests. Each request follows the lifecycle of its own form. |
| `"modern"` | Requires `2026-07-28`. | Accepts modern requests only. `server/discover` advertises only `2026-07-28`. |
| `"legacy"` | Uses `initialize`. | Accepts initialize-based requests only. |

Because `"auto"` is the default on both sides, existing clients can connect to an upgraded Ballerina server, and an upgraded Ballerina client can connect to an existing server.

### Server

#### Listener and service types

Version 2.0 keeps the Streamable HTTP names introduced in 1.2.0 and removes the deprecated and transport-agnostic aliases:

```ballerina
public isolated class StreamableHttpListener {
    public function init(int|http:Listener listenTo, *ListenerConfiguration config) returns Error?;
    public isolated function attach(StreamableHttpService|StreamableHttpAdvancedService mcpService,
            string[]|string? name = ()) returns Error?;
    public isolated function detach(StreamableHttpService|StreamableHttpAdvancedService mcpService) returns Error?;
    public isolated function 'start() returns Error?;
    public isolated function gracefulStop() returns Error?;
    public isolated function immediateStop() returns Error?;
}

public type StreamableHttpService distinct service object {
};

public type StreamableHttpAdvancedService distinct service object {
};
```

`mcp:Service` and `mcp:AdvancedService` are removed. With the modern protocol, more of the service contract depends on HTTP: routing headers, mirrored argument headers, subscriptions delivered as SSE responses to `POST`, and HTTP status codes for protocol errors. Only one transport is implemented, so a transport-agnostic tier would only be a second name for the same types. The split described in the transport-specific service types proposal stays the model for future transports. Transport-agnostic types will be reintroduced together with a second transport, once the shared contract can be defined against two real implementations.

#### Service configuration

A single annotation, `@mcp:StreamableHttpConfig`, replaces both `@mcp:ServiceConfig` and `@mcp:StreamableHttpServiceConfig`:

```ballerina
public type StreamableHttpConfiguration record {|
    # Server implementation information
    Implementation info;
    # Protocol selection
    ProtocolMode protocolMode = "auto";
    # Optional server configuration options
    ServerOptions options?;
    # HTTP service configuration for the underlying transport
    http:HttpServiceConfig httpConfig = {};
    # Session management for legacy requests
    HttpSessionMode sessionMode = AUTO;
    # Caching hints sent to modern clients on cacheable results
    CacheHints cacheHints = {};
|};

public annotation StreamableHttpConfiguration StreamableHttpConfig on service;
```

- `info` is returned in `InitializeResult.serverInfo` for legacy requests, and in `_meta` of every modern result under `io.modelcontextprotocol/serverInfo`.
- `options.instructions` is returned by `initialize` and by `server/discover`.
- The server advertises the `tools` capability only. It removes `tasks`, `logging`, `prompts`, `resources` and `completions` from `options.capabilities`, because the module has no runtime for them. `tools.listChanged` is `true` only for an advanced service that implements `onSubscribe`.
- The CORS `allowOrigins` list in `httpConfig` is also used for the `Origin` validation required by the Streamable HTTP transport.

#### Modern request handling

For a modern request, the dispatcher:

1. Reads the protocol version from `_meta["io.modelcontextprotocol/protocolVersion"]` and the `MCP-Protocol-Version` header. A version the service does not accept is rejected with `UNSUPPORTED_PROTOCOL_VERSION` (`-32022`). The error `data` lists the supported and requested versions, so that the client can select another version.
2. Validates the routing headers. `MCP-Protocol-Version` must match the request metadata, `Mcp-Method` must match the JSON-RPC method, and for `tools/call`, `Mcp-Name` must match the tool name. A mirrored argument header (see [Argument headers](#argument-headers)) must be present once and match the decoded argument. A mismatch is rejected with `HEADER_MISMATCH` (`-32020`) before the service is invoked.
3. Dispatches `server/discover`, `tools/list`, `tools/call`, and `subscriptions/listen` for an advanced service with `onSubscribe`. Any other method gets `METHOD_NOT_FOUND`.

Header values use the canonical encoding defined by the specification, and the dispatcher rejects values that are not encoded canonically.

Modern requests have no session. `sessionMode` applies only to legacy requests, and keeps the 1.x `STATEFUL`, `STATELESS` and `AUTO` behavior. The enum is renamed to `HttpSessionMode` to make this explicit.

#### HTTP sessions and the modern protocol

`mcp:Session` is renamed to `mcp:HttpSession`, and `mcp:SessionEntry` to `mcp:HttpSessionEntry`. A modern request never has a session, so how a tool declares the session parameter decides which protocols the service can serve:

| Session parameter | `"legacy"` | `"auto"` | `"modern"` |
|---|---|---|---|
| None | Allowed | Allowed | Allowed |
| `mcp:HttpSession` (required) | Allowed | Warning: the service serves legacy requests only | Error |
| `mcp:HttpSession?` (nilable) | Allowed | Warning: the value is `()` for modern requests | Warning: the value is always `()` |

`StreamableHttpListener.attach` repeats the error check at runtime and returns an error for a modern-mode service that requires `mcp:HttpSession`. State that modern clients need should be kept in the application and addressed through explicit handles in tool arguments.

#### Runtime parameters

In addition to `anydata` arguments, a basic tool can bind:

- `mcp:HttpSession` or `mcp:HttpSession?`, as the first parameter, for legacy session state;
- `mcp:RequestMetaObject?` (renamed from `mcp:Meta`), at any position, for the request's `_meta`. It must be nilable, because clients may omit `_meta`;
- `@http:Header` parameters, `http:Headers` and `http:Request`, as defined in the transport-specific service types proposal.

Runtime parameters are not part of the generated input schema. An omitted defaultable argument takes its default value.

#### Structured output

A basic tool may return any `anydata` value. The compiler generates an `outputSchema` from the return type, and `@mcp:Tool` can override it:

```ballerina
public type McpToolConfig record {|
    string description?;
    InputSchema schema?;
    # Advertised only to modern clients
    OutputSchema outputSchema?;
    # Whether modern requests receive structured output for this tool
    boolean structuredOutput = true;
|};
```

`InputSchema` requires an object root. `OutputSchema` allows any root. Both are open records, so they accept JSON Schema keywords the module does not declare. Ballerina has no runtime JSON Schema evaluation yet, so the schemas are carried as metadata, and Ballerina type binding continues to validate arguments.

The library always creates a text content block from the return value. The rest of the result depends on the protocol:

- **Modern:** `tools/list` advertises `outputSchema`, and `structuredContent` carries the return value with any JSON root, including `null`.
- **Legacy:** the 1.x wire shape is kept. `outputSchema` is not advertised. An object-root value is returned in `structuredContent`. Scalars and arrays are returned only as the text content block, because the legacy schema requires an object.

#### Argument headers

The modern protocol lets a server ask clients to copy selected tool arguments into `Mcp-Param-*` headers, so that gateways can route requests without parsing the body. Tool definitions mark these arguments with the `x-mcp-header` extension in the input schema. A basic tool declares them with `@mcp:Argument`:

```ballerina
public type ArgumentConfig record {|
    # Mirrors the argument into the corresponding `Mcp-Param-*` request header. The argument
    # remains present in `tools/call.params.arguments`.
    string headerName;
|};

public const annotation ArgumentConfig Argument on parameter;
```

```ballerina
remote isolated function weather(@mcp:Argument {headerName: "Region"} string region)
        returns Weather|error {
    // ...
}
```

The generated schema contains `"region": {"type": "string", "x-mcp-header": "Region"}`. The argument stays in `params.arguments`, and the dispatcher checks that the header matches it. In contrast, `@http:Header` binds a value that comes only from an HTTP header and is never a tool argument.

#### Advanced services

An advanced service owns tool discovery and dispatch. Its methods are validated by the compiler plugin:

```ballerina
remote isolated function onListTools() returns ListToolsResult|ServerError;

remote isolated function onCallTool(CallToolParams params)
        returns CallToolResult|InputRequiredResult|ServerError;

# Optional. Publishes change notifications to modern subscribers.
remote isolated function onSubscribe(SubscriptionFilter notifications)
        returns stream<JsonRpcNotification, error?>|ServerError;
```

- These methods can bind the same HTTP request values as basic tools. `onCallTool` reads request metadata from `params._meta`.
- `onCallTool` may return `InputRequiredResult` to a modern request. The input-request design is out of scope for this proposal (see [Non-Goals](#non-goals)).
- `onSubscribe` is invoked for `subscriptions/listen`. The library sends `notifications/subscriptions/acknowledged` with the accepted filter, forwards matching notifications tagged with the subscription ID, and sends the final `complete` result when the stream ends. Only `toolsListChanged` is accepted in this version.

```ballerina
public type SubscriptionFilter record {|
    boolean toolsListChanged = false;
    boolean promptsListChanged = false;
    boolean resourcesListChanged = false;
    string[] resourceSubscriptions = [];
|};
```

#### Result caching hints

`server/discover` and `tools/list` results carry `ttlMs` (how long a client may treat the result as fresh) and `cacheScope` (whether it may be shared between callers). A service sets them through `cacheHints`:

```ballerina
public type CacheScope "public"|"private";

public type CacheHint record {|
    # Must be non-negative
    int ttlMs?;
    CacheScope cacheScope?;
|};

public type CacheHints record {|
    CacheHint discover?;
    # Fields set on the `ListToolsResult` returned by `onListTools` take precedence
    CacheHint listTools?;
|};
```

```ballerina
@mcp:StreamableHttpConfig {
    info: {name: "weather", version: "2.0.0"},
    cacheHints: {
        discover: {ttlMs: 300000, cacheScope: "public"},
        listTools: {ttlMs: 60000, cacheScope: "public"}
    }
}
service mcp:StreamableHttpService /mcp on mcpListener {
    // ...
}
```

Each field is resolved separately. A value set by `onListTools` wins, then the configured hint, then the default (`ttlMs: 0`, `cacheScope: "private"`), so results are not reused unless the service opts in. `attach` rejects a negative configured `ttlMs`. Legacy responses never carry these fields.

### Client

#### Construction and connection

```ballerina
public distinct isolated client class StreamableHttpClient {
    public isolated function init(string serverUrl, *StreamableHttpClientConfig config) returns ClientError?;

    remote isolated function connect(Implementation clientInfo = {name: "MCP Client", version: "1.0.0"},
            ClientCapabilities capabilities = {}, map<string|string[]> headers = {})
            returns ConnectionInfo|ClientError;

    remote isolated function listTools(map<string|string[]> headers = {}, Cursor? cursor = (),
            CacheMode cacheMode = "use") returns ListToolsResult|ClientError;

    remote isolated function callTool(CallToolParams params, map<string|string[]> headers = {})
            returns CallToolResult|ClientError;

    remote isolated function callToolOnce(CallToolParams params, map<string|string[]> headers = {})
            returns CallToolResult|InputRequiredResult|ClientError;

    remote isolated function listen(SubscriptionFilter notifications = {toolsListChanged: true},
            map<string|string[]> headers = {}) returns stream<JsonRpcMessage, StreamError?>|ClientError;

    remote isolated function discover(map<string|string[]> headers = {}) returns DiscoverResult|ClientError;

    public isolated function adoptDiscovery(DiscoverResult discovered,
            Implementation clientInfo = {name: "MCP Client", version: "1.0.0"},
            ClientCapabilities capabilities = {}) returns ConnectionInfo|ClientError;

    remote isolated function initializeLegacy(Implementation clientInfo = {name: "MCP Client", version: "1.0.0"},
            ClientCapabilities capabilities = {}, map<string|string[]> headers = {})
            returns ConnectionInfo|ClientError;

    remote isolated function close() returns ClientError?;
}
```

`init` only configures the transport. In 1.x, `initialize()` always ran the legacy handshake, and nothing stopped an application from calling `listTools()` or `callTool()` without it. In 2.0, `connect()` selects the protocol and must be called before `listTools()`, `callTool()`, `callToolOnce()` or `listen()`, which return an error otherwise. It returns what was negotiated:

```ballerina
public type ConnectionInfo record {|
    string protocolVersion;
    Implementation serverInfo?;
    ServerCapabilities capabilities;
    string instructions?;
|};
```

#### Protocol selection

In `"auto"` mode, `connect()` sends `server/discover`. If the result lists `2026-07-28`, the client uses the modern protocol. If the request fails, the client falls back to `initialize` only when the failure shows a legacy server:

- HTTP `400`, `404` or `405`, or a response that cannot be parsed as a modern result;
- `UNSUPPORTED_PROTOCOL_VERSION` whose `data.supported` lists only legacy versions this module supports.

It does not fall back on `401`, `403` or `5xx`, on `HEADER_MISMATCH` or `MISSING_REQUIRED_CLIENT_CAPABILITY`, or when `data.supported` includes `2026-07-28`. A server that is modern but unavailable or unauthorized therefore returns an error instead of being treated as legacy. A configured `sessionId` implies a resumed legacy session, and cannot be combined with `"modern"`.

A modern `server/discover` result may omit `resultType`, `ttlMs` and `cacheScope`. Such a result is treated as `complete`, `0` and `"private"`, so `"auto"` mode does not fall back for a modern server that leaves them out.

The lower-level methods support applications that manage discovery themselves. `discover()` fetches discovery data without connecting. `adoptDiscovery()` connects from a `DiscoverResult` obtained earlier, without another request. `initializeLegacy()` runs the `initialize` handshake explicitly.

#### Modern requests

On the modern protocol, the client:

- adds the protocol version, client information and capabilities to `_meta` of every request, and sends `MCP-Protocol-Version`, `Mcp-Method` and, for `tools/call`, `Mcp-Name`;
- keeps the tool schemas from `tools/list`, and copies arguments marked with `x-mcp-header` into `Mcp-Param-*` headers on `tools/call`. Tools whose header declarations are invalid are left out of the `listTools()` result;
- refetches the tool list and retries the call once when a call fails with `HEADER_MISMATCH`, which usually means the cached schema is out of date;
- requires `resultType`, `ttlMs` and `cacheScope` on `tools/list` results.

`callTool()` returns when the call completes. If a modern server returns `InputRequiredResult`, it calls the configured `inputHandler`, echoes `requestState` unchanged, and retries, up to `maxInputRounds`. `callToolOnce()` performs one request and returns `CallToolResult|InputRequiredResult`, so that the application can handle continuations itself. On a legacy connection it behaves like `callTool()`. As noted in [Non-Goals](#non-goals), the input handler API will be revisited in a separate proposal.

`listen()` opens a `subscriptions/listen` stream on the modern protocol, and the session's `GET` event stream on the legacy protocol. Closing the stream cancels the subscription.

#### Result caching

The client reuses modern `tools/list` results while their `ttlMs` keeps them fresh. Each page is cached under its cursor.

```ballerina
public type StreamableHttpClientConfig record {|
    // HTTP client fields of http:ClientConfiguration ...
    (http:ClientAuthConfig|OAuthConfig)? auth = ();
    string sessionId?;
    ProtocolMode protocolMode = "auto";
    int maxInputRounds = 8;
    InputHandler inputHandler?;
    # `()` disables reuse
    ResultCacheConfig? resultCache = {};
|};

public type ResultCacheConfig record {|
    # Upper bound, in milliseconds, on how long a result is treated as fresh
    int maxTtlMs = 86400000;
    # Maximum number of results kept; the least recently used result is dropped first
    int maxEntries = 1024;
|};

# - `use` serves a fresh cached result, or fetches and caches the response
# - `refresh` always fetches and caches the response
# - `bypass` always fetches and leaves the cache untouched
public type CacheMode "use"|"refresh"|"bypass";
```

- Cached results are dropped when `listen()` delivers `notifications/tools/list_changed`, when the server rejects a cursor with `INVALID_PARAMS` (all pages are dropped), when a call fails with `HEADER_MISMATCH`, and on `close()`. A request that is already running cannot put back a result that was dropped while it ran.
- A negative `ttlMs` from a server is treated as `0`.
- Each client has its own cache and is treated as one authorization context. Credentials belong in `auth`, with a separate client for each user. Per-call headers are not part of the cache key.
- The tool schemas used for argument headers are kept in the same cache, and are merged across pages.

Servers default to `ttlMs: 0`, so caching changes nothing until a server opts in.

#### Authorization

`auth` accepts either an existing credential (`http:ClientAuthConfig`) or an `mcp:OAuthConfig`. With `mcp:OAuthConfig`, the client implements MCP authorization (OAuth 2.1). On a `401` it reads the `WWW-Authenticate` challenge, fetches the protected resource metadata (RFC 9728) and the authorization server metadata (RFC 8414), runs the configured grant, attaches the access token, and refreshes or requests a new token when it expires. An `insufficient_scope` challenge triggers a step-up token request for the challenged scopes together with the scopes already granted.

```ballerina
public type OAuthConfig record {|
    ClientCredentialsGrant|AuthorizationCodeGrant|IdentityAssertionGrant grant;
    # Used only when the challenge and the protected resource metadata give no scopes
    string[] scopes?;
|};
```

| Grant | Use |
|---|---|
| `ClientCredentialsGrant` | Access on the client's own behalf. Advertises the `io.modelcontextprotocol/oauth-client-credentials` extension. |
| `AuthorizationCodeGrant` | Access on behalf of a user, with PKCE `S256`. The application provides `redirectHandler` to send the user to the authorization URL, and `callbackHandler` to return the redirect parameters. RFC 9207 `iss` is checked when the server supports it. |
| `IdentityAssertionGrant` | Enterprise-Managed Authorization. An `assertionProvider` callback returns an Identity Assertion JWT Authorization Grant (ID-JAG) from the enterprise identity provider, and the client exchanges it at the MCP server's authorization server. Advertises the `io.modelcontextprotocol/enterprise-managed-authorization` extension. |

A client is either registered with one authorization server (`PreRegisteredClientConfig`, whose `issuer` must be listed in the protected resource metadata) or identified by a Client ID Metadata Document (`CimdClientConfig`). Client authentication at the token endpoint is one of:

```ballerina
public type ClientAuth ClientSecretConfig|PrivateKeyJwtConfig|MutualTlsConfig;
```

- `ClientSecretConfig`: `client_secret_basic` or `client_secret_post`.
- `PrivateKeyJwtConfig`: `private_key_jwt` (RFC 7523).
- `MutualTlsConfig`: `tls_client_auth` or `self_signed_tls_client_auth` (RFC 8705). The token endpoint alias in `mtls_endpoint_aliases` is used when published.

A CIMD client cannot use a shared secret. `clientAuth` can be omitted for a public client, except with the client credentials grant.

For the ID-JAG flow, `exchangeIdTokenForIdJag(idToken, context, IdentityProviderConfig)` performs the token exchange at the identity provider from the application's existing OpenID Connect session. The client calls `assertionProvider` only after discovery has resolved the audience, resource, client ID and scopes, and passes them in `IdentityAssertionContext`. The ID-JAG is never cached, and a refresh token from the resource authorization server is ignored. Only the final MCP access token is cached.

OAuth failures are returned as `mcp:AuthorizationError`. When a token endpoint rejects a request, the cause chain contains an `mcp:OAuthTokenError`, whose `detail()` carries the OAuth `error`, `error_description`, `error_uri`, the HTTP status and, for `insufficient_user_authentication`, `max_age`.

### Errors

The public error hierarchy is reduced to the types applications act on. Transport and decoder errors become module-private subtypes.

```
Error
├── ClientError
│   ├── TransportError
│   │   └── AuthorizationError
│   ├── ProtocolError
│   ├── StreamError
│   └── ToolCallError
├── ServerError
└── OAuthTokenError
```

`ToolCallError` carries the last `InputRequiredResult` in its detail when the continuation limit is reached. The modern error codes are public constants: `HEADER_MISMATCH` (`-32020`), `MISSING_REQUIRED_CLIENT_CAPABILITY` (`-32021`) and `UNSUPPORTED_PROTOCOL_VERSION` (`-32022`).

## Compile-Time Validation

In addition to the 1.x checks, the compiler plugin reports:

| Severity | Condition |
|---|---|
| Error | A required `mcp:HttpSession` parameter in a `"modern"` service. |
| Warning | A required `mcp:HttpSession` parameter in an `"auto"` service, which can then serve legacy requests only. |
| Warning | A nilable `mcp:HttpSession?` parameter in an `"auto"` service (may be `()`) or a `"modern"` service (always `()`). |
| Error | `@mcp:Argument` on a parameter that is not a non-nilable `string`, `int`, `float`, `decimal` or `boolean` tool argument. |
| Error | An invalid or duplicate `@mcp:Argument` header name in a tool. |
| Error | `@mcp:Argument` combined with an explicit `@mcp:Tool.schema`, since the schema would not contain the header declaration. |

The 1.x diagnostics that named `mcp:Session` and `mcp:Meta` now name `mcp:HttpSession` and `mcp:RequestMetaObject`. The diagnostic for transport-specific parameters on `mcp:Service` is removed together with that type.

## Example Usage

A server that serves modern and legacy clients:

```ballerina
import ballerina/mcp;

listener mcp:StreamableHttpListener mcpListener = check new (9090);

type Forecast record {|
    string region;
    decimal temperature;
|};

@mcp:StreamableHttpConfig {
    info: {name: "weather", version: "2.0.0"},
    cacheHints: {listTools: {ttlMs: 60000, cacheScope: "public"}}
}
service mcp:StreamableHttpService /mcp on mcpListener {

    # Returns the forecast for a region.
    remote isolated function forecast(@mcp:Argument {headerName: "Region"} string region,
            mcp:RequestMetaObject? meta) returns Forecast {
        return {region, temperature: 24.5d};
    }
}
```

A modern client sees `outputSchema` and `structuredContent: {"region": "...", "temperature": 24.5}`, and sends the region in `Mcp-Param-Region`. A `2025-11-25` client completes `initialize` and receives the same tool without `outputSchema`.

A client that connects to either kind of server:

```ballerina
import ballerina/io;
import ballerina/mcp;

public function main() returns error? {
    mcp:StreamableHttpClient mcpClient = check new ("http://localhost:9090/mcp");

    mcp:ConnectionInfo connection = check mcpClient->connect({name: "weather-client", version: "2.0.0"});
    io:println("Using MCP ", connection.protocolVersion);

    mcp:ListToolsResult tools = check mcpClient->listTools();
    mcp:CallToolResult result = check mcpClient->callTool({
        name: "forecast",
        arguments: {region: "Colombo"}
    });
    io:println(result.structuredContent);

    check mcpClient->close();
}
```

A client that obtains its own token with the client credentials grant:

```ballerina
configurable string clientSecret = ?;

mcp:StreamableHttpClient mcpClient = check new ("https://tools.example.com/mcp",
    auth = {
        grant: {
            clientConfig: {
                clientId: "reporting-agent",
                issuer: "https://auth.example.com",
                clientAuth: {clientSecret}
            }
        }
    }
);
```

## Backward Compatibility & Migration

Version 2.0 is a major release with breaking API changes. Wire compatibility with legacy peers is preserved by the default `"auto"` mode.

| 1.x | 2.0 |
|---|---|
| `mcp:Listener` | `mcp:StreamableHttpListener` |
| `mcp:Service` | `mcp:StreamableHttpService` |
| `mcp:AdvancedService` | `mcp:StreamableHttpAdvancedService` |
| `@mcp:ServiceConfig`, `@mcp:StreamableHttpServiceConfig` | `@mcp:StreamableHttpConfig` |
| `mcp:Session`, `mcp:SessionEntry` | `mcp:HttpSession`, `mcp:HttpSessionEntry` |
| `mcp:SessionMode` | `mcp:HttpSessionMode` |
| `mcp:Meta` | `mcp:RequestMetaObject` |
| `mcp:StreamableHttpClientTransportConfig` | `mcp:StreamableHttpClientConfig` |
| `initialize()` | `connect()`, or `initializeLegacy()` |
| `subscribeToServerMessages()` | `listen()` |

- Most migrations are renames. The client must now call `connect()` before other operations; 1.x did not enforce `initialize()`.
- Services that use `mcp:HttpSession` keep working for legacy clients in the default `"auto"` mode, and the compiler warns that modern clients cannot use them. To serve modern clients, move the state into the application.
- A legacy client keeps receiving the legacy wire shapes from a 2.0 server.
- A 2.0 client connects to a 1.x server through the `"auto"` fallback.

## Future Plans

- **Multi round-trip requests.** Elicitation from tools through `InputRequiredResult`, with a typed client handler and signed `requestState`, will be proposed separately.
- **Additional transports.** A stdio transport, with transport-agnostic service types reintroduced alongside it.
- **Prompts and resources.** Server and client support for the remaining primitives, including the list-changed and resource subscriptions that `SubscriptionFilter` already models.
- **Native JSON Schema validation**, once the language provides it, so that `InputSchema` and `OutputSchema` can be enforced at runtime.

## Conclusion

Version 2.0 lets Ballerina clients and services use MCP `2026-07-28` without breaking communication with the existing ecosystem. Protocol selection is explicit on the client and per request on the server. Session-dependent designs are reported at compile time, and caching is opt-in on the server and automatic on the client. The client handles MCP authorization itself. The release also completes the move to explicit Streamable HTTP names, which leaves a single, consistent API to build further protocol features on.
