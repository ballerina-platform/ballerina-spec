# 1485: Transactional RFC support (tRFC, qRFC, bgRFC) for the SAP JCo connector

- Authors - @RDPerera
- Reviewed by - TBD
- Created date - 2026/08/19
- Updated date - 2026/08/19
- Issue - [#1485](https://github.com/ballerina-platform/ballerina-spec/issues/1485)
- State - Submitted

## Summary

Add SAP's three transactional RFC protocols to the `ballerinax/sap.jco` connector for function-module calls: **tRFC** (applied exactly once), **qRFC** (exactly once and in order through an inbound queue), and **bgRFC** (one or more calls committed as a single logical unit of work). The proposal also surfaces the transaction ID and unit ID lifecycles, which are what make a retry safe when the caller never learned the outcome of an earlier attempt.

## Motivation

The connector calls function modules with `execute`, a request/response operation, and can already send IDocs over tRFC/qRFC with a transaction ID. Function-module calls themselves have no delivery guarantee.

If the connection drops after SAP has committed but before the response is received, the caller cannot tell whether the call ran. Retrying may post the same business document a second time; not retrying may lose it. The connector offers no way to express "apply this call exactly once".

This is not a theoretical concern for the workloads this connector serves. Posting goods movements, sales orders, or financial documents are exactly the operations where a duplicate is a business error requiring manual reversal, not a transient glitch. The options available to users today are:

- implement de-duplication in ABAP on the SAP side, which requires custom development in the system the integration is supposed to treat as fixed; or
- wrap a plain function call in an IDoc purely to borrow the tRFC guarantee already exposed by `sendIDoc`, which is a heavy detour that forces an IDoc type, partner profile, and inbound processing configuration onto a problem that is just a function call.

Two further gaps follow from the same limitation:

- **Ordering.** There is no way to guarantee that a sequence of calls affecting the same business object is applied in the order it was sent. Two updates to one material can overtake each other.
- **Atomicity.** Several related calls cannot be committed as one unit. A posting and its audit entry can diverge if the second call fails.

SAP solves all three with protocols that JCo already exposes and that the connector does not surface.

## Goals

- Allow a function module to be called with an exactly-once delivery guarantee.
- Allow a sequence of calls to be applied in order for a given business key.
- Allow several calls to be committed as one logical unit of work.
- Keep the identifier that carries the guarantee reachable to the caller, so a retry can reuse it — including after a process crash.
- Reuse the connector's existing parameter model and error hierarchy so the new operations are not a parallel API.

## Non-Goals

- Returning function-module results from a transactional call. These protocols are asynchronous on the SAP side; export and table values are discarded by SAP itself. `execute` remains the operation for request/response.
- Managing the SAP-side inbound queue scheduler. Registering a queue with the QIN scheduler (transaction `SMQR`) is backend configuration; the connector's responsibility ends at placing calls on the queue in order.
- A durable, connector-managed TID store. Persisting an identifier is an application concern; the proposal only ensures the identifier is available early enough for an application to persist it.
- Transactional support for the listener (inbound) direction, which already has its own TID handling.

## Design

### Operations

```ballerina
# tRFC — applied exactly once, tracked by a transaction ID.
isolated remote function sendTRfc(string functionName, RfcParameters parameters = {},
        string? tid = (), boolean autoConfirm = true) returns string|Error;

# qRFC — exactly once and in order, through an SAP inbound queue.
isolated remote function sendQRfc(string functionName, string queueName,
        RfcParameters parameters = {}, string? tid = (), boolean autoConfirm = true)
        returns string|Error;

# bgRFC — one or more calls committed as a single logical unit of work.
isolated remote function sendBgRfcUnit(FunctionCall[] functionCalls,
        BgRfcUnitConfig unitConfig = {}) returns BgRfcUnitInfo|Error;

isolated remote function getBgRfcUnitState(BgRfcUnitInfo unit) returns BgRfcUnitState|Error;
isolated remote function confirmBgRfcUnit(BgRfcUnitInfo unit) returns Error?;

# Transaction ID lifecycle.
isolated remote function createTid() returns string|Error;
isolated remote function confirmTid(string tid) returns Error?;
```

### Types

```ballerina
# A single function invocation inside a bgRFC unit of work.
public type FunctionCall record {|
    string functionName;
    RfcParameters parameters = {};
|};

public enum BgRfcUnitType {
    BGRFC_TYPE_T = "T",
    BGRFC_TYPE_Q = "Q"
}

public enum BgRfcUnitState {
    NOT_FOUND,
    IN_PROCESS,
    COMMITTED,
    CONFIRMED,
    ROLLED_BACK
}

public type BgRfcUnitConfig record {|
    string unitId?;
    string[] queueNames = [];
    boolean 'lock = false;
    boolean unitHistory = false;
    boolean kernelTrace = false;
    boolean commitCheck = false;
    string programName?;
    string transactionCode?;
|};

public type BgRfcUnitInfo record {|
    string unitId;
    BgRfcUnitType unitType;
|};

public type TransactionErrorDetail record {|
    *JCoErrorDetail;
    string tid?;
    string unitId?;
|};

public type TransactionError distinct error<TransactionErrorDetail>;
```

`TransactionError` joins the existing `Error` union.

### qRFC ordering

qRFC preserves the order in which calls reach the queue, not the order in which the application issued them. Two `sendQRfc` calls made concurrently to the same queue therefore have no defined relative order.

Callers that depend on ordering must serialise their sends for a given queue. The connector does not sequence them: doing so would require a per-queue lock across the client and would serialise throughput for every user in order to solve an application-level concern. Callers wanting parallelism should use a distinct queue per business key, which SAP processes independently.

Draining the queue remains a property of the SAP system: entries stay queued until the inbound queue is registered with the QIN scheduler (transaction `SMQR`).

### The identifier is the guarantee

The exactly-once property does not live in the call; it lives in the identifier SAP remembers until the caller confirms it. The API therefore keeps that identifier reachable at every point where a caller might need it, rather than hiding it behind the operation:

- A failure returns a `TransactionError` whose detail carries the `tid` or `unitId` in use, so an in-process retry can reuse it.
- A success returns the identifier, so it can be recorded.
- `createTid` exists for the case the other two cannot cover, discussed below.

### Why `createTid` exists when a TID is created automatically

With `autoConfirm = true` (the default), the connector creates a TID, sends, and confirms. This is sufficient for a fire-and-forget call, and if the send fails the TID is still returned in the error detail for an in-process retry.

It is not sufficient when the *process* fails. If the JVM dies during the send — pod eviction, OOM, power loss — there is no return value and no error value. A TID created inside the call existed only in that stack frame and is gone. On restart the integration cannot tell whether SAP applied the call; allocating a fresh TID and resending produces the duplicate the protocol was meant to prevent.

Durable idempotency therefore requires obtaining the identifier *before* the call:

```ballerina
string tid = check sapClient->createTid();
check persistTid(movementId, tid);          // survives a crash
_ = check sapClient->sendTRfc("Z_POST_GOODS_MOVEMENT", parameters, tid, autoConfirm = false);
check sapClient->confirmTid(tid);
```

`autoConfirm = false` is what makes this work: a confirmed TID is forgotten by SAP, so confirming before the outcome is known would discard the protection. The flow is obtain → persist → send → confirm → forget.

### Identifier validation

A caller-supplied TID is validated by **length only** — exactly 24 characters. SAP stores the TID components as `CHAR` (`ARFCTIDStructure` splits the value positionally, with no hexadecimal decoding), so an application may legitimately derive a TID from its own idempotency key, for example `IDEMPOTENCY-KEY-00123456`. Length is still enforced in both directions: a shorter value is split out of bounds by JCo, and a longer one is silently truncated, which would make SAP record a different identifier than the caller believes it used.

Unit IDs *are* validated as 32 hexadecimal characters. JCo documents that format and `JCo.createUnitIdentifier` enforces it, but `JCo.createFunctionUnit` accepts any length silently, so an invalid ID would otherwise surface only later when the unit is queried.

### Deriving a TID from a business key

A TID must be exactly 24 characters, so an application deriving one from a business key needs a rule for reaching that length. Truncating the key itself is unsafe: two different operations sharing a prefix would map to the same TID, and SAP would silently discard the second as a duplicate. That loses an update, which is a worse outcome than the duplicate the protocol exists to prevent.

The recommended derivation is a cryptographic hash of the canonical business key, hex-encoded in uppercase, truncated to 24 characters:

```ballerina
string tid = crypto:hashSha256(businessKey.toBytes()).toBase16().toUpperAscii().substring(0, 24);
```

This keeps 96 bits of the digest, which makes an accidental collision negligible at any realistic volume, and it is deterministic, so a restarted process derives the same TID from the same key. The business key must be canonicalised first — a fixed field order and encoding — so that the same logical operation always produces the same input.

Applications that have no natural business key should use `createTid` and persist the result, which avoids the derivation question entirely.

### Confirmation failures after a successful send

If the send succeeds but the subsequent confirmation fails, the failure is logged rather than surfaced. The call has already been delivered and SAP will discard the TID record on its own schedule; returning an error would push the caller into re-posting an update that already completed. This is the one place where the API deliberately does not report a failure, and it is reported in the logs so it remains diagnosable.

### bgRFC unit configuration

The unit type is selected by `queueNames` rather than by a separate field: supplying one or more queue names produces a type `Q` unit, and an empty list produces type `T`. An invalid queue name fails the call with a `ParameterError`. JCo accepts uppercase letters, digits, and underscores, and requires the name to start with a letter; lowercase letters, hyphens, slashes, and a leading digit are rejected. Note that JCo's own diagnostic advertises the pattern `[A-Z]([A-Z]|[0-9])*`, which is narrower than what it actually accepts — underscores are permitted despite not appearing in that expression. JCo signals a violation by raising a runtime exception, which the connector converts rather than letting it escape.

JCo does not enforce a length limit; names longer than 24 characters are accepted client-side. SAP's queue name column (`QNAME`) is 24 characters, so a longer name is a backend concern rather than one the connector can detect. A duplicate name is a no-op, because the queue is already assigned to the unit.

`commitCheck` maps to `JCoBackgroundUnitAttributes.setCommitCheckOn` and defaults to `false`, matching the JCo and SAP default. The check asks the SAP system to verify that the function modules in the unit do not issue their own `COMMIT WORK`, which would end the logical unit of work early. It is a diagnostic for badly behaved function modules; it does not itself provide atomicity, which comes from the unit. Enabling it costs an additional check per unit, so it is left off by default and is worth switching on while developing against unfamiliar function modules.

### bgRFC unit lifecycle

`COMMITTED` is the terminal state from the sender's point of view: processing has finished and the unit can be confirmed. `CONFIRMED` occurs only *after* `confirmBgRfcUnit`. Polling for `CONFIRMED` before confirming would never return, so the specification states the order explicitly: commit → poll until `COMMITTED` → confirm.

Supplying a `unitId` derived from a business key makes a repeated submission idempotent, the unit-level analogue of reusing a TID.

### Reuse of existing components

Parameters use the existing `RfcParameters` record and are bound with the existing `ImportParameterProcessor`, so import and table parameters behave exactly as they do for `execute`. `TransactionError` extends the existing `JCoErrorDetail` and joins the existing `Error` union. No existing behaviour changes; the addition is otherwise purely additive.

## Alternatives

**Do nothing.** Users continue to implement ABAP-side de-duplication or route function calls through IDocs. Both push work into the SAP system to compensate for a client-side gap, and the IDoc detour requires configuration unrelated to the actual integration.

**Expose only `sendTRfc` with an automatic TID.** Simpler, but it cannot support crash-safe idempotency, which is the primary reason the protocol exists. It also cannot express ordering or atomicity.

**A `transaction`-style block in Ballerina.** Superficially attractive, but the semantics do not match: these protocols are asynchronous with no rollback of an applied call, and the identifier must outlive the process for retries to work. Modelling them as a language-level transaction would misrepresent the guarantee.

**Return the identifier only through the error detail, without `createTid`.** Sufficient for in-process retries, but not for crash recovery, where no error value survives.

## Testing

Verified against a live SAP ECC system (release 750, kernel 753), with outcomes read back from the SAP database through `RFC_READ_TABLE` rather than inferred from return codes:

- **tRFC exactly-once** — the same payload sent twice under one unconfirmed TID produces exactly one row. Repeated across independent runs.
- **Business-key TID** — a 24-character non-hexadecimal TID is accepted end to end, confirming the length-only rule.
- **Wrong-length TID** — rejected before anything is sent; no row is created.
- **bgRFC atomicity** — the calls of a multi-call type `T` unit land together, in order, in a single unit of work.
- **bgRFC exactly-once** — committing the same explicit unit ID twice executes once.
- **Unit lifecycle** — `COMMITTED` → confirm → `CONFIRMED`; an unknown unit reports `NOT_FOUND`.
- **qRFC ordering** — entries land in `TRFCQIN` in send order with ascending counters.
- **Queue-name handling** — a duplicate queue name is accepted as a no-op, and an invalid one is rejected with a `ParameterError` rather than escaping as an unhandled error. The accepted character set, including underscores, and the absence of a client-side length limit were confirmed against JCo directly.
- **qRFC concurrency** — concurrent sends to one queue confirm that the connector does not impose an order, which is why callers must serialise sends when order matters.
- **Regression** — an A/B harness compiles the same source against the released connector and the proposed change, covering `execute` (records, tables, XML), `sendIDoc`, multiple clients, `close`, and the listener. All checks behave identically on both, confirming the addition is non-breaking.

## Risks and Assumptions

- **Queue draining is a backend property.** qRFC entries stay queued until the inbound queue is registered with the QIN scheduler. Users may read a queued entry as a connector failure; the documentation states the boundary.
- **A confirmed identifier must never be reused.** Reuse silently reintroduces duplicates. The specification and API documentation state this at every relevant operation.
- **Assumption: SAP tolerates a caller-supplied non-hexadecimal TID.** Verified against ECC 750 and consistent with the `CHAR` storage of the TID components, but it is an observed behaviour rather than a documented JCo contract.
- **A persisted identifier is scoped to the SAP system that issued it.** A TID is only meaningful on the destination and client that created it. An application that persists a TID and later resumes against a different SAP system or client would find no record of it there, and the call would execute again. Applications must key their identifier store by destination and client. The connector cannot enforce this, since a persistent identifier store is a Non-Goal.
- **Identifiers derived from business keys should not carry sensitive data.** A caller-supplied TID is transmitted to SAP and stored there, where it is visible in transaction `SM58` and table `ARFCSSTATE`, and it appears in connector logs when a confirmation fails. Applications deriving a TID from an idempotency key should use an opaque or hashed key rather than embedding personal or commercially sensitive values.
- **Users must not treat `autoConfirm = true` as crash-safe.** The default is convenient, not durable. The distinction is stated wherever the option appears.

## Dependencies

- SAP Java Connector (JCo) 3.1, already a dependency of the connector. Uses `JCoFunction.execute(destination, tid[, queueName])`, `JCo.createFunctionUnit`, `JCoBackgroundUnitAttributes`, `JCoUnitIdentifier`, and the `createTID`, `confirmTID`, `getFunctionUnitState`, and `confirmFunctionUnit` operations on `JCoDestination`.
- No dependency on other BEPs.

## Future Work

- Optional connector-managed TID persistence, so applications do not each implement their own store.
- Surfacing bgRFC unit state monitoring for operational tooling.
- Extending transactional semantics to the inbound direction beyond the TID handling the listener already performs.

## References

- [Implementation](https://github.com/ballerina-platform/module-ballerinax-sap.jco/pull/80)
- [Connector documentation](https://github.com/wso2/docs-integrator/pull/628)
- [SAP JCo documentation — transactional RFC and bgRFC](https://support.sap.com/en/product/connectors/jco.html)

[]: # (end)
[]: # Please add any comments to issue [#1485](https://github.com/ballerina-platform/ballerina-spec/issues/1485)
