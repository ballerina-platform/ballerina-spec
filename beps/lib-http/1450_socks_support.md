# 1450: Socket-Level (SOCKS) Proxy Support for the HTTP Client

- Authors
  - Thisaru Guruge
- Reviewed by
  - Danesh Kuruppu
  - Tharmigan Krishnananthalingam
- Created date
  - 2026-06-18
- Updated date
  - 2026-06-18
- Issue
  - [1450](https://github.com/ballerina-platform/ballerina-spec/issues/1450)
- State
  - Proposed

## Summary

The Ballerina `http` package currently lets an HTTP client route requests through an **HTTP-level proxy** only. This proposal adds support for **socket-level (SOCKS) proxies** — both **SOCKS4** and **SOCKS5** — to the HTTP client. The capability is exposed by extending the existing `http:ProxyConfig` record with a `protocol` field that selects between `HTTP` (the current behaviour, and the default), `SOCKS4`, and `SOCKS5`. Because the underlying transport already uses Netty — which ships `Socks4ProxyHandler` and `Socks5ProxyHandler` in the same `io.netty.handler.proxy` package as the `HttpProxyHandler` already in use — no new third-party dependency is required.

## Motivation

Enterprise users need their Ballerina HTTP clients to reach external endpoints through a **SOCKS proxy**. In many corporate networks a SOCKS proxy is the standard — and sometimes the only — sanctioned egress path, and infrastructure teams often prefer it over an HTTP proxy.

- **Current state:** The Ballerina HTTP client supports only HTTP protocol-based proxying. This is also a feature-parity gap with sibling integration products that already support SOCKS proxies natively.
- **Benefit:** SOCKS proxying is a transport (TCP) layer mechanism. Unlike an HTTP proxy, it is protocol-agnostic, works uniformly for plaintext and TLS traffic, and (with SOCKS5) can resolve the destination host name on the proxy side — which is essential when the client sits on a locked-down network that cannot resolve external DNS itself. Many enterprise egress setups standardise on SOCKS for exactly these reasons.

## Goals

- Allow an `http:Client` to route requests through a **SOCKS4** or **SOCKS5** proxy.
- Support SOCKS proxying uniformly for:
  - both `http://` (plaintext) and `https://` (TLS) target URLs, and
  - both HTTP/1.1 and HTTP/2.
- Support **username/password authentication** for SOCKS5 and **userId** for SOCKS4.
- Support **proxy-side (remote) DNS resolution** for SOCKS5.
- Keep the existing HTTP-proxy behaviour and API fully **backward compatible** (no change required to existing user code).
- Ship the feature with full test coverage (Java unit, Ballerina unit, Ballerina integration), an example, and updated documentation.

## Non-Goals

- **Fixing or changing the existing HTTP-proxy behaviour.** In particular, the existing HTTP proxy's per-scheme handling (absolute-form request for plaintext, CONNECT tunnel for TLS) is out of scope and left untouched.
- **SOCKS4a.** Only SOCKS4 and SOCKS5 are in scope. SOCKS4a (host-name capable SOCKS4) is explicitly excluded; see _Future Work_.
- **Proxy chaining** (e.g., routing through a SOCKS proxy and then an HTTP proxy). A client uses at most one proxy.
- **SOCKS proxy support for the HTTP listener / server side.** This proposal covers the client only.
- **SOCKS proxy support for other clients that do not build on the HTTP client transport** (e.g., WebSocket) unless they transparently inherit it; not validated here.

## Design

### 1. Public API (Ballerina)

The existing `ProxyConfig` record is extended with a single new field, `protocol`, that selects the proxy protocol. The default is `HTTP`, preserving the current behaviour and full backward compatibility.

A new enum is introduced:

```ballerina
# Defines the protocol used by a proxy server.
public enum ProxyProtocol {
    # HTTP proxy. Uses absolute-form requests for `http://` targets and the
    # `CONNECT` method to tunnel `https://` targets.
    HTTP,
    # SOCKS version 4 proxy. Supports an optional userId; does not support
    # passwords or proxy-side host-name resolution.
    SOCKS4,
    # SOCKS version 5 proxy. Supports username/password authentication and
    # proxy-side (remote) host-name resolution.
    SOCKS5
}
```

The `ProxyConfig` record gains the `protocol` field:

```ballerina
# Proxy server configurations to be used with the HTTP client endpoint.
#
# + host - Host name of the proxy server
# + port - Proxy server port
# + userName - Proxy server username (for SOCKS4 this is sent as the userId)
# + password - Proxy server password (ignored for SOCKS4, which has no password mechanism)
# + protocol - The proxy protocol to use. Defaults to `HTTP`
public type ProxyConfig record {|
    string host = "";
    int port = 0;
    string userName = "";
    string password = "";
    ProxyProtocol protocol = HTTP;
|};
```

The configuration looks as follows:

```ballerina
http:Client targetApi = check new ("http://target-api.com", {
    proxy: {
        host: "your.socks.proxy",
        port: 1080,
        protocol: SOCKS5
    }
});
```

The `proxy` field already lives on `CommonClientConfiguration` (`ballerina/http_types.bal`), which is shared by both HTTP/1.1 and HTTP/2 clients, and is also surfaced on `ClientHttp1Settings` (`ballerina/http_client_config.bal`). Both entry points are preserved; only the record they reference changes. No new top-level field is added — using a single discriminated record makes the contradictory "HTTP proxy and SOCKS proxy at once" state unrepresentable.

#### Validation

A SOCKS4 proxy has no password mechanism. To avoid silently ignoring user intent, configuring a SOCKS4 proxy with a non-empty `password` is rejected with a configuration error at client creation:

> `configuring a password is not supported for a SOCKS4 proxy`

### 2. Configuration plumbing (Ballerina → Java)

The proxy protocol is carried from the Ballerina record into the existing Java configuration object:

- **`HttpConstants`** — add a `PROXY_PROTOCOL` `BString` key (`"protocol"`) and the protocol value constants (`HTTP`, `SOCKS4`, `SOCKS5`).
- **`ProxyServerConfiguration`** (`...transport.contract.config`) — add a protocol field (a `ProxyProtocol` enum, or an equivalent typed field) alongside the existing host/port/username/password. Default `HTTP`.
- **`HttpUtil.populateSenderConfigurations`** — read the `protocol` value from the Ballerina `proxy` map, set it on `ProxyServerConfiguration`, and perform the SOCKS4-password validation described above.
- **`SenderConfiguration`** — already holds the `ProxyServerConfiguration`; no shape change beyond what it transitively carries.

### 3. Transport / Netty pipeline

The current code paths diverge by scheme; SOCKS introduces a third, uniform path. The relevant touch points:

#### 3.1 `HttpClientChannelInitializer.configureProxyServer`

Today this method adds a Netty `HttpProxyHandler` **only when `sslConfig != null`** (HTTPS). It is extended to branch on the configured protocol:

- `HTTP` → unchanged (existing `HttpProxyHandler`, HTTPS path only).
- `SOCKS5` → add `Socks5ProxyHandler` (with username/password when supplied), **regardless of `sslConfig`** (i.e., for both `http://` and `https://`).
- `SOCKS4` → add `Socks4ProxyHandler` (with userId when supplied), regardless of `sslConfig`.

