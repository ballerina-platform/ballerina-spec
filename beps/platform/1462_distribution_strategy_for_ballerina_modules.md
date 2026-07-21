# 1462: Distribution Strategy for `ballerina/*` Modules

- Authors
  - Niveathika Rajendran
  - Thisaru Guruge
- Reviewed by
  - Shafreen Anfar
  - Sameera Jayasoma
- Created date
  - 2026-07-20
- Updated date
  - 2026-07-20
- Issue
  - [1462](https://github.com/ballerina-platform/ballerina-spec/issues/1462)
- State
  - Submitted

## Summary

This proposal separates two decisions that are currently conflated: which organization a standard module is published under (`ballerina` vs. `ballerinax`), and which packages are bundled into the core Ballerina distribution (installer).
The first decision has so far been applied only informally, with no documented criteria; this proposal formally defines it.
The second decision has so far defaulted to "every `ballerina/*` module ships in the distribution"; this proposal changes that default so that new `ballerina/*` modules are published Central-first, and are only bundled into the distribution if they are foundational to most integration use cases.
Modules that address a narrower, specialized need (e.g. `smb`, `xlsx`) remain Central-only, the same way `ballerinax/*` connectors are today.
This proposal also calls for a one-time audit of currently bundled modules to identify existing candidates for removal in a future distribution release, and defines who decides classification and how a Central-only module can later be promoted into the distribution.

## Motivation

The Ballerina distribution has historically followed an "all-in" policy: every module published under the `ballerina` organization is packed into the core installer, regardless of how broadly applicable it is.
This made sense when the module count was small and closely aligned with core use cases.

As the standard module set grows — most recently with the `smb` and `xlsx` modules — this policy increases the size and maintenance surface of the distribution with modules that most integration use cases will never touch.
`ballerinax/*` connectors already avoid this problem by being Central-only; `ballerina/*` modules have no equivalent lightweight path.

This proposal formalizes a distribution policy that keeps the core installer lean while still giving every user full access to every `ballerina/*` module through Ballerina Central.

## Goals

- Formally define, for the first time, the criteria that distinguish a `ballerina` module from a `ballerinax` module.
  This distinction is applied today, but only informally and by convention; it is not documented anywhere.
- Keep the core distribution focused on modules that are broadly needed across most integration use cases.
- Default new, specialized `ballerina/*` modules to Central-only publishing instead of bundling them into the distribution.
- Define who decides a new module's org and bundling classification, and how disagreements are resolved.
- Establish a one-time audit of already-bundled `ballerina/*` modules to identify candidates that could move to Central-only in a future distribution release.
- Define how a Central-only module can later be promoted into the distribution based on adoption.

## Non-Goals

- Retroactively reclassifying or renaming any already-published module under the newly documented `ballerina`/`ballerinax` definition.
  This proposal documents the rule going forward; it does not audit or rename existing packages against it.
- Changing how `ballerinax/*` connectors are distributed today — they are already Central-only.
- Defining a fixed, numeric rubric for "foundational" vs. "specialized" `ballerina/*` modules.
  This proposal deliberately keeps that classification a case-by-case judgment call rather than a scorecard.
- Committing to specific adoption-metric thresholds or a fixed review cadence for promoting a module into the distribution.
  This proposal defines the process, not the numbers.
- Actually removing any currently bundled module as part of this proposal.
  The audit only identifies candidates; actual removal is tracked separately.

## Design

This proposal makes two separate classification decisions explicit.
The first decides which organization a module is published under (`ballerina` vs. `ballerinax`).
The second, which only applies within `ballerina/*`, decides whether the module ships inside the core distribution or is Central-only.
The two decisions are independent: a module's org is never decided by whether it ships inside the installer, and its distribution placement is never decided by which org it happens to be published under.

### 1. Defining `ballerina` vs. `ballerinax`

This distinction is applied today, but only by informal convention — there is no documented rule anywhere in the platform's specs or contributor guides.
This proposal formally defines it as follows.

A module belongs to **`ballerina`** when it implements functionality defined by an open specification, protocol, or file format, or when it is a fundamental, cross-cutting platform utility needed regardless of integration domain (e.g. `log`, `io`, `time`, `crypto`).
In both cases, the module's usefulness does not depend on any single vendor's product, account, or proprietary API surface remaining available.

A module belongs to **`ballerinax`** when it exists specifically to integrate with a particular third-party vendor's product, platform, or proprietary API — i.e. its functionality is defined by what that one vendor exposes, not by an independent, vendor-neutral specification.

A simple decision test: if the vendor most associated with the underlying protocol or format disappeared, would the module still make sense because other, independent implementations exist?
If yes, it belongs under `ballerina`.
If the module would stop making sense because it only exists to call one vendor's proprietary API, it belongs under `ballerinax`.

| Module                         | Org          | Why                                                                                                           |
| ------------------------------ | ------------ | ------------------------------------------------------------------------------------------------------------- |
| `http`, `grpc`                 | `ballerina`  | IETF/open RPC protocols, implemented by many independent parties                                              |
| `smb`                          | `ballerina`  | Open network file-sharing protocol, implemented by Samba, Windows, macOS, and others — not tied to one vendor |
| `xlsx`                         | `ballerina`  | Office Open XML is an ISO/IEC 29500 file-format standard, not a proprietary API                               |
| `log`, `io`, `crypto`, `regex` | `ballerina`  | Core, cross-cutting platform utilities, independent of any vendor                                             |
| `salesforce`, `twilio`         | `ballerinax` | Exist only to call one vendor's proprietary REST/SOAP API                                                     |
| `googleapis.gmail`, `aws.s3`   | `ballerinax` | Exist only to call one vendor's proprietary API                                                               |

A module's org classification is proposed by the Ballerina Connector team when the module's own proposal is authored, with the Lead Architect (or Architecture Group, if delegated) making the final call on disputed or ambiguous cases — for example, a format that originated with a single vendor but has since been standardized and is implemented independently by others.

### 2. Distribution bundling within `ballerina/*`

**New `ballerina/*` modules default to Central-only.**
A new module is bundled into the distribution only if it is judged foundational — i.e. broadly relevant across most integration use cases (illustrative existing examples: `http`, `io`, `log`, `graphql`, `mime`).
A module that addresses a narrower need (illustrative examples: `smb`, `xlsx`) is published to Ballerina Central only, the same way a `ballerinax` connector is today.

**Classification is case-by-case, not rubric-driven.**
There is no fixed scoring formula for "foundational" vs. "specialized."
Each new module is classified individually, using the same governance as the org classification above: the Ballerina Connector team proposes the classification when the module's own proposal/BEP is authored, and the Lead Architect makes the final call when it is disputed or unclear.

**Audit of existing bundled modules.**
As a one-time exercise, currently bundled `ballerina/*` modules are reviewed using the same case-by-case judgment to flag modules that, in hindsight, are specialized rather than foundational.
Flagged modules become candidates for removal from the distribution in a future release.
This proposal only establishes the audit and the candidate list; actual removal requires its own removal notice, since it might be a breaking change for users currently relying on implicit availability.

**Promotion path: Central-only to bundled.**
A Central-only module that's being published under the `ballerina` organization can be promoted into the distribution later.
There is no fixed metric or threshold.
Promotion is triggered ad hoc by a combination of signals — Ballerina Central download/usage trends and qualitative demand (community requests, partner asks, issue volume) — raised by the Ballerina Connector team or the Architecture Group.
The same governance as classification applies: the Connector team proposes, the Architect approves.

**No tooling or runtime changes required.**
Dependency resolution already falls back to Ballerina Central when a package is not found in the local distribution repository (see [Ballerina Package Specification §5.3.1](../../packages/package-spec.md)).
A Central-only `ballerina/*` module resolves exactly like a `ballerinax/*` module does today, so no compiler, build tool, or resolution changes are needed.
The only practical implication is that users depending on a Central-only module need network access to Central at build time, the same constraint that already exists for `ballerinax` connectors today.
This should be called out in release notes as a known characteristic, not treated as a regression.

### Example walk-through

`smb` and `xlsx` are being finalized as this proposal is written.
Under this model:

- Both are classified as `ballerina` org modules (open protocol/format, not vendor-specific), per the test above.
- Within `ballerina/*`, both are classified as specialized (a file-transfer protocol and a spreadsheet format respectively, each relevant to a subset of integration use cases) and are therefore published to Ballerina Central only.
- Neither is included in the core distribution installer at release.
- If adoption data and/or user demand later shows they are broadly needed, the Connector team can propose promoting them into a future distribution release, subject to the Architect's approval.

## Alternatives

- **Status quo ("all-in" bundling).**
  Rejected — the distribution's footprint grows with every new module regardless of how broadly applicable it is, and most users pay the cost (size, maintenance) for modules they will never use.
- **Fixed rubric with numeric thresholds for classification and promotion.**
  Considered, but rejected for this proposal.
  The module population and Central usage data are not yet mature enough to set meaningful numeric thresholds today, and a rigid rubric risks being wrong in ways that are hard to correct.
  Case-by-case judgment, with a clear final decision-maker, is preferred until more usage data exists.
  This can be revisited in a follow-up proposal.
- **Prior art:** [#1348 — Decouple bal tools from the distribution](../../bal-tools/proposals/idl-tool-decouple.md) solved an analogous problem for CLI tools (`bal openapi`, `bal graphql`, `bal grpc`, `bal persist`) by decoupling their release cadence from the distribution.
  This proposal applies the same underlying principle — the distribution should not have to contain everything — to `ballerina/*` standard modules.

## Testing

This is a process/policy change rather than a code change.
Validation is behavioral:

- Confirm a Central-only `ballerina/*` module resolves and builds correctly when absent from the local distribution repository, using the existing Central fallback resolution, no different from how a `ballerinax` connector resolves today.
- Confirm existing bundled modules are unaffected by this change.

## Risks and Assumptions

- **Risk:** Users who assume every `ballerina/*` module ships with the distribution will be surprised by a build-time Central dependency for new modules.
  Mitigation: call this out clearly in release notes for any new Central-only module.
- **Risk:** Without a fixed rubric, classification could feel inconsistent across modules over time.
  Mitigation: centralizing final decision authority with the Lead Architect keeps classification consistent even without a formula.
- **Risk:** Removing a module identified by the audit might be breaking, but only for users with no network access to Ballerina Central at build time.
  Even users behind a proxy can typically configure Central access, so this is a rare, niche scenario given the kind of integration use cases involved, not a general breaking change.
  Mitigation: mention the change in release notes and note that the removed packages need network access at build time to resolve.

## Dependencies

- Relies on the existing Ballerina Central fallback resolution behavior defined in the [Ballerina Package Specification](../../packages/package-spec.md), §5.3.1 (Platform distribution repository).
- Related prior art: [#1348 — Decouple bal tools from the distribution](../../bal-tools/proposals/idl-tool-decouple.md).

## Future Work

- A follow-up proposal could formalize concrete adoption-metric thresholds and a fixed review cadence for promotion, once enough Ballerina Central usage data exists for `ballerina/*` modules.
- The audit of existing bundled modules (see [Design](#design), "Audit of existing bundled modules") should produce a tracked list of candidate modules, most likely as a follow-up issue/checklist once this proposal is accepted.

## References

- [#1348 — Decouple bal tools from the distribution](../../bal-tools/proposals/idl-tool-decouple.md)
- [Ballerina Package Specification](../../packages/package-spec.md)

[]: # (end)
[]: # Please add any comments to issue [#1462]()
