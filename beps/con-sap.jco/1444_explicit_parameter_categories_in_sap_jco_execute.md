# Explicit Parameter Categories in SAP JCo `execute()`

- Authors - @TharmiganK
- Reviewed by - @daneshk @niveathika
- Created date - 2026-03-30
- Updated date - 2026-03-30
- Issue - [#1444](https://github.com/ballerina-platform/ballerina-spec/issues/1444)
- State - Draft

## Summary

Redesign the `execute()` method to explicitly model all four SAP RFC parameter categories — **import**, **export**, **table**, and **changing** — rather than merging them into a single flat input/output record. The immediate deliverable adds table parameter support. The design is forward-compatible so that changing parameter support can be added later without any API change.

## Motivation

SAP JCo defines four distinct parameter lists on every `JCoFunction`:

| Category | JCo API                      | Direction                                                                                        |
|----------|------------------------------|--------------------------------------------------------------------------------------------------|
| Import   | `getImportParameterList()`   | Input — scalar values and structures sent to SAP                                                 |
| Export   | `getExportParameterList()`   | Output — scalar values and structures returned by SAP                                            |
| Table    | `getTableParameterList()`    | **Bidirectional** — tabular data, used for both filter criteria (input) and result sets (output) |
| Changing | `getChangingParameterList()` | **Bidirectional** — scalar/structure parameters modified in-place by the RFC                     |

The current `execute()` signature conflates these categories:

```ballerina
isolated remote function execute(
    string functionName,
    record {|FieldType?...;|} importParams,   // flat — category unknown
    typedesc<record {|FieldType?...;|}|xml|json?> exportParams = <>
) returns exportParams|Error
```

This design has two concrete problems today and one structural problem for the future:

1. **Table parameters are silently dropped on output.** `Client.java` only calls `function.getExportParameterList()` — `function.getTableParameterList()` is never read after execution. Any tabular data returned by the RFC (e.g., `DATA` from `RFC_READ_TABLE`, `MATNRLIST` from `BAPI_MATERIAL_GETLIST`) is discarded.

2. **Table parameters fail at runtime on input.** `ImportParameterProcessor` routes array-typed fields to `importParamList.getTable(key)`. Top-level table parameters live in the *table* parameter list, not the import list. Calling `getTable()` on the wrong list throws a `JCoException`. Any RFC that takes table inputs (e.g., `OPTIONS`/`FIELDS` in `RFC_READ_TABLE`) fails at runtime.

3. **The flat design cannot scale.** When changing parameter support is eventually added, there is no unambiguous way to distinguish changing parameters from import parameters in a flat input record — both are non-array record fields. Any attempt to add changing parameters without a redesign would require heuristics or new parallel API methods, which is worse.

These problems matter because most real-world SAP BAPIs return data as table parameters. RFCs with only scalar export params are typically limited to status/return codes. Covering `RFC_READ_TABLE`, `BAPI_SALESORDER_GETLIST`, `BAPI_MATERIAL_GETLIST`, and others in the MM, SD, FI, PP, and HR modules requires table parameter support.

## Goals

- Support sending table parameters as input to `execute()`.
- Support receiving table parameters in the output of `execute()`.
- Produce a correct and forward-compatible public API that can absorb changing parameter support later with no breaking change.
- Keep full parity with the existing export-parameter behavior.

## Non-Goals

- Changing parameter support (bidirectional scalar/structure). This is explicitly designed for but not implemented in this proposal.
- Changes to `sendIDoc()` or the `Listener`.
- Async RFC / queued RFC (`qRFC`/`tRFC`) support.

## Design

### Vendor Landscape

A survey of how major iPaaS and low-code vendors handle RFC parameter categories informs the design:

| Vendor               | Input structure                                                            | Output structure                                     | Category separation       |
|----------------------|----------------------------------------------------------------------------|------------------------------------------------------|---------------------------|
| **MuleSoft**         | XML with explicit `<import>`, `<changing>`, `<tables>` child elements      | Same structure; sections populated by SAP            | Yes — named XML wrappers  |
| **Boomi**            | JSON with `importParameters`, `tableParameters`, `changingParameters` keys | JSON with `exportParameters`, `tableParameters` keys | Yes — named JSON keys     |
| **WSO2 EI**          | XML `<import>` and `<tables>` sections                                     | XML `<export>` and `<tables>` sections               | Yes — named XML wrappers  |
| **SAP CPI**          | Flat — all categories as siblings under the function root element          | Flat `<FunctionName.Response>`                       | No — schema-enforced      |
| **Azure Logic Apps** | Flat — all categories as sibling XML elements                              | Flat `<FunctionNameResponse>` element                | No — schema-enforced      |
| **TIBCO BW**         | XSD-generated flat schema                                                  | Same generated schema                                | No — type-system enforced |

The flat-schema approach (SAP CPI, Azure, TIBCO) works because those systems generate an XSD at design time that encodes which fields belong to which category. Without a code-gen step, the flat approach is opaque and error-prone for the programmer.

The explicit section-based approach (MuleSoft, Boomi, WSO2) is the correct pattern for a programmatic connector: the developer must know upfront which category a parameter belongs to, and the API makes that structure unambiguous. Boomi's JSON representation maps most naturally to Ballerina.

The key asymmetry across all vendors: **input is always categorized** (because different categories go to different JCo parameter lists) while **output is always flat** (because the caller only cares about the data, not which JCo list it came from). This proposal follows the same convention.

---

### API Changes

#### New public types (`types.bal`)

```ballerina
# A generic record used for RFC parameters — scalar, structure, or table row values.
# This is a named alias for the rest-field record pattern already used throughout the connector.
public type RfcRecord record {|
    FieldType?...;
|};

# Wraps all input parameters for an RFC call with explicit per-category sections.
#
# + importParameters - Scalar values and structures sent to SAP (import parameter list).
# + tableParameters  - Named tables sent to SAP as filter criteria or input data (table parameter list).
#                      Key = SAP table parameter name; Value = array of row records.
public type RfcParameters record {|
    RfcRecord importParameters?;
    map<RfcRecord[]> tableParameters?;
    // changingParameters will be added here in a future update — no API change required.
    // RfcRecord changingParameters?;
|};
```

`RfcRecord` replaces the anonymous `record {|FieldType?...;|}` pattern across the public API, making documentation and type references cleaner without any semantic change.

`map<RfcRecord[]>` for `tableParameters` is the most readable representation of a named mapping from SAP table parameter names to rows. It is equivalent to Ballerina's `record {|RfcRecord[]...;|}` but more idiomatic as a top-level type declaration.

#### Updated `execute()` signature (`client.bal`)

```ballerina
# Executes an RFC/BAPI function on the SAP system.
#
# + functionName - The name of the RFC/BAPI function module to call.
# + parameters   - Input parameters organized by category. Import parameters are scalar/structure
#                  values; table parameters are named tables containing rows of data.
#                  Defaults to an empty parameter set (valid for parameter-free RFCs).
# + returnType   - Typedesc for the expected response. The response record is populated from
#                  both the SAP export parameter list and the table parameter list. Fields are
#                  matched by name; unknown fields are skipped unless the record type allows
#                  rest fields.
# + return       - The RFC response cast to returnType, or an Error.
isolated remote function execute(
    string functionName,
    RfcParameters parameters = {},
    typedesc<RfcRecord|xml|json?> returnType = <>
) returns returnType|Error = @java:Method {
    'class: "io.ballerina.lib.sap.Client"
} external;
```

Key changes from the current signature:

| Aspect                     | Before                                                | After                                           |
|----------------------------|-------------------------------------------------------|-------------------------------------------------|
| Input type                 | `record {\| FieldType?...; \|}` (flat, category-free) | `RfcParameters` (explicit sections)             |
| Input default              | No default — always required                          | `= {}` — optional for parameter-free RFCs       |
| Output typedesc constraint | `record {\| FieldType?...; \|}`                       | `RfcRecord` (named alias, same type)            |
| Output parameter name      | `exportParams` (misleading — omits tables)            | `returnType` (accurate — export + table merged) |

When `changingParameters` is eventually added to `RfcParameters`, callers using `parameters = {}` or `{importParameters: {...}}` need no change. Callers who need changing params add the new field.

---

### Usage Examples

#### `RFC_READ_TABLE` — table params on both input and output

```ballerina
// Input: import params and table params are explicitly separated
type OptionsRow record {| string TEXT; |};
type FieldsRow record {| string FIELDNAME; |};

// Output: flat record — populated from both export and table param lists
type DataRow record {| string WA; |};
type ReadTableResponse record {|
    DataRow[] DATA;
|};

ReadTableResponse result = check sapClient->execute(
    "RFC_READ_TABLE",
    {
        importParameters: {"QUERY_TABLE": "MARA", "DELIMITER": "|", "ROWCOUNT": 100},
        tableParameters: {
            OPTIONS: [{"TEXT": "MATNR LIKE '100%'"}],
            FIELDS:  [{"FIELDNAME": "MATNR"}, {"FIELDNAME": "MBRSH"}]
        }
    },
    ReadTableResponse
);
```

#### `BAPI_MATERIAL_GETLIST` — table input filter, table output result set

```ballerina
type MaterialRow record {|
    string MATNR;
    string MAKTX;
|};

type ReturnMsg record {|
    string TYPE;
    string MESSAGE;
|};

type MaterialListResponse record {|
    MaterialRow[] MATNRLIST;
    ReturnMsg[]   RETURN;
|};

MaterialListResponse result = check sapClient->execute(
    "BAPI_MATERIAL_GETLIST",
    {
        importParameters: {"MAXROWS": 50},
        tableParameters: {
            "MATNRSELECTION": [{"SIGN": "I", "OPTION": "EQ", "MATNR_LOW": "000000000000100000"}]
        }
    },
    MaterialListResponse
);
```

#### RFC with no parameters

```ballerina
type PingResponse record {| string ECHOTEXT; string RESPTEXT; |};

// parameters defaults to {} — no explicit argument needed
PingResponse result = check sapClient->execute("STFC_CONNECTION", returnType = PingResponse);
```

#### XML/JSON output (unchanged behavior, now includes table data)

```ballerina
xml response = check sapClient->execute("RFC_READ_TABLE", {
    importParameters: {"QUERY_TABLE": "MARA"}
});
```

---

### Forward Compatibility: Changing Parameters

When changing parameter support is added, `RfcParameters` gains one new optional field:

```ballerina
public type RfcParameters record {|
    RfcRecord importParameters?;
    map<RfcRecord[]> tableParameters?;
    RfcRecord changingParameters?;   // NEW — bidirectional, no other change needed
|};
```

Callers who do not use changing parameters are completely unaffected. No public Ballerina API changes are required at that point.

---

### Migration from Current API

The change to `execute()` is **breaking**. The following mechanical transformation covers all existing call sites:

```ballerina
// Before
check client->execute("FUNC", {"IV_INPUT": "value"}, MyResult);

// After
check client->execute("FUNC", {importParameters: {"IV_INPUT": "value"}}, MyResult);
```

For callers with no import parameters:

```ballerina
// Before
check client->execute("FUNC", {}, MyResult);

// After — parameters defaults to {}, can omit entirely or keep explicit
check client->execute("FUNC", returnType = MyResult);
```

Callers who were accidentally passing array-valued fields in the old flat `importParams` (which failed at runtime) must move those fields to `tableParameters`.

## Alternatives

### Alternative 1: Fix the bug without redesigning the API

Route array-typed fields in the flat `importParams` to the table parameter list automatically, and merge `getTableParameterList()` into the output. No breaking change.

**Rejected.** This keeps the category confusion and makes it impossible to add changing parameter support later without a breaking change or an awkward parallel API. The developer experience is also worse: you cannot tell from the call site whether `{OPTIONS: [...]}` is an import-list entry or a table-list entry.

### Alternative 2: Add a separate `executeWithTables()` method

Keep the existing `execute()` for backward compatibility and add a new overload.

**Rejected.** It duplicates the API surface, forces choosing between two methods with non-obvious differences, and still doesn't solve the changing-parameter problem cleanly.

### Alternative 3: Section-based output (MuleSoft/Boomi style)

Return a structured `RfcResponse` record with explicit `exportParameters` and `tableParameters` sections, mirroring the input structure.

**Rejected** in favor of flat output. Every vendor that uses section-based input (MuleSoft, Boomi, WSO2) uses it on input but not on output — the output remains a flat envelope of all returned data. The reason: on input, categories map to different JCo API calls so the separation has a mechanical consequence. On output, the caller only cares about the data, not which JCo list it came from. A sectioned output would force users to write `result.tableParameters["DATA"]` instead of `result.DATA`, which is strictly worse DX with no compensating benefit. A flat output typedesc is also more idiomatic in Ballerina.

### Impact of doing nothing

Every integration that reads a list of records from SAP is blocked. The connector can only retrieve single-value export parameters (status codes, identifiers). The SAP integration scenarios covered by MM, SD, FI, PP, and HR modules are not addressable.

## Testing

### Unit tests

- `setTableParams`: Verify a `map<RfcRecord[]>` is correctly written to the JCo table parameter list with the right row count and field values.
- `getMergedParams`: Given a mock `JCoParameterList` for exports (string field) and a mock for tables (array of rows), verify both appear in the returned `BMap`.
- Null safety: `getTableParameterList()` returns `null` for RFCs with no table parameters; verify no `NullPointerException` in either direction.
- `parameters = {}`: Verify `execute()` with no arguments succeeds for a parameter-free RFC stub.

### Integration tests (SAP sandbox)

| RFC                       | Input table params  | Output table params | Export params          |
|---------------------------|---------------------|---------------------|------------------------|
| `RFC_READ_TABLE`          | `OPTIONS`, `FIELDS` | `DATA`              | —                      |
| `BAPI_MATERIAL_GETLIST`   | `MATNRSELECTION`    | `MATNRLIST`         | —                      |
| `BAPI_SALESORDER_GETLIST` | `MATERIAL`          | `SALES_ORDERS`      | —                      |
| `STFC_CONNECTION`         | —                   | —                   | `ECHOTEXT`, `RESPTEXT` |

`STFC_CONNECTION` is the regression baseline: an export-only RFC that must produce identical output before and after the change.

### Regression

All existing examples in the `examples/` directory use only scalar import/export parameters. After the mechanical migration (wrapping in `importParameters: {...}`), they must pass with no other change.

## Risks and Assumptions

| Risk                                                                       | Mitigation                                                                                                |
|----------------------------------------------------------------------------|-----------------------------------------------------------------------------------------------------------|
| `getTableParameterList()` returns `null` for RFCs with no table parameters | Null guards added in `Client.java` and `getMergedParams()` before touching the list                       |
| XML merge produces invalid XML if `toXML()` includes an XML declaration    | Strip XML declarations from fragment strings before combining                                             |
| JSON merge has key collisions between export and table params              | Export and table parameter lists for a valid RFC have disjoint field names; collision treated as an error |
| Existing call sites break                                                  | Documented as a breaking change; mechanical migration in release notes                                    |

## Dependencies

- SAP JCo 3.x (existing dependency): `JCoFunction.getTableParameterList()` is part of the standard JCo API in all supported versions.
- No new Ballerina standard library dependencies.

## Future Work

- **Changing parameters** (`getChangingParameterList()`): Bidirectional scalar/structure parameters. The `RfcParameters` record and `getMergedParams()` are pre-designed to accept this as an additive change.
- **Async RFC** (`tRFC`/`qRFC`): Transactional and queued RFC calls for guaranteed delivery, currently out of scope.

## References

- MuleSoft SAP Connector 5.x docs — explicit `<import>`, `<changing>`, `<tables>` XML sections
- Boomi SAP JCo V2 Connector — `importParameters`, `tableParameters`, `changingParameters` JSON keys
- WSO2 EI SAP Adapter — `<import>` and `<tables>` XML wrappers
- SAP JCo 3.x API: `JCoFunction`, `JCoParameterList`, `JCoTable`
- Root cause locations: `Client.java:87–103`, `ImportParameterProcessor.java:78–81`
