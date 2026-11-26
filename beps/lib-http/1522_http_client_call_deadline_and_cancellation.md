# HTTP Client Call Deadline and Cancellation

- Authors
  - Thisaru Guruge
- Reviewed by
  - _TBD_
- Created date
  - 2026-11-26
- Updated date
  - 2026-11-26
- Issue
  - [1522](https://github.com/ballerina-platform/ballerina-spec/issues/1522)
- State
  - Submitted

## Summary

The `ballerina/http` client has one response timeout, `timeout`, which is an inactivity timer restarted by every read and write, so nothing bounds how long a call takes as a whole. A request started with `submit` cannot be aborted: cancelling the future unblocks the caller but the exchange continues and the connection returns to the pool. This proposal adds a total call deadline (`ClientConfiguration.callTimeout` and `Client.withDeadline`), an explicit `Client.cancel` for submitted requests, two new error types that are distinct from `IdleTimeoutError`, and documentation of which phase each timeout covers. Expiry or cancellation closes the HTTP/1.1 connection, or resets the HTTP/2 stream, and removes it from the pool.

## Motivation

A caller that depends on a backend with a long and variable processing time needs to say "this call must finish within N seconds" and to release the connection when the answer is no longer wanted. Today neither is possible.

The `timeout` field is documented as the maximum time to wait for a response, but it measures the responsiveness of the remote endpoint. A peer that trickles one byte at a time keeps it from ever firing, and the remote methods take no per-call timeout, so calls with different budgets need separate `http:Client` instances.

`future.cancel()` is a strand operation. It sets the strand's cancelled flag and does not reach the native HTTP code, so the client sends nothing to the peer, reads and discards the late response, and keeps the connection in the pool. Timing out a `wait` on the future has the same effect.

Other HTTP clients treat these as basic features.

| Client | Total deadline | Cancel |
|---|---|---|
| OkHttp | `callTimeout` spans the whole call | `Call.cancel()` closes the socket or resets the stream |
| Go `net/http` | `Client.Timeout` covers the exchange including reading the body | Cancelling the request context closes the HTTP/1 connection |
| gRPC | Deadline per call | Cancellation resets the stream |
| Node `fetch` | `AbortSignal.timeout()` | `AbortController` aborts the request and its body |

## Goals

- A caller can bound the total time of a call, covering connection acquisition, connect, request write and the whole response body, including body bytes read after the `http:Response` is returned.
- The deadline can be set per client and overridden per call, for resource and remote methods, without changing any method signature.
- A submitted request can be aborted explicitly, and the underlying connection or stream is released.
- A deadline expiry and a cancellation are reported with error types distinct from the idle timeout and from each other.
- Retries and redirects share one deadline.
- The documentation states which phase each timeout covers.

## Non-Goals

- A per-call options record or a cancel token passed as an argument. Resource methods have no spare parameter for either.
- Cancelling calls other than submitted requests.
- A deadline for the failover and load balance clients.
- Changing the meaning of `timeout`, `socketConfig.connectTimeOut` or `poolConfig.waitTime`.
- Interrupting a request body producer or the retrieval of an auth token. The time they take counts towards the call.

## Current State Analysis

Verified against `ballerina/http` 2.18.1 (distribution `2201.14.1`), HTTP/1.1 measured and HTTP/2 from source.

- `timeout` is installed as an idle-state handler on the connection when the request starts to be sent (`SendingHeaders`, `Sending100Continue`), configured as an all-idle timer, so read or write activity restarts it. It does not cover pool wait or connect. A slow consumer that suspends reads is excused for a bounded time (`BackPressureAwareIdleStateHandler`).
- `HttpResponseFuture` has no cancel or abort operation, so cancelling the Ballerina future of an in-flight call does not reach the native HTTP code and the exchange continues.
- Closing the Netty channel is already a full abort on HTTP/1.1: `TargetHandler.channelInactive` hands the closure to the sender's state manager, which reports an error for the current state, and invalidates the channel. HTTP/2 keeps a per-stream timer (`Http2ClientTimeoutHandler`) that resets the stream when it expires.
- `poolConfig.waitTime` is the maximum wait of the HTTP/1.1 connection pool. The HTTP/2 channel pool does not use it.

## Design

### 1. Deadline

```ballerina
public type ClientConfiguration record {|
    // existing fields

    # The total time of each call in seconds, covering waiting for a pooled connection, connecting, writing the
    # request and reading the response, including body bytes read after the `http:Response` is returned. Retries and
    # redirects share it. `0` means no limit. `timeout` remains an inactivity timeout.
    decimal callTimeout = 0;
|};

public isolated client class Client {
    # Returns a view of this client with its own call deadline. The view shares the connection pool, cookies and the
    # retry, redirect and circuit breaker state. It covers resource and remote methods.
    #
    # + seconds - The total time of each call in seconds. `0` removes the limit. A negative value is an error
    # + return - The view
    public isolated function withDeadline(decimal seconds) returns Client;
}
```

```ballerina
http:Client orders = check new ("http://erp.example.com", callTimeout = 30);

// A different total time for some calls
Order[] pending = check orders.withDeadline(5)->/orders(status = "pending");
```

The deadline belongs to one invocation. It is passed to the native call and is not stored on the `http:Request`, so two concurrent calls that send the same request object do not affect each other's deadline. A view is created by a private factory from the shared client state, and creating one takes no module-wide lock.

`http:StatusCodeClient` honours `callTimeout` and has no `withDeadline`. A negative argument to `withDeadline` is rejected; if the signature cannot return an error, it panics, and the specification documents that.

### 2. Abort

When the deadline expires or the call is cancelled:

- On HTTP/1.1 the connection is closed and dropped from the pool.
- On HTTP/2 the stream is reset with `CANCEL` and the connection stays in use for other streams.
- The abort is tied to one attempt of one invocation, so a late timer or cancel does not reach a connection that another request has since borrowed, or another submission of the same `http:Request`.
- A connection that is still being established completes in the background and is then closed. It is never pooled.
- The abort does not run listener code on the shared timer thread or while holding a pool lock.
- The expected closure is not logged as an error.

### 3. Cancel

```ballerina
public isolated client class Client {
    # Aborts a request started with `submit`. The call completes with an `http:CallCancelledError`.
    #
    # + httpFuture - The future that `submit` returned
    # + return - An `http:ClientError` if the future is not one that `submit` returned, otherwise nil
    remote isolated function cancel(HttpFuture httpFuture) returns ClientError?;
}
```

`cancel` is a member of `http:Client` and is not added to `http:ClientObject`, so existing implementations of that type are unaffected. With `retryConfig` or `circuitBreaker`, `submit` returns the future only once the response starts, as before, so such a request cannot be cancelled while it waits for the response.

### 4. Errors

```ballerina
# Raised when a call does not complete within its call deadline. Distinct from `http:IdleTimeoutError`.
public type CallTimeoutError distinct ClientError;

# Raised when a call is aborted by `Client.cancel`.
public type CallCancelledError distinct ClientError;
```

The native layer creates these as typed errors. A caller-visible `CallTimeoutError` is never derived from matching message text, so a response body that happens to contain such text cannot produce one.

### 5. Retries, redirects and the circuit breaker

Retries and redirects share the call deadline. When the remaining time is shorter than the next retry interval, the retry client does not sleep: it returns the last real response or error. `CallTimeoutError` is raised only when the deadline expires during an attempt.

A `CallTimeoutError` counts as a circuit breaker failure only when the deadline came from the client's own `callTimeout`. A deadline set through `withDeadline` is the caller's own budget and says nothing about backend health, so it is not counted, because views share the breaker with the client and a short view deadline would otherwise open the circuit for every caller. A `CallCancelledError` is never counted. Only a timeout before the response headers arrive is recorded. A call whose headers have arrived is recorded as a success, and a later body-read timeout does not change that.

### 6. Documentation of timeouts

The specification states that `timeout` is an inactivity timeout and adds a table of what each setting covers.

| Setting | Pool wait | Connect | Request write | Response headers | Response body |
|---|---|---|---|---|---|
| `poolConfig.waitTime` | HTTP/1.1 only | No | No | No | No |
| `socketConfig.connectTimeOut` | No | Yes | No | No | No |
| `timeout` | No | No | Inactivity | Inactivity | Inactivity |
| `callTimeout` / `withDeadline` | Yes | Yes | Yes | Yes | Yes |

The inactivity timer starts when the request begins to be sent and is restarted by read and write activity.

## Alternatives

### Per-call options record

An optional `CallOptions` argument on every remote method. Explicit at the call site, but resource methods cannot take it without reserving a parameter name that would clash with query parameters, and every remote method, `http:ClientObject` and the retry, caching and failover wrappers change. Not chosen.

### Cancel token

A token object carrying both the deadline and the cancel handle. One mechanism for both features, but it has the same signature problem and adds a new concept whose lifecycle and sharing must be specified. Not chosen.

### Adding `cancel` to `http:ClientObject`

Allows polymorphic use but breaks every existing implementation of the object type. Not chosen.

### Counting every timeout in the circuit breaker

Simple, but a view deadline shorter than the backend's normal latency would fail every such call and open the circuit for all callers. Not chosen.

### Per-attempt deadline

Each retry and redirect gets a fresh deadline. The total can reach `(count + 1)` times the deadline, which defeats a bound on the whole call. Not chosen.

### Doing nothing

Callers keep a per-client inactivity timeout, need one client instance per timeout, and cannot release a connection that waits on an unresponsive peer.

## Testing

- HTTP/1.1 and HTTP/2: expiry during pool wait, connect, request write, response headers and body read, each yielding `CallTimeoutError` and releasing the connection or stream.
- Cancel of a submitted request on both protocols, and rejection of a foreign future.
- A late timer or cancel does not affect a connection another request has since borrowed, nor another submission of the same request object.
- Concurrent calls sharing one request object with different deadlines.
- Retry and redirect sharing one deadline, including the remaining-time-shorter-than-interval case.
- Circuit breaker: client `callTimeout` expiry counts, view deadline expiry and cancellation do not, body-read timeout does not.
- A connection still being established at expiry is closed and does not remain counted against `poolConfig.maxActiveConnections`.
- A response body containing the text of a timeout message does not produce `CallTimeoutError`.
- Regression: with `callTimeout = 0` behaviour is unchanged.

## Risks and Assumptions

### Risks

- **Abort timing on a shared timer.** Deadlines for all clients are scheduled on one timer. Expiry hands the abort off to the connection's event loop or a separate executor, so a slow abort cannot delay other deadlines.
- **Pool borrowing under a deadline.** A borrow that finishes at the deadline must hand its connection back exactly once, including when the waiting thread is interrupted. Mitigated by tests for the race.
- **HTTP/2 held request chunks.** An abort while waiting for `100 Continue` must release the held request chunks.

### Assumptions

- **Closing the channel aborts HTTP/1.1 exchanges.** Confirmed against 2.18.1.
- **GraalVM native image compatibility and OpenAPI client generation.** Not yet verified.

## Dependencies

- None on other BEPs.
- Forward dependency: a later proposal for failover and load balance deadlines depends on the semantics defined here.

## Future Work

- A deadline for the failover and load balance clients, including whether the budget is shared across targets or applies per target.
- Returning the future from `submit` before the response starts when `retryConfig` or `circuitBreaker` is configured, so that such requests can be cancelled while waiting.
- Cancelling calls that are not submitted requests.

## References

### Ballerina

- [ballerina-library issue 9438](https://github.com/ballerina-platform/ballerina-library/issues/9438) — the requirement: per-request deadline and an aborting cancel
- [Ballerina HTTP specification](https://github.com/ballerina-platform/module-ballerina-http/blob/master/docs/spec/spec.md)

### Comparable libraries

- [OkHttp `Call`](https://square.github.io/okhttp/5.x/okhttp/okhttp3/-call/index.html) — `cancel()` and `timeout()`
- [Go `net/http` Client](https://pkg.go.dev/net/http#Client) — `Timeout` and request contexts
- [gRPC deadlines](https://grpc.io/docs/guides/deadlines/) — per-call deadlines
- [`AbortSignal.timeout()`](https://developer.mozilla.org/en-US/docs/Web/API/AbortSignal/timeout_static) — abort of a `fetch` request

[]: # (end)
[]: # Please add any comments to issue [#1522]()
