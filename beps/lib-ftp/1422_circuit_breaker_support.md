# 1422: Circuit Breaker Support for FTP Client

- Authors: @niveathika
- Reviewed by:
- Created: 2026-01-28
- Updated: 2026-01-28
- Issue: [#1422](https://github.com/ballerina-platform/ballerina-spec/issues/1422)
- State: Draft

## Summary

Add circuit breaker support to the FTP client to prevent cascade failures by temporarily blocking requests when the FTP server is experiencing issues.

## Motivation

FTP/SFTP connections can experience prolonged outages due to server failures, network partitions, or infrastructure issues. Without a circuit breaker:

1. **Resource exhaustion**: Clients keep attempting connections to an unavailable server, wasting resources (strands, connections)
2. **Cascade failures**: Slow/failing FTP operations cause upstream timeouts and failures
3. **Delayed recovery**: No mechanism to gradually test if the server has recovered

The circuit breaker pattern addresses these by:
- Failing fast when the server is known to be unavailable
- Preventing resource exhaustion during outages
- Allowing controlled recovery through half-open state

## Goals

- Provide automatic circuit breaker protection for all FTP client operations
- Support configurable failure thresholds and recovery times
- Allow users to specify which error categories should trip the circuit
- Integrate seamlessly with the existing retry mechanism (retry counted as single request)
- Maintain per-client circuit breaker state

## Non-Goals

- Per-host shared circuit breaker state (each client has independent state)
- Manual circuit control APIs (forceOpen/forceClose)
- Circuit breaker for listener operations (only client-side)
- Custom failure predicates beyond the provided error categories
- Inter-process circuit breaking (state is local to the ballerina client)

---

## Design

### State Machine

```
┌─────────────────────────────────────────────────────────────────────────┐
│                                                                         │
│   CLOSED ──────(failure threshold exceeded)──────► OPEN                 │
│      ▲                                                │                 │
│      │                                           (reset time)           │
│      │                                                ▼                 │
│      └─────────(trial request succeeds)───────── HALF_OPEN              │
│                                                       │                 │
│                (trial request fails)──────────────────►                 │
│                (returns to OPEN state)                                  │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘
```

| State | Description | Behavior |
|-------|-------------|----------|
| **CLOSED** | Normal operation | All requests pass through; failures are tracked |
| **OPEN** | Circuit tripped | All requests fail immediately with `FtpServiceUnavailableError` |
| **HALF_OPEN** | Recovery testing | Allows one trial request to test if server has recovered |

### State Transitions

1. **CLOSED → OPEN**: When failure ratio exceeds `failureThreshold` within the rolling window (and `requestVolumeThreshold` is met)
2. **OPEN → HALF_OPEN**: After `resetTime` has elapsed since the circuit opened
3. **HALF_OPEN → CLOSED**: When the trial request succeeds
4. **HALF_OPEN → OPEN**: When the trial request fails

### Concurrency Safety

The circuit breaker state is concurrency-safe and can be shared across multiple concurrent strands using the same client.
- All state updates (failure counts, state transitions) are safe for concurrent access.
- The rolling window buckets are updated using appropriate isolation or locking mechanisms.
- Blocking in `OPEN` state is non-blocking for the strand (immediate error return).

---

### Configuration Types

#### FailureCategory Enum

```ballerina
# Categories of errors that can trip the circuit breaker.
public enum FailureCategory {
    # Connection-level failures (timeout, refused, reset, DNS resolution)
    CONNECTION_ERROR,
    # Authentication failures (invalid credentials, key rejected)
    AUTHENTICATION_ERROR,
    # Server disconnected unexpectedly during operation
    TRANSIENT_ERROR,
    # All errors regardless of type (includes any error not covered by other categories)
    ALL_ERRORS
}
```

#### RollingWindow Record

```ballerina
# Configuration for the sliding time window used in failure calculation.
public type RollingWindow record {|
    # Minimum number of requests in the window before evaluating failure threshold
    int requestVolumeThreshold = 10;
    # Time period in seconds for the sliding window
    decimal timeWindow = 60;
    # Granularity of time buckets in seconds
    decimal bucketSize = 10;
|};
```

#### CircuitBreakerConfig Record

```ballerina
# Configuration for circuit breaker behavior.
public type CircuitBreakerConfig record {|
    # Time window configuration for failure tracking
    RollingWindow rollingWindow = {};
    # Failure ratio threshold (0.0 to 1.0) that trips the circuit
    float failureThreshold = 0.5;
    # Seconds to wait in OPEN state before transitioning to HALF_OPEN
    decimal resetTime = 30;
    # Error categories that count as failures for the circuit breaker
    FailureCategory[] failureCategories = [CONNECTION_ERROR, TRANSIENT_ERROR];
|};
```


#### Extended ClientConfiguration

```ballerina
public type ClientConfiguration record {|
    Protocol protocol = FTP;
    string host = "127.0.0.1";
    int port = 21;
    AuthConfiguration auth?;
    boolean userDirIsRoot = false;
    boolean laxDataBinding = false;
    decimal connectTimeout = 30.0;
    SocketConfig socketConfig?;
    ProxyConfiguration proxy?;
    FileTransferMode fileTransferMode = BINARY;
    TransferCompression[] sftpCompression = [NO];
    string sftpSshKnownHosts?;
    FailSafeOptions csvFailSafe?;

    // Resiliency configuration
    RetryConfig? retryConfig = ();
    CircuitBreakerConfig? circuitBreaker = ();
|};
```

---

### Error Type

```ballerina
# Error returned when the circuit breaker is in OPEN state.
# This indicates the FTP server is unavailable and requests are being blocked
# to prevent cascade failures. The client should implement fallback logic
# or wait for the circuit to transition to HALF_OPEN state.
public type CircuitBreakerOpenError distinct ServiceUnavailableError;
```

---

### Error Category Mapping

The circuit breaker categorizes errors from the underlying library:

|  Condition | FailureCategory |
|---------------------------|-----------------|
| Connection Failure | CONNECTION_ERROR |
| Socket Timeout | CONNECTION_ERROR |
| Unknown Host | CONNECTION_ERROR |
| No Route To Host | CONNECTION_ERROR |
| Connection refused | CONNECTION_ERROR |
| Authentication Error | AUTHENTICATION_ERROR |
| Invalid credentials | AUTHENTICATION_ERROR |
| SSH key rejected | AUTHENTICATION_ERROR |
| SSH Error (auth-related) | AUTHENTICATION_ERROR |
| Connection reset during transfer | TRANSIENT_ERROR |
| Unexpected EOF | TRANSIENT_ERROR |
| Server closed connection | TRANSIENT_ERROR |
| All other errors | Maps to ALL_ERRORS only |

**Logic**: An error trips the circuit if its category is in the configured `failureCategories` list, OR if `ALL_ERRORS` is in the list.

---

### Sliding Window Implementation

The rolling window divides time into discrete buckets for efficient tracking:

```
timeWindow = 60 seconds
bucketSize = 10 seconds
noOfBuckets = 60 / 10 = 6 buckets

Timeline:
├────────┼────────┼────────┼────────┼────────┼────────┤
│ Bucket │ Bucket │ Bucket │ Bucket │ Bucket │ Bucket │
│   0    │   1    │   2    │   3    │   4    │   5    │
├────────┼────────┼────────┼────────┼────────┼────────┤
0s      10s      20s      30s      40s      50s      60s
```

Each bucket tracks:
- `totalCount`: Total requests in this time segment
- `failureCount`: Failed requests in this time segment
- `lastUpdatedTime`: Timestamp of last update

**Failure Ratio Calculation**:
```
failureRatio = sum(bucket.failureCount) / sum(bucket.totalCount)
```

**Bucket Rotation**: Stale buckets (older than `timeWindow`) are reset when accessed.

---

### Integration with Retry

The circuit breaker wraps the retry mechanism:

```
┌─────────────────────────────────────────────────────────┐
│ Client->getBytes(path)                        │
└─────────────────────────────────────────────────────────┘
                          ↓
┌─────────────────────────────────────────────────────────┐
│ CircuitBreakerClient.execute()                          │
│   - Check circuit state                                 │
│   - If OPEN → return ServiceUnavailableError         │
│   - If CLOSED/HALF_OPEN → proceed                       │
└─────────────────────────────────────────────────────────┘
                          ↓
┌─────────────────────────────────────────────────────────┐
│ RetryClient.execute()                            │
│   - Attempt operation                                   │
│   - On failure: wait, reconnect, retry                  │
│   - Repeat until success or max retries                 │
└─────────────────────────────────────────────────────────┘
                          ↓
┌─────────────────────────────────────────────────────────┐
│ Client->send()                         │
│   - Execute actual FTP operation                        │
└─────────────────────────────────────────────────────────┘
                          ↓
            Result bubbles up to CircuitBreaker
                          ↓
┌─────────────────────────────────────────────────────────┐
│ CircuitBreaker records result                     │
│   - Success → recordSuccess()                           │
│   - Failure → recordFailure() if category matches       │
└─────────────────────────────────────────────────────────┘
```

**Key Points**:
- All retry attempts count as ONE request for circuit breaker
- Circuit breaker sees the final result after all retries are exhausted
- If circuit is OPEN, no retry is attempted (fail fast)

---

### Protected Operations

Circuit breaker applies to **all** client operations:

### Usage Examples

#### Basic Configuration

```ballerina
import ballerina/ftp;

ftp:Client ftpClient = check new ({
    protocol: ftp:SFTP,
    host: "sftp.example.com",
    port: 22,
    auth: {
        credentials: {
            username: "user",
            privateKey: {
                path: "/path/to/key"
            }
        }
    },
    circuitBreaker: {
        rollingWindow: {
            timeWindow: 60,
            bucketSize: 10,
            requestVolumeThreshold: 10
        },
        failureThreshold: 0.5,
        resetTime: 30,
        failureCategories: [ftp:CONNECTION_ERROR, ftp:TRANSIENT_ERROR]
    }
});
```

#### Handling Circuit Open

```ballerina
byte[]|ftp:Error result = ftpClient->getBytes("/files/data.txt");

if result is ftp:ServiceUnavailableError {
    // Circuit is open - use fallback
    log:printWarn("FTP server unavailable, using cached data");
    return getCachedData();
} else if result is ftp:Error {
    // Other FTP error
    return error("Failed to fetch file", result);
}

// Success
return result;
```

#### Combined with Retry

```ballerina
ftp:Client ftpClient = check new ({
    host: "ftp.example.com",
    auth: {credentials: {username: "user", password: "pass"}},

    // Retry handles transient failures (3 attempts with backoff)
    retryConfig: {
        count: 3,
        interval: 1.0,
        backOffFactor: 2.0,
        maxWaitInterval: 30.0
    },

    // Circuit breaker handles prolonged outages
    circuitBreaker: {
        rollingWindow: {
            timeWindow: 60,
            bucketSize: 10,
            requestVolumeThreshold: 10
        },
        failureThreshold: 0.5,
        resetTime: 60
    }
});

// Flow:
// 1. Check circuit state
// 2. If OPEN → fail immediately with FtpServiceUnavailableError
// 3. If CLOSED/HALF_OPEN → try operation with retry
// 4. After all retries, final result updates circuit health
```

#### Sensitive to Authentication Failures

```ballerina
// Trip circuit on auth failures (e.g., when credentials are revoked)
ftp:Client ftpClient = check new ({
    host: "ftp.example.com",
    auth: {credentials: {username: "user", password: "pass"}},
    circuitBreaker: {
        failureThreshold: 0.3,
        resetTime: 120,
        failureCategories: [
            ftp:CONNECTION_ERROR,
            ftp:TRANSIENT_ERROR,
            ftp:AUTHENTICATION_ERROR
        ]
    }
});
```

#### Catch All Errors

```ballerina
// Trip circuit on any error
ftp:Client ftpClient = check new ({
    host: "ftp.example.com",
    auth: {credentials: {username: "user", password: "pass"}},
    circuitBreaker: {
        failureThreshold: 0.5,
        resetTime: 30,
        failureCategories: [ftp:ALL_ERRORS]
    }
});
```

---

### Configuration Tuning Guide

#### High-Traffic Server

```ballerina
circuitBreaker: {
    rollingWindow: {
        timeWindow: 60,
        bucketSize: 10,
        requestVolumeThreshold: 50  // Higher threshold for statistical significance
    },
    failureThreshold: 0.3,          // 30% - more sensitive
    resetTime: 30                    // Quick recovery attempts
}
```

#### Low-Traffic Server

```ballerina
circuitBreaker: {
    rollingWindow: {
        timeWindow: 300,            // 5-minute window to accumulate samples
        bucketSize: 30,
        requestVolumeThreshold: 5   // Lower threshold
    },
    failureThreshold: 0.5,          // 50% - more tolerant
    resetTime: 120                   // Longer recovery period
}
```

#### Critical Operations

```ballerina
circuitBreaker: {
    rollingWindow: {
        timeWindow: 30,
        bucketSize: 5,
        requestVolumeThreshold: 3   // Trip quickly
    },
    failureThreshold: 0.2,          // Very sensitive - 20%
    resetTime: 60
}
```

## Risks and Assumptions

**Risks:**
- Misconfigured thresholds may cause premature circuit trips or delayed detection
- Per-client state means multiple clients to the same server don't share health information
- Error categorization heuristics may misclassify some errors

**Assumptions:**
- Server failures are detectable through error patterns
- Recovery is possible after reset time
- Users understand failure category semantics

---

## Future Work

- Per-host shared circuit breaker state (opt-in)
- Metrics/observability for circuit state and failure rates
- Custom failure predicates for advanced use cases
- Circuit breaker for listener operations

---

## References

- [Ballerina HTTP Circuit Breaker Spec](https://ballerina.io/spec/http/)
- [Circuit Breaker Pattern (Martin Fowler)](https://martinfowler.com/bliki/CircuitBreaker.html)
- [Resilience4j Circuit Breaker](https://resilience4j.readme.io/docs/circuitbreaker)
