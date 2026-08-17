# GraphQL Compiler Plugin Diagnostic Code Convention

- Authors
  - Thisaru Guruge
- Reviewed by
  - Danesh Kuruppu
- Created date
  - 2026-08-14
- Updated date
  - 2026-08-17
- Issue
  - [1471](https://github.com/ballerina-platform/ballerina-spec/issues/1471)
- State
  - Submitted

## Summary

The `ballerina/graphql` compiler plugin emits 58 diagnostic codes today: `GRAPHQL_101`–`GRAPHQL_148` for errors and `GRAPHQL_201`–`GRAPHQL_210` for warnings, assigned in whatever order the feature that needed them landed. This proposal replaces that ad hoc numbering with a documented, severity- and area-based convention, `GRAPHQL_<S><A><NN>`, whose digits encode severity, the area of the package a diagnostic concerns, and its sequence within that area. It maps all 58 existing codes onto the new scheme and fixes the `WARNING_209`/`WARNING_210` naming bug as part of the regeneration. This is not a breaking change: a diagnostic code is compiler output, and no Ballerina program's source or binary compatibility depends on a diagnostic's number. This BEP is one of a set of proposals revamping the Ballerina GraphQL package, and the sibling BEPs allocate the numbers for their new diagnostics from the areas defined here.

## Motivation

The current numbering carries no information. `GRAPHQL_133`–`GRAPHQL_138` (federation) sit between `GRAPHQL_128`/`129` (interceptors) and `GRAPHQL_139`/`140` (scalars and `@graphql:ID`), so a code number on its own gives no hint what part of the package a diagnostic concerns. The error/warning split at the hundreds digit follows from chronological assignment rather than a documented rule. Nothing enforces it, two constants already break it, and errors have consumed 48 of the 99 slots available before the next hundred. The package has no `HINT` severity anywhere, even though the diagnostics API supports one. Two things make now the time to fix it. The coordinated set of changes across the sibling BEPs already touches much of the diagnostic surface: every diagnostic that encodes the `resource`/`remote` split is re-expressed, the data loader and directive work introduces new ones, and two federation codes are retired on delivery. And the sibling BEPs need somewhere to allocate their new codes from; allocating them under today's scheme would mean renumbering them again afterwards.

## Goals

- Replace the compiler plugin's chronologically-assigned diagnostic codes with a documented, severity- and area-based convention that has headroom for years of growth, as a non-breaking overhaul.
- Map every one of the 58 codes shipping today onto that convention, so the renumbering is one mechanical pass rather than incremental drift.
- Fix the `WARNING_209`/`WARNING_210` naming bug in the same regeneration, and make its reintroduction a test failure rather than a review catch.
- Serve as the registry the sibling BEPs in this release allocate their new diagnostic codes from.

## Non-Goals

- **Changing what any diagnostic does.** This proposal changes a diagnostic's number and, where the constant is misnamed, its name. It does not add, remove, or re-specify the behaviour, trigger condition, severity, or message text of any diagnostic. Where a row in [Section 3](#3-full-mapping) is annotated as new, re-specified, re-worded, or removed on delivery, the sibling BEP named in the annotation owns that change; this BEP records only the number it is filed under.
- **Allocating the federation BEP's codes.** `GRAPHQL_1207`+ and `GRAPHQL_2203`+ are reserved for the [Apollo Federation v2 Parity BEP](1477_graphql_federation_v2_parity.md) ([#1477](https://github.com/ballerina-platform/ballerina-spec/issues/1477)), which defines those diagnostics itself. It currently allocates `GRAPHQL_1207` and `GRAPHQL_1208` for errors and `GRAPHQL_2203` and `GRAPHQL_2204` for warnings, recorded there rather than here.
- **The runtime error surface.** Only compiler-plugin diagnostics are in scope. Client-side errors and the listener's runtime error output are runtime values, not compile-time diagnostics, which is why area `5` (client) is reserved and empty.

## Current State Analysis

This section records the present-day behaviour that [Design](#design) changes. Every claim is sourced from the package at `ballerina/graphql` v1.18.0 (distribution `2201.13.3`).

> **Note on `GRAPHQL_nnn` codes.** Every diagnostic code cited under its _current_ number (`GRAPHQL_101` and so on) comes from the GraphQL **compiler plugin**, an implementation detail of this package rather than a Ballerina language error code. This BEP replaces every one of these numbers. The current numbers are used here, and in the sibling BEPs, because they are what ships today.

### Diagnostic codes

Across the compiler plugin's diagnostic definitions, the package emits **58** diagnostic codes today: 48 errors (`GRAPHQL_101`–`GRAPHQL_148`, contiguous, no gaps) and 10 warnings (`GRAPHQL_201`–`GRAPHQL_210`, contiguous). No diagnostic in the package uses `HINT` severity, even though `io.ballerina.tools.diagnostics.DiagnosticSeverity` supports one. The numbering puts errors in the 100s and warnings in the 200s, but that pattern comes from chronological assignment, not a documented rule. Nothing enforces it, and two codes already break it: `DiagnosticCode.WARNING_209` and `DiagnosticCode.WARNING_210` are named `WARNING_209`/ `WARNING_210` rather than `GRAPHQL_209`/`GRAPHQL_210`, unlike every other constant in the same enum. Errors occupy 101–148, 48 of a 99-wide block before the next hundred. Codes are assigned in whatever order the feature that needed them landed: `GRAPHQL_133`–`138` (federation) sit between `GRAPHQL_128`/`129` (interceptors) and `GRAPHQL_139`/`140` (scalars/`@graphql:ID`) with no grouping by topic, so the code number alone gives no hint what area of the package a diagnostic concerns.

## Design

### 1. What's wrong with the current scheme

[Current State Analysis, Diagnostic codes](#diagnostic-codes) has the facts: 58 chronologically-assigned codes, an undocumented error/warning split that is running low on room, no `HINT` severity, no topic grouping, and the `WARNING_209`/`WARNING_210` naming bug. **This is not a breaking change.** A diagnostic code is compiler output: informational text, and for tooling a string identifier, emitted during `bal build`. No Ballerina program's source or binary compatibility depends on a diagnostic's number. The one cost is that external tooling matching on a code string, such as a CI lint rule suppressing a known warning, needs updating. That is a changelog line, not a version-compatibility concern.

### 2. The new convention

```text
GRAPHQL_<S><A><NN>
         │ │  └─ two-digit sequence within the area, in the order the diagnostic was introduced
         │ └──── one-digit area code (what part of the package)
         └────── one-digit severity (1 = ERROR, 2 = WARNING, 3 = HINT)
```

Area codes:

| Area    | Covers                                                                                                                                  |
| ------- | --------------------------------------------------------------------------------------------------------------------------------------- |
| `0`     | Core service & resolver structure — accessors, resource paths, listener wiring, service config                                          |
| `1`     | Type system — return/input types, unions, interfaces, `graphql:Upload`, `graphql:ID`, default values, scalars                           |
| `2`     | Federation / subgraph                                                                                                                   |
| `3`     | Data loader / prefetch methods                                                                                                          |
| `4`     | Interceptors                                                                                                                            |
| `5`     | Client (reserved — no compiler-plugin diagnostics exist here today; client-side errors are runtime types, not compile-time diagnostics) |
| `6`     | Directives & spec-edition extensions (`@oneOf`, `@deprecated` on arguments/input fields, and any future ratified-directive support)     |
| `7`–`8` | Reserved for areas not yet identified                                                                                                   |
| `9`     | General / misc (doesn't fit a specific area — e.g. schema-generation failure)                                                           |

Each area gets a full `01`–`99` sequence per severity: 99 codes per area per severity, 2,970 codes total across the scheme, against 58 in use today. The headroom is generous on purpose.

### 3. Full mapping

Every code below is **proposed, not frozen**: final numbers are confirmed during implementation against whatever else has landed in the package by then.

<details>
<summary>See detailed error code examples:</summary>

#### Area 0 — Core service & resolver structure

| Current       | New            | Name                                                                                                                                            |
| ------------- | -------------- | ----------------------------------------------------------------------------------------------------------------------------------------------- |
| `GRAPHQL_101` | `GRAPHQL_1001` | `INVALID_FUNCTION` (remote method inside a `service class`)                                                                                     |
| `GRAPHQL_106` | `GRAPHQL_1002` | `INVALID_RESOURCE_FUNCTION_ACCESSOR` (nested accessor)                                                                                          |
| `GRAPHQL_107` | `GRAPHQL_1003` | `INVALID_MULTIPLE_LISTENERS`                                                                                                                    |
| `GRAPHQL_109` | `GRAPHQL_1004` | `INVALID_LISTENER_INIT`                                                                                                                         |
| `GRAPHQL_113` | `GRAPHQL_1005` | `MISSING_RESOURCE_FUNCTIONS`                                                                                                                    |
| `GRAPHQL_117` | `GRAPHQL_1006` | `INVALID_PATH_PARAMETERS`                                                                                                                       |
| `GRAPHQL_118` | `GRAPHQL_1007` | `INVALID_RESOURCE_PATH`                                                                                                                         |
| `GRAPHQL_124` | `GRAPHQL_1008` | `INVALID_HIERARCHICAL_RESOURCE_PATH`                                                                                                            |
| `GRAPHQL_125` | `GRAPHQL_1009` | `INVALID_SUBSCRIBE_RESOURCE_RETURN_TYPE`                                                                                                        |
| `GRAPHQL_126` | `GRAPHQL_1010` | `INVALID_ROOT_RESOURCE_ACCESSOR`                                                                                                                |
| `GRAPHQL_148` | `GRAPHQL_1011` | `INVALID_MODIFICATION_OF_SERVICE_CONFIG_FIELD`                                                                                                  |
| —             | `GRAPHQL_1012` | **New**, both approaches: `DUPLICATE_FIELD_DECLARATION` — allocated by the [GraphQL Unified Resolver Model BEP](1473_graphql_unified_resolver_model.md) ([#1473](https://github.com/ballerina-platform/ballerina-spec/issues/1473)) |
| —             | `GRAPHQL_1013` | **New, Approach A only**: `INVALID_REMOTE_METHOD` (remote forbidden entirely; subsumes `GRAPHQL_1001`'s root-level case) — [GraphQL Unified Resolver Model BEP](1473_graphql_unified_resolver_model.md) ([#1473](https://github.com/ballerina-platform/ballerina-spec/issues/1473)) |
| —             | `GRAPHQL_2001` | **New, Approach B only**: `DEPRECATED_REMOTE_METHOD` (warning) — [GraphQL Unified Resolver Model BEP](1473_graphql_unified_resolver_model.md) ([#1473](https://github.com/ballerina-platform/ballerina-spec/issues/1473))   |
| —             | `GRAPHQL_2002` | **New, Approach B only**: `DEPRECATED_GET_ACCESSOR` (warning, two message variants) — [GraphQL Unified Resolver Model BEP](1473_graphql_unified_resolver_model.md) ([#1473](https://github.com/ballerina-platform/ballerina-spec/issues/1473)) |

#### Area 1 — Type system

| Current                                          | New            | Name                                                                                                                      |
| ------------------------------------------------ | -------------- | ------------------------------------------------------------------------------------------------------------------------- |
| `GRAPHQL_102`                                    | `GRAPHQL_1101` | `INVALID_RETURN_TYPE`                                                                                                     |
| `GRAPHQL_103`                                    | `GRAPHQL_1102` | `INVALID_INPUT_PARAMETER_TYPE`                                                                                            |
| `GRAPHQL_104`                                    | `GRAPHQL_1103` | `INVALID_RETURN_TYPE_NIL`                                                                                                 |
| `GRAPHQL_105`                                    | `GRAPHQL_1104` | `INVALID_RETURN_TYPE_ERROR_OR_NIL`                                                                                        |
| `GRAPHQL_108`                                    | `GRAPHQL_1105` | `INVALID_RETURN_TYPE_ERROR`                                                                                               |
| `GRAPHQL_110`                                    | `GRAPHQL_1106` | `INVALID_UNION_MEMBER_TYPE`                                                                                               |
| `GRAPHQL_111`                                    | `GRAPHQL_1107` | `INVALID_FIELD_NAME`                                                                                                      |
| `GRAPHQL_112`                                    | `GRAPHQL_1108` | `INVALID_RETURN_TYPE_ANY`                                                                                                 |
| `GRAPHQL_114`                                    | `GRAPHQL_1109` | `INVALID_RETURN_TYPE_INPUT_OBJECT`                                                                                        |
| `GRAPHQL_115`                                    | `GRAPHQL_1110` | `INVALID_RESOURCE_INPUT_OBJECT_PARAM`                                                                                     |
| `GRAPHQL_116`                                    | `GRAPHQL_1111` | `NON_DISTINCT_INTERFACE`                                                                                                  |
| `GRAPHQL_119`                                    | `GRAPHQL_1112` | `INVALID_FILE_UPLOAD_IN_RESOURCE_FUNCTION` (re-specified by the [GraphQL Unified Resolver Model BEP](1473_graphql_unified_resolver_model.md) ([#1473](https://github.com/ballerina-platform/ballerina-spec/issues/1473))) |
| `GRAPHQL_120`                                    | `GRAPHQL_1113` | `MULTI_DIMENSIONAL_UPLOAD_ARRAY`                                                                                          |
| `GRAPHQL_121`                                    | `GRAPHQL_1114` | `INVALID_INPUT_TYPE`                                                                                                      |
| `GRAPHQL_122`                                    | `GRAPHQL_1115` | `INVALID_INPUT_TYPE_UNION`                                                                                                |
| `GRAPHQL_123`                                    | `GRAPHQL_1116` | `NON_DISTINCT_INTERFACE_IMPLEMENTATION`                                                                                   |
| `GRAPHQL_130`                                    | `GRAPHQL_1117` | `INVALID_ANONYMOUS_FIELD_TYPE`                                                                                            |
| `GRAPHQL_131`                                    | `GRAPHQL_1118` | `INVALID_ANONYMOUS_INPUT_TYPE`                                                                                            |
| `GRAPHQL_132`                                    | `GRAPHQL_1119` | `INVALID_RETURN_TYPE_CLASS`                                                                                               |
| `GRAPHQL_139`                                    | `GRAPHQL_1120` | `UNSUPPORTED_TYPE_ALIAS`                                                                                                  |
| `GRAPHQL_140`                                    | `GRAPHQL_1121` | `INVALID_USE_OF_ID_ANNOTATION`                                                                                            |
| `GRAPHQL_146`                                    | `GRAPHQL_1122` | `INVALID_EMPTY_RECORD_OBJECT_TYPE`                                                                                        |
| `GRAPHQL_147`                                    | `GRAPHQL_1123` | `INVALID_EMPTY_RECORD_INPUT_TYPE`                                                                                         |
| `GRAPHQL_205`                                    | `GRAPHQL_2101` | `UNABLE_TO_INFER_DEFAULT_VALUE_AT_COMPILE_TIME`                                                                           |
| `GRAPHQL_206`                                    | `GRAPHQL_2102` | `...PROVIDE_KEY_VALUE_PAIR`                                                                                               |
| `GRAPHQL_207`                                    | `GRAPHQL_2103` | `...PROVIDE_LITERAL_OR_CONSTRUCTOR_EXPRESSION`                                                                            |
| `GRAPHQL_208`                                    | `GRAPHQL_2104` | `...AVOID_USING_SPREAD_OPERATION`                                                                                         |
| `GRAPHQL_209` (currently misnamed `WARNING_209`) | `GRAPHQL_2105` | `UNABLE_TO_VALIDATE_DEFAULT_VALUES_OF_INPUT_FIELD`                                                                        |
| `GRAPHQL_210` (currently misnamed `WARNING_210`) | `GRAPHQL_2106` | `UNABLE_TO_VALIDATE_DEFAULT_VALUES_OF_INPUT_OBJECT`                                                                       |

#### Area 2 — Federation / subgraph

| Current       | New            | Name                                                                                                                                   |
| ------------- | -------------- | -------------------------------------------------------------------------------------------------------------------------------------- |
| `GRAPHQL_133` | `GRAPHQL_1201` | `INVALID_USE_OF_RESERVED_REMOTE_METHOD_NAME`                                                                                           |
| `GRAPHQL_134` | `GRAPHQL_1202` | `INVALID_USE_OF_RESERVED_RESOURCE_PATH`                                                                                                |
| `GRAPHQL_135` | `GRAPHQL_1203` | `INVALID_USE_OF_RESERVED_TYPE_AS_OUTPUT_TYPE`                                                                                          |
| `GRAPHQL_136` | `GRAPHQL_1204` | `INVALID_USE_OF_RESERVED_TYPE_AS_INPUT_TYPE`                                                                                           |
| `GRAPHQL_137` | `GRAPHQL_1205` | `FAILED_TO_ADD_ENTITY_RESOLVER` — **removed on delivery** of engine-native `_entities` ([GraphQL Attach-Time Dispatch BEP](1472_graphql_attach_time_dispatch.md) ([#1472](https://github.com/ballerina-platform/ballerina-spec/issues/1472))) |
| `GRAPHQL_138` | `GRAPHQL_1206` | `FAILED_TO_ADD_SERVICE_RESOLVER` — **removed on delivery**, same reason                                                                |
| `GRAPHQL_203` | `GRAPHQL_2201` | `PROVIDE_KEY_VALUE_PAIR_FOR_ENTITY_ANNOTATION`                                                                                         |
| `GRAPHQL_204` | `GRAPHQL_2202` | `PROVIDE_A_STRING_LITERAL_OR_AN_ARRAY_OF_STRING_LITERALS_FOR_KEY_FIELD`                                                                |

> **Note:** `GRAPHQL_1207`+ and `GRAPHQL_2203`+ are reserved for the [Apollo Federation v2 Parity BEP](1477_graphql_federation_v2_parity.md) ([#1477](https://github.com/ballerina-platform/ballerina-spec/issues/1477)), which allocates its own codes from that range.

#### Area 3 — Data loader / prefetch

| Current       | New            | Name                                                                                                                                             |
| ------------- | -------------- | ------------------------------------------------------------------------------------------------------------------------------------------------ |
| `GRAPHQL_141` | `GRAPHQL_1301` | `MISSING_GRAPHQL_CONTEXT_PARAMETER`                                                                                                              |
| `GRAPHQL_142` | `GRAPHQL_1302` | `INVALID_PARAMETER_IN_PREFETCH_METHOD`                                                                                                           |
| `GRAPHQL_143` | `GRAPHQL_1303` | `INVALID_RETURN_TYPE_IN_PREFETCH_METHOD`                                                                                                         |
| `GRAPHQL_144` | `GRAPHQL_1304` | `UNABLE_TO_FIND_PREFETCH_METHOD`                                                                                                                 |
| `GRAPHQL_145` | `GRAPHQL_1305` | `INVALID_USAGE_OF_PREFETCH_METHOD_NAME_CONFIG` (message re-worded by the [GraphQL Data Loader Streamlining BEP](1474_graphql_dataloader_streamlining.md) ([#1474](https://github.com/ballerina-platform/ballerina-spec/issues/1474))) |
| —             | `GRAPHQL_1306` | **New**: `UNDECLARED_DATA_LOADER` (exact trigger depends on which registration path the [GraphQL Data Loader Streamlining BEP](1474_graphql_dataloader_streamlining.md) ([#1474](https://github.com/ballerina-platform/ballerina-spec/issues/1474)) resolves to) |
| —             | `GRAPHQL_1307` | **New**: `INVALID_DATA_LOADER_LOAD_IN_MUTATION` — single-call `load()`/`loadMany()`, [GraphQL Data Loader Streamlining BEP](1474_graphql_dataloader_streamlining.md) ([#1474](https://github.com/ballerina-platform/ballerina-spec/issues/1474)) |
| `GRAPHQL_202` | `GRAPHQL_2301` | `UNABLE_TO_VALIDATE_PREFETCH_METHOD`                                                                                                             |

#### Area 4 — Interceptors

| Current       | New            | Name                                       |
| ------------- | -------------- | ------------------------------------------ |
| `GRAPHQL_128` | `GRAPHQL_1401` | `RESOURCE_METHOD_INSIDE_INTERCEPTOR`       |
| `GRAPHQL_129` | `GRAPHQL_1402` | `INVALID_REMOTE_METHOD_INSIDE_INTERCEPTOR` |

#### Area 6 — Directives & spec-edition extensions

| Current       | New            | Name                                                                                                                                                    |
| ------------- | -------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `GRAPHQL_201` | `GRAPHQL_2601` | `UNSUPPORTED_INPUT_FIELD_DEPRECATION` — **removed on delivery** of `@deprecated` on input fields ([GraphQL September 2025 Spec Alignment BEP](1475_graphql_september_2025_spec_alignment.md) ([#1475](https://github.com/ballerina-platform/ballerina-spec/issues/1475))) |
| —             | `GRAPHQL_1601` | **New**: `INVALID_ONEOF_FIELD` — `@oneOf`, [GraphQL September 2025 Spec Alignment BEP](1475_graphql_september_2025_spec_alignment.md) ([#1475](https://github.com/ballerina-platform/ballerina-spec/issues/1475))                    |
| —             | `GRAPHQL_1602` | **New**: `INVALID_REQUIRED_DEPRECATED_INPUT` — `@deprecated` on arguments and input fields, [GraphQL September 2025 Spec Alignment BEP](1475_graphql_september_2025_spec_alignment.md) ([#1475](https://github.com/ballerina-platform/ballerina-spec/issues/1475)) |

#### Area 9 — General

| Current       | New            | Name                       |
| ------------- | -------------- | -------------------------- |
| `GRAPHQL_127` | `GRAPHQL_1901` | `SCHEMA_GENERATION_FAILED` |

This accounts for all 58 current codes, plus the eight new codes the sibling BEPs currently allocate from the scheme. Three of the eight are conditional on the resolver-model decision (one under Approach A, two under Approach B). The `WARNING_209`/`WARNING_210` naming bug is fixed as a side effect: every constant in the regenerated `DiagnosticCode` enum follows the same `GRAPHQL_nnnn` pattern.
</details>

### 4. Allocating codes from this scheme

This BEP owns two things: the scheme, and the mapping of the 58 codes shipping today onto it. It does not own the diagnostics the rest of the release introduces. Each sibling BEP allocates its own new codes from the area ranges defined in [Section 2](#2-the-new-convention), specifies what each one means and when it fires, and stays the authority on that behaviour; this BEP records only the number and the name. The tables in [Section 3](#3-full-mapping) are the registry of which numbers are taken: a BEP that allocates a new code adds its row here in the same revision, so the next allocation needs one document rather than five.

The sibling BEPs currently draw from these ranges. The [GraphQL Unified Resolver Model BEP](1473_graphql_unified_resolver_model.md) ([#1473](https://github.com/ballerina-platform/ballerina-spec/issues/1473)) allocates from area 0: `GRAPHQL_1012` under both approaches, `GRAPHQL_1013` under Approach A, `GRAPHQL_2001` and `GRAPHQL_2002` under Approach B. It also re-specifies `GRAPHQL_1112` in area 1 without renumbering it. The [GraphQL Data Loader Streamlining BEP](1474_graphql_dataloader_streamlining.md) ([#1474](https://github.com/ballerina-platform/ballerina-spec/issues/1474)) allocates `GRAPHQL_1306` and `GRAPHQL_1307` from area 3. The [GraphQL September 2025 Spec Alignment BEP](1475_graphql_september_2025_spec_alignment.md) ([#1475](https://github.com/ballerina-platform/ballerina-spec/issues/1475)) allocates `GRAPHQL_1601` and `GRAPHQL_1602` from area 6, and retires `GRAPHQL_2601` on delivery. The [GraphQL Attach-Time Dispatch BEP](1472_graphql_attach_time_dispatch.md) ([#1472](https://github.com/ballerina-platform/ballerina-spec/issues/1472)) allocates none; it retires `GRAPHQL_1205` and `GRAPHQL_1206` from area 2 when engine-native `_entities`/`_service` resolution lands. The [GraphQL Client Schema Validation BEP](1476_graphql_client_schema_validation.md) ([#1476](https://github.com/ballerina-platform/ballerina-spec/issues/1476)) allocates none either, so area `5` stays reserved and empty: client-side validation surfaces runtime error values rather than compile-time diagnostics. Area 2's remaining range is reserved for the Apollo Federation v2 Parity BEP, per the note in [Section 3](#3-full-mapping).

## Testing

Fixture-level test obligations are left to implementation. The categories of coverage:

- **Number and message, per code.** Every renumbered code needs a fixture asserting its new number and message.
- **No survivors of the old numbering.** A repository-wide grep confirms no reference to a pre-renumbering code string survives outside historical/changelog text.
- **Naming.** A test asserts every constant in the regenerated diagnostic-code enum follows the `GRAPHQL_nnnn` pattern, so the `WARNING_209`/`WARNING_210`-style naming bug cannot come back.

## Risks and Assumptions

### Risks

- **Diagnostic renumbering is non-breaking, but not zero-cost.** External tooling that pattern-matches on a `GRAPHQL_nnn` string, such as CI lint suppressions, needs updating. Worth a changelog line; not a version-compatibility concern.
- **`GRAPHQL_1xxx`/`2xxx`/`3xxx` code allocation ([Section 3](#3-full-mapping)) is proposed, not final**; the numbers must be confirmed against whatever else has landed in the package by implementation time.

### Assumptions

- **The 58-code census is complete and current.** 48 errors and 10 warnings, counted across the compiler plugin's diagnostic definitions at `ballerina/graphql` v1.18.0 (distribution `2201.13.3`). Anything that lands in the package between now and implementation adds to it, so the mapping is confirmed against the package before it is applied rather than taken as read.
- **A diagnostic's number is not part of the package's compatibility contract.** No Ballerina program's source or binary compatibility depends on it; the external-tooling cost recorded under Risks is the only consequence.

## Dependencies

- **None.** This is the only BEP in the set with no dependency on another. Nothing in it needs the resolver-model decision, the dispatch work, or any other design in the release; the work is mechanical and can start ahead of every other BEP in the set.
- **Every other BEP in the set depends on this one** for the numbers its new diagnostics are filed under. That is a forward dependency this BEP creates rather than one it carries.

## Future Work

- **First use of `HINT` severity.** The scheme defines severity digit `3` and nothing uses it: the package emits no `HINT`-severity diagnostic today, even though `io.ballerina.tools.diagnostics.DiagnosticSeverity` supports one.
- **The [Apollo Federation v2 Parity BEP](1477_graphql_federation_v2_parity.md) ([#1477](https://github.com/ballerina-platform/ballerina-spec/issues/1477))'s codes**, allocated from `GRAPHQL_1207`+ and `GRAPHQL_2203`+ and recorded in that BEP.
- **Areas `5`, `7` and `8`**, left unallocated and available when a feature area emerges that does not fit an existing one.

## References

- [Ballerina GraphQL module specification](https://github.com/ballerina-platform/module-ballerina-graphql/blob/master/docs/spec/spec.md)
- [BEP process](../AAA-bep-resources/0000_bep_process.md)
- [Ballerina GraphQL module specification](https://github.com/ballerina-platform/module-ballerina-graphql/blob/master/docs/spec/spec.md)

[]: # (end)
[]: # Please add any comments to issue [#1471](https://github.com/ballerina-platform/ballerina-spec/issues/1471)
