# Transport-Specific Service Types for MCP Servers in Ballerina

- Author: @RadCod3
- Reviewers: @MaryamZi
- Created: 2026-06-17
- Updated: 2026-06-17
- Issue: [#1451](https://github.com/ballerina-platform/ballerina-spec/issues/1451)
- Status: Submitted

## Summary

The MCP server APIs currently expose a single `mcp:Service` type and an `mcp:Listener`, both of which are implicitly tied to the Streamable HTTP transport. This proposal keeps the base `mcp:Service` transport-agnostic and introduces transport-specific service types `mcp:StreamableHttpService` and `mcp:StreamableHttpAdvancedService` that allow tools to access transport-specific request information such as HTTP headers and the underlying request. It also renames `mcp:Listener` to `mcp:StreamableHttpListener` to make the transport explicit. This establishes a model that can grow to additional transports (e.g. stdio) without breaking the transport-neutral abstraction.

## Goals

- Keep `mcp:Service` (and `mcp:AdvancedService`) transport-agnostic, so the same service can target any current or future MCP transport.
- Allow tools served over Streamable HTTP to access transport-specific request information such as HTTP headers and the `http:Request` in an idiomatic, type-safe way.
- Enforce service ↔ listener compatibility through the type system, so transport-specific services can only be attached to a matching listener.
- Make the transport explicit in the listener name (`mcp:StreamableHttpListener`).
- Preserve backward compatibility with the current `mcp:Service` and `mcp:Listener` APIs.

## Non-Goals

- Introducing new transports (such as stdio) themselves. This proposal defines the service-type model that makes them possible, but each transport is proposed separately.
- Per-tool OAuth scope validation or authorization enforcement.
- Any changes to the MCP client APIs.

## Motivation

A primary driver is connecting AI agents to MCP servers secured with OAuth. When an agent calls a tool, the server frequently needs request-scoped context — most commonly the `Authorization` header or an identity derived from it to authorize the call or to act on behalf of the calling user. Today there is no idiomatic way for a tool to read that information.

The deeper issue is that the current `mcp:Service` and `mcp:Listener` are implicitly coupled to Streamable HTTP: HTTP-specific configuration lives on the neutral service, and the listener name does not state its transport. MCP is a transport-agnostic protocol (Streamable HTTP and stdio are both defined by the specification). Baking HTTP assumptions into the base service type blocks future transports and conflates protocol-level concerns with transport-level concerns.

This proposal resolves both: the base service stays transport-neutral, while transport-specific service types provide a typed channel to transport-specific request data. The natural consequence is that tools served over Streamable HTTP can bind HTTP headers and the request object — which is exactly what the OAuth use case needs.

## Background: Current state

The MCP server APIs define:

- `mcp:Service`: a basic service whose tools are declared as `remote` functions annotated with `@mcp:Tool`.
- `mcp:AdvancedService`: a service that takes manual control of tool listing and invocation via `onListTools` and `onCallTool`.
- `mcp:Listener`: the listener that serves these services.
- `@mcp:ServiceConfig`: a service-level annotation that carries server metadata (`info`, `options`) **and** HTTP/transport configuration (`httpConfig`, `sessionMode`).

Because `@mcp:ServiceConfig` carries HTTP configuration and the listener is unconditionally an HTTP listener, the supposedly neutral `mcp:Service` is in practice Streamable-HTTP-only, and there is no way for a tool to reach the underlying request.

## Design

### Transport-agnostic vs transport-specific service types

The service types are split into two tiers:

- **Transport-agnostic** types describe an MCP service independent of how it is exposed. They expose only protocol-level concepts (tools, sessions) and can be attached to any transport listener.
- **Transport-specific** types describe an MCP service exposed over a particular transport, and may additionally expose that transport's request information.

This yields four service types:

| Type | Tier | Tool model | Transport request access |
|---|---|---|---|
| `mcp:Service` | Transport-agnostic | `remote` functions (`@mcp:Tool`) | No |
| `mcp:AdvancedService` | Transport-agnostic | `onListTools` / `onCallTool` | No |
| `mcp:StreamableHttpService` | Streamable HTTP | `remote` functions (`@mcp:Tool`) | Yes |
| `mcp:StreamableHttpAdvancedService` | Streamable HTTP | `onListTools` / `onCallTool` | Yes |

The transport-agnostic and transport-specific basic types are **distinct sibling types**, not subtypes of one another. This is deliberate: it lets the type system enforce listener compatibility in both directions (see below).

```ballerina
# Transport-agnostic basic service. Tools are `remote` functions and cannot access
# transport-specific request information.
public type Service distinct service object {
};

# Transport-agnostic advanced service.
public type AdvancedService distinct service object {
    remote isolated function onListTools() returns ListToolsResult|ServerError;
    remote isolated function onCallTool(CallToolParams params, Session? session = ())
        returns CallToolResult|ServerError;
};

# Streamable HTTP basic service. Tool `remote` functions may additionally bind HTTP request
# information (`@http:Header` parameters, an `http:Headers` parameter, or an `http:Request`).
public type StreamableHttpService distinct service object {
};

# Streamable HTTP advanced service. `onListTools`/`onCallTool` may bind transport-specific
# request information in the same way.
public type StreamableHttpAdvancedService distinct service object {
};
```

### Listener: `mcp:StreamableHttpListener`

`mcp:Listener` is renamed to `mcp:StreamableHttpListener` so the transport is explicit at the point of use. The existing `mcp:Listener` is retained as a deprecated alias that delegates to `mcp:StreamableHttpListener`, so existing code continues to compile.

```ballerina
public isolated class StreamableHttpListener {
    public function init(int|http:Listener listenTo, *ListenerConfiguration config) returns Error? { /* ... */ }
    public isolated function attach(
            Service|AdvancedService|StreamableHttpService|StreamableHttpAdvancedService mcpService,
            string[]|string? name = ()) returns Error? { /* ... */ }
    // detach / start / gracefulStop / immediateStop ...
}

# Deprecated. Use `mcp:StreamableHttpListener` instead.
@deprecated
public isolated class Listener { /* delegates to StreamableHttpListener */ }
```

### Type-system-enforced listener ↔ service compatibility

A listener's `attach` method accepts a union of the service types it supports. `mcp:StreamableHttpListener` accepts all four types, because a Streamable HTTP listener can serve both transport-agnostic services and Streamable-HTTP-specific services.

A future transport listener (e.g. `mcp:StdioListener`) would accept only the transport-agnostic types and its own transport-specific types — **not** `mcp:StreamableHttpService`. Because the transport-specific types are distinct sibling types rather than subtypes of `mcp:Service`, attaching a `mcp:StreamableHttpService` to a non-HTTP listener is a compile-time type error, with no possibility of leaking through a supertype. This makes "this service requires this transport" a guarantee enforced by the type checker rather than a runtime check.

### Configuration

HTTP/transport configuration moves off the neutral `@mcp:ServiceConfig` annotation onto a transport-specific annotation, `@mcp:StreamableHttpServiceConfig`:

```ballerina
# Transport-agnostic service configuration.
public type ServiceConfiguration record {|
    Implementation info;
    ServerOptions options?;
    # # Deprecated
    # HTTP configuration is transport-specific. Use `@mcp:StreamableHttpServiceConfig` instead.
    @deprecated
    http:HttpServiceConfig httpConfig = {};
    # # Deprecated
    # Session management is transport-specific. Use `@mcp:StreamableHttpServiceConfig` instead.
    @deprecated
    SessionMode sessionMode = AUTO;
|};

public annotation ServiceConfiguration ServiceConfig on service;

# Streamable HTTP service configuration.
public type StreamableHttpServiceConfiguration record {|
    Implementation info;
    ServerOptions options?;
    http:HttpServiceConfig httpConfig = {};
    SessionMode sessionMode = AUTO;
|};

public annotation StreamableHttpServiceConfiguration StreamableHttpServiceConfig on service;
```

The `httpConfig` and `sessionMode` fields of `@mcp:ServiceConfig` are deprecated (compiler-enforced via `@deprecated`) but still honored at runtime for backward compatibility. New Streamable HTTP services should configure transport behavior through `@mcp:StreamableHttpServiceConfig`. The transport-specific annotation takes precedence when both are present.

## Accessing Transport-Specific Request Information

Tools and advanced methods on the Streamable HTTP service types may bind HTTP request information. The binding model deliberately mirrors `ballerina/http` so the experience is familiar to Ballerina developers.

### `@http:Header` parameters

A parameter annotated with `@http:Header` binds a single header value (or a record of header values), with the same supported types and semantics as `ballerina/http` resource functions — `string`, `int`, `float`, `decimal`, `boolean`, arrays of those, their nilable variants, finite/enum string types, and closed records of those types. Header binding honors the `treatNilableAsOptional` setting. `@http:Header` parameters are not part of the tool's input schema.

### `http:Headers` parameter

A parameter of type `http:Headers` receives the request's headers object, giving the tool full access to read any header. At most one `http:Headers` parameter is allowed per tool.

### `http:Request` parameter

A parameter of type `http:Request` receives the underlying HTTP request, from which headers and other request information can be read. At most one `http:Request` parameter is allowed per tool.

> Note: consistent with `ballerina/http`, nilable `http:Headers?`/`http:Request?` parameters are not supported.

### Basic services

```ballerina
@mcp:StreamableHttpServiceConfig {
    info: {name: "weather-server", version: "1.0.0"}
}
service mcp:StreamableHttpService /mcp on new mcp:StreamableHttpListener(9090) {

    @mcp:Tool {description: "Returns the forecast for the authenticated user's saved location"}
    remote function forecast(@http:Header {name: "Authorization"} string authorization, string day)
            returns string {
        // `authorization` is bound from the request header; `day` is a tool argument.
        // ...
    }
}
```

### Advanced services

The advanced service types declare `onListTools` and `onCallTool` `remote` methods. In addition to `mcp:CallToolParams` and an optional `mcp:Session`, these methods may bind the same transport-specific information (`@http:Header`, `http:Headers`, `http:Request`):

```ballerina
@mcp:StreamableHttpServiceConfig {
    info: {name: "advanced-server", version: "1.0.0"}
}
service mcp:StreamableHttpAdvancedService /mcp on new mcp:StreamableHttpListener(9091) {

    remote function onListTools(http:Headers headers) returns mcp:ListToolsResult|mcp:ServerError {
        // Filter the advertised tool list based on the caller, etc.
    }

    remote function onCallTool(mcp:CallToolParams params, mcp:Session? session,
            @http:Header {name: "Authorization"} string authorization)
            returns mcp:CallToolResult|mcp:ServerError {
        // ...
    }
}
```

### Compile-time validation

The split is enforced at compile time:

- Transport-specific parameters (`@http:Header`, `http:Headers`, `http:Request`) are rejected on the transport-agnostic `mcp:Service`, with a diagnostic that points the developer to a transport-specific service type such as `mcp:StreamableHttpService`.
- Parameter types are validated against the supported set, and duplicate `http:Headers`/`http:Request` parameters are reported.
- For the advanced service types, the compiler validates that `onListTools` and `onCallTool` are present with the correct return types, that `onCallTool` declares exactly one `mcp:CallToolParams` parameter, and that no unsupported `remote` methods are declared.

## Example Usage

A Streamable HTTP MCP server whose tool reads the OAuth bearer token from the request to act on behalf of the calling user:

```ballerina
import ballerina/http;
import ballerina/mcp;

@mcp:StreamableHttpServiceConfig {
    info: {name: "calendar-server", version: "1.0.0"},
    sessionMode: mcp:STATELESS
}
service mcp:StreamableHttpService /mcp on new mcp:StreamableHttpListener(9090) {

    @mcp:Tool {description: "Creates a calendar event for the authenticated user"}
    remote function createEvent(@http:Header {name: "Authorization"} string authorization,
            string title, string startTime) returns string|error {
        string userId = check resolveUser(authorization);
        // create the event for `userId` ...
        return string `Event '${title}' created for ${userId}`;
    }
}
```

A transport-agnostic service that does not need request information remains unchanged and portable across transports:

```ballerina
@mcp:ServiceConfig {
    info: {name: "math-server", version: "1.0.0"}
}
service mcp:Service /mcp on new mcp:StreamableHttpListener(9092) {

    @mcp:Tool {description: "Adds two numbers"}
    remote function add(int a, int b) returns int => a + b;
}
```

## Backward Compatibility & Migration

- `mcp:Service` and `mcp:AdvancedService` continue to work unchanged and can be attached to `mcp:StreamableHttpListener`.
- `mcp:Listener` continues to work as a deprecated alias for `mcp:StreamableHttpListener`.
- The `httpConfig` and `sessionMode` fields of `@mcp:ServiceConfig` continue to be honored at runtime, but are deprecated; new services should use `@mcp:StreamableHttpServiceConfig`.
- Accessing HTTP headers or the request from a tool requires migrating that service from `mcp:Service` to `mcp:StreamableHttpService` (or to the advanced equivalent). This is an explicit, compiler-guided migration.

## Future Plans

- **Additional transports.** The transport-agnostic/transport-specific split is designed so that a stdio transport can be added as `mcp:StdioListener` with `mcp:StdioService`/`mcp:StdioAdvancedService`, reusing the transport-agnostic `mcp:Service`/`mcp:AdvancedService` unchanged.
- **Authorization.** Building on request access, per-tool scope/authorization support can be layered on later.
- **`_meta` propagation.** Protocol-level request metadata (`_meta`) can be exposed to tools through the transport-agnostic types, complementing the transport-specific request access defined here.

## Conclusion

By keeping `mcp:Service` transport-agnostic and introducing transport-specific service types and listener, this proposal lets MCP tools access transport-specific request information, enabling OAuth and other header-driven use cases - without coupling the core service abstraction to a single transport. The design is enforced by the type system and the compiler, preserves backward compatibility, and leaves a clean path for future transports.