Netty proxy handlers must sit at the **head** of the pipeline (before the SSL handler and the HTTP codec). `configureProxyServer` is already invoked first in `initChannel`, and is invoked on both the HTTP/1.1 and HTTP/2 branches, so SOCKS coverage for HTTP/2 follows naturally. A pipeline handler name (e.g. reuse `Constants.PROXY_HANDLER`) identifies the handler.

#### 3.2 `PoolableTargetChannelFactory.connectToRemoteEndpoint`

Today, for an **HTTP proxy on a plaintext `http://` target**, the socket connects _directly to the proxy_ host:port (and the request is sent in absolute form — see 3.3). For SOCKS, the socket must instead connect to the **destination** (`httpRoute` host:port); the SOCKS handler in the pipeline transparently establishes the tunnel through the proxy. Therefore:

- The existing "connect directly to the proxy" branch is guarded so it applies **only to the `HTTP` protocol**, not to SOCKS.
- For **SOCKS5**, the connect address is created with `InetSocketAddress.createUnresolved(host, port)` and the client `Bootstrap` resolver is set to `NoopAddressResolverGroup.INSTANCE` **only when a SOCKS5 proxy is configured**, so Netty defers host-name resolution to the proxy (remote DNS). For non-proxy and HTTP-proxy paths the resolver behaviour is unchanged.
- For **SOCKS4**, the destination is resolved client-side as today (the SOCKS4 protocol cannot carry a host name); a resolution failure surfaces as a client error.

#### 3.3 `DefaultHttpClientConnector` / `Util.getRequestPath`

The absolute-form request-URI rewriting (gated by `Constants.IS_PROXY_ENABLED` and `scheme == http`) is **HTTP-proxy specific**. For SOCKS, requests use origin-form exactly as a direct connection would. Accordingly, `IS_PROXY_ENABLED` is **not** set when the configured protocol is SOCKS4/SOCKS5, so `Util.getRequestPath` continues to return the origin-form path.

### 4. Behavioural matrix

