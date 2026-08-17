# Apollo Federation v2 Parity for the Ballerina GraphQL Package

- Authors
  - Thisaru Guruge
- Reviewed by
  - Danesh Kuruppu
- Created date
  - 2026-08-14
- Updated date
  - 2026-08-17
- Issue
  - [1477](https://github.com/ballerina-platform/ballerina-spec/issues/1477)
- State
  - Submitted

## Summary

The Ballerina GraphQL package can declare a service as an Apollo Federation subgraph, but implements two of the nineteen Federation v2 directives — `@key` and `@link`. This proposal closes that gap. It adds the remaining composition-relevant directives as `graphql.subgraph` annotations, and validates `FieldSet` selection strings at compile time instead of never. It narrows the `ReferenceResolver` type, so a resolver returning the wrong entity type fails to compile rather than at runtime. It makes the exported SDL federation-ready, so `rover subgraph compose` can consume it without a running service. It lifts the requirement that entities be declared in the same module as the service. Engine-native `_entities`/`_service` resolution is not part of this proposal: it is committed in, and owned by, the [Attach-Time-Resolved Dispatch BEP](1472_graphql_attach_time_dispatch.md) ([#1472](https://github.com/ballerina-platform/ballerina-spec/issues/1472)), because it builds on that BEP's dispatch structure rather than on anything federation-specific — see [Dependencies](#dependencies).

**The design below is carried forward from draft work that was never reviewed.** It was drafted while federation was still part of a larger GraphQL package revamp proposal, then moved to a working note that told its reader to re-verify every claim against the package before relying on it. Promoting it to a BEP does not perform that verification: the annotation declarations in [Section 1](#1-the-directive-set) must be re-derived against the current `commons` and `subgraph` modules, and the directive-exclusion reasons in the same section were recorded when the work was last drafted and may no longer hold.

## Motivation

Apollo Federation is the dominant way large organisations compose multiple GraphQL services into one graph. A subgraph that supports only `@key` is limited to the simplest composition topology. Every directive missing from the package is a modelling pattern a Ballerina subgraph cannot express: `@shareable` for a field two subgraphs can both resolve, `@external`/`@requires` for a resolver that needs a field it does not own, `@provides` for a subgraph that can short-circuit a hop, `@override` for migrating a field between subgraphs, `@inaccessible` for a field that exists in a subgraph but must not reach the public supergraph, `@tag` for the metadata contract-filtering depends on, `@interfaceObject` for extending an interface without knowing its implementations. A team evaluating Ballerina for a subgraph in an existing federated graph will hit one of these within the first few services. The gap is not confined to the directive set: three of the package's federation behaviours fail later than they should, or not at all.

- A `FieldSet` string — the `fields` argument of `@key`, and of `@requires`/`@provides` once they exist — is never validated. A typo in `@subgraph:Entity { key: "idd" }` compiles cleanly and produces SDL the compiler accepts. It surfaces as a composition failure in `rover`, or a resolution failure at runtime, far from the line that caused it.
- A reference resolver is typed loosely enough that returning the wrong entity type is a runtime error. The engine detects this and reports `Incorrect return type specified for the '<name>' entity reference resolver.` — a check the compiler could have done.
- Composition requires a running service. The package emits SDL at build time, but that SDL is not federation-ready, so the only route into `rover subgraph compose` is introspection against a deployed subgraph. That makes composition a deployment-time concern rather than a build-time one, and nothing in CI proves that the directives the package emits are valid Federation v2. This compounds as the directive set grows: Federation is an Apollo-defined, versioned specification, and Apollo adds directives in minor versions — `@interfaceObject` arrived in v2.3. Without a composition check in CI, the package has no mechanism that notices.

## Goals

- Implement the composition-relevant Federation v2 directives the package lacks — `@shareable`, `@inaccessible`, `@tag`, `@external`, `@override`, `@requires`, `@provides`, `@interfaceObject`, `@composeDirective` — as `graphql.subgraph` annotations, each with schema-output coverage.
- Derive the `@link` import list from the directives a subgraph actually uses, rather than from the set the package happens to implement.
- Validate `FieldSet` selection strings against the annotated type at compile time, erroring where the value is a literal and warning where it is not.
- Make a reference resolver's return type a compile-time-checked contract against the entity type it resolves.
- Produce federation-ready SDL at build time, and prove in CI against a pinned `rover` version that it composes.
- Allow entities to be declared in a module other than the one declaring the service.

## Non-Goals

- **Engine-native `_entities`/`_service` resolution.** Committed in and owned by the [Attach-Time-Resolved Dispatch BEP](1472_graphql_attach_time_dispatch.md) ([#1472](https://github.com/ballerina-platform/ballerina-spec/issues/1472)). This proposal depends on it and does not re-specify it — see [Dependencies](#dependencies).
- **Acting as a federation gateway or router.** The package is a subgraph implementation. Whether it should ever be a gateway is an open question carried forward from the working note, not a commitment either way — see [Future Work](#future-work).
- **`@authenticated`, `@requiresScopes`, `@policy`.** These overlap the package's existing `ListenerAuthConfig` and interceptor models, and need their own design against whatever those models look like when this is picked up — see the exclusion table in [Section 1](#1-the-directive-set).
- **`@cost` and `@listSize`.** Deferred because reconciling the package's single server-side `maxComplexity` model with Federation's router-side, per-query cost model is design work, not a mechanical mapping — see the exclusion table in [Section 1](#1-the-directive-set) and [Future Work](#future-work).
- **`@extends`.** Federation v1 compatibility only; a v2 subgraph applies `@key` to the type directly.

## Current State Analysis

This section records the present-day behaviour that [Design](#design) changes, sourced from the package at `ballerina/graphql` v1.18.0 (distribution `2201.13.3`).

### The subgraph module

`ballerina/modules/subgraph/` is three files — `annotation.bal`, `types.bal`, `constants.bal`, 70 lines in total including licence headers. It holds declarations only, with no logic: the `@subgraph:Subgraph` service annotation, the `@subgraph:Entity` annotation and its `FederatedEntity` record, the `Representation` record, the `ReferenceResolver` function type, and the `_Any` scalar name constant. Everything else federation-related lives in the compiler plugin and the `commons` schema types.

### Directive coverage

Supported Federation directives are **exactly two**: `@key` (on object and interface types, taking a `fields` selection and a `resolvable` flag) and `@link` (schema-level). Relative to the full v2 set, the missing directives are `@external`, `@requires`, `@provides`, `@shareable`, `@inaccessible`, `@override`, `@tag`, `@interfaceObject`, `@composeDirective`, `@extends` (v1-compatibility only, not needed for v2 parity), `@authenticated`, `@requiresScopes`, `@policy`, `@cost`, `@listSize`, and `@context`/`@fromContext`. The `@link` directive the package emits already points at `https://specs.apollo.dev/federation/v2.0`, so the package is not stuck on the Federation v1 specification. What it lacks is breadth of directive coverage, not a declared spec version. The import list in that `@link` is derived from the set of directives the package *implements*, not the set a given subgraph *uses*. Every subgraph therefore emits `@link(url: "https://specs.apollo.dev/federation/v2.0", import: ["@key", "FieldSet"])` regardless of what it declares. With two directives implemented this is close enough to correct to be invisible; with eleven it would not be.

### `FieldSet` and entity annotation values

`@key` takes a `FieldSet` selection-set string. It is never validated against the schema — not for syntax, and not for whether the fields it names exist on the annotated type. Separately, the compiler plugin can only read `@subgraph:Entity` annotation values that are string literals. Where the value is not a literal, the plugin warns (`GRAPHQL_2201`, `GRAPHQL_2202` under the numbering in the [Diagnostic Code Convention BEP](1471_graphql_diagnostic_code_convention.md) ([#1471](https://github.com/ballerina-platform/ballerina-spec/issues/1471))).

### Reference resolvers

`ReferenceResolver` is declared as:

```ballerina
public type ReferenceResolver isolated function (Representation representation)
returns map<any>|service object {}|error?;
```

A resolver that returns the wrong entity type satisfies this type. The engine detects the mismatch at runtime and reports `Incorrect return type specified for the '<name>' entity reference resolver.`, never at compile time.

### Composition

`SchemaExporter` already writes SDL at build time via `SdlSchemaStringGenerator`, but that SDL is not federation-ready. Composition works only through introspection against a running service. There is no build-time artifact `rover subgraph compose` can consume, and so no CI check that the directives the package emits are valid Federation v2.

### Module boundaries

Entities must be declared in the same module as the service that exposes them.

### `_entities` and `_service`

These are injected as Ballerina source at compile time, generated from template files with placeholder substitution and parsed back in. This is out of scope here: replacing it with engine-native resolution is committed in the [Attach-Time-Resolved Dispatch BEP](1472_graphql_attach_time_dispatch.md) ([#1472](https://github.com/ballerina-platform/ballerina-spec/issues/1472)), and this proposal builds on the result — see [Dependencies](#dependencies).

## Design

> **On the status of what follows.** This design is carried forward near-verbatim from unreviewed draft work. See the caution in the [Summary](#summary): the annotation declarations and the exclusion dispositions in [Section 1](#1-the-directive-set) must be re-verified before implementation, not taken as given.

The five design items below are ordered as the drafted work recommends implementing them. The directive set comes first: it is the bulk of the surface area, and the rest either depends on it or is easier to test once schema output is right. Then `FieldSet` validation, which two of those directives need; then the reference-resolver narrowing; then static composition, which needs the directives emitting correctly before it can prove anything; then cross-module entities.

### 1. The directive set

The missing directives are added as annotations in `graphql.subgraph`. Drafted declarations:

```ballerina
public annotation Shareable      on object function, record field, type, class;
public annotation Inaccessible   on object function, record field, type, class;
public annotation External       on object function, record field;
public annotation InterfaceObject on type, class;

public type Requires record {| string fields; |};
public annotation Requires on object function;

public type Provides record {| string fields; |};
public annotation Provides on object function;

public type Override record {| string from; string label?; |};
public annotation Override on object function, record field;

public type Tag record {| string name; |};
public annotation Tag on object function, record field, type, class, parameter;

public type ComposeDirective record {| string name; |};
public annotation ComposeDirective on service;
```

Re-derive these declarations against the current `commons` and `subgraph` modules before implementation, and confirm the attachment points with a `bal build` against the real module. The `@link` import list is derived from the set of annotations used, so a subgraph using only `@key` emits `@link(url: "https://specs.apollo.dev/federation/v2.x", import: ["@key"])`. This replaces today's behaviour, where the list follows the set of directives the package *implements* rather than the set a given subgraph *uses*. The distinction has no visible consequence at two directives and a clear one at eleven:

```graphql
# A subgraph applying only @key, under the derivation rule
extend schema @link(url: "https://specs.apollo.dev/federation/v2.x", import: ["@key"])

# The same subgraph, if the list continued to follow what the package implements
extend schema @link(url: "https://specs.apollo.dev/federation/v2.x", import: ["@key", "@shareable", "@inaccessible", "@tag", "@external", "@override", "@requires", "@provides", "@interfaceObject", "@composeDirective"])
```

Work directive by directive, each with its own schema-output test, in this order: `@shareable`, `@inaccessible`, `@tag` first (no argument resolution); then `@external`, `@override` (simple arguments); then `@requires`, `@provides` (these need the `FieldSet` validation in [Section 2](#2-compile-time-fieldset-validation)); then `@interfaceObject`, `@composeDirective`.

**Excluded, with reasons that should be re-checked rather than assumed:**

| Directive | Disposition when last drafted |
| --- | --- |
| `@extends` | v1-compatibility only; v2 subgraphs use `@key` on the type directly |
| `@authenticated`, `@requiresScopes`, `@policy` | Overlaps `ListenerAuthConfig`/interceptors; needs its own design against whatever that BEP looks like by the time this is picked up |
| `@cost`, `@listSize` | Assessed as additive (derivable from `@graphql:ResourceConfig { complexity }` with no signature change), but deferred: reconciling the package's single server-side `maxComplexity` with Federation's router-side, per-query cost model is design work, not a mechanical mapping |
| `@context`/`@fromContext` | Depends on `@requires`-style `FieldSet` resolution across subgraph boundaries; sequence after the directives above |

### 2. Compile-time `FieldSet` validation

`@key`, `@requires`, and `@provides` all take a `FieldSet` selection-set string, never validated today. The compiler plugin already holds the generated `Schema` object at this point in compilation, so it can parse the `FieldSet` with the packaged `graphql.parser` and resolve each selection against the annotated type. A syntactically invalid `FieldSet`, or one that selects a field that does not exist on the annotated type, is an error: **`GRAPHQL_1207`** (`INVALID_FIELD_SET`). Where the annotation value is not a compile-time literal, the plugin warns instead — **`GRAPHQL_2203`** (`UNABLE_TO_VALIDATE_FIELD_SET_AT_COMPILE_TIME`) — matching the existing pattern for non-literal `@subgraph:Entity` values. Both numbers come from the range the [Diagnostic Code Convention BEP](1471_graphql_diagnostic_code_convention.md) ([#1471](https://github.com/ballerina-platform/ballerina-spec/issues/1471)) reserves for this BEP in area 2, federation (`GRAPHQL_1207`+ for errors, `GRAPHQL_2203`+ for warnings). As that BEP says of its own mapping, these numbers are **proposed, not frozen**. They are confirmed during implementation against whatever else has landed in the package by then.

### 3. Compile-time-checked reference resolvers

`ReferenceResolver` narrows to:

```ballerina
public type ReferenceResolver isolated function (Representation representation)
returns anydata|service object {}|error?;
```

and the compiler plugin checks the resolver's declared return type against the annotated entity type at compile time, emitting **`GRAPHQL_1208`** (`INVALID_REFERENCE_RESOLVER_RETURN_TYPE`) on a mismatch. This turns the engine's runtime `Incorrect return type specified for the '<name>' entity reference resolver.` failure into a compile error for the cases the plugin can see. **This is a breaking change:** any existing reference resolver declared as returning `map<any>` no longer satisfies `ReferenceResolver` and must be narrowed to the entity type it resolves.

```ballerina
// Before — compiles today, satisfies the current ReferenceResolver
isolated function resolveProduct(subgraph:Representation representation) returns map<any>|error? {
    // ...
}

// After — the return type names the entity, and the plugin checks it against @subgraph:Entity
isolated function resolveProduct(subgraph:Representation representation) returns Product|error? {
    // ...
}
```

The rewrite is mechanical at each site: the resolver was already returning the entity, or it was already failing at runtime. It is still a source-compatibility break, and belongs in the changelog and the migration tooling.

### 4. Static composition

`SchemaExporter` already produces SDL. This proposal requires that, for a service annotated `@subgraph:Subgraph`, the exported SDL is federation-ready — carrying `@link` and every applied federation directive — so that `rover subgraph compose` can consume it without a running service. A CI check runs composition against a **pinned `rover` version**. It is the only end-to-end proof that the directives the package emits are valid Federation v2: every other test in the package asserts that the package produces the output the package expects; only `rover` asserts that Apollo agrees. It is also the early warning for Apollo adding directives in a later minor Federation version — `@interfaceObject` arrived in v2.3, and nothing in the package would notice an equivalent addition.

### 5. Cross-module entities

Lift the same-module requirement. `@subgraph:Entity` resolves through the type symbol regardless of the defining module. Where the annotation value cannot be read across the module boundary, the plugin follows the warning pattern already used for cross-module default values and emits **`GRAPHQL_2204`** (`UNABLE_TO_RESOLVE_ENTITY_ANNOTATION_ACROSS_MODULES`) rather than failing the build. As with `GRAPHQL_1207`, `GRAPHQL_2203`, and `GRAPHQL_1208`, this number is proposed rather than frozen.

## Testing

- **Directive set.** One schema-output test per directive, in the implementation order given in [Section 1](#1-the-directive-set): the emitted SDL for a service applying that directive, asserted against a golden file. `@link` import-list derivation needs its own coverage — a subgraph using only `@key`, one using several directives, and one using none beyond `@key` — each asserting the import list contains the directives in use and no others.
- **`FieldSet` validation.** `GRAPHQL_1207` positive and negative fixtures for both failure modes — a syntactically invalid selection set, and a syntactically valid one naming a field that does not exist on the annotated type — across all three of `@key`, `@requires`, and `@provides`. A `GRAPHQL_2203` fixture for a non-literal annotation value, asserting a warning and not an error, and asserting the service still compiles.
- **Reference resolvers.** `GRAPHQL_1208` positive and negative fixtures. A regression test confirming the runtime error path is unreachable for the cases the compiler now rejects, and still reachable — with its existing message text — for any case the compiler cannot see.
- **Static composition.** A CI job running `rover subgraph compose` against the exported SDL of a multi-subgraph fixture, on a pinned `rover` version, failing the build on a composition error. This is the acceptance test for the directive set as a whole.
- **Cross-module entities.** An entity declared in a module other than the service's, resolving correctly; and a cross-module case where the annotation value cannot be read, asserting `GRAPHQL_2204` and a successful build.

## Risks and Assumptions

### Risks

- **The design in this document is carried forward from unreviewed draft work.** This is the primary risk on the proposal, and promotion to a BEP does not mitigate it. The annotation declarations in [Section 1](#1-the-directive-set) are the item most likely to be wrong in detail. Re-deriving them against the current `commons` and `subgraph` modules is cheap and must happen before implementation starts, not during it.
- **Federation directive semantics are Apollo-defined and versioned.** Apollo adds directives in minor versions — `@interfaceObject` in v2.3 — so "v2 parity" is a moving target. The pinned-`rover` CI check in [Section 4](#4-static-composition) is the early-warning mechanism; without it, drift is silent.
- **Narrowing `ReferenceResolver` ([Section 3](#3-compile-time-checked-reference-resolvers)) is a source-compatibility break** for anyone currently returning `map<any>`. It is mechanical to fix per site, but it needs a changelog entry, migration-guide coverage, and a release in which breaking changes are permitted.
- **`rover` becomes a new CI dependency.** A pinned external binary in the build adds a supply-chain and availability surface the package does not have today. Pinning also trades drift detection for staleness: a pin that is never bumped stops being an early-warning mechanism. Bumping the pin is a scheduled action, not a background one.
- **The diagnostic numbers allocated here (`GRAPHQL_1207`, `GRAPHQL_1208`, `GRAPHQL_2203`, `GRAPHQL_2204`) are proposed, not final.** They must be confirmed against the area-2 range in the [Diagnostic Code Convention BEP](1471_graphql_diagnostic_code_convention.md) ([#1471](https://github.com/ballerina-platform/ballerina-spec/issues/1471)) and against whatever else has landed in the package at implementation time.

### Assumptions

- **The compiler plugin holds the generated `Schema` object at the point `FieldSet` validation would run.** Stated in the drafted work and used as the basis for [Section 2](#2-compile-time-fieldset-validation). Not re-verified for this document.
- **The packaged `graphql.parser` can parse a bare selection set.** [Section 2](#2-compile-time-fieldset-validation) assumes the existing parser can parse a `FieldSet` string without a new parsing entry point. Not yet verified.
- **The drafted annotation shapes compile as written.** Not verified. See [Risks](#risks).
- **Open question, carried forward unresolved: should the federation-reserved-name diagnostics move into area 2?** The diagnostics for `_entities`/`_service` used as user-declared field names (`GRAPHQL_1201`–`GRAPHQL_1204` under the new numbering) sit in area 0, core structure, on the reasoning that they are about reserved names in general rather than about federation. The counter-argument is that they are federation's reserved names and nothing else's, and that area 2 is where a reader would look for them. The drafted work left this open pending knowledge of how many diagnostics federation would need; that count is now four ([Section 2](#2-compile-time-fieldset-validation), [Section 3](#3-compile-time-checked-reference-resolvers), [Section 5](#5-cross-module-entities)), so the question is ready for a decision. This proposal does not make it: it belongs to whoever owns the [Diagnostic Code Convention BEP](1471_graphql_diagnostic_code_convention.md) ([#1471](https://github.com/ballerina-platform/ballerina-spec/issues/1471))'s mapping, and moving codes is a renumbering concern rather than a federation one.

## Dependencies

- **[Attach-Time-Resolved Dispatch BEP](1472_graphql_attach_time_dispatch.md) ([#1472](https://github.com/ballerina-platform/ballerina-spec/issues/1472)).** A hard dependency. That BEP replaces the compile-time injection of `_entities`/`_service` as Ballerina source with engine-native resolution. It gives this proposal the base everything here sits on: an entity type map keyed by `__typename` (mapping to the type symbol and its `resolveReference`), recorded by `SchemaGenerator` into the same attach-time-resolved dispatch structure ordinary field dispatch uses, and the removal of source-template injection. This proposal does not re-specify that work and should not be scheduled ahead of it.
- **[Diagnostic Code Convention BEP](1471_graphql_diagnostic_code_convention.md) ([#1471](https://github.com/ballerina-platform/ballerina-spec/issues/1471)).** Defines the severity- and area-based `GRAPHQL_nnnn` scheme and reserves area 2 for federation, specifically `GRAPHQL_1207`+ and `GRAPHQL_2203`+. Every new diagnostic in this proposal comes from that range.
- **Apollo Federation v2 specification.** An external, Apollo-defined, versioned dependency. The directive set is whatever Apollo says it is at the version the package targets, and that version must be an explicit decision.
- **`rover` in CI.** A pinned external binary, required by [Section 4](#4-static-composition). New to the package's build.

## Future Work

- **Open question, carried forward unresolved: should the package support acting as a federation gateway or router, or stay subgraph-only indefinitely?** This has not been attempted in any draft, and no comparable Ballerina package does it today. It is undecided rather than deferred: a scope decision nobody has made. If the answer is ever yes, it is a much larger body of work than this proposal and needs its own BEP.
- **Open question, carried forward unresolved: `@cost`/`@listSize` versus the existing `QueryComplexityConfig` model.** The drafted assessment was that these directives are additive and derivable from `@graphql:ResourceConfig { complexity }` with no signature change. That assessment is about the *mechanics*; the unresolved part is the *model*. The package enforces a single server-side `maxComplexity` at the subgraph. Federation's cost model is router-side and per-query, computed across subgraphs. Reconciling the two needs design, not a mapping: whether the subgraph's own limit still applies, what it means for the router's budget, and which one a user is configuring when they set `complexity`. That work is out of scope here and unstarted.
- **Open question, carried forward unresolved: should `@authenticated`/`@requiresScopes`/`@policy` wait on a separate access-control redesign, or is federation's arrival itself the forcing function to do that redesign?** These directives overlap the package's `ListenerAuthConfig` and interceptor models, which is why they are excluded from this proposal. Whether that exclusion is permanent depends on a decision about the access-control model that this proposal does not make.
- **`@context`/`@fromContext`.** Excluded here because they depend on `@requires`-style `FieldSet` resolution across subgraph boundaries. Sequence after the directives in [Section 1](#1-the-directive-set) have landed.
- **`@extends`.** Not planned. Recorded so that a future reader looking for it finds the reason: it is Federation v1 compatibility, and a v2 subgraph applies `@key` to the type directly.

## References

- [Apollo Federation directives reference](https://www.apollographql.com/docs/graphos/schema-design/federated-schemas/reference/directives) — the normative list of directives and their arguments
- [Apollo Federation subgraph specification](https://www.apollographql.com/docs/graphos/schema-design/federated-schemas/reference/subgraph-spec) — `_entities`, `_service`, and the `_Any`/`FieldSet` scalars
- [Apollo Federation versions and changelog](https://www.apollographql.com/docs/graphos/schema-design/federated-schemas/reference/versions) — which directives arrived in which minor version, the basis for the drift risk in [Risks](#risks)
- [`rover subgraph compose`](https://www.apollographql.com/docs/rover/commands/supergraphs) — the composition command the CI check in [Section 4](#4-static-composition) runs
- [Attach-Time-Resolved Dispatch BEP](1472_graphql_attach_time_dispatch.md) ([#1472](https://github.com/ballerina-platform/ballerina-spec/issues/1472)) — commits and owns the engine-native `_entities`/`_service` resolution and the entity type map this proposal builds on
- [Diagnostic Code Convention BEP](1471_graphql_diagnostic_code_convention.md) ([#1471](https://github.com/ballerina-platform/ballerina-spec/issues/1471)) — the `GRAPHQL_nnnn` scheme and the area-2 range this proposal's new codes are allocated from
- [Ballerina GraphQL Module Specification](https://github.com/ballerina-platform/module-ballerina-graphql/blob/master/docs/spec/spec.md)

[]: # (end)
[]: # Please add any comments to issue [#1477](https://github.com/ballerina-platform/ballerina-spec/issues/1477)
