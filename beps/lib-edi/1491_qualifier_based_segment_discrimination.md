# Qualifier-based segment discrimination for `ballerina/edi`

- Authors
  - Dilan Perera
- Reviewed by
  - Niveathika, Danesh Kuruppu
- Created date
  - 2026-09-03
- Issue
  - [#1491](https://github.com/ballerina-platform/ballerina-spec/issues/1491)
- State
  - Submitted

## Summary

EDI formats reuse one segment code for entries that mean different things and rely on a small qualifier value to identify each one. The Ballerina EDI schema cannot record those qualifier values, so the parser matches segments by segment code and schema order alone. When an optional entry is absent, the next segment carrying the same code is silently assigned to it, producing wrong data with no error.

This proposal adds two optional attributes — `values` and `discriminator` — to fields, components, and sub-components of a segment definition. `values` records the legal codes of an element and is validated when writing EDI. `discriminator` records the codes that identify a definition and takes part in segment matching. It also defines the matching semantics, the rules enforced when a schema is loaded, and how segment definitions shared across positions are specialized.

Please add any comments to issue [#1491](https://github.com/ballerina-platform/ballerina-spec/issues/1491).

## Goals

- Allow a schema to state which qualifier values identify a segment definition, at whatever depth the value lives.
- Let an optional definition be recognised as *absent* rather than absorbing the next same-code segment.
- Define what happens when no definition matches, when several match, and when the identifying value is missing.
- Keep schemas that do not use the attributes byte-for-byte identical in behaviour.
- Allow schema-generation tools to attach standard code lists without changing how existing messages parse.

## Non-Goals

- Intra-segment relational rules (X12 syntax notes `P`/`R`/`E`/`C`/`L`, EDIFACT dependency notes `D1`–`D7`).
- Mutual exclusion between definitions (`xs:choice`).
- Structural matching, such as requiring that earlier mandatory units were satisfied before a definition may match.

These are separate concerns that this proposal deliberately leaves to later work; none of them is blocked by the design below.

## Motivation

An X12 834 member loop defines three entries that all use the segment code `REF`, distinguished only by the qualifier in `REF01`:

| Definition | Code | Qualifier | Occurrence |
| --- | --- | --- | --- |
| `SubscriberIdentifier` | `REF` | `0F` | required |
| `MemberPolicyNumber` | `REF` | `1L` | **optional** |
| `MemberSupplementalIdentifier` | `REF` | `17`, `23`, `DX`, … | up to 13 |

A file in which the optional policy number is absent is perfectly valid:

```edi
REF*0F*110011113~
REF*17*Bargained~
REF*DX*1018~
```

At the optional `MemberPolicyNumber` entry the parser must decide whether the next segment belongs to it or whether the entry is absent from this file. Comparing only the segment code, every `REF` answers yes:

```json
"SubscriberIdentifier": {
    "REF01__ReferenceIdentificationQualifier": "0F",
    "REF02__SubscriberIdentifier": "110011113"
},
"MemberPolicyNumber": {
    "REF01__ReferenceIdentificationQualifier": "17",
    "REF02__MemberGroupOrPolicyNumber": "Bargained"
},
"MemberSupplementalIdentifier": [
    {"REF01__ReferenceIdentificationQualifier": "DX", "REF02__MemberSupplementalIdentifier": "1018"}
]
```

No error is raised. A bargaining-unit label is read as a policy number, and the same segment lands in a different field depending on whether an unrelated segment is present. This was reported by a user processing 834 enrolment files (ballerina-platform/ballerina-library#9100).

The information needed to resolve this exists in the source schemas — X12 XSDs carry `xs:enumeration` restrictions per position and EDIFACT directories carry code lists — but the EDI schema has nowhere to hold it, so the generators discard it.

The same shape appears in the other formats the library supports. In EDIFACT the qualifier sits one level deeper, inside a composite element (`RFF` / `C506`), so any rule that can only name whole fields cannot express it at all. EDIFACT- and ESL-generated schemas add a further constraint: they define each segment once in `segmentDefinitions` and reference it from many positions, so a rule placed on the definition cannot differ per position.

## Design

### Schema attributes

Two optional attributes are added to `EdiFieldSchema`, `EdiComponentSchema`, and `EdiSubcomponentSchema`:

| Attribute | Type | Meaning | When it applies |
| --- | --- | --- | --- |
| `values` | `string[]?` | The legal codes of the element | Validated when **writing** EDI. Never affects segment matching |
| `discriminator` | `string[]?` | The codes that **identify** this definition | Used when **matching** segments, and validated when writing |

```json
{
    "code": "REF",
    "tag": "MemberPolicyNumber",
    "minOccurances": 0,
    "fields": [
        {"tag": "code"},
        {"tag": "qualifier", "required": true, "discriminator": ["1L"]},
        {"tag": "identifier", "required": true}
    ]
}
```

Both attributes are optional and carry no default, so a schema that uses neither serialises exactly as before and continues to load on runtime versions that predate them.

Because `values` never affects matching, a generator may attach a full standard code list — the X12 code list for element 128 holds roughly 1,700 codes — without changing how any existing message parses. Routing changes only where a `discriminator` is declared. An element may carry both, which is the common real-world shape: `values` records what the element legally allows, `discriminator` the narrower set an implementation guide permits at that position.

```json
{"tag": "qualifier", "values": ["0F", "1L", "17", "23", "DX"], "discriminator": ["1L"]}
```

### Matching semantics

An input segment is an instance of a definition when its segment code matches **and**, for every element of that definition declaring a `discriminator`, the corresponding input value is present and contained in that element's set.

- A **missing or empty** discriminator value never matches. A segment that does not carry its identity cannot claim a discriminated definition.
- When a segment matches **no** definition at the current schema position, parsing fails with an error naming the segment. An optional discriminated definition is correctly recognised as absent and skipped.
- When **several** definitions could match, the first in schema order wins. The schema loader logs a warning when sibling definitions sharing a segment code have overlapping discriminator sets.

A run of **consecutive definitions sharing one segment code, each declaring at least one discriminator**, is matched as an **unordered set**: while input segments carry the run's code, every member that can still accept an occurrence is tried in schema order, so occurrences may arrive in any order and interleave. This is required because implementation guides do not fix an order among same-code entries — HIPAA schemas mark such groups as any-order, and EANCOM interleaves `ALC+A` and `ALC+C` occurrences.

Occurrence bounds within a run are as follows.

- A member is offered an input segment only while it can still accept one, so `maxOccurances` is enforced exactly: an occurrence beyond a member's maximum is not assigned to it and falls through to the remaining members.
- The run is left when a segment with a different code arrives, when a same-code segment matches no member, or when the input ends.
- On exit, every member declaring `minOccurances > 0` must have at least one occurrence; otherwise parsing fails, naming the member.
- A same-code segment that matches no member **stays unconsumed**: the input cursor does not advance, the schema cursor moves past the whole run, and the segment is offered to the units that follow. It is never dropped and never retried against the same run. If no later unit accepts it, it is reported by the existing unmatched-segment check, which names the segment and its position.

The exit condition is a **presence** check rather than an exact count, which is how `minOccurances` is already treated everywhere else when reading: a definition declaring `minOccurances` greater than `1` is satisfied by a single occurrence outside a run as well as inside one. Enforcing exact minimum counts while reading is a pre-existing gap that applies to all units, not only to discriminated runs, and is listed under Future Work so that runs do not diverge from the rest of the parser.

### Rules enforced when a schema is loaded

- A `discriminator` must list at least one code.
- A `discriminator` must not be declared on a repeating field, nor on any component or sub-component of one: repetitions are position-insignificant, so nothing inside a repeating field can identify a definition.
- Both attributes belong on the element that holds the value: on a component rather than the composite field around it, and on a sub-component rather than the component around it. Declaring either on a node whose value is a group of child elements is rejected.
- A sub-component `discriminator` requires `delimiters.subcomponent` to be configured; without it a sub-component cannot be isolated from the surrounding component text.
- When an element declares both attributes, every `discriminator` code must also appear in `values`; a definition requiring a code the element does not permit could never match.
- Definitions sharing a segment code within one segment list must either all declare discriminators or none. A mix is rejected, because a code-only sibling would capture the segments its discriminated siblings rejected.

### Definitions shared across positions

EDIFACT- and ESL-generated schemas define each segment once and reference it from many positions. A segment reference (`EdiUnitRef`) carries only `ref`, `tag`, `minOccurances`, and `maxOccurances`, and **this proposal adds no constraint override to it**: value constraints belong to a definition, so every position referencing one definition necessarily shares its constraints.

Positions that accept different qualifiers are therefore expressed by referencing **distinct specialized definitions** — a narrowed copy of the shared definition per meaning, which is what the tooling emits and what a schema author writes by hand. Because a reference is resolved by cloning its definition when the schema is loaded, the parser then sees one inline definition per position, and no new construct is required.

```json
"segmentDefinitions": {
    "RFF_SellersReference": {
        "code": "RFF",
        "tag": "SellersReference",
        "fields": [
            {"tag": "code"},
            {"tag": "REFERENCE", "required": true, "components": [
                {"tag": "qualifier", "required": true, "discriminator": ["SS"]},
                {"tag": "number", "required": true}
            ]}
        ]
    },
    "RFF_VatNumber": {
        "code": "RFF",
        "tag": "VatNumber",
        "fields": [
            {"tag": "code"},
            {"tag": "REFERENCE", "required": true, "components": [
                {"tag": "qualifier", "required": true, "discriminator": ["VA"]},
                {"tag": "number", "required": true}
            ]}
        ]
    }
},
"segments": [
    {"ref": "RFF_SellersReference", "minOccurances": 0},
    {"ref": "RFF_VatNumber", "minOccurances": 0}
]
```

With those two positions, `RFF+SS:1111-000000'` is assigned to `SellersReference` and `RFF+VA:SE556421030901'` to `VatNumber`, in either arrival order; a file carrying only the VAT reference leaves `SellersReference` absent rather than capturing the segment.

Reusing one definition at several positions remains valid where the positions genuinely accept the same codes. What is not expressible — deliberately — is one definition whose constraints differ per position, since that would make a definition's meaning depend on where it is referenced.

### Tooling

`bal edi` populates the attributes where it can prove they are needed:

- **X12 XSD** — both styles of code list are read: inline `xs:enumeration` restrictions, and named simple types resolved through `xs:include` (the shared `Codes.xsd` used by standard schema sets, from which nothing was extracted before). An unresolvable include produces a warning rather than a silent omission.
- Only inline, guide-narrowed enumerations on definitions that share a segment code with a sibling become a `discriminator`. Everything else, including full standard code lists, is attached as `values`.
- **ESL** — optional `values` code lists on element definitions are carried into the generated schema.
- **Generated records** — an element carrying a `discriminator` is typed as a union of its codes, for example `("17"|"23"|"DX") qualifier`, so an out-of-set qualifier becomes a compile-time error. Elements carrying only `values` keep their base type, since standard code lists are too large to be useful as union types and narrowing them would reject inbound data that parses correctly.

## Alternatives

**A map of allowed values on the segment definition.** A `map<string[]>` keyed by field tag was prototyped first. It cannot express EDIFACT, where the qualifier is a component inside a composite: the key space stops at field level, and component tags are unique only within their parent, so there is no unambiguous address. Attaching the constraint to the element itself reaches every depth without an addressing scheme.

**A boolean flag over `values`.** `discriminator` was first modelled as `boolean` opting `values` into matching. A defaulted boolean is written on every element when a schema record is serialized, including in schemas that never use the feature, which broke loading on runtime versions predating the attribute and forced the tools to strip the key. Modelling it as an array of codes removes that entirely and makes two invalid states unrepresentable: a discriminator with no values, and a discriminator whose values are not a set.

**Making `values` participate in matching by default.** Rejected. Code lists are attached broadly by the generators, so this would turn every coded element into a routing rule, make legally empty optional elements unmatchable, and change how existing files parse whenever a schema is regenerated against a newer code list.

**Doing nothing.** Users must post-process the parsed output to correct mis-assigned segments, and cannot tell a correctly parsed file from a silently wrong one.

## Testing

- Unit tests in `module-ballerina-edi` cover matching at field, component, and sub-component depth; absent optional definitions; unknown and blank qualifiers; any-order and interleaved arrival; occurrence limits; writer validation; and each load-time rule.
- Conversion tests in `edi-tools` cover both XSD code-list styles, the rule deciding which elements become discriminators, the ESL path, and the generated union types, whose output is compiled as part of the test.
- The design was verified against 966 real schemas converted from X12 releases 003010 to 008040 and a HIPAA implementation guide: all load, and discriminators appear only in the guide-derived schemas while base releases carry `values` only.
- Real EDI payloads were parsed against converter-generated schemas, including a full interchange, the reported 834 case using the user's own implementation-guide XSD, and a HIPAA 278 with discriminated `REF` segments nested under a four-level `HL` chain.
- An adversarial suite covers delimiter characters inside codes, case sensitivity, empty codes, duplicate output tags, overlapping sets, runs split by another code, malformed input, fixed-length schemas, and a 2,000-code set.

## Risks and Assumptions

- A schema that uses either attribute requires a runtime that knows it; earlier runtimes reject unknown schema keys. Schemas using neither are unaffected.
- Regenerating a schema with the updated tools attaches code lists, so the regenerated schema requires the new runtime even when it declares no discriminator. Users who need to stay on an older runtime should keep their existing schema.
- The load-time rules make some previously accepted schema shapes invalid — specifically, mixing discriminated and code-only siblings of one code. Such a schema could not have behaved correctly, but the failure now occurs at load rather than silently at parse time.
- The design assumes discriminating values are codes on leaf elements. This holds across X12, EDIFACT, EANCOM, and TRADACOMS, where qualifiers are mandatory position-01 elements or first components of a composite.

## Dependencies

None. The proposal is additive to the EDI schema specification and requires no other BEP.

## Future Work

- Intra-segment relational rules (X12 syntax notes, EDIFACT dependency notes) for standards-faithful write validation.
- Mutual exclusion between definitions, corresponding to `xs:choice`.
- Structural matching, so that a definition may match only when earlier mandatory units were satisfied.
- Reading EDIFACT `UNCL` code lists in the converter so EDIFACT-derived schemas carry `values` as X12-derived ones now do.
- An option to treat overlapping discriminator sets as an error rather than a warning.
- Enforcing exact minimum occurrence counts when reading, for all units rather than only discriminated runs, so that a definition declaring `minOccurances` greater than `1` is not satisfied by a single occurrence.

## References

- Tracking issue: [ballerina-platform/ballerina-library#9100](https://github.com/ballerina-platform/ballerina-library/issues/9100)
- Runtime implementation: [ballerina-platform/module-ballerina-edi#102](https://github.com/ballerina-platform/module-ballerina-edi/pull/102)
- Tooling implementation: [ballerina-platform/edi-tools#82](https://github.com/ballerina-platform/edi-tools/pull/82)
- EDI schema specification: [module-ballerina-edi `docs/spec/spec.md`](https://github.com/ballerina-platform/module-ballerina-edi/blob/main/docs/spec/spec.md)
