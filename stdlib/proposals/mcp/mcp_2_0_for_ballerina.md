# MCP 2.0 for Ballerina: Modern Protocol Support and API Revision

- Author: @RadCod3
- Reviewers:
- Created: 2026-10-15
- Updated: 2026-10-19
- Issue: [#1511](https://github.com/ballerina-platform/ballerina-spec/issues/1511)
- Status: Submitted

## Summary

MCP `2026-07-28` replaces the `initialize` handshake and HTTP sessions with per-request negotiation. Every request carries its protocol version, client information and capabilities, and a server describes itself through `server/discover`. The revision also adds standard routing headers, tool argument headers, change notification subscriptions over `POST`, structured output with any JSON root, and caching hints on cacheable results.

This proposal defines version 2.0 of `ballerina/mcp`. It:

- adds support for MCP `2026-07-28` (the "modern" protocol) to the client and the server, while keeping interoperability with every initialize-based revision up to `2025-11-25` (the "legacy" protocol) through a configurable protocol mode;
- revises the public API around the Streamable HTTP transport, removing the aliases deprecated in 1.x and making the client connect explicitly;
- adds result caching on both sides;
- adds MCP authorization (OAuth 2.1) to the client, including Enterprise-Managed Authorization, and to services, which act as OAuth protected resources.

## Goals

- Support MCP `2026-07-28` for tools on both the client and the server.
- Let existing MCP clients and servers that only speak the legacy protocol keep working with Ballerina by default, without extra configuration.
- Report service designs that cannot work with the modern protocol, such as tools that require an HTTP session, at compile time.
- Give Streamable HTTP concepts explicit names, and remove the deprecated 1.x aliases.
- Make protocol selection an explicit client step whose result is visible to the application.
- Support the caching hints defined in `2026-07-28`, so that servers can mark results as reusable and clients reuse them.
- Let a client obtain its own access tokens from an MCP server's authorization server.
- Let a service enforce MCP authorization: publish protected resource metadata, challenge requests without a valid token, accept only tokens issued for it, and require scopes per tool.

## Non-Goals

- Server-to-client requests through multi round-trip requests, such as elicitation. The `InputRequiredResult` continuation types described in this proposal are the minimal surface that the `tools/call` result shape needs. How a server asks for input and how a client answers it will be covered by a separate proposal, which may change the client's input handler API.
- Prompts, resources, completions and logging. The module implements tools only, and these capabilities are not advertised.
- Change notifications. `subscriptions/listen` is not supported, and `tools.listChanged` is always `false`. Change notification subscriptions will be added in a later minor release (see [Future Plans](#future-plans)).
- Tasks. Neither the task-augmented requests of `2025-11-25` nor the `io.modelcontextprotocol/tasks` extension of `2026-07-28` is supported, and the `2025-11-25` task fields are removed from the client and server types.
- Transports other than Streamable HTTP, such as stdio.
- Acting as an authorization server. A service validates tokens issued by external authorization servers, and does not issue tokens or register clients.

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

### Clients and servers need authorization

MCP servers are increasingly protected with OAuth. The 1.x client accepts only an existing credential through `http:ClientAuthConfig`. It cannot discover the authorization server from protected resource metadata, run an OAuth grant, or refresh tokens, so each application implements MCP authorization itself.

On the server side, a 1.x service can use `ballerina/http` listener authentication, which validates a bearer token but does not implement the MCP authorization specification. It publishes no protected resource metadata and sends no `WWW-Authenticate` challenge that points to it, so an MCP client cannot discover where to obtain a token. It does not check that a token was issued for this server, and it cannot require scopes per tool or ask a client to obtain more scopes.

## Background: Current State (1.x)

- `mcp:Listener` (deprecated) and `mcp:StreamableHttpListener` serve `mcp:Service`, `mcp:AdvancedService`, `mcp:StreamableHttpService` and `mcp:StreamableHttpAdvancedService`.
- `@mcp:ServiceConfig` and `@mcp:StreamableHttpServiceConfig` configure a service, and `sessionMode` selects `STATEFUL`, `STATELESS` or `AUTO` session handling.
- A tool can bind `mcp:Session` (first parameter) and `mcp:Meta?`. Streamable HTTP tools can also bind `@http:Header` parameters, `http:Headers` and `http:Request`.
- A Streamable HTTP service is authenticated through `auth` in its `http:HttpServiceConfig`, with `http:ListenerAuthConfig[]`.
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

Modern revisions are kept in a list even though there is only one, so that a future revision can be added without changing how versions are checked.

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
| The server lists its versions in `server/discover` and in `UNSUPPORTED_PROTOCOL_VERSION` errors | `MODERN_PROTOCOL_VERSIONS` in `"modern"` mode, `SUPPORTED_PROTOCOL_VERSIONS` in `"auto"` mode, and `LEGACY_PROTOCOL_VERSIONS` in the error a `"legacy"` mode server returns to modern requests |

A protocol mode selects which of these a client or service uses. It is independent of HTTP session management.

```ballerina
public type ProtocolMode "legacy"|"auto"|"modern";
```

| Mode | Client | Server |
|---|---|---|
| `"auto"` (default) | Tries modern discovery. Falls back to `initialize` only when the response shows a legacy server. | Accepts modern requests and initialize-based requests. Each request follows the lifecycle of its own form. |
| `"modern"` | Requires a version in `MODERN_PROTOCOL_VERSIONS`. | Accepts modern requests only. `server/discover` advertises only `MODERN_PROTOCOL_VERSIONS`, and `initialize` is rejected with `UNSUPPORTED_PROTOCOL_VERSION`, listing those versions. |
| `"legacy"` | Uses `initialize`. | Accepts initialize-based requests only. A modern request, including `server/discover`, is rejected with `UNSUPPORTED_PROTOCOL_VERSION`, listing `LEGACY_PROTOCOL_VERSIONS`, so that an `"auto"` client falls back. |

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

`mcp:Service` and `mcp:AdvancedService` are removed. The [transport-specific service types proposal](https://github.com/ballerina-platform/ballerina-spec/pull/1452) added the Streamable HTTP service types so that tools could access HTTP headers and requests without giving a transport-agnostic name an HTTP-only feature. It kept `mcp:Service` for backward compatibility, and for transport-agnostic services once another transport, such as stdio, is supported. A major version no longer needs that compatibility, and while Streamable HTTP is the only transport, keeping `mcp:Service` would leave two service types for the same transport, one of them without HTTP access. The transport-agnostic types can be reintroduced together with a second transport without breaking existing services.

#### Service configuration

`@mcp:StreamableHttpServiceConfig`, introduced in 1.2.0, is the only service annotation. The deprecated `@mcp:ServiceConfig` is removed:

```ballerina
public type StreamableHttpServiceConfiguration record {|
    # Server implementation information
    Implementation info;
    # Protocol selection
    ProtocolMode protocolMode = "auto";
    # Optional server configuration options
    ServerOptions options?;
    # HTTP service configuration for the underlying transport, including authorization
    HttpServiceConfig httpConfig = {};
    # Session management for legacy requests
    HttpSessionMode sessionMode = AUTO;
    # Caching hints sent to modern clients on cacheable results
    CacheHints cacheHints = {};
|};

public annotation StreamableHttpServiceConfiguration StreamableHttpServiceConfig on service;
```

- `info` is returned in `InitializeResult.serverInfo` for legacy requests, and in `_meta` of every modern result under `io.modelcontextprotocol/serverInfo`.
- `options.instructions` is returned by `initialize` and by `server/discover`.
- The server advertises the `tools` capability only. It removes `logging`, `prompts`, `resources` and `completions` from `options.capabilities`, because the module has no runtime for them. `tools.listChanged` is always `false`.
- The CORS `allowOrigins` list in `httpConfig` is also used for the `Origin` validation required by the Streamable HTTP transport, on both modern and legacy requests. A request without an `Origin` header is accepted, since clients other than browsers do not send one. A request whose `Origin` is not listed, and is not matched by `*`, is rejected with `403 Forbidden`. The list is empty by default, so a service that browser clients call must list their origins. `Origin` is checked before authentication (see [Service authorization](#service-authorization)).

#### Modern request handling

For a modern request, the dispatcher:

1. Reads the protocol version from `_meta["io.modelcontextprotocol/protocolVersion"]` and the `MCP-Protocol-Version` header. A version the service does not accept is rejected with `UNSUPPORTED_PROTOCOL_VERSION` (`-32022`) and HTTP status `400`. The error `data` lists the supported and requested versions, so that the client can select another version.
2. Validates the routing headers. `MCP-Protocol-Version` must match the request metadata, `Mcp-Method` must match the JSON-RPC method, and for `tools/call`, `Mcp-Name` must match the tool name. A mirrored argument header (see [Argument headers](#argument-headers)) must be present once and match the decoded argument. A mismatch is rejected with `HEADER_MISMATCH` (`-32020`) before the service is invoked.
3. Dispatches `server/discover`, `tools/list` and `tools/call`. Any other method, including `subscriptions/listen`, gets `METHOD_NOT_FOUND`.

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

- `mcp:HttpSession` or `mcp:HttpSession?`, at any position, for legacy session state. Unlike 1.x, it no longer has to be the first parameter;
- `mcp:RequestMeta?` (renamed from `mcp:Meta`), at any position, for the request's `_meta`. It must be nilable, because clients may omit `_meta`;
- `@http:Header` parameters, `http:Headers` and `http:Request`, as defined in the transport-specific service types proposal;
- `mcp:AuthContext` or `mcp:AuthContext?`, at any position, for the authenticated caller (see [Service authorization](#service-authorization)).

Runtime parameters are not part of the generated input schema. An omitted defaultable argument takes its default value.

The `_meta` objects of requests and results are typed as `mcp:RequestMeta` and `mcp:ResultMeta`. Each is an open record that declares the keys this module uses:

```ballerina
public type RequestMeta record {
    ProgressToken progressToken?;
};

public type ResultMeta record {
    # Server implementation that produced the response
    Implementation serverInfo?;
};
```

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

The library always builds the result's content from the return value. A `string` becomes a text content block as is. Any other value except `()` becomes a text content block holding its JSON serialization, as the specification recommends for structured results. `()` produces no content block. The rest of the result depends on the protocol:

- **Modern:** `tools/list` advertises `outputSchema`, and `structuredContent` carries the return value with any JSON root, including `null` for a nilable return type such as `string?`.
- **Legacy:** the 1.x behavior is kept. `outputSchema` is not advertised, and the result contains only the text content block, without `structuredContent`.

Setting `structuredOutput: false` marks a tool's output as unstructured, whatever its return type:

- the compiler does not generate an `outputSchema`, so a return type that cannot be mapped to a JSON Schema does not cause a compilation error;
- `tools/list` does not advertise an `outputSchema`, and `tools/call` returns only the text content block, without `structuredContent`, on both protocols.

A tool that declares no return type, or whose return type allows only `()` apart from `error`, such as `error?`, is unstructured in the same way. It has no output to describe, so it advertises no `outputSchema` and returns no `structuredContent`.

`structuredOutput: false` cannot be combined with an explicit `outputSchema`; the compiler reports an error, since the tool would advertise a schema for output it never sends.

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

`@mcp:Argument` applies to a non-nilable `string`, `int` or `boolean` argument, the types that the specification allows in argument headers. Header names are compared case-insensitively, so two arguments of a tool cannot use names that differ only in case. The specification also limits integers in headers to ±(2<sup>53</sup>−1), so the client rejects a call whose `int` argument header is outside that range.

#### Advanced services

An advanced service owns tool discovery and dispatch. Its methods are validated by the compiler plugin:

```ballerina
remote isolated function onListTools(Cursor? cursor) returns ListToolsResult|ServerError;

remote isolated function onCallTool(CallToolParams params)
        returns CallToolResult|InputRequiredResult|ServerError;
```

- These methods can bind the same HTTP request values as basic tools. `onCallTool` reads request metadata from `params._meta`.
- The `cursor` parameter of `onListTools` is optional. A service that declares it receives the request's cursor, and can return the tools in pages by setting `nextCursor`. A basic service always returns all of its tools in one page.
- For a legacy request, the library keeps results within the legacy schema. It removes an `outputSchema` or `structuredContent` whose root is not an object, and rejects an `InputRequiredResult`.
- `onCallTool` may return `InputRequiredResult` to a modern request. The input-request design is out of scope for this proposal (see [Non-Goals](#non-goals)).

#### Tool errors

The specification separates tool execution errors, which are returned in the tool result so that the model can see them, from protocol errors, which are JSON-RPC errors. The library maps failures the same way on both protocols:

| Failure | Response |
|---|---|
| A basic tool returns an `error` | A `CallToolResult` with `isError: true`, whose text is the error message |
| A basic tool panics | A `CallToolResult` with `isError: true` and a generic message |
| A tool or an advanced service method returns an `mcp:InsufficientScopeError` | HTTP `403` with an `insufficient_scope` challenge (see [Service authorization](#service-authorization)) |
| An HTTP request value cannot be bound to a parameter | A JSON-RPC `INVALID_PARAMS` error |
| An advanced service method returns a `ServerError` | A JSON-RPC error with the `ServerError` message |
| An advanced service method returns another error, or panics | A JSON-RPC `INTERNAL_ERROR` with a generic message |

Only an `error` returned by a basic tool, or a `ServerError`, reaches the client with its own message, so that internal details of other failures are not exposed. An advanced service reports a tool execution error by returning a `CallToolResult` with `isError: true`.

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
@mcp:StreamableHttpServiceConfig {
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

Each field is resolved separately. A value set by `onListTools` wins, then the configured hint, then the default (`ttlMs: 0`, `cacheScope: "private"`), so results are not reused unless the service opts in. `attach` rejects a negative configured `ttlMs`. A negative `ttlMs` set by `onListTools` is treated as `0`, and the library logs an error. Legacy responses never carry these fields.

#### Service authorization

A service implements MCP authorization by acting as an OAuth protected resource. `httpConfig` is an `mcp:HttpServiceConfig`. It has the fields of `http:HttpServiceConfig`, in the same order and with the same defaults, except that `auth` also accepts `mcp:OAuthProtectedResourceConfig`. As on the client, the fields are copied because Ballerina cannot widen an included field.

```ballerina
public type HttpServiceConfig record {|
    string host = "b7a.default";
    http:CompressionConfig compression = {};
    http:Chunking chunking = http:CHUNKING_AUTO;
    http:CorsConfig cors = {};
    # MCP authorization, or HTTP listener authentication without discovery
    OAuthProtectedResourceConfig|http:ListenerAuthConfig[] auth?;
    string mediaTypeSubtypePrefix?;
    boolean treatNilableAsOptional = true;
    byte[] openApiDefinition = [];
    boolean validation = true;
    typedesc<http:ServiceContract> serviceType?;
    string basePath?;
    boolean laxDataBinding = false;
|};

public type OAuthProtectedResourceConfig record {|
    # Canonical URI of the service as clients address it, such as `https://mcp.example.com/mcp`
    string 'resource;
    # Authorization servers whose access tokens are accepted
    AuthorizationServer[] authorizationServers;
    # Scopes every request must carry
    string[] requiredScopes = [];
    # Scopes that a broader scope grants, keyed by the broader scope
    map<string[]> scopeHierarchy = {};
    # Published as `scopes_supported`; defaults to `requiredScopes`
    string[] scopesSupported?;
    string resourceName?;
    string resourceDocumentation?;
    string resourcePolicyUri?;
    string resourceTosUri?;
|};

public type AuthorizationServer record {|
    # Issuer identifier, advertised in the metadata and required as `iss` in JWT access tokens
    string issuer;
    # Audience of this server's tokens for the service; defaults to `resource`
    string|string[] audience?;
    JwtTokenValidator|IntrospectionTokenValidator validator;
|};

public type JwtTokenValidator record {|
    http:JwtValidatorConfig jwtValidatorConfig;
|};

public type IntrospectionTokenValidator record {|
    http:OAuth2IntrospectionConfig oauth2IntrospectionConfig;
|};
```

With an `mcp:OAuthProtectedResourceConfig`, the service:

- publishes protected resource metadata (RFC 9728) at `<origin>/.well-known/oauth-protected-resource<path>`, where the origin and path come from `resource`. The document lists `resource`, the issuers as `authorization_servers`, `bearer_methods_supported: ["header"]`, `scopes_supported` and the optional resource fields. It is served without authentication, with CORS open to any origin.
- authenticates every request, on both protocols, including `initialize`, `server/discover` and session `DELETE`. A request without a bearer token gets `401` with a `WWW-Authenticate: Bearer` challenge carrying `resource_metadata` and the `requiredScopes` as `scope`. An invalid or expired token gets the same challenge with `error="invalid_token"`.
- accepts a token only from the authorization server that issued it. A JWT is validated by the server named in its `iss`, and a JWT that names no configured issuer is rejected. An opaque token names no issuer, so at most one authorization server can use introspection.
- accepts a token only when it was issued for this service: its audience must match the server's `audience`, or `resource` by default. The expected issuer and audience are set on `AuthorizationServer`, not in `jwtValidatorConfig`.
- answers a request whose token lacks a required scope with `403` and `error="insufficient_scope"`. The challenge's `scope` lists every scope the operation needs, not only the missing ones, so that the client can obtain a sufficient token and retry.
- answers `503` when the introspection endpoint cannot be reached, so that the client keeps its token and retries. JWT validation does not distinguish a failure to fetch the authorization server's keys from an invalid token, so such a failure is answered as `invalid_token`.
- exposes `WWW-Authenticate` through its CORS configuration, so that browser clients can read challenges.

Scopes apply at three levels:

- `requiredScopes` apply to every request. They are local policy, not a metadata field.
- `scopes` on `@mcp:Tool` apply to calls of that tool, in addition to `requiredScopes`. They are never sent to clients: `tools/list` lists every tool, and a call without the scopes gets the `403` challenge.
- A tool or an advanced service method that decides at run time that more scopes are needed returns `mcp:InsufficientScopeError`, whose detail names them. The service answers with the `403` challenge instead of a tool result.

```ballerina
public type InsufficientScopeErrorDetail record {|
    # Scopes the operation needs, in addition to `requiredScopes`
    string[] scopes;
|};

public type InsufficientScopeError distinct ServerError & error<InsufficientScopeErrorDetail>;
```

When an authorization server issues hierarchical scopes, `scopeHierarchy` declares which scopes a broader scope grants. A token holding a key satisfies every scope listed for it, transitively. Challenges still name the exact scopes an operation needs. Scopes must be valid OAuth scope tokens, and `offline_access` cannot be required, because it asks the authorization server for a refresh token rather than granting access to the service.

A tool, `onListTools` and `onCallTool` can declare `mcp:AuthContext` to receive the authenticated caller:

```ballerina
public type AuthContext record {|
    # `sub` claim
    string? subject;
    # `client_id` or `azp` claim
    string? clientId;
    string? issuer;
    # Granted scopes, together with the scopes they imply through `scopeHierarchy`
    string[] scopes;
    # All claims of the token, or the introspection response
    map<json> claims;
    # The raw token, for token exchange only; it must not be passed through to upstream APIs
    string token;
|};
```

A legacy HTTP session belongs to the issuer, client and subject of the token that created it. A request with a token that differs in any of them gets `404`, as for an unknown session, so the same user signed in through two clients cannot share a session. A token that names neither a subject nor a client gets no session: `initialize` succeeds without a session ID, unless the service requires sessions.

`attach` returns an error for a configuration that cannot be enforced: no authorization servers, a `resource` that is not a canonical absolute HTTP(S) URI, a duplicate issuer, more than one introspection server, an invalid scope, an empty `scopeHierarchy` entry, two services on one host with the same metadata path, or a non-nilable `mcp:AuthContext` parameter or `@mcp:Tool` scopes on a service without an `mcp:OAuthProtectedResourceConfig`.

`auth` still accepts `http:ListenerAuthConfig[]`, HTTP listener authentication as in 1.x. Such a service publishes no metadata, answers failures with `401` or `403` without a challenge, and gives a nilable `mcp:AuthContext?` the value `()`.

```ballerina
@mcp:StreamableHttpServiceConfig {
    info: {name: "files", version: "2.0.0"},
    httpConfig: {
        auth: {
            'resource: "https://mcp.example.com/files",
            authorizationServers: [
                {
                    issuer: "https://login.example.com",
                    validator: {
                        jwtValidatorConfig: {
                            signatureConfig: {jwksConfig: {url: "https://login.example.com/oauth2/jwks"}}
                        }
                    }
                }
            ],
            requiredScopes: ["files:read"],
            scopeHierarchy: {"files:write": ["files:read"]}
        }
    }
}
service mcp:StreamableHttpService /files on mcpListener {

    @mcp:Tool {scopes: ["files:write"]}
    remote isolated function deleteFile(mcp:AuthContext auth, string path) returns string|error {
        return string `deleted ${path} for ${auth.subject ?: "unknown"}`;
    }
}
```

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

`init` only configures the transport. In 1.x, `initialize()` always ran the legacy handshake, and nothing stopped an application from calling `listTools()` or `callTool()` without it. In 2.0, `connect()` selects the protocol and must be called before `listTools()`, `callTool()` or `callToolOnce()`, which return an error otherwise. It returns what was negotiated:

```ballerina
public type ConnectionInfo record {|
    string protocolVersion;
    Implementation serverInfo?;
    ServerCapabilities capabilities;
    string instructions?;
|};
```

Calling `connect()` on a connected client returns the existing `ConnectionInfo` without another request. `initializeLegacy()` and `adoptDiscovery()` return an error on a connected client. `close()` ends a legacy session, clears the result cache and resets the connection, even when the server cannot be reached, so the same client can call `connect()` again.

#### Client configuration

```ballerina
public type StreamableHttpClientConfig record {|
    # Protocol selection
    ProtocolMode protocolMode = "auto";
    # HTTP transport settings, including authorization
    HttpClientConfig httpConfig = {};
    # Reuse of modern results; `()` disables it
    ResultCacheConfig? resultCache = {};
    # Callback for input-required continuations
    InputHandler inputHandler?;
    # Maximum number of input-required continuations per call
    int maxInputRounds = 8;
    # Legacy session to resume; cannot be combined with `"modern"`
    string sessionId?;
|};
```

HTTP settings are grouped under `httpConfig`, as on the service side. `HttpClientConfig` has the fields of `http:ClientConfiguration`, in the same order and with the same defaults, with two exceptions: `auth` also accepts `mcp:OAuthConfig` (see [Authorization](#authorization)), and `followRedirects` is decided by the module when it is `()`:

```ballerina
public type HttpClientConfig record {|
    http:HttpVersion httpVersion = http:HTTP_2_0;
    http:ClientHttp1Settings http1Settings = {};
    http:ClientHttp2Settings http2Settings = {};
    decimal timeout = 30;
    string forwarded = "disable";
    http:FollowRedirects? followRedirects = ();
    http:PoolConfiguration? poolConfig = ();
    http:CacheConfig cache = {};
    http:Compression compression = http:COMPRESSION_AUTO;
    # An existing credential, or MCP authorization through OAuth
    (http:ClientAuthConfig|OAuthConfig)? auth = ();
    http:CircuitBreakerConfig? circuitBreaker = ();
    http:RetryConfig? retryConfig = ();
    http:CookieConfig? cookieConfig = ();
    http:ResponseLimitConfigs responseLimits = {};
    http:ProxyConfig? proxy = ();
    boolean validation = true;
    http:ClientSocketConfig socketConfig = {};
    boolean laxDataBinding = false;
    http:ClientSecureSocket? secureSocket = ();
|};
```

- When `followRedirects` is `()`, redirects are followed, except with `mcp:OAuthConfig`. An explicit `followRedirects` is used as given.
- With `mcp:OAuthConfig`, redirects are never followed: the client attaches the token itself, so a redirect could send it to another host or hide the authorization challenge. `init` returns an error if `followRedirects` enables them.
- The OAuth metadata and token endpoint requests reuse `secureSocket` and `proxy`.

#### Protocol selection

In `"auto"` mode, `connect()` sends `server/discover`. If the result lists a version in `MODERN_PROTOCOL_VERSIONS`, the client uses the newest one. If it lists none of them but lists a version in `LEGACY_PROTOCOL_VERSIONS`, the client falls back to `initialize`. Otherwise, `connect()` returns an error. If the request fails, the client falls back to `initialize` only when the failure shows a legacy server:

- HTTP `400`, `404` or `405`, or a response that cannot be parsed as a modern result;
- `UNSUPPORTED_PROTOCOL_VERSION` whose `data.supported` lists only legacy versions this module supports.

It does not fall back on `401`, `403` or `5xx`, on `HEADER_MISMATCH` or `MISSING_REQUIRED_CLIENT_CAPABILITY`, or when `data.supported` includes a version in `MODERN_PROTOCOL_VERSIONS`. A server that is modern but unavailable or unauthorized therefore returns an error instead of being treated as legacy. A configured `sessionId` implies a resumed legacy session, and cannot be combined with `"modern"`.

A modern `server/discover` result may omit `resultType`, `ttlMs` and `cacheScope`. Such a result is treated as `complete`, `0` and `"private"`, so `"auto"` mode does not fall back for a modern server that leaves them out.

The lower-level methods support applications that manage discovery themselves. `discover()` fetches discovery data without connecting. `adoptDiscovery()` connects from a `DiscoverResult` obtained earlier, without another request. `initializeLegacy()` runs the `initialize` handshake explicitly.

#### Modern requests

On the modern protocol, the client:

- adds the protocol version, client information and capabilities to `_meta` of every request, and sends `MCP-Protocol-Version`, `Mcp-Method` and, for `tools/call`, `Mcp-Name`;
- keeps the tool schemas from `tools/list`, and copies arguments marked with `x-mcp-header` into `Mcp-Param-*` headers on `tools/call`. Tools whose header declarations are invalid are left out of the `listTools()` result;
- refetches the tool list and retries the call once when a call fails with `HEADER_MISMATCH`, which usually means the cached schema is out of date;
- requires `resultType`, `ttlMs` and `cacheScope` on `tools/list` results.

`callTool()` returns when the call completes. If a modern server returns `InputRequiredResult`, it calls the configured `inputHandler`, echoes `requestState` unchanged, and retries, up to `maxInputRounds`. `callToolOnce()` performs one request and returns `CallToolResult|InputRequiredResult`, so that the application can handle continuations itself. On a legacy connection it behaves like `callTool()`. As noted in [Non-Goals](#non-goals), the input handler API will be revisited in a separate proposal.

#### Result caching

The client reuses modern `tools/list` results while their `ttlMs` keeps them fresh. Each page is cached under its cursor. `server/discover` results are not cached, and `cacheMode` has no effect on a legacy connection.

Caching is configured through `resultCache`:

```ballerina
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

- Cached results are dropped when the server rejects a cursor with `INVALID_PARAMS` (all pages are dropped), when a call fails with `HEADER_MISMATCH`, when a `401` or `insufficient_scope` challenge yields a different token (a step-up can change the tool list), and on `close()`. A token refreshed on expiry does not drop them. A request that is already running cannot put back a result that was dropped while it ran.
- A negative `ttlMs` from a server is treated as `0`.
- `init` returns an error for a negative `maxTtlMs` or `maxEntries`. A value of `0` for either disables storing results.
- Each client has its own cache and is treated as one authorization context, so `cacheScope` does not change how the client caches. Credentials belong in `httpConfig.auth`, with a separate client for each user. Per-call headers are not part of the cache key, so a call whose headers carry `Authorization` bypasses the cache: `listTools()` fetches without storing, and `callTool()` lists the tools again instead of using the kept schemas.
- The tool schemas used for argument headers are kept even when `resultCache` is `()` or `ttlMs` is `0`, and are merged across pages. Only the drops listed above remove them; a `bypass` listing does not record them.

Servers default to `ttlMs: 0`, so caching changes nothing until a server opts in.

#### Authorization

`httpConfig.auth` accepts either an existing credential (`http:ClientAuthConfig`) or an `mcp:OAuthConfig`. With `mcp:OAuthConfig`, the client implements MCP authorization (OAuth 2.1). On a `401` it reads the `WWW-Authenticate` challenge, fetches the protected resource metadata (RFC 9728) and the authorization server metadata (RFC 8414), runs the configured grant, attaches the access token, and refreshes or requests a new token when it expires. An `insufficient_scope` challenge triggers a step-up token request for the challenged scopes together with the scopes already granted.

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

```ballerina
public type ClientCredentialsGrant record {|
    ClientCredentialsClientConfig clientConfig;
|};

public type AuthorizationCodeGrant record {|
    OAuthClientConfig clientConfig;
    string redirectUri;
    AuthorizationRedirectHandler redirectHandler;
    AuthorizationCallbackHandler callbackHandler;
|};

public type IdentityAssertionGrant record {|
    OAuthClientConfig clientConfig;
    IdentityAssertionProvider assertionProvider;
|};
```

The grant records are closed and have no discriminator field. The grant is selected by the fields that are set: a `grant` with only `clientConfig` is a client credentials grant.

A client is either registered with one authorization server (`PreRegisteredClientConfig`, whose `issuer` must be listed in the protected resource metadata) or identified by a Client ID Metadata Document (`CimdClientConfig`):

```ballerina
public type PreRegisteredClientConfig record {|
    string clientId;
    # Issuer identifier of the authorization server that registered the client
    string issuer;
    # Omit for a public client
    ClientAuth clientAuth?;
|};

public type CimdClientConfig record {|
    # HTTPS URL of the Client ID Metadata Document
    string url;
    # Omit for a public client
    CimdClientAuth clientAuth?;
|};

public type OAuthClientConfig PreRegisteredClientConfig|CimdClientConfig;

# The client credentials grant requires client authentication
public type PreRegisteredClientCredentialsConfig record {|
    *PreRegisteredClientConfig;
    ClientAuth clientAuth;
|};

public type CimdClientCredentialsConfig record {|
    *CimdClientConfig;
    CimdClientAuth clientAuth;
|};

public type ClientCredentialsClientConfig PreRegisteredClientCredentialsConfig|CimdClientCredentialsConfig;
```

Client authentication at the token endpoint is one of:

```ballerina
public type ClientAuth ClientSecretConfig|PrivateKeyJwtConfig|MutualTlsConfig;

# A shared secret cannot be established through a metadata document
public type CimdClientAuth PrivateKeyJwtConfig|MutualTlsConfig;
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
│   └── InsufficientScopeError
└── OAuthTokenError
```

`ToolCallError` means the client could not complete or accept a tool call: the continuation limit is reached (the detail carries the last `InputRequiredResult`), the tool is not in the cached tool list, an argument cannot be copied into its header, a result is malformed, or a declared `outputSchema` comes back without `structuredContent`. A tool execution error is not a `ClientError`: it arrives as a `CallToolResult` with `isError: true`. A JSON-RPC error response is a `ProtocolError`, including a `HEADER_MISMATCH` that remains after the retry described in [Modern requests](#modern-requests).

The modern error codes are public constants: `HEADER_MISMATCH` (`-32020`), `MISSING_REQUIRED_CLIENT_CAPABILITY` (`-32021`) and `UNSUPPORTED_PROTOCOL_VERSION` (`-32022`).

## Compile-Time Validation

In addition to the 1.x checks, the compiler plugin reports:

| Severity | Condition |
|---|---|
| Error | A required `mcp:HttpSession` parameter in a `"modern"` service. |
| Warning | A required `mcp:HttpSession` parameter in an `"auto"` service, which can then serve legacy requests only. |
| Warning | A nilable `mcp:HttpSession?` parameter in an `"auto"` service (may be `()`) or a `"modern"` service (always `()`). |
| Error | `@mcp:Argument` on a parameter that is not a non-nilable `string`, `int` or `boolean` tool argument. |
| Error | An invalid `@mcp:Argument` header name, or a header name used twice in a tool, compared case-insensitively. |
| Error | `@mcp:Argument` combined with an explicit `@mcp:Tool.schema`, since the schema would not contain the header declaration. |
| Error | `@mcp:Tool` with `structuredOutput: false` and an explicit `outputSchema`. |

The 1.x diagnostics that named `mcp:Session` and `mcp:Meta` now name `mcp:HttpSession` and `mcp:RequestMeta`. The diagnostic requiring the session parameter to be first is removed, since `mcp:HttpSession` can be declared at any position. The diagnostic for transport-specific parameters on `mcp:Service` is removed together with that type.

## Example Usage

A server that serves modern and legacy clients:

```ballerina
import ballerina/mcp;

listener mcp:StreamableHttpListener mcpListener = check new (9090);

type Forecast record {|
    string region;
    decimal temperature;
|};

@mcp:StreamableHttpServiceConfig {
    info: {name: "weather", version: "2.0.0"},
    cacheHints: {listTools: {ttlMs: 60000, cacheScope: "public"}}
}
service mcp:StreamableHttpService /mcp on mcpListener {

    # Returns the forecast for a region.
    remote isolated function forecast(@mcp:Argument {headerName: "Region"} string region,
            mcp:RequestMeta? meta) returns Forecast {
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
    httpConfig = {
        auth: {
            grant: {
                clientConfig: {
                    clientId: "reporting-agent",
                    issuer: "https://auth.example.com",
                    clientAuth: {clientSecret}
                }
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
| `@mcp:ServiceConfig` | `@mcp:StreamableHttpServiceConfig` |
| `mcp:Session`, `mcp:SessionEntry` | `mcp:HttpSession`, `mcp:HttpSessionEntry` |
| `mcp:SessionMode` | `mcp:HttpSessionMode` |
| `mcp:Meta` | `mcp:RequestMeta` |
| `mcp:StreamableHttpClientTransportConfig` | `mcp:StreamableHttpClientConfig` |
| `http:HttpServiceConfig` in `httpConfig` | `mcp:HttpServiceConfig`, with the same fields |
| `initialize()` | `connect()`, or `initializeLegacy()` |
| `subscribeToServerMessages()` | Removed, without a replacement |

- `mcp:HttpSession` can be declared at any position, so existing tools that declare it first keep compiling.
- HTTP client settings move from the top level of the client configuration into `httpConfig`, for example `timeout = 60` becomes `httpConfig = {timeout: 60}`.
- Most migrations are renames. The client must now call `connect()` before other operations; 1.x did not enforce `initialize()`.
- Services that use `mcp:HttpSession` keep working for legacy clients in the default `"auto"` mode, and the compiler warns that modern clients cannot use them. To serve modern clients, move the state into the application.
- A legacy client keeps receiving the legacy wire shapes from a 2.0 server. The text content of a tool that returns a structured value is now its JSON serialization.
- Services that set `httpConfig.auth` to `http:ListenerAuthConfig[]` keep working unchanged. To implement MCP authorization, replace it with an `mcp:OAuthProtectedResourceConfig`.
- 1.x did not validate `Origin`. A 2.0 service rejects browser requests from origins that are not listed in `httpConfig.cors.allowOrigins`.
- The `2025-11-25` task fields are removed: `CallToolParams.task`, `ToolDefinition.execution` and the `tasks` client and server capabilities. A client still connects to a server that advertises tasks.
- A 2.0 client connects to a 1.x server through the `"auto"` fallback.

## Future Plans

- **Multi round-trip requests.** Elicitation from tools through `InputRequiredResult`, with a typed client handler and signed `requestState`, will be proposed separately.
- **Additional transports.** A stdio transport, with transport-agnostic service types reintroduced alongside it.
- **Change notifications.** `subscriptions/listen` on the client and on advanced services, starting with `notifications/tools/list_changed`, with cached tool lists dropped when it arrives. It can be added in a minor release, since it only adds an optional service method, a client method and new types.
- **Prompts and resources.** Server and client support for the remaining primitives, including their list-changed notifications and resource subscriptions.
- **Native JSON Schema validation**, once the language provides it, so that `InputSchema` and `OutputSchema` can be enforced at runtime.

## Conclusion

Version 2.0 lets Ballerina clients and services use MCP `2026-07-28` without breaking communication with the existing ecosystem. Protocol selection is explicit on the client and per request on the server. Session-dependent designs are reported at compile time, and caching is opt-in on the server and automatic on the client. The client handles MCP authorization itself. The release also completes the move to explicit Streamable HTTP names, which leaves a single, consistent API to build further protocol features on.
