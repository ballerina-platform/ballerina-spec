# Unified GraphQL Resolver Model

- Authors
  - Thisaru Guruge
- Reviewed by
  - Danesh Kuruppu
- Created date
  - 2026-08-14
- Updated date
  - 2026-08-17
- Issue
  - [1473](https://github.com/ballerina-platform/ballerina-spec/issues/1473)
- State
  - Submitted

## Summary

The Ballerina GraphQL package maps the three GraphQL operation types onto three different constructs: a `query` field is a `resource function get`, a `mutation` field is a `remote function`, and a `subscription` field is a `resource function subscribe`. This asymmetry is the most frequent source of confusion for users coming from a GraphQL background. This proposal unifies all three onto one construct, the resource method, with the operation type named by the accessor (`query`, `mutate`, `subscribe`). How `get` and `remote` are retired is left open: a major-version hard break and a dual-syntax deprecation window are both developed in full and compared in [Section 4](#4-comparison-the-decision-this-proposal-does-not-make) for reviewers to decide.

This proposal is part of the Ballerina GraphQL package revamp and builds on two sibling proposals: the compile-time-resolved dispatch structure from the [GraphQL Compile-Time Dispatch BEP](1472_graphql_compile_time_dispatch.md) ([#1472](https://github.com/ballerina-platform/ballerina-spec/issues/1472)), and the diagnostic numbering from the [GraphQL Diagnostic Code Convention BEP](1471_graphql_diagnostic_code_convention.md) ([#1471](https://github.com/ballerina-platform/ballerina-spec/issues/1471)). Every diagnostic code cited in [Design](#design) uses the new convention's numbers.

## Motivation

### The resolver model does not resemble GraphQL

A user writing a GraphQL service in Ballerina today must learn three unrelated constructs for the three GraphQL operation types. None of the three names the operation type:

```ballerina
service on new graphql:Listener(9090) {

    // Query.greeting
    resource function get greeting(string name) returns string {
        return string `Hello, ${name}`;
    }

    // Mutation.updateName
    remote function updateName(string name) returns string {
        return name;
    }

    // Subscription.updates
    resource function subscribe updates(string topic) returns stream<string, error?> {
        return getUpdateStream(topic);
    }
}
```

Nothing in `resource function get greeting` says "query", and nothing in `remote function updateName` says "mutation". Developers have to learn the mapping because it is unintuitive.

> **Note:** See [ballerina-library discussion #757](https://github.com/ballerina-platform/ballerina-library/discussions/757).

- **`get` for queries** was chosen by analogy with the HTTP `GET` method, on the grounds that a GraphQL query is a read operation. HTTP methods are orthogonal to GraphQL operation types. The GraphQL over HTTP specification requires servers to accept `POST` for _all_ operation types and makes `GET` support optional ([GraphQL over HTTP, draft](https://graphql.github.io/graphql-over-http/draft/)), and the Ballerina GraphQL listener accepts both. So a `query` field is usually served over `POST` while being declared with `get`, which breaks the analogy.
- **`remote` for mutations** was chosen on the grounds that mutating data is usually a remote interaction (a database write, a call to another service). That mixes the field's _semantics_ with its _implementation_: an in-memory mutation is still a `mutation` field, and a `query` field that hits a database is still a query. It also puts an implementation detail into the schema-facing declaration, which the code-first model is meant to hide. It also argued that the `mutation` is not done on a resource, therefore it does not qualify as a "Ballerina resource"; but this does not hold as well since GraphQL treats the mutations as any other field in a type.

The asymmetry costs more than readability:

- **`graphql:Upload` is only permitted in `remote` methods** (diagnostic `GRAPHQL_119` rejects it in resource methods). The rule the package wants is "file upload is only meaningful on a mutation". Because mutations are the only remote methods, the rule is written against method kind instead. This is a symptom of having different constructs.
- **Interceptors are declared with a `remote function execute`** (`graphql:Interceptor`), so `remote function` means two unrelated things inside the same package.
- The runtime maintains two parallel dispatch paths — `getResourceMethod(...)` keyed by accessor and `getRemoteMethod(...)` keyed by name — and the compiler plugin maintains two parallel validation paths, for one concept.

### No comparable library borrows HTTP vocabulary

Every widely-used GraphQL server library names the operation type explicitly, and none reuses HTTP method names:

| Library                        | Query                           | Mutation                           | Subscription                  |
| ------------------------------ | ------------------------------- | ---------------------------------- | ----------------------------- |
| Apollo Server / graphql-js     | `Query` key in the resolver map | `Mutation` key                     | `Subscription` key            |
| HotChocolate (.NET)            | `[QueryType]` / `Query` type    | `[MutationType]` / `Mutation` type | `[SubscriptionType]`          |
| Spring for GraphQL             | `@QueryMapping`                 | `@MutationMapping`                 | `@SubscriptionMapping`        |
| gqlgen (Go)                    | `QueryResolver`                 | `MutationResolver`                 | `SubscriptionResolver`        |
| graphql-go/graphql             | object named `Query`            | object named `Mutation`            | object named `Subscription`   |
| Strawberry / Graphene (Python) | `Query` class                   | `Mutation` class                   | `Subscription` class          |
| Ballerina                      | `resource function get`         | `remote function`                  | `resource function subscribe` |

Spring for GraphQL is the closest precedent: `@QueryMapping`, `@MutationMapping`, and `@SubscriptionMapping` are meta-annotations over the same `@SchemaMapping`, differing only in the preset `typeName` ([Spring for GraphQL — Annotated Controllers](https://docs.spring.io/spring-graphql/reference/controllers.html)). This proposal does the same with resource accessors: one construct, three values, operation type named at the declaration site.

## Goals

- Unify the three GraphQL operation types onto one Ballerina construct, the resource method, with the operation type named by the accessor (`query`, `mutate`, `subscribe`), and decide how `get` and `remote` are retired, informed by [Section 4](#4-comparison-the-decision-this-proposal-does-not-make).
- Re-express every compiler-plugin diagnostic that encodes the `resource`/`remote` split so that it constrains operation type rather than method kind.

## Non-Goals

- **A decision between the two resolver-model approaches.** This proposal designs both the major-version break and the dual-syntax deprecation window in full and compares them in [Section 4](#4-comparison-the-decision-this-proposal-does-not-make). It does not pick one.
- **The `bal graphql` tool.** Schema-first service generation and client generation are a separate effort. The tool must be updated to emit the new resolver forms, tracked separately. Under the dual-syntax approach this is a soft dependency, because old-form generated code still compiles. Under the major-version approach it is a hard release dependency — see [Section 4](#4-comparison-the-decision-this-proposal-does-not-make).
- **User-declarable `Query`/`Mutation`/`Subscription` root type names.** The engine infers these three root type names. A user cannot supply their own or attach type-level documentation to them, because no user-authored symbol represents the root type. The service-typing proposal ([ballerina-library#4620](https://github.com/ballerina-platform/ballerina-library/issues/4620)) aims at this gap more generally — see [Future Work](#future-work).

## Current State Analysis

This section records the present-day behaviour that [Design](#design) changes. Every claim is sourced from the package at `ballerina/graphql` v1.18.0 (distribution `2201.13.3`) and, where noted, the [Ballerina GraphQL Specification](https://github.com/ballerina-platform/module-ballerina-graphql/blob/master/docs/spec/spec.md).

> **Note on `GRAPHQL_nnn` codes.** Every code cited in this section under its _current_ number (`GRAPHQL_101` and so on) comes from the GraphQL **compiler plugin**, not from the Ballerina language. The [GraphQL Diagnostic Code Convention BEP](1471_graphql_diagnostic_code_convention.md) ([#1471](https://github.com/ballerina-platform/ballerina-spec/issues/1471)) replaces all of these numbers. This section keeps the current numbers because they are what ships today; [Design](#design) uses the new ones.

### Resolver model

| GraphQL root type | Ballerina form                                                |
| ----------------- | ------------------------------------------------------------- |
| `Query`           | `resource function get <path>(...)`                           |
| `Mutation`        | `remote function <name>(...)`                                 |
| `Subscription`    | `resource function subscribe <name>(...) returns stream<...>` |

Additional rules in force today:

- Non-root object fields (inside a `service class` or `distinct service object`) may use **only** the `get` accessor; `subscribe` is rejected there (`GRAPHQL_106`).
- At least one `get` resource is mandatory (`GRAPHQL_113`). The diagnostic message still refers to the `@dataloader:Loader` annotation, which does not exist in the shipped `graphql.dataloader` module.
- Only `get` and `subscribe` are accepted as root accessors (`GRAPHQL_126`).
- Hierarchical resource paths are supported for `get` and rejected for `subscribe` (`GRAPHQL_124`).
- A `service class` used as an object type may not contain `remote` methods (`GRAPHQL_101`).
- `graphql:Upload` is permitted only in `remote` methods (`GRAPHQL_119`).
- Mutations execute serially; queries execute in parallel. This is keyed off the _document's_ operation type, not off the method kind.

The accessor strings (`"get"`, `"subscribe"`) are hardcoded as literals in both the compiler plugin's validation logic and the runtime engine's dispatch logic, rather than centralized in one place. This is another symptom of the same asymmetry.

### Root type naming

`Query`, `Mutation`, and `Subscription` are not user-authored symbols anywhere in the package. The engine infers them from the service: the root object at the service declaration becomes `Query`, its resource methods with a `mutate` accessor become `Mutation`, and so on. There is no equivalent of the `schema { query: MyQuery }` root-operation-type alias that the GraphQL specification permits ([GraphQL specification — Type System, Schema](https://spec.graphql.org/September2025/#sec-Schema)). Two consequences: a user cannot give the root types their own names, and a user cannot attach a type-level doc comment to `Query`, `Mutation`, or `Subscription`. The gap is narrow in practice and out of scope here; see [Non-Goals](#non-goals) and [Future Work](#future-work).

### Blast radius, by approach

The blast radius depends on which approach in [Section 3](#3-the-open-decision) is chosen. Under the major-version break, every existing `get`/`remote` declaration across the ecosystem must be rewritten. Under dual-syntax, existing declarations do not change at all; only new fixtures for the new forms and the deprecation warnings are added. The comparison table in [Section 4](#4-comparison-the-decision-this-proposal-does-not-make) puts the two side by side.

## Design

Sections 1 and 2 are shared by both approaches: the destination the resolver model moves to, and the two cross-cutting rules that destination requires. Section 3 designs the two approaches for retiring `get` and `remote` in full, and Section 4 compares them.

### 1. Shared: the three accessors

The new, recommended forms, identical under both approaches:

```ballerina
service on new graphql:Listener(9090) {

    // Query.greeting
    resource function query greeting(string name) returns string {
        return string `Hello, ${name}`;
    }

    // Mutation.updateName
    resource function mutate updateName(string name) returns string {
        return name;
    }

    // Subscription.updates
    resource function subscribe updates(string topic) returns stream<string, error?> {
        return getUpdateStream(topic);
    }
}
```

| GraphQL keyword | Accessor    | Form                        |
| --------------- | ----------- | --------------------------- |
| `query`         | `query`     | noun and verb are identical |
| `mutation`      | `mutate`    | verb form                   |
| `subscription`  | `subscribe` | verb form (already shipped) |

Accessors are verbs in Ballerina by convention (`get`, `post`, `put` in `ballerina/http`), and a resource accessor is grammatically an _identifier_: `resource-method-name := identifier` ([Ballerina language specification, Resources](https://ballerina.io/spec/lang/master/#resources_defn)). All three names are therefore legal with no language change. The GraphQL engine uses its own runtime resource-method lookup, validated by its compiler plugin.

`resource function mutate updateName` reads on first encounter like an instruction, "mutate updateName", rather than a name for an operation. This was also a reason to use `remote` functions for mutations. The accessor describes **what the client does**, not what the method does: a client _queries_ `greeting`, _mutates_ via `updateName`, and _subscribes_ to `updates`. That is the pattern the already-shipped `resource function subscribe updates` set. Alternatives, including the noun `mutation`, are in [Alternatives](#mutation-as-the-accessor-instead-of-mutate).

Nested object fields (`service class`, `distinct service object`) use `query`:

```ballerina
distinct service class Author {
    resource function query name() returns string { ... }
    resource function query books() returns Book[] { ... }
}
```

`mutate` and `subscribe` remain invalid on non-root object types under both approaches. The GraphQL specification places mutation and subscription root fields only on the `Mutation` and `Subscription` types, so a nested `mutate` field has no schema representation.

### 2. Shared: the two cross-cutting rules the new model requires

Both rules below are enforced where the [GraphQL Compile-Time Dispatch BEP](1472_graphql_compile_time_dispatch.md) ([#1472](https://github.com/ballerina-platform/ballerina-spec/issues/1472)) builds its compile-time-resolved map from schema coordinate to resolving method. That map visits every declared resource and remote method once, whatever accessor spelling produced it, so it is the right place for a rule about operation type rather than method kind. This proposal depends on that BEP for both rules.

- **Two declarations that resolve to the same schema coordinate is a compile error.** A service can declare both `resource function get profile()` and `resource function query profile()` on the same type: permanently under Approach B, or transiently during a migration under either approach. A **new compile-time check** (`GRAPHQL_1012`, `DUPLICATE_FIELD_DECLARATION`) catches this. The compiler plugin collects query-type fields (from `get`- and `query`-accessor resource methods) and mutation-type fields (from `remote` methods and `mutate`-accessor resource methods) into one namespace per operation type, then rejects a name collision within a namespace. The language does not do this: to the language, `remote function updateName` and `resource function mutate updateName` are unrelated declarations that happen to share a name.
- **`graphql:Upload`'s permitted-accessor check (`GRAPHQL_1112`) is re-specified against operation type, not method kind.** It is legal in the method bound to any `Mutation`-type coordinate (`remote` or `mutate`) and illegal in the method bound to any `Query`- or `Subscription`-type coordinate (`get`, `query`, or `subscribe`). One rule, expressed once. This retires the "rule written against method kind" cost recorded in [Motivation](#the-resolver-model-does-not-resemble-graphql).

### 3. The open decision

Two approaches were developed in full for what happens to `get` and `remote`. I am leaning towards the [Approach A](#approach-a-major-version-hard-break) since it will be a single-breaking change release without keeping dual-syntax window, which would make the functionality ambiguous and implementation complex.

#### Approach A — Major version hard break

`get` and `remote` are removed, in a release where breaking changes are permitted, with a major version bump and a required migration tool. There is no release in which both old and new forms compile.

**Diagnostics** (using the numbering from the [GraphQL Diagnostic Code Convention BEP](1471_graphql_diagnostic_code_convention.md) ([#1471](https://github.com/ballerina-platform/ballerina-spec/issues/1471))):

- `GRAPHQL_1001` (`service class` contains a `remote` method) is **removed**, subsumed by the new `GRAPHQL_1013` (`INVALID_REMOTE_METHOD`: `remote methods are not allowed in a GraphQL service; use a "mutate" resource method for a GraphQL mutation field`). It fires on a `remote` method anywhere on a GraphQL service, root or nested.
- `GRAPHQL_1002` (nested accessor): re-worded to "must be `query`", since `get` is no longer accepted anywhere. `GRAPHQL_1005` (`MISSING_RESOURCE_FUNCTIONS`): re-worded to "no `query` resource", and the stale `@dataloader:Loader` reference in the message is removed.
- `GRAPHQL_1008` (hierarchical paths): the rejection set becomes **all three accessors**, `query`, `mutate`, and `subscribe`. Hierarchical resource paths are removed entirely, not just rejected on one accessor. Two reasons converge. For `mutate`, the GraphQL specification guarantees serial execution only for top-level mutation fields; a hierarchical `mutate` path would synthesise intermediate types whose fields execute in parallel, breaking that guarantee. For `query`, hierarchical paths give up capability that the equivalent nested `service class` form has for free: no `graphql:ResourceConfig` on an intermediate segment, no reusable intermediate type, no arguments at an intermediate level. In exchange they add a second way to reach the same schema shape. The two long-standing TODOs in the result-assembly path that exist only to support hierarchical paths are then deleted rather than worked around further.
- `GRAPHQL_1010` (root accessor set): becomes `{query, mutate, subscribe}`.
- `GRAPHQL_1112` (`Upload`): permitted set becomes `{mutate}` only.
- `GRAPHQL_1201` (reserved `remote` method name): folded into `GRAPHQL_1202` (reserved resource path), since there is no longer a `remote` method namespace to protect separately.
- `GRAPHQL_2601` (`@deprecated` on input fields, unsupported): removed once `@oneOf`/`@deprecated` ship, per the [GraphQL September 2025 Specification Alignment BEP](1475_graphql_september_2025_spec_alignment.md) ([#1475](https://github.com/ballerina-platform/ballerina-spec/issues/1475)), which is unaffected by the choice here.

**Migration.** The accessor rename is mechanical (`get`→`query`, `remote function`→`resource function mutate`). Hierarchical paths need a restructuring decision rather than a rename: they must become nested `service class` types. A migration tool — `bal graphql migrate`, or a documented mechanical recipe as a fallback — **must ship in the same release**. Without it, this is a tax on every user rather than a one-command upgrade. The `bal graphql` tool, Ballerina by Example, and VS Code templates all become hard release dependencies: any of them still emitting `get`/`remote` produces code that does not compile.

#### Approach B — Dual-syntax deprecation window

`get` and `remote` keep working, with unchanged behaviour, for as long as this approach is in effect. Each triggers a compiler-plugin **warning** (never an error) that names no removal version. A service may mix `get`/`remote` and `query`/`mutate` field by field. This is the intended migration path, not an edge case to tolerate.

**Diagnostics:**

- `GRAPHQL_1001`, `GRAPHQL_1201` (both `remote`-related) are **unchanged**. `remote` methods still exist, so the rules about where they are allowed and what names are reserved apply as today.
- `GRAPHQL_1002` (nested accessor): both `query` and `get` are valid; using `get` here also triggers `GRAPHQL_2002`.
- `GRAPHQL_1005` (`MISSING_RESOURCE_FUNCTIONS`): the **check condition** changes, not just the message. It must fire only when there is _no_ `get` **and** no `query` resource. A service written entirely with `get` is valid and must not trip this diagnostic.
- `GRAPHQL_1008` (hierarchical paths): the rejection set gains `query` alongside the existing `subscribe`. `get` is **not** added; it keeps accepting hierarchical paths as today. `mutate` never had a path concept, because mutations were not resource methods before, so there is nothing to reject there.
- `GRAPHQL_1010` (root accessor set): becomes `{get, query, mutate, subscribe}`. `remote` continues to be validated on a separate axis, as today, not through this accessor check.
- `GRAPHQL_1112` (`Upload`): permitted set becomes `{remote, mutate}`, both allowed.
- `GRAPHQL_1305` (prefetch-method-name config message): names all four resolver forms.
- **New**: `GRAPHQL_2001` (`DEPRECATED_REMOTE_METHOD`, warning) fires on any `remote function` on a GraphQL service: `remote methods for GraphQL mutations are deprecated and will not be supported in a future release; use a "mutate" resource method instead`.
- **New**: `GRAPHQL_2002` (`DEPRECATED_GET_ACCESSOR`, warning) fires on any `resource function get`, root or nested, in **two message variants**. A user relying on a hierarchical path cannot rename to `query`, so a shared message would give them wrong advice:
  - Plain (single-segment path): `the "get" accessor for GraphQL query fields is deprecated and will not be supported in a future release; use "query" instead`.
  - Hierarchical (multi-segment path): `the "get" accessor is deprecated; hierarchical resource paths are only supported under "get" and have no direct "query" equivalent — migrating requires restructuring into nested service classes`.

**No removal version is set by this proposal.** That is on purpose, matching how this approach was specified, but it is also the approach's central risk — see [Section 4](#4-comparison-the-decision-this-proposal-does-not-make) and [Risks](#risks). "Deprecated" without a tracked target tends to become permanent.

**Migration.** Optional, at the user's pace. The before/after table from Approach A applies as _guidance_, not as a forced step. Hierarchical-path services have no forced decision at all: `get` keeps working for them indefinitely, whether or not they ever restructure. **A migration tool is not required for this release**, since nothing is forced to migrate. A tool is still valuable and should be scoped and built ahead of whichever future release removes `get`/`remote`, tracked as [Future Work](#future-work) rather than as a dependency of this proposal. The `bal graphql` tool, Ballerina by Example, and VS Code templates should start emitting the new forms, but a lag is a quality gap, not a compile failure: old-form generated code keeps compiling.

### 4. Comparison: the decision this proposal does not make

Both approaches solve the same problem, the resolver-model asymmetry described in [Motivation](#the-resolver-model-does-not-resemble-graphql). They differ in the shape of the risk they take on. The table is presented without a recommendation; the choice is for the reviewers.

| Dimension                                                         | Approach A — Major version, hard break                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                      | Approach B — Dual-syntax deprecation window                                                                                                                                                                                                                                                                                                                                                  |
| ----------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Migration cost, this release**                                  | High and mandatory: every existing GraphQL service must be edited to compile. Mitigated only by a migration tool that does not yet exist.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                   | Zero and optional: nothing that compiles today stops compiling.                                                                                                                                                                                                                                                                                                                              |
| **Test/fixture churn, this release**                              | The existing tests, fixtures, examples, and specification are rewritten for the new forms. That carries a risk of missed regressions, though the existing integration test suite covers most functionality.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                 | No existing test, fixture, or example changes. New coverage only: `query`/`mutate` fixtures, deprecation-warning fixtures, mixed-form fixtures.                                                                                                                                                                                                                                              |
| **Runtime/compiler-plugin complexity, ongoing**                   | Simplifies over time: one accessor set, one dispatch path, one validation path — today's package minus the asymmetry.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                       | A standing cost with no end date: both `get`/`remote` and `query`/`mutate` are supported until a future release removes the old forms. The [GraphQL Compile-Time Dispatch BEP](1472_graphql_compile_time_dispatch.md) ([#1472](https://github.com/ballerina-platform/ballerina-spec/issues/1472))'s dispatch table removes the _performance_ cost of dual support, but not the _design surface_: two validation paths, two sets of fixtures, one more diagnostic family. |
| **Hierarchical resource paths**                                   | Removed entirely, for all three accessors. Closes the two long-standing result-assembly TODOs tied to hierarchical paths.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                   | Removed only from the _new_ accessor (`query`); `get` keeps them as today, open-ended. The TODOs stay live for as long as `get` is supported.                                                                                                                                                                                                                                                |
| **AI-assistant regeneration risk**                                | Low: an old-form suggestion fails to compile immediately. The strongest available backstop against assistants trained on the old pattern.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                   | Medium, and higher than doing nothing: an old-form suggestion compiles, with only a warning that is easy to miss in CI noise, for the whole deprecation window. Mitigated by refreshing `examples/`, the spec, and Ballerina by Example promptly, and possibly by letting teams promote these warnings to build failures internally (see [Risks](#risks)).                                   |
| **Risk of an indefinite half-migrated state**                     | None — there is no state in which both forms exist.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                         | The central risk of this approach: without a committed removal version, `get`/`remote` can become permanent "deprecated-in-name-only" fixtures, and the original motivation never lands, because tutorials, StackOverflow, and AI training data keep teaching the old form for years.                                                                                                        |
| **`bal graphql` tool / Ballerina by Example / VS Code templates** | Hard release dependency: any of them still emitting old forms produces code that fails to compile. Must be coordinated and released together.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                               | Soft dependency: lagging tooling produces code that still compiles but does not show the recommended form. Coordination is a quality goal, not a release gate.                                                                                                                                                                                                                               |
| **Ecosystem/version-resolution consideration**                    | A user pinned to the old major version in their `Dependencies.toml` keeps working on that version; new projects start on the new one. Ballerina's package resolution does not permit two major versions of the _same_ package in one project's dependency graph. For foundational packages such as `ballerina/io` and `ballerina/http`, which many connectors depend on transitively, that makes a hard break costly: a project can get stuck between two transitive dependents that need different majors. For `ballerina/graphql` the risk is narrow, since no other Ballerina Central packages or connectors are known to depend on `graphql` transitively. The conflict arises mainly if a _user_ has published a reusable library on top of `graphql` v1 that other users also import. | Not applicable in the same way: there is only ever one major version in play, because nothing is removed.                                                                                                                                                                                                                                                                                    |
| **What ships fastest**                                            | Gated on a migration tool that does not exist yet, the largest schedule risk.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                               | Ships as soon as the compiler-plugin and runtime changes land; no external tooling dependency gates the release.                                                                                                                                                                                                                                                                             |
| **Second migration risk**                                         | None — one migration, done.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                 | If `get`/`remote` are removed in a later major version, users who adopted `query`/`mutate` early pay nothing further. Users who never migrated face the same mandatory migration Approach A would have required now, deferred — and, if the "indefinite" risk above materializes, deferred indefinitely.                                                                                     |

Both approaches keep [Section 1](#1-shared-the-three-accessors) and [Section 2](#2-shared-the-two-cross-cutting-rules-the-new-model-requires) identical; the table above is the complete set of differences. Neither approach is the recommendation of this proposal, though I personally lean towards Approach A, alongside a new Ballerina Platform update.

### API Reference

The resolver declarations after this proposal, **branched where [Section 3](#3-the-open-decision)'s two approaches differ**.

| Declaration                                                         | GraphQL mapping               | Under Approach A             | Under Approach B                |
| ------------------------------------------------------------------- | ----------------------------- | ---------------------------- | ------------------------------- |
| `resource function query <path>(...) returns T`                     | `Query` field, root or nested | new                          | new (recommended)               |
| `resource function get <path>(...) returns T`                       | `Query` field, root or nested | **removed**                  | deprecated, unchanged behaviour |
| `resource function mutate <name>(...) returns T`                    | `Mutation` root field         | new                          | new (recommended)               |
| `remote function <name>(...) returns T` on a GraphQL service        | `Mutation` root field         | **removed** (`GRAPHQL_1013`) | deprecated, unchanged behaviour |
| `resource function subscribe <name>(...) returns stream<T, error?>` | `Subscription` root field     | unchanged                    | unchanged                       |

### Migration Guide

#### Service side — under Approach A

This is a **major-version, breaking change**. No release accepts both the old and the new resolver forms.

| Before                                                  | After                                                   |
| ------------------------------------------------------- | ------------------------------------------------------- |
| `resource function get greeting(...)`                   | `resource function query greeting(...)`                 |
| `remote function updateName(...)`                       | `resource function mutate updateName(...)`              |
| `resource function subscribe updates(...)`              | unchanged                                               |
| `resource function get name()` inside a `service class` | `resource function query name()`                        |
| `remote function uploadFile(graphql:Upload f)`          | `resource function mutate uploadFile(graphql:Upload f)` |

Cases requiring a decision rather than a rename:

1. **Hierarchical resource paths, on any accessor.** Removed outright, not renamed — restructure as nested `service class` types:
   ```ballerina
   // Before
   resource function get profile/address/number() returns int { ... }

   // After
   distinct service class Profile {
       resource function query address() returns Address { ... }
   }
   distinct service class Address {
       resource function query number() returns int { ... }
   }
   service on new graphql:Listener(9090) {
       resource function query profile() returns Profile { ... }
   }
   ```
   The migration tool should flag these sites for manual attention rather than attempt the rewrite automatically.
2. **`remote` methods that were never GraphQL fields.** Move to a plain `function` or out of the service. `GRAPHQL_1013` flags it.

Three further migration items ship in the same release but are not resolver-model changes. Each is specified by its own BEP: `Context.getDataLoader` and `Context.registerDataLoader` call sites by the [GraphQL Data Loader Streamlining BEP](1474_graphql_dataloader_streamlining.md) ([#1474](https://github.com/ballerina-platform/ballerina-spec/issues/1474)); `@deprecated` on a required argument or input field by the [GraphQL September 2025 Specification Alignment BEP](1475_graphql_september_2025_spec_alignment.md) ([#1475](https://github.com/ballerina-platform/ballerina-spec/issues/1475)); and narrowing a reference resolver's `map<any>` return type to the entity type, which follows the Apollo Federation v2 Parity BEP's compile-time reference-resolver check.

**Tooling.** A migration tool is a release requirement for this approach, not a nice-to-have — see [Section 3](#approach-a--major-version-hard-break).

#### Service side — under Approach B

Nothing is forced. Both forms compile for as long as this approach is in effect. The before/after table above applies as _guidance_ for users who choose to migrate now, with two differences from Approach A: hierarchical-path services have no forced decision, since `get` keeps working for them; and there is no committed timeline by which migration must be complete.

**Tooling.** Not required for this release — see [Section 3](#approach-b--dual-syntax-deprecation-window). Track building one as [Future Work](#future-work), triggered by whichever future release removes `get`/`remote`.

## Alternatives

### Dual-accessor support during a deprecation window

**No longer an alternative — this is [Section 3](#approach-b--dual-syntax-deprecation-window)'s Approach B, one of the two options this proposal presents in full.** Two objections to dual support have to be answered, and both now are. First, accessor-keyed dispatch would have to try each accepted accessor in turn on the hot path; the [GraphQL Compile-Time Dispatch BEP](1472_graphql_compile_time_dispatch.md) ([#1472](https://github.com/ballerina-platform/ballerina-spec/issues/1472))'s compile-time-resolved dispatch table makes accessor spelling irrelevant to per-request dispatch cost. Second, dual support left the semantics of a mixed-form service undefined; [Section 3](#approach-b--dual-syntax-deprecation-window) now specifies them — free per-field mixing, plus a new compile-time duplicate-field check for a same-coordinate collision across accessor families. With both objections answered, the option moved from a rejected alternative to one of the two designs presented for a decision.

### `mutation` as the accessor instead of `mutate`

`resource function mutation updateName`, matching the GraphQL keyword exactly. **Rejected**, though this is the closest call in the proposal. In favour: it is the GraphQL keyword verbatim, so there is nothing to map. Against: Ballerina resource accessors are verbs by convention (`get`, `post`, `put`, `delete` in `ballerina/http`), and `mutation` is a noun. Adopting it would also force a choice between an inconsistent set (`query`, `mutation`, `subscribe`) and renaming the already-shipped `subscribe` to `subscription`, a second breaking change to the one resolver form nobody is complaining about. `mutate` keeps all three accessors in the same grammatical form and leaves `subscribe` alone.

### `post` as the accessor for mutations

Retaining the HTTP analogy by pairing `get` with `post`. **Rejected.** This doubles down on the analogy the proposal is trying to remove, and it is backwards: a GraphQL `query` is usually served over `POST`, so `get`/`post` would misdescribe both operation types.

### Keeping mutations as `remote` methods and renaming only the query accessor

A smaller change: `get` → `query`, mutations stay `remote`. **Rejected.** It fixes the weaker of the two problems and leaves the stronger one. It also leaves the `graphql:Upload` restriction expressed against method kind rather than operation type, and leaves `remote` meaning two different things inside the package (mutation field, interceptor entry point).

### An annotation-based resolver model

`@graphql:Query`, `@graphql:Mutation`, `@graphql:Subscription` on plain methods, following Spring for GraphQL and HotChocolate directly. **Rejected.** Annotations are metadata in Ballerina, whereas the method kind and accessor are part of the declaration that the compiler and the language server reason about natively. Spring and HotChocolate use annotations because Java and C# have no resource-method concept; Ballerina does.

## Testing

Fixture-level test obligations are for implementation, not this document. The coverage categories this proposal needs:

- **Resolver model, whichever approach ships.** The new duplicate-field-declaration check (`GRAPHQL_1012`) needs positive and negative fixtures covering the cross-family collision: `get`/`query` on the same path, and under Approach B also `remote`/`mutate` on the same name. Mutation-serial and query-parallel execution must remain unaffected, since they key off the document's operation type, not the method kind. Every field, including nested-object fields, must still resolve to the correct method through the dispatch structure the [GraphQL Compile-Time Dispatch BEP](1472_graphql_compile_time_dispatch.md) ([#1472](https://github.com/ballerina-platform/ballerina-spec/issues/1472)) specifies, whichever accessor spelling declared it.
- **Migration tool (Approach A only).** Its own coverage, separate from the resolver-model fixtures above: corpus coverage against the existing fixture set, hierarchical-path sites flagged rather than silently rewritten, idempotency on already-migrated input, and correct handling of partially-migrated input.

## Risks and Assumptions

### Risks

- **Approach A and Approach B carry different risk profiles — see the comparison table in [Section 4](#4-comparison-the-decision-this-proposal-does-not-make) rather than a restatement here.** The largest open risk in this proposal is that the decision has not been made yet.
- **AI coding assistants have been trained on the current `get`/`remote` pattern.** Under Approach A the mitigation is simple: an old-form suggestion fails to compile. Under Approach B the risk is larger, because an old-form suggestion compiles with only a warning, for the whole open-ended deprecation window. Mitigations, in order of leverage: refresh `examples/`, the specification, and Ballerina by Example promptly, so new material shows only the recommended forms under either approach; investigate whether specific diagnostics can be promoted to build failures for teams that want to self-enforce under Approach B; and, under Approach A, rely on the new diagnostics (`GRAPHQL_1013` and others) failing the build.

### Assumptions

- **`query`, `mutate`, and `subscribe` are usable as resource accessors with no language change.** Confirmed — see [Section 1](#1-shared-the-three-accessors).
- **The runtime's argument-binding path does not care whether a mutation is bound via a resource method or a remote method.** This matters under either approach, since both add `mutate`. Not yet verified.
- **Serial mutation execution is unaffected**, because it keys off the document's operation type, not the Ballerina method kind. Verified against the current execution logic.
- **Ballerina's package-resolution behaviour regarding two major versions of one package** is a **reported claim requiring verification** in [Section 4](#4-comparison-the-decision-this-proposal-does-not-make)'s comparison table, not confirmed fact. Verify it before using it as a decision input.

## Dependencies

- **[GraphQL Compile-Time Dispatch BEP](1472_graphql_compile_time_dispatch.md) ([#1472](https://github.com/ballerina-platform/ballerina-spec/issues/1472)).** A hard dependency under both approaches. Its compile-time-resolved dispatch table is where [Section 2](#2-shared-the-two-cross-cutting-rules-the-new-model-requires)'s two cross-cutting rules are enforced. It is also what makes Approach B viable: the table makes the number of accessor spellings a field can have irrelevant to per-request dispatch cost, so supporting `get`/`remote` and `query`/`mutate` at once costs nothing on the hot path. Without it, the earlier objection to dual-accessor support (see [Alternatives](#dual-accessor-support-during-a-deprecation-window)) stands and only Approach A is available.
- **[GraphQL Diagnostic Code Convention BEP](1471_graphql_diagnostic_code_convention.md) ([#1471](https://github.com/ballerina-platform/ballerina-spec/issues/1471)).** Supplies every `GRAPHQL_nnnn` number this proposal cites, including the new `GRAPHQL_1012` and, by approach, `GRAPHQL_1013` (A) or `GRAPHQL_2001`/`GRAPHQL_2002` (B).
- **A migration tool for the resolver change** — a hard release dependency under Approach A only; parked, tracked as [Future Work](#future-work), under Approach B.
- **`bal graphql` tool updates** for service and client generation — a hard release dependency under Approach A; a soft/quality dependency under Approach B.

## Future Work

- **A decision between Approach A and Approach B**, and, if Approach B is chosen: a target release for eventually removing `get`/`remote`, and a migration tool built ahead of that release rather than left indefinitely deferred.
- **User-declarable `Query`/`Mutation`/`Subscription` root type names**, via the service-typing proposal ([ballerina-library#4620](https://github.com/ballerina-platform/ballerina-library/issues/4620)).

> **Resolved, not deferred.** Under Approach A, the two long-standing TODOs in the hierarchical-path result-assembly code are removed as a side effect of removing hierarchical paths. Under Approach B, they remain live, tracked against whichever future release removes `get`.

## References

### Specifications

- [GraphQL specification, September 2025 edition](https://spec.graphql.org/September2025/)
- [GraphQL over HTTP specification (draft)](https://graphql.github.io/graphql-over-http/draft/) and [version index](https://graphql.github.io/graphql-over-http/)
- [Ballerina language specification](https://ballerina.io/spec/lang/master/)

### Comparable libraries

- [Spring for GraphQL — Annotated Controllers](https://docs.spring.io/spring-graphql/reference/controllers.html)
- [HotChocolate — Defining a schema](https://chillicream.com/docs/hotchocolate/v15/defining-a-schema/)
- [HotChocolate — Mutations](https://chillicream.com/docs/hotchocolate/v15/defining-a-schema/mutations/)
- [Apollo Server — Federated subgraph setup](https://www.apollographql.com/docs/apollo-server/using-federation/apollo-subgraph-setup)
- [gqlgen — chat example resolvers](https://github.com/99designs/gqlgen/blob/master/_examples/chat/resolvers.go)

### Ballerina

- [Ballerina GraphQL module specification](https://github.com/ballerina-platform/module-ballerina-graphql/blob/master/docs/spec/spec.md)
- [ballerina-library discussion #757 — "Accessors in GraphQL Resources"](https://github.com/ballerina-platform/ballerina-library/discussions/757) — the 2021 discussion where the team first moved toward `query`/`mutation`/`subscription` accessors, and where `remote` was chosen for mutations instead
- [ballerina-library#4620](https://github.com/ballerina-platform/ballerina-library/issues/4620) — decoupling GraphQL API development from API design (service typing); see [Root type naming](#root-type-naming) and [Future Work](#future-work)
- [Ballerina by Example — GraphQL service](https://ballerina.io/learn/by-example/graphql-service/) and supplementary guide material such as [`graphql-guide`](https://github.com/ThisaruGuruge/graphql-guide) — all carry the current resolver forms and are in scope for the documentation sweep the release plans track

[]: # (end)
[]: # Please add any comments to issue [#1473](https://github.com/ballerina-platform/ballerina-spec/issues/1473)
