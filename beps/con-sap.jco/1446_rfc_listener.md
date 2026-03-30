# RFC Server Support and Listener Redesign

- Authors - @TharmiganK
- Reviewed by - @daneshk @niveathika
- Created date - 2026-03-30
- Updated date - 2026-03-30
- Issue - [#1446](https://github.com/ballerina-platform/ballerina-spec/issues/1446)
- State - Draft

## Summary

Extend the existing SAP JCo `Listener` to support RFC server mode — enabling SAP to call registered function modules on the Ballerina side. The redesign introduces distinct `IDocService` and `RfcService` types, fixes several existing limitations in the listener configuration, and corrects the error-handling gap in `BallerinaThrowableListener`.

## Motivation

The connector is today asymmetric: Ballerina can call SAP via `Client.execute()`, but SAP cannot call Ballerina via RFC. This rules out a large class of SAP integration patterns where SAP initiates the communication:

- **Event-driven workflows:** SAP triggers Ballerina on business events (order creation, goods receipt, goods issue).
- **Real-time data enrichment:** SAP calls an external RFC to check pricing, credit limits, or inventory during a transaction.
- **Push-based data transfer:** SAP pushes data to Ballerina via tRFC/qRFC as a structured, transactional alternative to IDocs.

Without RFC listener support these scenarios require polling, middleware, or HTTP workarounds — none of which give the transactional guarantees or native SAP connectivity that JCo provides.

Beyond the RFC gap, the current listener has three existing problems:

### Problem 1: `Service` type name is wrong

`service_type.bal` declares a type named `Service`. This is the IDoc service type but the name implies it is the generic service type for everything the connector supports. Adding an `RfcService` type alongside a type still named `Service` creates confusion.

### Problem 2: `ServerConfig` is incomplete for RFC server mode

```ballerina
public type ServerConfig record {|
    string gwhost;   // jco.server.gwhost
    string gwserv;   // jco.server.gwserv
    string progid;   // jco.server.progid
|};
```

For an RFC server, JCo requires `jco.server.repository-destination` — the name of a registered SAP destination used to fetch RFC function module metadata (parameter lists, types). Without it, JCo cannot deserialize incoming RFC calls. The current `ServerConfig` has no field for this, forcing RFC-capable configurations through the opaque `AdvancedConfig` map. `jco.server.connection-count` (number of gateway registrations) is also absent.

### Problem 3: `BallerinaThrowableListener` silently swallows server errors

`Listener.java:attach()` registers a `BallerinaThrowableListener` for server errors and exceptions. Its implementation only logs:

```java
public void serverErrorOccurred(..., Error error) {
    logger.error("Server error occurred: {}", error.getMessage());
}
```

The service's `onError()` method is never called for server-level errors. If the JCo gateway connection drops or the server encounters a fatal error, the Ballerina service has no way to observe or react to it.

## Goals

- Enable SAP to call Ballerina function modules via sRFC, tRFC, and qRFC.
- Introduce clearly named service types: `IDocService` and `RfcService`.
- Fix `ServerConfig` to include RFC-required configuration fields.
- Route server-level errors to the service's `onError()` handler.
- Use a single `Listener` for both service types (no separate listener class needed).

## Non-Goals

- ABAP proxy generation or code generation for specific function modules.
- Inbound IDoc changes (existing IDoc handling is preserved as-is).
- Load balancing across multiple gateway registrations (connection count only).
- qRFC queue management beyond what `BallerinaTidHandler` already provides.

## Design

### Why one Listener, not two

In SAP JCo, `JCoIDocServer` extends `JCoServer`. The existing listener already creates a `JCoIDocServer` instance. This instance is a full `JCoServer` and supports:

- IDoc reception via `setIDocHandlerFactory()` (current use)
- RFC function handling via `setFunctionHandlerFactory()` (new use)

Both handler factories can be set on the same server object simultaneously. A single `Listener` can therefore support attaching one `IDocService` and one `RfcService` at the same time, running on one gateway-registered server. No separate `RfcListener` class is needed.

---

### Ballerina API Changes

#### Prerequisite types (`types.bal`)

`RfcService.onCall()` uses `RfcRecord` and `RfcParameters`, which are introduced by the table parameter support proposal. They are reproduced here for completeness.

```ballerina
# A generic record for RFC parameters and response values.
# All field values must be FieldType-compatible (scalar, structure, or array of records).
public type RfcRecord record {|
    FieldType?...;
|};

# Input parameters for an RFC call, organized by JCo parameter category.
#
# + importParameters - Scalar values and structures sent to SAP (import parameter list).
# + tableParameters  - Named tables sent to SAP as input (table parameter list).
#                      Key = SAP table parameter name; Value = array of row records.
public type RfcParameters record {|
    RfcRecord importParameters?;
    map<RfcRecord[]> tableParameters?;
    // changingParameters will be added in a future update
|};
```

These types appear in `types.bal`. This proposal does not re-introduce them — it depends on them already being present from the table parameter support change.

---

#### 1. Rename `Service` → `IDocService` (breaking)

`service_type.bal` currently exports a type named `Service`. This is renamed to `IDocService` to make the protocol explicit and to free the `Service` name for other potential use. The method signatures are unchanged.

```ballerina
# Service type for receiving IDocs pushed from an SAP system.
public type IDocService distinct service object {
    # Invoked when an IDoc document list is received.
    # + iDoc - The full IDoc payload as XML.
    # + return - An error if processing fails.
    remote function onReceive(xml iDoc) returns error?;

    # Invoked when a server-level error occurs.
    # + 'error - The error.
    # + return - An error if error handling fails.
    remote function onError(Error 'error) returns error?;
};
```

#### 2. New `RfcService` type

```ballerina
# Service type for handling inbound RFC calls from an SAP system.
# SAP calls the Ballerina service as if it were a registered RFC function module.
public type RfcService distinct service object {
    # Invoked synchronously when SAP calls a function module registered on this server.
    # The return value is serialized and sent back to the SAP caller as the RFC response.
    #
    # + functionName - The name of the RFC function module being called.
    # + parameters   - The import and table parameters sent by the SAP caller.
    # + return       - The response to send back to SAP, or an error.
    #                  Three return formats are supported (mirrors execute() output):
    #                    - RfcRecord: scalar/structure fields → export parameter list;
    #                                 array fields → table parameter list.
    #                    - xml:       RFC XML document; parsed and written field-by-field
    #                                 into the export and table parameter lists.
    #                    - json:      JSON object; scalar values → export parameter list;
    #                                 array values → table parameter list.
    #                  Returning nil sends an empty response (valid for fire-and-forget RFCs).
    #                  Returning Error causes an AbapException to be raised back to the SAP caller.
    remote function onCall(string functionName, RfcParameters parameters) returns RfcRecord|xml|json|Error?;

    # Invoked when a server-level error or gateway connectivity problem occurs.
    # + 'error - The error.
    # + return - An error if error handling fails.
    remote function onError(Error 'error) returns error?;
};
```

The `onCall` contract is synchronous from SAP's perspective: JCo blocks the SAP caller until `onCall` returns and the response is written back. For tRFC/qRFC, the JCo TID handler already manages transactional commit/rollback.

**Return type comparison with `execute()`**

The three return formats mirror the output side of the client `execute()`, but in the opposite direction — the developer is now *producing* the response rather than consuming it:

| Return type | Client `execute()` | Server `onCall()` |
|---|---|---|
| `RfcRecord` | JCo → Ballerina record (typed fields) | Ballerina record → JCo (scalar → export list, array → table list) |
| `xml` | JCo parameter list serialized as XML string | XML string parsed; fields written to export/table lists |
| `json` | JCo parameter list serialized as JSON string | JSON object parsed; scalars → export list, arrays → table list |
| `nil` | Empty response / null output | Empty response sent to SAP caller |

`RfcRecord` is the recommended format because field types are explicit and the routing (scalar vs array) is unambiguous. `xml` and `json` are useful when the response is already available in those formats from downstream systems.

#### 3. Updated `ServerConfig` (breaking additions)

```ballerina
# Configuration for the SAP JCo server (gateway registration).
#
# + gwhost                - Gateway host (jco.server.gwhost).
# + gwserv                - Gateway service/port (jco.server.gwserv).
# + progid                - Program ID registered in the SAP gateway (jco.server.progid).
# + repositoryDestination - Name of the SAP destination used to fetch RFC metadata.
#                           Required when attaching an RfcService; optional for IDocService only.
#                           Must match a destination registered via DestinationConfig or AdvancedConfig.
# + connectionCount       - Number of connections to register with the SAP gateway (jco.server.connection-count).
#                           Higher values allow more concurrent inbound calls. Defaults to 2.
public type ServerConfig record {|
    string gwhost;
    string gwserv;
    string progid;
    string repositoryDestination?;
    int connectionCount = 2;
|};
```

#### 4. Updated `Listener.attach()` (breaking)

```ballerina
# Attaches a service to the listener.
# At most one IDocService and one RfcService can be attached to the same listener.
#
# + s    - The service to attach. Must be either an IDocService or an RfcService.
# + name - Optional service name (unused at runtime; present for Ballerina listener contract).
# + return - An error if the service type is already attached or attachment fails.
public isolated function attach(IDocService|RfcService s, string[]|string? name = ()) returns Error?
```

The listener enforces: at most one `IDocService` and at most one `RfcService` at a time (same as the current single-service limit but per service type). Attaching an `RfcService` when `repositoryDestination` was not provided in `ServerConfig` returns an `Error` immediately.

---

### Usage

#### RFC listener (server-initiated calls from SAP)

```ballerina
import ballerinax/sap.jco;

// The DestinationConfig registers the SAP system used for RFC metadata lookup
jco:DestinationConfig destConfig = {
    ashost: "sap-host", sysnr: "00", jcoClient: "100",
    user: "RFC_USER", passwd: "secret", lang: "EN"
};

// ServerConfig — repositoryDestination must match the destination name
jco:ServerConfig serverConfig = {
    gwhost: "sap-gateway", gwserv: "3300", progid: "BALLERINA_RFC",
    repositoryDestination: "SAP_DEST",
    connectionCount: 3
};

listener jco:Listener rfcListener = new (serverConfig);

service jco:RfcService on rfcListener {

    // SAP calls ZBAPI_PRICE_CHECK → Ballerina handles it here
    remote function onCall(string functionName, jco:RfcParameters parameters)
            returns jco:RfcRecord|jco:Error? {
        if functionName == "ZBAPI_PRICE_CHECK" {
            decimal price = check self.calculatePrice(parameters);
            // Scalar fields → export parameter list; arrays → table parameter list
            return {PRICE: price, CURRENCY: "USD"};
        }
        return error jco:Error("Unsupported function: " + functionName);
    }

    remote function onError(jco:Error 'error) returns error? {
        log:printError("RFC server error", 'error = 'error);
    }

    function calculatePrice(jco:RfcParameters params) returns decimal|error {
        // Access import params
        string material = (params.importParameters["MATERIAL"] ?: "").toString();
        // ... business logic ...
        return 99.95d;
    }
}
```

#### IDoc listener (unchanged semantics, updated service type name)

```ballerina
service jco:IDocService on idocListener {
    remote function onReceive(xml iDoc) returns error? {
        // process IDoc XML
    }
    remote function onError(jco:Error 'error) returns error? {
        log:printError("IDoc error", 'error = 'error);
    }
}
```

#### Returning XML or JSON from `onCall`

```ballerina
service jco:RfcService on rfcListener {

    // Return XML — useful when response is assembled from an XML-producing downstream call
    remote function onCall(string functionName, jco:RfcParameters parameters)
            returns jco:RfcRecord|xml|json|jco:Error? {
        if functionName == "ZBAPI_ENRICH" {
            xml enrichedData = check fetchEnrichedDataAsXml(parameters);
            // XML is parsed field-by-field into the export/table parameter lists
            return enrichedData;
        }
        if functionName == "ZBAPI_LOOKUP" {
            // JSON object: scalar values → export list, array values → table list
            json lookupResult = check fetchLookupResultAsJson(parameters);
            return lookupResult;
        }
        // RfcRecord is the default: explicit typed fields, recommended for most cases
        return {STATUS: "OK", RESULT_COUNT: 0};
    }

    remote function onError(jco:Error 'error) returns error? { ... }
}
```

#### Both on the same listener

```ballerina
// One listener supporting both IDoc reception and RFC function calls simultaneously
listener jco:Listener sapListener = new ({
    gwhost: "sap-gw", gwserv: "3300", progid: "BALLERINA_SAP",
    repositoryDestination: "SAP_DEST"
});

service jco:IDocService on sapListener { ... }
service jco:RfcService on sapListener { ... }
```

---

### Migration Guide

#### Rename `Service` → `IDocService`

```ballerina
// Before
service jco:Service on myListener { ... }

// After
service jco:IDocService on myListener { ... }
```

#### `ServerConfig` — new optional fields

Existing `ServerConfig` values (`gwhost`, `gwserv`, `progid`) are unchanged. The new fields default safely: `connectionCount = 2` (same as the JCo default), `repositoryDestination` is optional and only required when attaching an `RfcService`.

#### `attach()` type signature update

If you have code that explicitly passes a `Service` to `attach()`, update the type to `IDocService`. The Listener's `attach()` parameter type changes from `Service` to `IDocService|RfcService`.

## Alternatives

### Alternative 1: Separate `RfcListener` class

Add a completely separate `RfcListener` class alongside the existing `Listener`.

**Rejected.** `JCoIDocServer` already extends `JCoServer` and can handle RFC function calls via `setFunctionHandlerFactory()`. A separate class would duplicate the entire lifecycle management (`init`, `start`, `stop`, `attach`, `detach`) with no functional benefit. One `Listener` handling both service types is cleaner and maps to the actual JCo server architecture.

### Alternative 2: Per-function resource methods in `RfcService`

Instead of a generic `onCall(functionName, parameters)`, use Ballerina resource functions, routing each RFC function name to a distinct resource:

```ballerina
service jco:RfcService on rfcListener {
    resource function get ZBAPI_PRICE_CHECK(jco:RfcParameters params)
        returns jco:RfcRecord|error? { ... }
}
```

**Deferred as future work.** This would require a compiler plugin to validate resource names against an SAP RFC metadata source and is a significant design effort on its own. The generic `onCall` handler covers all use cases without the compiler plugin dependency.

### Alternative 3: Keep `Service` name, add `RfcService`

Keep `Service` as the IDoc service type and add `RfcService` alongside it.

**Rejected.** The name `Service` is ambiguous. With an `RfcService` now existing, `Service` would be understood by new users as the base type for all services. Renaming to `IDocService` is a clean break that makes the code self-documenting.

## Testing

### Unit tests

- `handleRequest()` — `RfcRecord` return: Mock a `JCoFunction` with import and table params; verify `onCall` receives the correct `functionName` and `RfcParameters`; verify scalar fields in the returned `RfcRecord` are written to the export list and array fields to the table list.
- `handleRequest()` — `xml` return: Verify the XML string is parsed and fields are set on the export/table parameter lists correctly.
- `handleRequest()` — `json` return: Verify JSON scalar values go to the export list and JSON arrays go to the table list.
- `handleRequest()` — `Error` return: Verify an `AbapException` with the error message is thrown back toward the SAP caller.
- `handleRequest()` — `nil` return: Verify the export/table lists are left unpopulated and no exception is thrown.
- `BallerinaThrowableListener`: Simulate a server error; verify `onError()` is invoked on the attached service.
- `attach()` validation: Attaching `RfcService` without `repositoryDestination` in config returns `Error`. Attaching a second `RfcService` returns `Error`.
- `attach()` with both service types: Verify `IDocService` and `RfcService` can both be attached to the same listener.

### Integration tests (SAP sandbox)

| Scenario | RFC function | Service type | Verified |
|---|---|---|---|
| sRFC server call | `STFC_CONNECTION` | `RfcService` | SAP receives echo response |
| tRFC delivery | `STFC_WRITE_TO_TCPIC` | `RfcService` | TID confirmed, idempotent |
| IDoc + RFC same listener | Any IDoc + `STFC_CONNECTION` | Both attached | Both trigger respective handlers |
| Server error | Gateway drop | `RfcService` | `onError()` invoked in service |
| Unknown function | Unregistered RFC name | `RfcService` | `onCall()` receives it; returns error to SAP |

### Regression

- Existing IDoc listener tests: Attach an `IDocService` (renamed) to a `Listener` and verify `onReceive()` and `onError()` behaviour is unchanged.
- All existing examples in `examples/` must pass after renaming `Service` → `IDocService`.

## Risks and Assumptions

| Risk | Mitigation |
|---|---|
| `JCoIDocServer.setFunctionHandlerFactory()` may not be exposed on the `JCoIDocServer` interface | It is inherited from `JCoServer` — `JCoIDocServer extends JCoServer`; confirmed available |
| `handleRequest()` must not block indefinitely | `CountDownLatch` with timeout; if Ballerina `onCall()` hangs, the latch times out and an `AbapException` is returned to SAP |
| tRFC/qRFC: SAP may call `onCall()` multiple times for the same TID before confirmation | `BallerinaTidHandler.checkTID()` returns `true` only on the first call for a TID; duplicates are suppressed |
| RFC server needs SAP gateway configuration (SM59) | Documented in the connector setup guide as a prerequisite; not a code concern |
| `repositoryDestination` must be registered as a JCo destination before attaching an `RfcService` | Validation added in `attach()`: look up the destination via `JCoDestinationManager`; return a clear error if not found |

## Dependencies

- **Table parameter support proposal** (prerequisite): The `RfcRecord` and `RfcParameters` types used by `RfcService.onCall()` are introduced in the table parameter support proposal. This proposal must be implemented first, or the two proposals must be implemented together in the same release.
- SAP JCo 3.x (existing dependency): `JCoServer`, `JCoServerFunctionHandlerFactory`, `JCoServerFunctionHandler`, `JCoServerContext` — all part of the standard JCo API.
- No new external library dependencies.

## Future Work

- **Per-function resource routing in `RfcService`:** A compiler plugin could validate resource function names against live SAP RFC metadata and generate typed parameter records at compile time, removing the need for the generic `onCall` dispatch.
- **`onCall` with typed parameter records:** Leverage the `RfcParameters` typedesc pattern from the client `execute()` proposal to deliver strongly typed parameters to each handler.
- **qRFC inbound queue management:** Surface the queue name from the `JCoServerContext` in the `onCall` call so the Ballerina service can implement queue-specific logic.

## References

- SAP JCo 3.x API: `JCoServer`, `JCoIDocServer`, `JCoServerFunctionHandlerFactory`, `JCoServerFunctionHandler`, `JCoServerTIDHandler`
- Existing handler: `BallerinaIDocHandler`, `BallerinaIDocHandlerFactory`, `BallerinaTidHandler`
- Existing listener init: `Listener.java:44–90`
- Error routing gap: `BallerinaThrowableListener.java:33–43`
- Current service type: `service_type.bal:18–30`
