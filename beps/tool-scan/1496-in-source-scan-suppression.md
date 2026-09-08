# 1496: In-source suppression of scan findings

- Authors - @TharmiganK
- Reviewed by - TBD
- Created date - 2026-09-04
- Updated date - 2026-09-08
- Issue - [#1496](https://github.com/ballerina-platform/ballerina-spec/issues/1496)
- State - Draft

## Summary

Allow a developer to suppress an individual `bal scan` finding at the point in the source where it occurs, with a mandatory justification, recorded in the output so suppressions remain auditable rather than invisible.

The mechanism is a comment directive placed immediately before, or at the end of, the line that produced the finding. Because it lives in the source, each suppression is reviewed in the diff that introduces it and attributed through version control, and an audit run can disregard suppressions entirely to show the unfiltered picture.

## Motivation

A build gate is only adoptable if there is a sanctioned way to say "this one is fine, and here is why".

Two mechanisms exist today and neither is that:

- **Project-wide rule exclusion** turns a rule off everywhere. One accepted instance disables the rule for the whole project, including for code written next year.
- **File-level exclusion** written from the IDE is finer, but still file-scoped, detached from the code it concerns, and reachable only from the editor.

Neither records *why*. A reviewer reading an exclusion list cannot distinguish an accepted risk from a false positive from someone silencing a rule to get a build green. For a tool producing compliance evidence, an unexplained suppression is worse than no suppression: it is an audit finding.

Without this, a team adopting the gate has two options — fix everything first, or disable the rule globally. Most choose the second, and the gate stops meaning anything.

## Goals

- Suppress a single finding at the exact construct that produced it, for every rule the tool ships.
- A justification is **mandatory**, not conventional.
- No runtime footprint.
- Where a suppression can be placed is governed by where findings occur, not by the constraints of an unrelated language feature.
- Suppressions are visible in the output without reading the source.
- Every suppression records **what** was accepted and **why**, in the source.
- **Who** accepted it and **when** are answerable from version control, without the directive carrying them.
- The true unsuppressed picture is obtainable on demand, so a security review never has to take suppressions on trust.
- One coherent story across the existing exclusion mechanisms.

## Non-Goals

- **Removing project-wide rule exclusion.** It remains legitimate: a project with no HTTP services does not need HTTP rules.
- **Expiring suppressions.** Time-boxed suppressions need a policy owner before they need a syntax.
- **Bulk acceptance of an existing backlog.** Suppression handles individually reviewed exceptions, one at a time, each with a reason. Grandfathering in everything a codebase already has is the job of the [baseline work](https://github.com/ballerina-platform/ballerina-spec/issues/1498), and using suppression for it means hundreds of directives carrying invented justifications — which destroys the value of requiring one.
- **Extending the language.** This requires no language or specification change.

## Design

### The directive

```
// scan:suppress <rule-id>[,<rule-id>]* reason="<justification>"
```

```ballerina
// scan:suppress ballerina/crypto:2 reason="Legacy hash retained for migration, SEC-1042"
string hashed = check crypto:hashBcrypt(password, 4);

log:printInfo(summary);  // scan:suppress ballerina/log:1 reason="values redacted upstream"
```

The leading form applies to the construct that follows it. The trailing form applies to the construct on its own line.

`reason` is quoted so the justification may contain any character. The rule list is non-empty: a directive naming no rule is rejected, because blanket suppression is how a mechanism becomes a way to disable analysis.

### Binding

A directive binds to the **construct** it precedes, not to a line number. Formatting moves lines; the construct a comment sits against does not move with them. Anything that anchors on line position will silently drift the first time a file is reformatted.

A finding is suppressed when it falls within the bound construct and its rule appears in the directive's list. For nearly every rule the bound construct is the finding's own statement or expression. Placing a directive before a declaration is legal and scopes to the whole body — occasionally useful, and made safe by the rule list being mandatory.

A directive does not leak into a nested construct carrying its own directive; the innermost wins.

### Coverage

Every one of the 27 shipped rules was triggered and confirmed suppressible at the exact construct that produced it. The cases worth recording are those that defeat a declaration-oriented mechanism, because a finding can sit somewhere no declaration exists:

| Rule | Where the finding sits |
|---|---|
| `ballerina:1` checkpanic | an expression inside a `return` statement |
| `ballerina:10` self-assignment | an assignment statement |
| `ballerina:12` invalid range | an expression inside a `foreach` |
| `file:2` path injection | a call statement |
| `log:1` sensitive value logged | a call statement |
| `http:4` open redirect | a field in a map literal |
| `http:2` permissive CORS | a field inside a service-config annotation's value |

`http:2` is the decisive case: the finding sits inside **another annotation's value**, a position where by construction no annotation can be attached. A comment reaches it.

Directives are also correctly ignored inside string literals and templates, because comments are recognised by the parser rather than by scanning text — so an entire class of false-positive bugs that affects text-matching implementations does not arise.

### Justification

`reason` is required. A directive without one is itself reported as a finding, at `LOW`, from a built-in rule. That keeps the requirement enforceable without failing the build for it by default, and lets a team gate on it if they choose.

**This is stricter than the norm, deliberately.** Comparable tools offer a justification but do not insist on one: SpotBugs and .NET analyzers expose an optional justification field, while ESLint and golangci-lint support a reason and enforce it only if a team opts into a meta-rule. Java and Python suppressions carry no reason at all. The enforcement *mechanism* proposed here — a rule that reports a missing justification — is the same one ESLint and golangci-lint use; the difference is that it ships enabled. Given that the motivation for this work is compliance evidence, an optional justification would leave the tool producing exactly the unexplained suppressions it exists to prevent.

**The directive records what and why; version control supplies who and when.** An audit asks four questions of any accepted risk. For

```ballerina
// scan:suppress ballerina/crypto:2 reason="Legacy hash kept for migration window, SEC-1042"
string hashed = check crypto:hashBcrypt(password, 4);
```

the answers are:

| | Answer | Source |
|---|---|---|
| What was accepted | `ballerina/crypto:2`, at this call, in this file | the directive's rule list and position |
| Why | a legacy hash kept for a migration window, tracked as SEC-1042 | the `reason` text |
| By whom | the author of the line, and the reviewer who approved the change | version control |
| When | the commit date | version control |

The directive deliberately does not carry an author or a date. Recording them in the source means two more fields to write, to keep accurate, and to lie in — while version control already answers both, and cannot be edited without leaving a trace. This division is the strongest argument for in-source suppression over an external suppression list, where the last two questions have no answer at all.

Because a directive is text rather than a typed construct, a malformed one is a diagnostic rather than a compile error. Three cases are reported: a missing `reason`, an empty rule list, and a directive that matched no finding.

### Reporting

**SARIF.** Suppressed findings appear with a `suppressions` entry of kind `inSource` carrying the justification. They are present and marked, not omitted — that is what makes them auditable, and what the SARIF specification intends.

**Console.** A summary line: `12 issues, 3 suppressed`. Suppressed findings are not listed by default.

**JSON.** A suppression object mirroring the SARIF shape.

**Gate.** Suppressed findings do not count toward severity or issue-count thresholds.

**Unmatched directives are reported.** A directive that suppressed nothing is stale — the finding was fixed, the rule was removed, or the rule identifier is misspelled. This count is the mitigation for the absence of compile-time validation, and it is the most important diagnostic in the proposal. It is also an audit control in its own right: accumulated stale suppressions are the clearest signal that a codebase's exceptions are no longer being maintained. The control is well established elsewhere — ESLint, Ruff and golangci-lint all report suppressions that no longer suppress anything.

**New suppressions appear in code review.** Because a directive is part of the source, adding one shows up in the diff alongside the change that needed it. The exception is scrutinised at the moment it is created, by someone with the context to judge it — which is worth more than any report produced months later. An external suppression file achieves this only if reviewers happen to read it.

**An audit run reports the unsuppressed picture.** `--ignore-suppressions` runs the scan with every directive disregarded, so the full set of findings is reported and gated as though no suppression existed. A security review's first question is what the codebase looks like without them, and "trust our suppressions" is not an answer. The flag changes nothing about the scan itself, only whether the suppression filter is applied.

### Relationship to the existing mechanisms

The three mechanisms are not variants of one another. Two of them are **rule selection** — deciding which rules apply at all — and one is **finding acceptance**, where the rule applied, found something real, and a person accepted it. That distinction determines how they combine.

| Mechanism | Category | Granularity | Records why | Use |
|---|---|---|---|---|
| Project-wide rule inclusion/exclusion | Rule selection | Project | No | The rule does not apply to this project |
| File-level exclusion | Rule selection | File | No | The rule does not apply to this file — generated code, fixtures |
| In-source directive | Finding acceptance | Finding | **Yes** | This specific occurrence is accepted |

### Precedence

Rule selection is resolved first, then findings are produced, then directives are applied:

1. **Rule selection** — command-line options and scan configuration decide which rules can produce findings. Command line overrides configuration.
2. **Analysis** — the selected rules run and produce findings.
3. **File-level exclusion** — removes findings for a rule within a file.
4. **In-source directives** — suppress individual remaining findings.
5. **Gate** — evaluates what is left.

Two consequences follow, and both are deliberate.

**Rule selection wins, because it acts earlier.** A directive naming a rule that is excluded project-wide, or absent from an inclusion list, has nothing to suppress. It is reported as **unmatched** — which is the useful outcome: it tells a team they are carrying a justified exception for a rule that is not even running, usually because someone disabled the rule globally and forgot the directive.

**Exclusion and suppression differ in what reaches the output.** An excluded finding is *absent*: no record, nothing to review. A suppressed finding is *present and marked*, with its justification. This is the whole reason both exist — exclusion says "not applicable", suppression says "applicable, and accepted". A team that wants an auditable trail must suppress rather than exclude, and the documentation should say so plainly.

Between directives, the innermost wins; a directive on an enclosing construct does not override one on a construct inside it.

### Scope of the audit run

`--ignore-suppressions` disregards **directives only**. Rule selection is configuration rather than accepted risk, so an audit run does not re-enable excluded rules.

This leaves an honest gap: a team can dodge findings by excluding a rule project-wide, and the audit run will not reveal it. Rule selection is visible in the checked-in configuration and in its diff, so it is not hidden — but it is not surfaced by the same command. A fuller audit mode that also disregards rule selection is worth considering, and is recorded in Future Work rather than resolved here.

### Migration from file-level exclusion

File-level exclusion overlaps this mechanism, is the newest of the three, and writes to the scan configuration file from the IDE — putting a machine-edited section into a hand-edited file.

**Proposed: the IDE's "suppress this finding" action inserts an in-source directive** rather than a configuration entry. File-level exclusion is retained for genuine whole-file cases — generated code, test fixtures — but stops being the default action. Without this the IDE entrenches a third mechanism and the IDE integration work inherits the ambiguity.

### Consistency across entry points

The scan runs from two entry points, the command line and the language server, and they currently duplicate the filtering sequence rather than sharing it. Suppression must behave identically from both. This assumes the shared filtering path introduced by the gating work has landed; otherwise suppression is built twice, in two places that have already diverged.

### Compatibility and migration

**Additive.** No existing configuration changes meaning, and there are no suppressions in the field to migrate.

**No new dependency.** A project does not import anything in order to suppress a finding.

**No runtime impact.** A comment is not present in the compiled program.

**Formatting is safe, and this was verified rather than assumed.** Reformatting moves and re-indents directives but does not detach them from the construct they precede. Because a formatter change could break every suppression in the field at once, this must be guarded continuously rather than confirmed once.

**Output shape changes.** SARIF and JSON findings gain an optional suppression entry; console output gains a summary count. Existing output fixtures need regenerating.

## Alternatives

### A source-only annotation

Declare a suppression annotation in a published module, using the source-only attachment points the language provides for compile-time metadata.

**In favour**

- **Rule identifiers are validated at compile time.** An unknown identifier is a diagnostic, not a directive that silently does nothing. This is the one capability a comment cannot offer, and it is a real loss.
- **The justification is a typed field** rather than text requiring its own grammar and error handling.
- **No runtime footprint**, the same as a comment.
- **Idiomatic**: it is how the language expresses metadata about a construct, and editor tooling understands it for free.

**Against**

- **It couples suppression placement to the annotation attachment-point list.** Those points exist to express where language-level metadata belongs, which is a different question from where a lint rule reports. Rule authoring would become constrained by that list, and any future request to widen it would arrive justified by "a scan rule reports there" — pressure on the language driven by an unrelated concern.
- **Coverage is incomplete.** Of the 27 shipped rules, an annotation reaches the exact construct or its enclosing statement for 20 and falls back to the enclosing declaration for 7 — call statements, control-flow expressions and fields inside other values. A declaration-level fallback silences every finding of that rule in the scope, including ones added later by another author.
- **The gap skews wrong for what is planned.** The next wave of rules is weighted toward call statements, which is the fallback group.
- **It requires a published module** and an import in every project that suppresses anything.

**Assessment.** The compile-time validation is genuinely valuable and its loss is mitigated deliberately, through unmatched-directive reporting, rather than shrugged off. But a mechanism that cannot be placed at the finding for a quarter of the rule set, and that grows a dependency between rule design and language design, does not meet the goals. Comments are also the conventional answer in most languages, so the syntax will be familiar.

### Binding a directive to a line number rather than a construct

**In favour:** simpler, and what several tools do.

**Against:** line numbers move under formatting; the construct does not.

**Assessment:** rejected.

### A suppression file outside the source

**In favour:** no directives cluttering the code, and all suppressions visible in one place.

**Against:** entries drift on every edit so the file rots, and the justification sits far from the code it justifies.

**Assessment:** rejected.

### Per-file or per-line keys in the scan configuration file

**In favour:** reuses a format that already exists.

**Against:** the same drift problem, and it puts machine-maintained data into a hand-edited file.

**Assessment:** rejected.

### Optional justification

**In favour:** lower friction, so developers actually use it.

**Against:** an unexplained suppression is the failure mode this proposal exists to prevent, and "required by convention" means "absent under deadline".

**Assessment:** rejected.

### Omitting suppressed findings from the output

**In favour:** cleaner reports.

**Against:** an invisible suppression cannot be reviewed. SARIF defines a suppression construct precisely so they stay visible.

**Assessment:** rejected.

### No suppression, relying on baseline adoption instead

**In favour:** one mechanism rather than two.

**Against:** a baseline accepts a backlog wholesale and without justification. It is a migration tool, not an exception mechanism.

**Assessment:** rejected.

## Testing

**Suppression coverage must be verified for every rule and guarded.** The claim that all 27 rules are suppressible at their exact construct was established by measurement, and becomes a standing check so that a new rule reporting somewhere no directive can bind is caught at review rather than by a user who cannot suppress it.

**Formatter stability must be guarded continuously.** Directives are captured, the source reformatted, and the bindings compared. A formatter regression must break our build rather than users' suppressions.

Beyond that:

- Directive parsing: single and multiple rule identifiers, missing justification, empty rule list, unknown rule reported as unmatched, malformed directive reported rather than ignored.
- Binding: leading form binds to the following construct; trailing form to the construct on its line; a directive with no following construct is reported as dangling.
- Scoping: a directive on a declaration covers its body and nothing outside it; a nested directive overrides an outer one; no leakage to siblings.
- Directives inside string literals and templates are ignored.
- Reporting: suppression entries present in SARIF with the justification; console and unmatched counts correct; JSON mirrors SARIF.
- Gate interaction: a suppressed high-severity finding does not trip the threshold; an unsuppressed one does.
- Audit mode: with `--ignore-suppressions`, every suppressed finding is reported and counted toward the gate, and the output is identical to a run with the directives deleted.
- Identical behaviour from both entry points, asserted by shared fixtures.

## Risks and Assumptions

| Risk | Mitigation |
|---|---|
| A misspelled rule identifier silently suppresses nothing — the cost of choosing comments over annotations | Unmatched directives are counted and reported on every run; the IDE validates identifiers against the loaded rule set |
| A future formatter change detaches directives from their constructs | Continuous formatter-stability check, so the regression breaks our build first |
| Directives proliferate as a way to get builds green | Mandatory justification; each one surfaces in the pull request diff when added; visible counts; suppressed findings present in the output; `--ignore-suppressions` exposes the true picture on demand |
| Suppressions accumulate permanently, since nothing expires them | Stale-directive counts show which have outlived their finding, and the audit run shows total exposure. A real fix needs expiry, which is deferred pending a policy owner — this is the known weakness of the GA scope |
| A new rule reports where no directive can bind | Standing coverage check; rule review asks "where does this report, and can it be suppressed there?" |
| Directive syntax diverges from other tooling conventions | The prefix is namespaced `scan:`; confirm against existing conventions before it ships |
| Suppression built twice across the two entry points | Depends on the shared filtering path from the gating work |
| The IDE entrenches a third mechanism | The IDE action inserts an in-source directive; decided here rather than in the IDE work |

**Assumptions.** That comment placement conventions are stable enough for the trailing form to be unambiguous. That coverage measured against today's rule set holds for the next wave; unlike the annotation design this does not depend on what kind of construct a finding sits in, so the risk is low.

## Dependencies

- **Rule severity and security standard metadata** — for the severity of the missing-justification rule.
- **Severity and security metadata in SARIF output** — for the suppression output surface.
- **Build gating and the exit code contract** — for the shared filtering path, and because suppression is what makes the gate adoptable.

No language or specification change, and no new published module.

## Future Work

- **Expiring suppressions**, with a review date that turns the suppression back into a finding once passed. The highest-value governance addition, and deferred only because it cannot ship until someone owns the policy question of what expiry does — break the build, or report.
- **Structured justification fields** — a ticket reference, an approver, a review date — replacing free text where a team wants them enforced rather than conventional.
- **An aggregated suppression report.** A convenience view over data already present in the SARIF output, so nothing is blocked without it.
- IDE quick fix to insert a directive, and rule-identifier validation as you type.
- Migration tooling from project-wide and file-level exclusions to in-source directives.
- A fuller audit mode that also disregards rule selection, closing the gap where a project-wide exclusion hides findings that the suppression audit run cannot reveal.

## References

- [Ballerina Language Specification §9.1 — Annotations](https://ballerina.io/spec/lang/master/#section_9.1) — attachment points; the basis for the annotation alternative
- [SARIF 2.1.0](https://docs.oasis-open.org/sarif/sarif/v2.1.0/sarif-v2.1.0.html) — `suppression` object, `kind: "inSource"`
- NIST SP 500-268 SCSA-RO-2 — suppression as an analyzer capability requirement
