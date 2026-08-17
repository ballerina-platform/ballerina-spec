# Introduce XLSX Module

- Authors
  - Yasan Punchihewa
- Reviewed by
- Created date
  - 2026-08-16
- Updated date
  - 2026-08-16
- Issue
  - [#1467](https://github.com/ballerina-platform/ballerina-spec/issues/1467)
- State
  - Submitted

## Summary

Ballerina has first-class, type-safe support for JSON, XML, CSV, and EDI, but until now no way to read or write Microsoft Excel files — the most common tabular exchange format in enterprise integration. This BEP documents the design of **`ballerina/xlsx`**, a library module for reading and writing Excel files in the XLSX (Office Open XML) format with type-safe data binding to Ballerina records, implemented in [`module-ballerina-xlsx`](https://github.com/ballerina-platform/module-ballerina-xlsx) and released on [Ballerina Central](https://central.ballerina.io/ballerina/xlsx/latest). The module provides two API tiers: one-shot functions (`parseSheet` / `writeSheet` / `parseTable` / `writeTable`) for simple file-based ETL, and an object-based Workbook API (`Workbook`, `Sheet`, `Table`) for multi-sheet operations, byte-array I/O, and cell-level control. It includes first-class Excel Table (ListObject) support, target-type-driven date/time binding to `ballerina/time` types, optional row-level fail-safe parsing with error logging, `ballerina/constraint` integration, and atomic file writes. The public API is implemented over a native Java adaptor wrapping Apache POI.

## Motivation

1. **Excel is the enterprise tabular format.** B2B data exchange, finance and operations reporting, HR extracts, and ad-hoc business data routinely arrive and leave as `.xlsx` files. Every ecosystem an integration developer might compare Ballerina against treats Excel processing as table stakes: Python has openpyxl and pandas, Java has Apache POI, Go has excelize, Node has SheetJS. Ballerina — a language purpose-built for integration — had no support at all.

2. **The workarounds are poor.** Without this module, an application that must consume an XLSX file has three options, none good:
   - **Direct Java interop against POI:** verbose per-project boilerplate, manual cell-type dispatch, no data binding, and handle lifecycle managed by hand. Every project re-solves the same problems (date cells, formula cells, blank-vs-missing, header mapping) with none of the type safety Ballerina is built around.
   - **Convert to CSV externally, then `ballerina/data.csv`:** adds an external pipeline step and loses everything CSV cannot express — multiple sheets, cell data types, date/time values, and Excel Tables.
   - **Cloud connectors** (`ballerinax/microsoft.excel` via the Graph API, `ballerinax/googleapis.sheets`): these operate on documents hosted in a cloud service. They cannot process a local file, or a byte payload that just arrived over HTTP, FTP, or an email attachment — the dominant shapes in which Excel data actually reaches an integration.

3. **Data binding is Ballerina's core strength; XLSX completes the `data.*` family.** The `data.jsondata`, `data.xmldata`, and `data.csv` modules established a shared model: `parse*` functions driven by an inferred `typedesc`, projection controls (`allowDataProjection`), and constraint validation (`enableConstraintValidation`). Applying the same model to XLSX gives Excel processing the same one-line ergonomics users already know:

   ```ballerina
   Employee[] employees = check xlsx:parseSheet("staff.xlsx");
   ```

## Goals

* Read and write XLSX files with type-safe, bidirectional binding between sheet rows and Ballerina records, maps, or string arrays, following the conventions of the `data.*` module family.
* Provide a functional one-shot API for the common cases — parse a sheet to records, write records to a sheet — with no lifecycle management.
* Provide a complete object-based Workbook API for multi-sheet operations, byte-array I/O (HTTP/FTP payloads without touching disk), sheet and table management, and cell-level control.
* Support Excel Tables (ListObjects) as first-class citizens, reachable from both tiers.
* Bind date, time, and date-time cells to `time:Civil` / `time:Date` / `time:TimeOfDay` driven by the target type, with an ISO 8601 `string` fallback.
* Default to safe, non-destructive behaviour: writes fail rather than silently overwrite, and all file writes are atomic (a failed write never destroys the original file).
* Offer row-level fail-safe parsing — log and skip bad rows instead of failing the parse — for messy real-world files, with structured console and file logging.
* Integrate with `ballerina/constraint` annotations on parsed records.

## Non-Goals

The first release deliberately defers several features; each is future work rather than permanently rejected (see [Future Work](#future-work)):

- **Formula authoring and re-evaluation.** Formula cells are *read* (cached value or formula text), but strings starting with `=` are written verbatim as text, and there is no formula recalculation.
- **Streaming.** All operations load the workbook into memory (DOM model); there is no row-streaming API for files larger than memory.
- **Round-trip fidelity of the target sheet in the one-shot tier.** `parseSheet → writeSheet` is a data-only pipe for the sheet being written; formatting, formulas, charts, and comments on that sheet are not preserved (sibling sheets are). The Workbook API edits cells in place for richer preservation.
- **XLS (legacy 97-2003) format, password-protected files, named ranges, cell styling, and range operations.**

## Design

This section summarizes the API surface and the design decisions behind it. The full normative specification, including every option record, method table, and sample, is maintained in the module repository: [Ballerina XLSX Module Specification](https://github.com/ballerina-platform/module-ballerina-xlsx/blob/main/docs/spec/spec.md).

### 1. Module overview

The module is `ballerina/xlsx`. The package has two parts: a `ballerina/` module holding the public API and a `native/` Java subproject that adapts it onto Apache POI (5.3.0), the de-facto standard JVM library for Office Open XML processing. POI's XSSF (DOM) model is used, so the workbook is fully materialized in memory; this is what enables random cell access, Excel Table geometry operations, and read-modify-write of existing files.

The API is organized in two tiers because Excel workloads come in two shapes:

- **Tier 1 — module-level functions** (`parseSheet`, `writeSheet`, `parseTable`, `writeTable`): one-shot, file-based, open-and-close-within-the-call. This is the ETL shape — "read this file into records", "dump these records to a file" — and it needs no lifecycle management.
- **Tier 2 — the Workbook API** (`Workbook`, `Sheet`, `Table` objects): explicit lifecycle for everything the one-shot shape cannot express — coordinated multi-sheet operations, byte-array input and output, sheet and table management, and cell-level reads and writes.

### 2. Type model

The atomic data unit is a single row:

```ballerina
# A single row in a sheet — the atomic data unit.
public type Row map<CellValue> | string[];

# An XLSX cell value, including the empty cell (`()` for a blank cell).
public type CellValue string|int|float|decimal|boolean
                    | time:Date|time:Civil|time:TimeOfDay|();
```

A row is either a **`map<CellValue>`** keyed by column header, or a **`string[]`** of raw cell text in column order. A typed **record** also binds when every field type is a subtype of `CellValue` — fields match headers by name (overridable per field with the `@xlsx:Name` annotation), and a `CellValue` rest descriptor captures columns beyond the declared fields.

The map's value type is deliberately `CellValue`, not `anydata`: the row contract matches exactly what a cell can hold, so a target field of an unsupported type (`xml`, `byte[]`, a nested record) is rejected **at compile time** rather than failing at runtime.

Read functions take the row shape as an inferred `typedesc<Row> t = <>` parameter and return `t[]`, so contextual typing at the call site selects the binding:

```ballerina
type Order record {| int id; decimal amount; |};
Order[] orders     = check xlsx:parseSheet("orders.xlsx");    // typed records
string[][] raw     = check xlsx:parseSheet("orders.xlsx");    // raw text
map<CellValue>[] m = check xlsx:parseSheet("orders.xlsx");    // natural cell values
```

When the target does not pin a scalar type (a `map<CellValue>` value, a rest field, cell-level reads), each cell binds to its natural `CellValue`: whole number → `int`, fractional → `decimal`, boolean → `boolean`, string → `string`, date/time cell → ISO 8601 `string`, blank → `()`. `float` is produced only target-driven — a natural read never yields it — and a blank cell binding to a non-nilable scalar target raises `TypeConversionError`.

A `CellRange` record (four 0-based inclusive indices) describes rectangular regions for the used-range and table-geometry operations; A1-notation strings are accepted alongside it where natural.

### 3. Simple API

```ballerina
public isolated function parseSheet(string path, string|int sheet = 0,
        ParseOptions options = {}, typedesc<Row> t = <>) returns t[]|Error;

public isolated function writeSheet(Row[] data, string path,
        string sheetName = "Sheet1", *SheetWriteOptions options) returns Error?;

public isolated function parseTable(string path, string tableName,
        TableParseOptions options = {}, typedesc<Row> t = <>) returns t[]|Error;

public isolated function writeTable(Row[] data, string path, string tableName,
        *TableWriteOptions options) returns Error?;
```

Key semantics:

- **`parseSheet`** selects the sheet by name or 0-based index (default: first sheet), binds the header row to field names, and reads the data window below it.
- **`writeSheet`** opens the file if it exists and affects **only the named sheet** — sibling sheets, their tables, and formulas are preserved; if the file does not exist it is created. The default mode fails if the named sheet already exists, so no data is overwritten by accident (see [§5](#5-options-and-write-modes)).
- **`parseTable` / `writeTable`** address an Excel Table by name. Table names are unique across a workbook, so no sheet specifier is needed, and the table is self-describing — its own header row and data range are authoritative. `writeTable` replaces the table's data and **resizes the data range to fit exactly** (or appends under `APPEND` mode); the totals row and content below the table are carried along by the resize, and a resize that would shift another table fails with `TableOverlapError` writing nothing.
- All file writes in both tiers are **atomic**: temp file in the same directory plus atomic rename, so a failed write never destroys the original file.

### 4. Workbook API

Empty workbooks are constructed with `new`; existing ones are opened through module-level factory functions:

```ballerina
xlsx:Workbook wb1 = new;                                    // empty in-memory
xlsx:Workbook wb2 = check xlsx:fromFile("report.xlsx");     // open existing file
xlsx:Workbook wb3 = check xlsx:fromBytes(sourceBytes);      // open from bytes
```

`Workbook` exposes sheet access (`getSheet`, `createSheet`, `deleteSheet`, name lookups are case-insensitive to match Excel), table access (`getTable`, `getAllTables`), and lifecycle (`save`, `saveAs`, `toBytes`, `close`). `toBytes()` serializes the workbook as XLSX bytes for HTTP/FTP transfer without going through disk. `close()` is the resource contract; a phantom-reference cleanup thread backstops workbooks that escape without it, and every method on a closed workbook returns a typed `Error` rather than panicking.

`Sheet` handles (obtained from the workbook, never constructed directly) carry the full read/write surface: bulk reads and writes (`getRows` / `putRows`, the tier-2 equivalents of `parseSheet` / `writeSheet`), single-row, single-column, and single-cell access (by index or A1 address), row deletion with dense reindexing, renaming, and table creation (from an explicit range or sized to data).

`Table` handles expose identity and geometry (name, ranges in both A1 and `CellRange` form), header and data reads following table-read semantics, `putRows` with the same resize contract as `writeTable`, totals-row access, `rename`, `resize`, and single-data-row deletion.

A deliberate invariant spans the two: **a table is modified only through the Table API.** Sheet-level row inserts or deletes that would shift a table's cells without moving its definition are refused with `TableOverlapError`, in both directions. This keeps table geometry consistent by construction instead of by user discipline.

Workbooks and their vended handles are not safe for concurrent mutation; deleting a sheet or table invalidates its outstanding handles.

### 5. Options and write modes

Options records are modelled by **applicability**: each operation accepts only the fields it can honour, enforced by the type system rather than documentation. Two fields are universal to every read (`formulaMode`, `caseInsensitiveHeaders`); sheet reads add absolute row-window positioning (`headerRowIndex`, `dataStartRowIndex`, both 0-based, with headerless-sheet support); record/map reads add the binding controls shared with the `data.*` family (`enableConstraintValidation`, `allowDataProjection`); bulk reads add `rowCount` and `failSafe`. Table reads omit the positional fields entirely — a table is self-describing. Single-row reads are fail-fast by construction (no `failSafe` — skipping the only requested row would leave nothing to return).

Formula cells are read under a `FormulaMode`: `CACHED` (default) returns the last calculated value; `TEXT` returns the formula expression as a string.

Sheet writes share one contract, `SheetWriteMode` — the disposition toward content already at the target — with per-operation defaults chosen so that the default is always the least destructive behaviour that makes sense for that operation:

| Mode | Meaning |
|---|---|
| `FAIL_IF_EXISTS` | Fail rather than touch existing content. |
| `REPLACE` | Overwrite in place (`writeSheet` drops and recreates the sheet; row writers overwrite the target rows). |
| `APPEND` | Add content without overwriting; content in the way shifts down. |

`writeSheet` defaults to `FAIL_IF_EXISTS` (a one-shot export must not silently destroy a sheet), `Sheet.putRows` defaults to `APPEND` (bulk writes into an open workbook accumulate), and `Sheet.setRow` defaults to `REPLACE` (writing *row 5* means replacing row 5). Table writes use a separate `TableWriteMode` (`REPLACE` resizes-to-fit, `APPEND` inserts; a table always has a data region, so there is no `FAIL_IF_EXISTS`). Empty input is defined everywhere: an empty table `REPLACE` clears the table to a single blank data row, an empty table `APPEND` is a no-op, and an empty sheet write creates the target sheet and writes nothing.

### 6. Header mapping — `@xlsx:Name`

Record field names rarely match spreadsheet column headers (`firstName` vs `"First Name"`). The `@xlsx:Name` annotation maps a record field to its Excel column header, bidirectionally — on read the header binds to the field, on write the field produces the header:

```ballerina
type Employee record {|
    @xlsx:Name {value: "First Name"}
    string firstName;
    @xlsx:Name {value: "Employee ID"}
    int id;
|};
```

This follows the precedent of `@jsondata:Name` and `@xmldata:Name` in the existing data modules.

### 7. Date and time binding

Excel stores dates as formatted numeric cells, and every ecosystem's Excel library has to decide how to surface them. The module makes the decision target-type-driven: a date/time cell binds to `time:Civil` (date-time), `time:Date` (date), or `time:TimeOfDay` (time) when the target field declares one of those types, and falls back to an ISO 8601 `string` otherwise. Writing a `time:*` value produces a real date-formatted numeric cell, not text — so typed date fields round-trip.

### 8. Fail-safe parsing

Real-world spreadsheets are edited by humans and contain malformed rows. By default a bad row fails the parse (fail-fast), but bulk reads accept a `failSafe` option: row-level errors (`TypeConversionError`, `ConstraintValidationError`) are logged and the offending row skipped, and the parse returns the good rows. Logging is structured — console logging with optional source-row data, and optional file logging in one of three line-delimited JSON shapes (metadata, raw row, or both), described by public `LogOutput` / `Location` records with 1-based coordinates matching the Excel UI. Structural errors (missing file, missing sheet or table, non-workbook input) always fail immediately regardless of `failSafe`.

### 9. Errors

Every module error is a subtype of a base `Error` carrying `ErrorDetails` (sheet/table name, A1 cell address, 1-based row/column, offending record field — each populated when determinable). The subtypes fall into two behavioural groups, and the split is load-bearing for fail-safe semantics:

- **Structural errors** — always immediate: `ParseError`, `FileNotFoundError`, `SheetNotFoundError` / `SheetExistsError`, `TableNotFoundError` / `TableExistsError`, `TableOverlapError`, `InvalidTableRangeError`.
- **Row-level errors** — fail-fast by default, skippable under `failSafe`: `TypeConversionError`, `ConstraintValidationError` (which chains the underlying `constraint:Error` as its cause).

Index conventions are uniform: option fields and `CellRange` are 0-based (programmer-facing), error locations are 1-based (matching what the user sees in Excel).

### 10. Usage

One-shot ETL:

```ballerina
import ballerina/xlsx;

type Employee record {|
    string name;
    int age;
    decimal salary;
|};

public function main() returns error? {
    Employee[] employees = check xlsx:parseSheet("staff.xlsx");
    // ... transform ...
    check xlsx:writeSheet(employees, "staff-out.xlsx", "Employees");
}
```

Multi-sheet coordination through the Workbook API:

```ballerina
xlsx:Workbook wb = check xlsx:fromFile("sales.xlsx");
do {
    xlsx:Sheet rawSheet = check wb.getSheet("Raw");
    Sale[] sales = check rawSheet.getRows();

    Sale[] highValue = from Sale s in sales where s.price > 100d select s;

    xlsx:Sheet summary = check wb.createSheet("HighValue");
    check summary.putRows(highValue);
    check wb.save();
} on fail error e {
    check wb.close();
    return e;
}
check wb.close();
```

Bytes in, bytes out — no disk touched:

```ballerina
byte[] inputBytes = check sftp->get("/in/orders.xlsx");
xlsx:Workbook wb = check xlsx:fromBytes(inputBytes);
do {
    xlsx:Sheet sheet = check wb.getSheet(0);
    Order[] orders = check sheet.getRows();
    check sheet.putRows(from Order o in orders select {...o, amount: o.amount * 1.1d});
    check sftp->put("/out/orders-enriched.xlsx", check wb.toBytes());
} on fail error e {
    check wb.close();
    return e;
}
check wb.close();
```

## Alternatives

* **Route Excel data through CSV and `ballerina/data.csv`.** Rejected: CSV cannot express multiple sheets, cell data types, date/time values, or Excel Tables, and it forces an external conversion step into every pipeline. The formats look adjacent but the workloads are not.
* **A thin Java-interop wrapper exposing POI's classes directly.** Rejected: navigating `XSSFWorkbook → XSSFSheet → XSSFRow → XSSFCell` with manual cell-type dispatch is Java ergonomics, not Ballerina ergonomics, and it abandons data binding — the core value of the module. POI is an implementation detail, not the API.
* **A streaming-first design (POI's SAX reader / SXSSF writer).** Deferred, not taken for the first release: streaming read and write cannot support random cell access, read-modify-write of existing files, or Excel Table geometry — the operations the Workbook API exists for — and would fragment the API into incompatible halves. The DOM model covers the dominant workloads; a streaming tier can be added later as an additive API (see [Future Work](#future-work)).
* **Building on a lighter-weight library (e.g. fastexcel) instead of POI.** Rejected: the lighter libraries trade away exactly the surface this module needs — Excel Table (ListObject) support, cached formula values, read-modify-write — and POI is the actively-maintained de-facto standard with the broadest format coverage.
* **`anydata` as the row value type.** Rejected: with `map<anydata>`, an unbindable target field (an `xml` value, a nested record) becomes a runtime error discovered in production. With `CellValue` the same mistake is a compile error.
* **A single stateful API (everything through `Workbook`).** Rejected: the dominant use case — parse one file into records — should not require constructing, saving, and closing an object. Conversely, functions alone cannot express multi-sheet coordination or byte-level I/O. Two tiers with mirrored semantics (`getRows` *is* `parseSheet` at sheet level) keep both shapes first-class.

## Testing

The module repository carries the test suite: a binding matrix across every `CellValue` member (including blank cells against nilable and non-nilable targets, and date/time cells against each `time:*` target and the string fallback), round-trip tests for records, maps, and raw rows including `@xlsx:Name` mapping, option-matrix tests for the read/write option records and every `SheetWriteMode` / `TableWriteMode` combination, table-geometry tests (resize grow/shrink, totals-row carry, overlap refusal in both directions), error-path tests for the full error hierarchy including the closed-workbook contract, fail-safe tests validating each log-entry shape, constraint-validation integration tests, atomicity tests (a failed write leaves the original file intact), and fixtures produced by Excel, LibreOffice, and openpyxl to guard interoperability. As a standard library module with a native Java component, the module also runs GraalVM native-image tests in CI per the library process.

## Risks and Assumptions

* **Memory.** The DOM model assumes workbooks fit in memory; the bytes path additionally sustains roughly 1.5–2.5× the DOM heap for the workbook's lifetime (the underlying parser inflates every zip entry up front). Both are documented, with a temp-file pattern recommended for large byte payloads. Files larger than memory are out of scope until a streaming tier exists.
* **Untrusted input.** The parse path is protected by POI's `ZipSecureFile` defaults — a 1% minimum inflate ratio and per-entry size caps — which reject classic zip-bomb payloads. Overall workbook memory remains bounded only by the heap; configurable module-level limits with a typed error are future work.
* **Large integers lose precision silently on write.** Excel stores numeric cells as IEEE-754 doubles, so integers with `|n| > 2^53` round silently — the same behaviour as POI, openpyxl, and Excel itself. The documented escape hatch is declaring the field as `string`, which round-trips digits exactly as a text cell.
* **Dependency weight.** POI and its transitive dependencies (xmlbeans, commons-compress, and others) are a substantial native payload, affecting package size and requiring GraalVM reachability configuration. This is the accepted cost of complete OOXML support.
* **Concurrency.** A workbook and its vended handles are not safe for concurrent mutation; this is a documented contract rather than an enforced one.

## Dependencies

* Apache POI (`org.apache.poi:poi-ooxml`, 5.3.0) and its transitive dependencies, in the native adaptor.
* `ballerina/time` (date/time binding targets), `ballerina/constraint` (validation integration).
* No dependencies on other BEPs.

## Future Work

* **Streaming tier** for files larger than memory (row-streaming reads; append-only streaming writes).
* **Formula support**: a `Formula` wrapper type for authoring on write, and `EVALUATE` / `RECALCULATE` / `PRESERVE` formula modes beyond today's `CACHED` / `TEXT`.
* **Cell styling** (number formats, fonts, fills) and **named ranges**.
* **Password-protected (encrypted) workbooks** and the legacy **XLS** format.
* **Range operations** (rectangular multi-cell reads and writes).
* **Configurable resource limits** for untrusted input (input size, row and cell caps) surfaced with a typed error, beyond POI's built-in ZIP protections.
* **A distinct lifecycle error subtype** for methods invoked on invalidated (deleted or closed) `Workbook`, `Sheet`, and `Table` handles.
* **A defined contract for formula cells with missing cached results** under `FormulaMode.CACHED`, with fixtures covering the never-evaluated case.

## References

* [`ballerina/xlsx` on Ballerina Central](https://central.ballerina.io/ballerina/xlsx/latest)
* [Ballerina XLSX Module Specification](https://github.com/ballerina-platform/module-ballerina-xlsx/blob/main/docs/spec/spec.md)
* [Module repository: `ballerina-platform/module-ballerina-xlsx`](https://github.com/ballerina-platform/module-ballerina-xlsx)
* [ECMA-376: Office Open XML file formats](https://ecma-international.org/publications-and-standards/standards/ecma-376/)
* [Apache POI](https://poi.apache.org/)
* [`ballerina/data.csv`, the data-binding precedent](https://central.ballerina.io/ballerina/data.csv/latest)
