# GraphQL September 2025 Specification Alignment

- Authors
  - Thisaru Guruge
- Reviewed by
  - Danesh Kuruppu
- Created date
  - 2026-08-14
- Updated date
  - 2026-08-17
- Issue
  - [1475](https://github.com/ballerina-platform/ballerina-spec/issues/1475)
- State
  - Submitted

## Summary

The Ballerina GraphQL package is a mature implementation of the [October 2021 edition](https://spec.graphql.org/October2021/) of the GraphQL specification. This proposal brings it up to the [September 2025 edition](https://spec.graphql.org/September2025/). It implements `@oneOf` and `@deprecated` on `ARGUMENT_DEFINITION` and `INPUT_FIELD_DEFINITION` — both ratified in that edition, and the package actively rejects the second today. It sets the direction for user-definable custom scalars and `@specifiedBy` without designing the API here. It aligns the listener with the companion [GraphQL over HTTP](https://graphql.github.io/graphql-over-http/draft/) draft on response media type and status codes. The unifying theme is specification conformance, which is what makes these four items one proposal. Three are directive-surface gaps against a single ratified edition. The fourth, over-HTTP alignment, is a media-type and status-code concern rather than a directive, but GraphQL over HTTP belongs to the same specification family and the same conformance gap. This proposal is independent of the [GraphQL Unified Resolver Model BEP](1473_graphql_unified_resolver_model.md) ([#1473](https://github.com/ballerina-platform/ballerina-spec/issues/1473)) and unaffected by which approach ships there, so this work can proceed while the resolver-model decision is still open.

## Motivation

The September 2025 edition ratified two directives the package does not have. `@oneOf` gives GraphQL a first-class way to express "exactly one of these inputs", which Ballerina has never had: the package rejects input unions other than `T|()`, and the Ballerina GraphQL specification records "Input Unions" as a known gap. `@deprecated` on arguments and input fields is worse than absent. The compiler plugin emits a warning telling the user the construct is unsupported, so a schema author who wants to retire an argument has no supported way to signal it. `@specifiedBy` is the third ratified directive the package lacks, and it is unimplementable for a structural reason rather than a scheduling one: it attaches a specification URL to a custom scalar, and there is no user-definable custom scalar mechanism. That mechanism is the largest remaining type-system gap in the package, large enough to need its own BEP, so this proposal fixes the direction and stops there. Separately, the listener predates the GraphQL over HTTP work and does not implement its response media type or its status-code guidance. That specification is still a Stage 2 draft, so the response is bounded alignment rather than a conformance claim.

## Goals

- Implement the directives ratified in the September 2025 edition of the GraphQL specification that the package currently lacks or rejects: `@oneOf`, and `@deprecated` on arguments and input fields.
- Establish the direction for user-definable custom scalars, the largest remaining type-system gap, without designing the full API in this proposal.
- Align the listener's response media type and status codes with the GraphQL over HTTP draft, as a bounded and separable work item.

## Non-Goals

- **The full custom scalar API.** Direction only in this proposal; the API belongs in a dedicated custom scalar BEP.
- **`@defer` / `@stream`.** Incremental delivery is at Stage 2 (experimental) in the GraphQL specification process and has no ratified response format ([graphql-spec #1018](https://github.com/graphql/graphql-spec/pull/1018), [graphql-js defer/stream docs](https://www.graphql-js.org/docs/defer-stream/)). Deferred to [Future Work](#future-work).
- **Conformance to the GraphQL over HTTP specification.** [Section 4](#4-graphql-over-http-alignment) proposes alignment with a Stage 2 draft that "may continue to evolve", not conformance to a ratified specification.

## Current State Analysis

This section records the behaviour that [Design](#design) changes, sourced from the package at `ballerina/graphql` v1.18.0 (distribution `2201.13.3`). Diagnostic codes named here are the numbers the package emits today. The [GraphQL Diagnostic Code Convention BEP](1471_graphql_diagnostic_code_convention.md) ([#1471](https://github.com/ballerina-platform/ballerina-spec/issues/1471)) renumbers them, and the Design sections below cite the post-renumbering numbers.

### Directives and type system

Supported directives: `@skip`, `@include` (executable), and `@deprecated` (type system). Gaps against the [September 2025 edition of the GraphQL specification](https://spec.graphql.org/September2025/):

- **`@oneOf`** — ratified in the September 2025 edition ([announcement](https://graphql.org/blog/2025-09-08-september-edition/), [background](https://graphql.org/blog/2025-09-04-multioption-inputs-with-oneof/)). Not implemented. Related: the package rejects input unions other than `T|()` (`GRAPHQL_122`, renumbered `GRAPHQL_1115`), and the specification records "Input Unions" as a known gap.
- **`@deprecated` on `ARGUMENT_DEFINITION` and `INPUT_FIELD_DEFINITION`** — also ratified in the September 2025 edition. The package _actively rejects_ this today with warning `GRAPHQL_201` (renumbered `GRAPHQL_2601`).
- **`@specifiedBy`** — not implemented, and not implementable without custom scalars.

There is **no user-definable custom scalar mechanism**. `ScalarType` is a closed Java enum, and the usual workaround — aliasing a primitive — is rejected by `GRAPHQL_139` (renumbered `GRAPHQL_1120`). `map<T>` and `json` are absent from both the return-type and input-type validator switches and so fall through to `GRAPHQL_102`; `table<T>` is supported on output only.

### GraphQL over HTTP conformance

The listener accepts three request content types today: `application/json`, `application/graphql`, and `multipart/form-data`. It does not handle the `application/graphql-response+json` response media type and does no `Accept` header negotiation. The GraphQL over HTTP specification is at Stage 2 (draft) and "may continue to evolve", so alignment is proposed as a separable item rather than as a conformance requirement.

## Design

### 1. `@oneOf`

`@oneOf` was ratified in the September 2025 edition of the GraphQL specification. It marks an input object as accepting exactly one of its fields, and every field of a `@oneOf` input object must be nullable and must not have a default value. The Ballerina mapping is an input record annotated `@graphql:OneOf`, all of whose fields are optional and nilable. The annotation is new public API:

```ballerina
# NEW — marks an input record as a GraphQL @oneOf input object.
# Every field must be optional, nilable, and without a default value.
public annotation OneOf on type;
```

```ballerina
@graphql:OneOf
public type ProductLookup record {|
    string? id?;
    string? sku?;
    string? upc?;
|};

service on new graphql:Listener(9090) {
    resource function query product(ProductLookup by) returns Product? { ... }
}
```

Generated schema:

```graphql
input ProductLookup @oneOf {
  id: String
  sku: String
  upc: String
}
```

Enforcement is split between compile time and request time. The request-time check completes **before the engine resolves any field**, not only when the `@oneOf` argument's own field would have been resolved:

- **Compile time** (`GRAPHQL_1601`, `INVALID_ONEOF_FIELD`) — every field of a `@graphql:OneOf` record must be optional and nilable, and must not carry a default value. Violations are compile errors.
- **Request time** — a `@oneOf` argument supplied as a literal in the document is checked during document validation, alongside the existing field, variable, directive, and fragment validation. One supplied through a variable is checked during variable coercion. The specification requires both to complete before execution starts. Either path rejects an argument that supplies zero fields, more than one field, or exactly one field with an explicit `null` value, with the error the specification prescribes in each case. Because both checks run before execution, a malformed `@oneOf` argument anywhere in the document fails the whole request up front, and no field is partially resolved first.

This also gives Ballerina a usable input-union idiom for the first time. The existing restriction that input unions may only be `T|()` (`GRAPHQL_1115`) is unchanged; `@graphql:OneOf` is the supported way to express "one of several inputs". The specification's note on input unions is updated to point at `@oneOf`. A `@oneOf` field's type is not limited to scalars. It can be any valid GraphQL input type, including another input object, as the [September 2025 edition of the GraphQL specification](https://spec.graphql.org/September2025/)'s own example does:

```ballerina
public type OrganizationAndEmailInput record {|
    string organizationId;
    string email;
|};

@graphql:OneOf
public type UserUniqueCondition record {|
    @graphql:ID string? id?;
    string? username?;
    OrganizationAndEmailInput? organizationAndEmail?;
|};

service on new graphql:Listener(9090) {
    resource function query user(UserUniqueCondition condition) returns User? {
        string? id = condition.id;
        string? username = condition.username;
        OrganizationAndEmailInput? organizationAndEmail = condition.organizationAndEmail;

        if id is string {
            return getUserById(id);
        } else if username is string {
            return getUserByUsername(username);
        } else if organizationAndEmail is OrganizationAndEmailInput {
            return getUserByOrgAndEmail(organizationAndEmail);
        }
        return ();
    }
}
```

which generates:

```graphql
input UserUniqueCondition @oneOf {
    id: ID
    username: String
    organizationAndEmail: OrganizationAndEmailInput
}
```

`OrganizationAndEmailInput` is an ordinary input type: it does not itself carry `@graphql:OneOf`. Like every other field on a `@oneOf` record, it is compile-time-valid here only because it is optional and nilable (`OrganizationAndEmailInput?`, not `OrganizationAndEmailInput`). The same `GRAPHQL_1601` check and coercion-time rule apply whether a field's type is a scalar or an input object.

### 2. `@deprecated` on arguments and input fields

The September 2025 edition extends `@deprecated` to `ARGUMENT_DEFINITION` and `INPUT_FIELD_DEFINITION`. The package currently emits warning `GRAPHQL_2601` telling the user this is unsupported. The warning is removed and the directive is emitted into the schema for a resolver parameter or input-object record field carrying Ballerina's `@deprecated` annotation. A deprecated argument or input field must be optional: a required deprecated input is a contradiction and is a **new compile error** (`GRAPHQL_1602`, `INVALID_REQUIRED_DEPRECATED_INPUT`). The existing `# # Deprecated` documentation-section convention supplies the `reason`. **This is a new source of compile breaks:** a service that carries Ballerina's `@deprecated` annotation on a _required_ resolver argument or input field compiles today, because `GRAPHQL_2601` is only a warning. Under this change it becomes a compile error, since the specification does not allow a required deprecated input. It should be rare — deprecating a required input is unusual practice — and it is independent of anything in the [GraphQL Unified Resolver Model BEP](1473_graphql_unified_resolver_model.md) ([#1473](https://github.com/ballerina-platform/ballerina-spec/issues/1473)).

|         | For shipping as a compile error | Against |
| ------- | ------------------------------- | ------- |
| **Pro** | The situation being rejected is a contradiction, not a stylistic preference: the specification defines `@deprecated` on a required input as invalid, so accepting it would mean emitting a schema element the spec disallows. Catching it at compile time beats emitting a bad schema. | — |
| **Con** | It is a new way for existing (if unusual) code to stop compiling. | Affected code is rare enough — deprecating a required field appears nowhere in the package's own examples — that softening this into a warning would mostly delay a fix the user needs to make anyway. |

This proposal ships it as a compile error, as designed. The migration is mechanical and affects one class of call site: `@deprecated` on a required argument or input field fails to compile, and the fix is to make the input optional or to drop the deprecation.

### 3. Custom scalars and `@specifiedBy`: direction only

`@specifiedBy` attaches a specification URL to a custom scalar, so it is not implementable while `ScalarType` remains a closed enum. Custom scalars are the largest remaining type-system gap: there is no mechanism to define one, and the conventional workaround of aliasing a primitive is rejected by `GRAPHQL_1120` (`UNSUPPORTED_TYPE_ALIAS`). The consequences reach further than they first appear. It is why `json` and `map<T>` are unusable in a schema, why `Decimal` had to be special-cased into the built-in enum, and why domain types such as `DateTime`, `URL`, or `EmailAddress` cannot be expressed. The intended direction, to be designed in a dedicated custom scalar BEP:

- A user declares a custom scalar by annotating a type definition with a scalar configuration that supplies a coercion pair — a function from the wire representation to the Ballerina value and back — plus an optional specification URL that becomes `@specifiedBy`.
- `ScalarType` stops being a closed enum in `commons`; the schema model carries user-defined scalars alongside the built-ins.
- `GRAPHQL_1120` is narrowed: aliases over primitives become the _mechanism_ for declaring a custom scalar rather than an error.

This proposal stops at direction.

### 4. GraphQL over HTTP alignment

The listener accepts `application/json`, `application/graphql`, and `multipart/form-data` request content types, does not emit `application/graphql-response+json`, and performs no `Accept` header negotiation. The GraphQL over HTTP specification remains at Stage 2 (draft), so this proposal treats alignment as a bounded, separable work item, not a conformance requirement:

- Emit `application/graphql-response+json` when the request's `Accept` header indicates it, falling back to `application/json` otherwise.
- Follow the draft's status-code guidance for well-formed-but-invalid documents under each response media type.

> **Open item for review.** Whether the current draft still permits `application/graphql` as a _request_ content type must be confirmed against the draft at implementation time before the existing behaviour is changed or removed.

## Alternatives

### Full custom scalar design in this proposal

**Rejected for scope**, per [Section 3](#3-custom-scalars-and-specifiedby-direction-only).

### Implementing `@defer` / `@stream` now

**Rejected.** Stage 2 (experimental), response format still under active revision across competing RFCs.

## Testing

`@oneOf` needs schema-output, compile-error, and coercion-error coverage (zero, two, and exactly-one-with-explicit-null field cases, plus introspection). Argument/input-field `@deprecated` needs schema-output coverage and the new required-input compile error.

## Risks and Assumptions

### Risks

- **The new compile error in [Section 2](#2-deprecated-on-arguments-and-input-fields) is a narrow source of compile breaks.** Everything else in this proposal is additive. `@deprecated` on a required argument or input field compiles today under a warning and stops compiling under this change. The for/against analysis and the decision to ship it as designed are in that section.

### Assumptions

- **`@oneOf` and `@deprecated` on arguments and input fields are ratified**, per the September 2025 edition of the GraphQL specification. The exact normative text must be read against [spec.graphql.org/September2025](https://spec.graphql.org/September2025/) at implementation time.
- **The GraphQL over HTTP draft is a moving target.** [Section 4](#4-graphql-over-http-alignment) is scoped as alignment with a Stage 2 draft, not conformance to a ratified specification.

## Dependencies

- **[GraphQL Diagnostic Code Convention BEP](1471_graphql_diagnostic_code_convention.md) ([#1471](https://github.com/ballerina-platform/ballerina-spec/issues/1471)).** Supplies the code numbers this proposal uses: `GRAPHQL_1601` (`INVALID_ONEOF_FIELD`) and `GRAPHQL_1602` (`INVALID_REQUIRED_DEPRECATED_INPUT`) are new codes allocated there, and `GRAPHQL_2601` (`UNSUPPORTED_INPUT_FIELD_DEPRECATION`) is the renumbered code this proposal removes on delivery.
- **[GraphQL Client-Side Schema Validation BEP](1476_graphql_client_schema_validation.md) ([#1476](https://github.com/ballerina-platform/ballerina-spec/issues/1476)) — a forward dependency this proposal creates rather than one it depends on.** That BEP's `SCHEMA` validation tier reuses [Section 1](#1-oneof)'s `@oneOf` validation rule, so a client rejects a malformed literal `@oneOf` argument with the same error the listener would. Its SDL parser must carry the `@oneOf` directive through onto an input object type definition for that reuse to work. The two are not independent, and `@oneOf` must land first.
- **A dedicated custom scalar BEP** — likewise a forward dependency this proposal creates, per [Section 3](#3-custom-scalars-and-specifiedby-direction-only).
- **No dependency on the [GraphQL Unified Resolver Model BEP](1473_graphql_unified_resolver_model.md) ([#1473](https://github.com/ballerina-platform/ballerina-spec/issues/1473)).** Nothing here is affected by which approach ships there, and this work can be implemented and released while that decision is open.

## Future Work

- **Custom scalars** — the full API, per the direction in [Section 3](#3-custom-scalars-and-specifiedby-direction-only). Unblocks `@specifiedBy`, a `JSON` scalar, and domain scalars such as `DateTime` and `URL`.
- **`@defer` / `@stream`**, once incremental delivery reaches Stage 3 and the response format is settled.
- **Schema coordinates**, ratified in the September 2025 edition, as an addressing scheme for diagnostics, tracing, and cache invalidation.

## References

### Specifications

- [GraphQL specification, September 2025 edition](https://spec.graphql.org/September2025/)
- [Announcing the September 2025 Edition of the GraphQL Specification](https://graphql.org/blog/2025-09-08-september-edition/)
- [Safer Multi-option Inputs with `@oneOf`](https://graphql.org/blog/2025-09-04-multioption-inputs-with-oneof/)
- [GraphQL specification, October 2021 edition](https://spec.graphql.org/October2021/)
- [GraphQL over HTTP specification (draft)](https://graphql.github.io/graphql-over-http/draft/) and [version index](https://graphql.github.io/graphql-over-http/)

### Incremental delivery (for the deferral rationale)

- [Enabling Defer and Stream — GraphQL.js](https://www.graphql-js.org/docs/defer-stream/)
- [graphql-spec #1018 — Alternative proposal for `@stream`/`@defer`](https://github.com/graphql/graphql-spec/pull/1018)
- [graphql-spec #1023 — Incremental delivery without branching](https://github.com/graphql/graphql-spec/pull/1023)
- [graphql-spec #1026 — Incremental delivery with deduplication](https://github.com/graphql/graphql-spec/pull/1026)

### Ballerina

- [BEP process](../AAA-bep-resources/0000_bep_process.md)
- [Ballerina GraphQL module specification](https://github.com/ballerina-platform/module-ballerina-graphql/blob/master/docs/spec/spec.md)
- [Ballerina GraphQL accepted proposals](https://github.com/ballerina-platform/module-ballerina-graphql/tree/master/docs/proposals)

[]: # (end)
[]: # Please add any comments to issue [#1475](https://github.com/ballerina-platform/ballerina-spec/issues/1475)
