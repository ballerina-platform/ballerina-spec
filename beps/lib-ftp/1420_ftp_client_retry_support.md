# Automatic Retry Support for FTP Client

- Authors: @niveathika
- Reviewed by:
- Created: 2026-01-28
- Updated: 2026-01-28
- Issue: [1420](https://github.com/ballerina-platform/ballerina-spec/issues/1420)
- State: Draft

## Summary

Add automatic retry support with exponential backoff for FTP client and listener operations to handle transient network failures gracefully.

## Motivation

FTP/SFTP connections are prone to transient failures due to network instability, server-side connection limits, and temporary unavailability. Currently, users must implement custom retry logic, leading to boilerplate code and inconsistent implementations. This proposal adds built-in retry support with exponential backoff to handle these failures automatically.

## Goals

- Provide automatic retry for transient failures in FTP/SFTP operations
- Support exponential backoff to avoid overwhelming servers
- Keep the implementation simple and predictable
- Support both client read operations and listener fetch content operations

## Non-Goals

- Retry support for streaming operations (`getBytesAsStream`, `putBytesAsStream`, `getCsvAsStream`, `putCsvAsStream`)
- Retry support for client write operations (`putBytes`, `putText`, `putJson`, `putXml`, `putCsv`)
- Retry support for deprecated APIs (`get`, `put`, `append`)
- Circuit breaker pattern (may be considered in future)

## Design

### Retry Configuration

A new `RetryConfig` record is added to `ClientConfiguration`:

```ballerina
# Configuration for retry behavior on transient failures.
#
# + count - Maximum number of retry attempts (default: 3)
# + interval - Initial wait time in seconds between retries (default: 1.0)
# + backOffFactor - Multiplier for exponential backoff (default: 2.0)
# + maxWaitInterval - Maximum wait time cap in seconds (default: 30.0)
public type RetryConfig record {|
    int count = 3;
    decimal interval = 1.0;
    float backOffFactor = 2.0;
    decimal maxWaitInterval = 30.0;
|};
```

### Usage Example

```ballerina
ftp:Client ftpClient = check new ({
    host: "ftp.example.com",
    auth: {
        credentials: {username: "user", password: "pass"}
    },
    retryConfig: {
        count: 3,
        interval: 1.0,
        backOffFactor: 2.0,
        maxWaitInterval: 30.0
    }
});

// Automatically retries on transient failures
byte[] content = check ftpClient->getBytes("/path/to/file.txt");
```

### Supported Operations

#### Client Operations

| Operation | Retry Support | 
|-----------|---------------|
| `getBytes` | Yes |
| `getText` | Yes |
| `getJson` | Yes |
| `getXml` | Yes |
| `getCsv` | Yes |

#### Listener Operations

| Operation | Retry Support |
|-----------|---------------|
| `onFile` | Yes |
| `getText` | Yes |
| `getJson` | Yes |
| `getXml` | Yes |
| `getCsv` | Yes |

### Unsupported Operations

| Operation | Reason |
|-----------|--------|
| Client `putBytes`, `putText`, `putJson`, `putXml`, `putCsv` | Not idempotent in failure scenarios |
| Streaming operations (`*AsStream`) | Stream state cannot be restored; input streams cannot be replayed |
| `put`, `append` (deprecated) | Deprecated APIs |
| Directory/file operations | Quick atomic operations; failures indicate real problems, not transient issues |
| Metadata operations | Quick operations; failures indicate real problems |

### Retry Behavior

1. **On failure**: Wait for `interval` seconds, then retry
2. **Exponential backoff**: Each retry multiplies wait time by `backOffFactor`
3. **Cap**: Wait time never exceeds `maxWaitInterval`
4. **Reconnection**: Reconnects to the server before each retry
5. **Final failure**: After exhausting retries, returns error with cause

Example with defaults (count=3, interval=1s, backOffFactor=2.0):
```
Attempt 1 → FAIL → Wait 1s → Reconnect
Attempt 2 → FAIL → Wait 2s → Reconnect
Attempt 3 → FAIL → Wait 4s → Reconnect
Attempt 4 → FAIL → Return error
```

## Alternatives

Alternative designs considered:

1. **Per-operation retry configuration**: Allow retry config per method call rather than at client level. Rejected due to complexity and API clutter.

2. **Support for streaming operations**: Would require buffering or server-side resume capability. Rejected because it defeats the purpose of streaming and adds significant complexity.

3. **Retry for write operations**: Could be supported for idempotent writes, but rejected because failure scenarios (partial writes) make it non-idempotent and risky.

4. **Circuit breaker pattern**: Would prevent cascading failures but adds complexity. Deferred to future work.

## Testing

Test scenarios will include:

1. **Transient failure simulation**: Mock FTP server that fails N times before succeeding
2. **Exponential backoff verification**: Verify wait intervals follow exponential pattern with cap
3. **Reconnection behavior**: Verify client reconnects before each retry
4. **Exhausted retries**: Verify error returned after max retries
5. **Mixed scenarios**: Combination of successful and failed operations
6. **Configuration validation**: Test with various retry config values
7. **Listener fetch operations**: Verify retry behavior for listener content fetch methods

## Risks and Assumptions

**Risks:**
- Retry delays may not be suitable for all use cases (user can disable by setting count=0)
- Reconnection overhead may impact performance in high-frequency scenarios
- Not idempotent write operations could cause data corruption if retried

**Assumptions:**
- Transient failures are temporary and will resolve within retry window
- Server can handle reconnection requests
- Users understand which operations are retryable

## Dependencies

None. This is a self-contained feature within the FTP module.

## Future Work

- Circuit breaker pattern for sustained failures
- Retry policy customization (which errors to retry)
- Metrics/observability for retry attempts
- Streaming operation retry with resume support

## References

- [Ballerina FTP Module](https://github.com/ballerina-platform/module-ballerina-ftp)
- [Exponential Backoff Pattern](https://en.wikipedia.org/wiki/Exponential_backoff)