| Protocol          | `http://` target               | `https://` target | HTTP/1.1 | HTTP/2 | Auth              | Remote DNS             |
| ----------------- | ------------------------------ | ----------------- | -------- | ------ | ----------------- | ---------------------- |
| `HTTP` (existing) | absolute-form, direct-to-proxy | `CONNECT` tunnel  | ✅       | ✅     | Basic (user/pass) | proxy-side via CONNECT |
| `SOCKS5`          | TCP tunnel                     | TCP tunnel        | ✅       | ✅     | user/pass         | ✅                     |
| `SOCKS4`          | TCP tunnel                     | TCP tunnel        | ✅       | ✅     | userId only       | ❌ (client-side only)  |

## Alternatives

- **Separate `SocksProxyConfig` record in a new `socksProxy` field.** Rejected: a client uses at most one proxy, so two independent fields create a contradictory, un-meaningful "both set" state that would need runtime validation, and it diverges from the natural extension of reusing the existing `proxy` field.
- **Separate `SocksProxyConfig` record unioned onto the existing `proxy` field (`ProxyConfig|SocksProxyConfig`).** Considered. It is type-safe and keeps a single field, but changes the type of an existing public field and relies on union type-inference (requiring `protocol` to be non-defaultable to disambiguate). The chosen single-record approach is simpler, keeps a single intuitive configuration, and is fully backward compatible.
- **Do nothing / require an external SOCKS-to-HTTP bridge.** Rejected: pushes operational burden onto users and leaves a real egress scenario unsupported.

## Testing

- **Java unit tests** (`native/src/test/.../transport/proxyserver/`, TestNG + MockServer): add SOCKS4 and SOCKS5 cases mirroring `HttpProxyServerTestCase` / `HttpsProxyServerTestCase` — over both plaintext and TLS, with and without authentication, asserting the request reaches the backend through the proxy. Add a `ProxyServerConfigurationTest` case for the new protocol field.
- **Ballerina unit tests** (`ballerina-tests/http-misc-tests/`, mirroring `proxy_enabled_client_test.bal`): a SOCKS-enabled client routed through a SOCKS proxy listener to a backend, plus the negative case asserting the SOCKS4-with-password configuration error. New ports added to `test_service_ports.bal`.
- **Ballerina integration tests** (`integration-tests/`): end-to-end client → SOCKS proxy → backend.
- **Test environments:** the SOCKS proxy is stood up in-process using a lightweight **embedded Netty SOCKS server** (Netty's `io.netty.handler.codec.socksx` server-side codecs, already on the classpath). MockServer — which the existing HTTP-proxy tests use — is deliberately **not** used for SOCKS: the pinned MockServer 3.11 has no SOCKS support, and even current MockServer supports SOCKS5 only, not SOCKS4 ([mock-server/mockserver#528](https://github.com/mock-server/mockserver/issues/528)). The existing HTTP/HTTPS proxy tests remain on MockServer, untouched.

## Risks and Assumptions

- **Remote DNS coupling.** Setting `NoopAddressResolverGroup` and an unresolved address must be scoped strictly to the SOCKS5 path so the non-proxy and HTTP-proxy connection paths are unaffected. Mitigated by branching on the configured protocol in `PoolableTargetChannelFactory`.
- **Connection pooling.** Pooled connections are keyed by route (host:port). SOCKS connections target the real destination route (the proxy is a transport detail), so pooling semantics are preserved; existing `ConnectionPoolProxyTestCase`-style coverage is extended for SOCKS.
- **SOCKS4 limitations are protocol-inherent**, not bugs: no password, no remote DNS. These are surfaced via validation (password) and documentation (DNS).
- **Assumption:** Netty `4.1.133.Final` (current pinned version) provides `Socks4ProxyHandler` / `Socks5ProxyHandler` with the constructors used here — confirmed; they reside in `io.netty.handler.proxy`, already a transitive dependency in use.

## Dependencies

- Netty `io.netty.handler.proxy` (already present via the existing HTTP-proxy support; no version bump required).
- No dependency on other BEPs.

## Future Work

- **SOCKS4a** support (host-name capable SOCKS4) if requested.
- Optionally revisiting the existing HTTP-proxy plaintext path for consistency (explicitly out of scope here).
- Extending SOCKS support to other transports built on this client (e.g., WebSocket) if required.

## References

- Ballerina network proxy docs: https://ballerina.io/learn/configure-a-network-proxy/
- Netty proxy handlers: https://netty.io/4.1/api/io/netty/handler/proxy/package-summary.html
- BEP template: https://github.com/ballerina-platform/ballerina-spec/blob/master/beps/AAA-bep-resources/0000_bep_template.md
