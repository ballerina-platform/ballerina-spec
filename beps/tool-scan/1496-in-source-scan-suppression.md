# 1496: In-source suppression of scan findings

- Authors - @TharmiganK
- Reviewed by - TBD
- Created date - 2026-09-04
- Updated date - 2026-09-08
- Issue - [#1496](https://github.com/ballerina-platform/ballerina-spec/issues/1496)
- State - Draft

## Summary

Allow a developer to suppress an individual `bal scan` finding at the point in the source where it occurs, with a justification, recorded in the output so suppressions remain auditable rather than invisible. The justification is optional by default and a team can require it, failing the scan when one is missing.

The mechanism is a comment directive placed immediately before, or at the end of, the line that produced the finding. Because it lives in the source, each suppression is reviewed in the diff that introduces it and attributed through version control, and an audit run can disregard suppressions entirely to show the unfiltered picture.

## Motivation

A build gate is only adoptable if there is a sanctioned way to say "this one is fine, and here is why".

One mechanism exists today and it is not that. **Project-wide rule exclusion** turns a rule off everywhere: one accepted instance disables the rule for the whole project, including for code written next year. It is configured in the scan configuration file, and it is also what the IDE's exclusion action writes, so the finest exclusion reachable from the editor is still project-wide.

It has nowhere to record *why*. A reviewer reading an exclusion list cannot distinguish an accepted risk from a false positive from someone silencing a rule to get a build green. For a tool producing compliance evidence, an unexplained exception is worse than none: it is an audit finding. What is missing is not only a finer granularity but somewhere to put the reason, and a way for a team that needs one to insist on it.

Without this, a team adopting the gate has two options — fix everything first, or disable the rule globally. Most choose the second, and the gate stops meaning anything.

## Goals

- Suppress a single finding at the exact construct that produced it, for every rule the tool ships.
- Every suppression can carry a justification, and a team that requires one can make the scan fail without it.
- No runtime footprint.
- Where a suppression can be placed is governed by where findings occur, not by the constraints of an unrelated language feature.
- Suppressions are visible in the output without reading the source.
- Every suppression records **what** was accepted, and **why** wherever a justification is given.
- **Who** accepted it and **when** are answerable from version control, without the directive carrying them.
- The true unsuppressed picture is obtainable on demand, so a security review never has to take suppressions on trust.
- One coherent story alongside the existing rule exclusion, so it is clear which to reach for.

## Non-Goals

- **Removing project-wide rule exclusion.** It remains legitimate: a project with no HTTP services does not need HTTP rules.
- **Expiring suppressions.** Time-boxed suppressions need a policy owner before they need a syntax.
- **Bulk acceptance of an existing backlog.** Suppression handles individually reviewed exceptions, one at a time, each with a reason. Grandfathering in everything a codebase already has is the job of the [baseline work](https://github.com/ballerina-platform/ballerina-spec/issues/1498), and using suppression for it means hundreds of directives carrying invented justifications — which destroys the value of requiring one.
- **Extending the language.** This requires no language or specification change.

## Design

### The directive

```
// scan:suppress [<rule-id>[,<rule-id>]*] [reason="<justification>"]
```

```ballerina
// scan:suppress ballerina/crypto:2 reason="Legacy hash retained for migration, SEC-1042"
string hashed = check crypto:hashBcrypt(password, 4);

log:printInfo(summary);  // scan:suppress ballerina/log:1 reason="values redacted upstream"

// scan:suppress ballerina:10
x = x;

// scan:suppress reason="generated block, reviewed once"
foreach var row in rows {
    ...
}
```

Everything after the prefix is optional, as the third and fourth examples show: omit the justification, omit the rule list, or omit both. A directive with no rule list suppresses **every** finding in the construct it binds to; a directive with no justification suppresses silently. The Justification section below covers how a team makes either of them required.

The leading form applies to the construct that follows it. The trailing form applies to the construct on its own line.

`reason` is quoted, so the justification may contain any character.

Precisely:

```
directive   ::= "//" WS* "scan:suppress" ( WS+ body )? WS*
body        ::= rule-list ( WS+ reason )?
              | reason
reason      ::= "reason" WS* "=" WS* quoted
rule-list   ::= rule-id ( WS* "," WS* rule-id )*
rule-id     ::= segment ( "/" segment )? ":" DIGIT+
segment     ::= [A-Za-z0-9_.]+
quoted      ::= '"' ( [^"\\] | "\\" ["\\] )* '"'
```

`rule-id` is the identifier the tool already prints and already accepts in rule inclusion and exclusion — `ballerina:1` for a language rule, `ballerina/crypto:2` for a module rule — so a developer copies it from the finding rather than learning a second form. Within `quoted`, `\"` and `\\` are the two escapes. Repeated identifiers are de-duplicated. An absent `rule-list` means every rule.

**More than one directive may apply to the same construct**, and their rule lists combine — necessary rather than incidental, since a directive carries one justification and a construct may need two justifications for two rules.

### Binding

A directive binds to the **construct** it precedes, not to a line number. Formatting moves lines; the construct a comment sits against does not move with them. Anything that anchors on line position will silently drift the first time a file is reformatted.

The two forms scope differently, and the difference is worth stating because it is not symmetric. The **leading form** binds to the construct that starts on the line below it — a directive above a field binds to that field, one above a declaration binds to that declaration, and one at the top of a file binds to the first declaration rather than to the file. The **trailing form** binds to the construct enclosing everything written on its own line, which is not the same as the construct ending where the comment sits: on `foreach int i in 5...1 {  // scan:suppress …` the finding is in the range expression, and the line's construct is the `foreach`.

A finding is suppressed when it falls **wholly within** the bound construct and the directive applies to its rule — because the rule is named, or because the directive names none and so applies to all. Containment rather than overlap is what keeps a directive from reaching a sibling. For nearly every rule the bound construct is the finding's own statement or expression. Placing a directive before a declaration is legal and scopes to the whole body, which is worth being deliberate about: a directive with no rule list, placed on a declaration, silences everything in it, including findings a later author introduces.

Where directives nest, **the innermost directive that applies to the rule wins**: it supplies the recorded justification and it is the one credited with the match. A directive on an inner construct naming an unrelated rule does not cancel an accepted exception on an enclosing one — the stricter reading would make a declaration-scoped directive stop applying the moment anyone added an unrelated directive inside the body.

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

Directives are also correctly ignored inside string literals and templates, because comments are recognised by the parser rather than by scanning text — so an entire class of false-positive bugs that affects text-matching implementations does not arise. Markdown documentation (`#`) is a separate construct and does not carry directives either.

One consequence of matching by containment: a rule reporting a range wider than the construct a developer would naturally mark needs its directive one level further out. No shipped rule is in that position, and the standing check under Testing is what keeps that true.

### Justification

**`reason` is optional, and requiring it is opt-in.** By default a directive without one suppresses and nothing is reported about it. A team that wants the justification guaranteed switches the requirement on, and then a directive missing one is reported as an **error** — `bal scan` fails, naming the directive and the file and line it sits on. The requirement is expressed in the scan configuration file, so it is a property of the project rather than of one invocation, with a command-line option to switch it on for a single run:

```toml
[suppression]
requireReason = true
```

**Requiring the reason does not make the directive inert.** With the requirement on, an unjustified directive still suppresses its finding; what fails the scan is the missing justification, reported at the directive. The alternative — refusing to suppress until a reason is written — means switching the requirement on in an existing project floods the output with the accepted findings *and* the missing-reason errors at once, and a developer cannot tell which they are being asked to fix. Failing on the one thing that is actually wrong is the more useful behaviour.

**This is the prevailing shape, not a departure from it.** Suppression mechanisms in comparable analyzers treat the reason as optional and, where they enforce it at all, do so through a setting a team switches on. Some offer a justification field with no enforcement; several carry no reason at all. Keeping the field optional and the requirement configurable means a team with a compliance obligation gets it enforced, and a team without one gets a mechanism they will use rather than route around.

**Naming the rules is requirable on the same terms.** By default a directive with no rule list suppresses every finding in its construct. `--require-suppression-rule-id`, or `requireRuleId` in the same table, reports a directive that names no rule as an error and fails the scan, exactly as the justification requirement does.

The two requirements are independent, so a project can insist on one, both or neither. A team using suppression as compliance evidence will want both on; a team using it to quiet a handful of false positives may want neither, and the audit run tells them what they are carrying either way.

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

Because a directive is text rather than a typed construct, a malformed one is a diagnostic rather than a compile error. These are reported as warnings alongside the results, with counts: an unquoted justification, trailing content, a malformed rule identifier, a directive preceding no construct, and a directive that matched no finding. An absent justification or rule list is not malformed — both are legal — and becomes an error only when the corresponding requirement is switched on. A comment only becomes a directive if it opens with the prefix, so `// TODO: scan:suppress this later` stays an ordinary comment; once it does, any deviation from the grammar is reported rather than ignored.

### Reporting

**SARIF.** Suppressed findings appear with a `suppressions` entry of kind `inSource` carrying the justification. They are present and marked, not omitted — that is what makes them auditable, and what the SARIF specification intends.

**Console.** A summary line: `12 issues, 3 suppressed`. Suppressed findings are not listed by default, so the console listing and the saved report no longer hold the same set — the report keeps them, the console does not.

**JSON.** A suppression object mirroring the SARIF shape.

**Gate.** Suppressed findings do not count toward severity or issue-count thresholds. The gate itself arrives with the gating work, so this becomes observable there rather than here.

**Unmatched directives are reported.** A directive that suppressed nothing is stale — the finding was fixed, the rule was removed, or the rule identifier is misspelled. This count is the mitigation for the absence of compile-time validation, and it is the most important diagnostic in the proposal. It is also an audit control in its own right: accumulated stale suppressions are the clearest signal that a codebase's exceptions are no longer being maintained. The control is well established: comparable analyzers all report suppressions that no longer suppress anything.

**New suppressions appear in code review.** Because a directive is part of the source, adding one shows up in the diff alongside the change that needed it. The exception is scrutinised at the moment it is created, by someone with the context to judge it — which is worth more than any report produced months later. An external suppression file achieves this only if reviewers happen to read it.

**An audit run reports the unsuppressed picture.** `--ignore-suppressions` runs the scan with every directive disregarded, so the full set of findings is reported and gated as though no suppression existed. A security review's first question is what the codebase looks like without them, and "trust our suppressions" is not an answer. The flag changes nothing about the scan itself, only whether the suppression filter is applied.

The flag also silences the unmatched report, which would otherwise name every directive in the project. Findings and warnings about the directives themselves, an absent justification among them, describe the source rather than the suppression and are still reported.

### Relationship to the existing mechanisms

The two mechanisms are not variants of one another. **Rule selection** decides which rules apply at all; **finding acceptance** is where the rule applied, found something real, and a person accepted it. That distinction determines how they combine.

| Mechanism | Category | Granularity | Records why | Use |
|---|---|---|---|---|
| Project-wide rule inclusion/exclusion | Rule selection | Project | No | The rule does not apply to this project |
| In-source directive | Finding acceptance | Finding | **Yes** | This specific occurrence is accepted |

A file-scoped exclusion, for the case where a rule genuinely does not apply to a whole file — generated code, test fixtures — would be a third entry in the rule-selection column. None exists today. If one is wanted it should be designed as rule selection, not as a way to accept a finding.

### Precedence

Rule selection is resolved first, then findings are produced, then directives are applied:

1. **Rule selection** — command-line options and scan configuration decide which rules can produce findings. Command line overrides configuration.
2. **Analysis** — the selected rules run and produce findings.
3. **In-source directives** — suppress individual findings.
4. **Gate** — evaluates what is left, and arrives with the gating work.

A file-scoped exclusion, were one added, would sit between analysis and directives.

Two consequences follow, and both are deliberate.

**Rule selection wins, because it acts earlier.** A directive naming a rule that is excluded project-wide, or absent from an inclusion list, has nothing to suppress. It is reported as **unmatched** — which is the useful outcome: it tells a team they are carrying a justified exception for a rule that is not even running, usually because someone disabled the rule globally and forgot the directive.

**Exclusion and suppression differ in what reaches the output.** An excluded finding is *absent*: no record, nothing to review. A suppressed finding is *present and marked*, with its justification. This is the whole reason both exist — exclusion says "not applicable", suppression says "applicable, and accepted". A team that wants an auditable trail must suppress rather than exclude, and the documentation should say so plainly.

Between directives, the innermost one naming the rule wins, as described under Binding.

### Scope of the audit run

`--ignore-suppressions` disregards **directives only**. Rule selection is configuration rather than accepted risk, so an audit run does not re-enable excluded rules.

This leaves an honest gap: a team can dodge findings by excluding a rule project-wide, and the audit run will not reveal it. Rule selection is visible in the checked-in configuration and in its diff, so it is not hidden — but it is not surfaced by the same command. A fuller audit mode that also disregards rule selection is worth considering, and is recorded in Future Work rather than resolved here.

### The IDE's exclusion action

What the IDE offers today writes a project-wide rule exclusion into the scan configuration file — putting a machine-edited array into a hand-edited file, and disabling the rule everywhere in response to one accepted finding.

**Proposed: the IDE's "suppress this finding" action inserts an in-source directive** rather than a configuration entry. Rule exclusion is retained for genuine whole-file and whole-project cases — generated code, test fixtures, rules that do not apply — but stops being the default response to a single finding. Deciding this here rather than in the IDE work is the point: otherwise the editor entrenches configuration editing as the normal way to accept a finding, and the IDE integration inherits the ambiguity.

### Consistency across entry points

The scan runs from two entry points, the command line and the language server, and they currently duplicate the filtering sequence rather than sharing it — they have already diverged. Suppression must behave identically from both, so **this work extracts the shared analyze-and-filter path** rather than waiting for the gating work to do it. The gating proposal leaves the placement of that extraction to review; it belongs here, because this is the first piece of work that would otherwise write the duplicate.

### Compatibility and migration

**Additive.** No existing configuration changes meaning, and there are no suppressions in the field to migrate.

**No new dependency.** A project does not import anything in order to suppress a finding.

**No runtime impact.** A comment is not present in the compiled program.

**Formatting is safe, and this was verified rather than assumed.** Reformatting moves and re-indents directives but does not detach them from the construct they precede. Because a formatter change could break every suppression in the field at once, this must be guarded continuously rather than confirmed once.

**Output shape changes.** SARIF and JSON findings gain an optional suppression entry, present only on a suppressed finding; console output gains a summary count and, where relevant, directive warnings. Existing output fixtures need regenerating.

**New options, all opt-in and all default off.** `--ignore-suppressions` for the audit run, and `--require-suppression-reason` and `--require-suppression-rule-id` with their `[suppression] requireReason` and `requireRuleId` counterparts. None changes the behaviour of an existing invocation, and `[suppression]` is a new table, so no existing scan configuration changes meaning. In particular, a project that adopts suppression without switching a requirement on never sees a new failure.

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

**Assessment:** rejected. What is rejected is *recording* a line number, which goes stale; the trailing form under Binding reads the line the comment is written on, and a comment cannot leave its own line.

### A suppression file outside the source

**In favour:** no directives cluttering the code, and all suppressions visible in one place.

**Against:** entries drift on every edit so the file rots, and the justification sits far from the code it justifies.

**Assessment:** rejected.

### Per-file or per-line keys in the scan configuration file

**In favour:** reuses a format that already exists.

**Against:** the same drift problem, and it puts machine-maintained data into a hand-edited file. Anchoring an entry to a place in a file needs something to relocate it by — a symbol name, a line hash — which is a workaround for the drift rather than an answer to it, and the entry is still lost when the line is edited.

**Assessment:** rejected.

### Requiring every directive to name a rule

**In favour:** a directive with no rule list silences everything in its construct, including findings a later author introduces, and unlike a missing justification that cannot be spotted by reading the directive.

**Against:** it is the same decision-for-everyone objection as the justification, and it removes the one form that makes the mechanism usable on generated or vendored code where the whole block is accepted. Whether specificity is required is a project's policy, not a property of the mechanism.

**Assessment:** rejected as unconditional, provided as `requireRuleId`. The reporting is the compensating control: a suppression entry records which rules it actually suppressed, so a blanket directive's real effect is visible in the report rather than inferred from the source.

### A justification required unconditionally

**In favour:** the requirement is either absolute or it is advisory, and "required by convention" means "absent under deadline". Compliance evidence is the motivation for this work, so an unexplained suppression is the failure mode it exists to prevent.

**Against:** it decides for every project a question only some of them have. It also adds friction exactly where the mechanism most needs adoption — a developer who cannot suppress a false positive without composing a sentence will reach for project-wide exclusion instead, which records nothing at all, and the outcome is worse than an unexplained directive. And no comparable tool does it, so the behaviour would surprise.

**Assessment:** rejected, in favour of a requirement any project can switch on. The team with the compliance obligation gets enforcement; the team without one gets a mechanism they will actually use instead of routing around.

### Making the directive inert when the justification is required but absent

**In favour:** the strictest reading of "required" — a directive that does not meet the requirement does not take effect.

**Against:** switching the requirement on then republishes every accepted finding alongside the missing-reason errors, and a developer cannot tell which of the two they are being asked to fix. A suppression's validity is also a separate question from whether it is documented, and conflating them makes the requirement expensive to adopt.

**Assessment:** rejected. The missing justification fails the scan; the suppression still applies.

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

The check has two halves, because the rules do. For rules shipped in the tool, adding a rule without a suppression case must fail the build. For rules shipped by other modules, the check is published in the tool's test utilities and run by those modules — the only place it can live when the rule's source is elsewhere.

**Formatter stability must be guarded continuously.** Directives are captured, the source reformatted, and the bindings compared. A formatter regression must break our build rather than users' suppressions.

Beyond that:

- Directive parsing: single and multiple rule identifiers, no rule list, no justification, neither, unknown rule reported as unmatched, malformed directive reported rather than ignored, and a comment merely mentioning the prefix left alone.
- Suppressing without a rule list: every finding in the bound construct is suppressed, and nothing outside it.
- Each requirement, independently: off, the directive suppresses silently; on, it still suppresses and the scan fails with an error naming the directive's file and line. Both on together. The command-line option overrides the configuration file.
- Binding: leading form binds to the following construct; trailing form to the construct on its line; a directive with no following construct is reported as dangling.
- Scoping: a directive on a declaration covers its body and nothing outside it; a nested directive naming the same rule overrides an outer one; a nested directive naming a different rule does not; no leakage to siblings; two directives on one construct combine.
- Directives inside string literals and templates are ignored.
- Reporting: suppression entries present in SARIF with the justification; console and unmatched counts correct; JSON mirrors SARIF.
- Gate interaction: deferred with the gate itself.
- Audit mode: with `--ignore-suppressions`, every suppressed finding is reported. Findings from every other rule match a run with the directives deleted; the directives' own findings and warnings do not, because deleting a directive also deletes what there was to report about it.
- Identical behaviour from both entry points, asserted by shared fixtures.

## Risks and Assumptions

| Risk | Mitigation |
|---|---|
| A misspelled rule identifier silently suppresses nothing — the cost of choosing comments over annotations | Unmatched directives are counted and reported on every run; the IDE validates identifiers against the loaded rule set |
| A future formatter change detaches directives from their constructs | Continuous formatter-stability check, so the regression breaks our build first |
| Directives proliferate as a way to get builds green | Each one surfaces in the pull request diff when added; visible counts; suppressed findings present in the output; `--ignore-suppressions` exposes the true picture on demand; a team can require the justification and fail the scan without it |
| A directive with no rule list on a declaration silences findings a later author introduces | The suppression entry in the report names the rules actually suppressed, so the effect is visible rather than inferred; `requireRuleId` forbids the form outright for projects that want it forbidden; the audit run shows total exposure |
| Suppressions accumulate permanently, since nothing expires them | Stale-directive counts show which have outlived their finding, and the audit run shows total exposure. A real fix needs expiry, which is deferred pending a policy owner — this is the known weakness of the GA scope |
| A new rule reports where no directive can bind | Standing coverage check; rule review asks "where does this report, and can it be suppressed there?" |
| Directive syntax diverges from other tooling conventions | The prefix is namespaced `scan:`; confirm against existing conventions before it ships |
| Suppression built twice across the two entry points | The shared filtering path is extracted as part of this work, and a parity test asserts both entry points agree |
| The IDE entrenches configuration editing as the way to accept a finding | The IDE action inserts an in-source directive; decided here rather than in the IDE work |
| Requiring the justification breaks a project that already carries unjustified directives | Off by default and switched on per project, so it never fires on upgrade; and it fails on the missing reason only, never by resurfacing the suppressed findings |
| The justification stays optional in practice, so suppressions go unexplained | The field is there, it appears in the report, and the requirement is one setting away. Enforcing it for everyone was considered and rejected under Alternatives |
| The console listing and the saved report disagree, and someone reads the console as complete | The summary line states the suppressed count on every run; documented alongside the audit run |

**Assumptions.** That comment placement conventions are stable enough for the trailing form to be unambiguous. That coverage measured against today's rule set holds for the next wave; unlike the annotation design this does not depend on what kind of construct a finding sits in, so the risk is low.

## Dependencies

- **Rule severity and security standard metadata** — for the severity carried by the missing-justification error when the requirement is switched on.
- **Severity and security metadata in SARIF output** — for the suppression output surface.
- **Build gating and the exit code contract** — not a prerequisite. The shared filtering path is extracted by this work and the gate consumes it. Suppression is what makes the gate adoptable, so the two ship together.

No language or specification change, and no new published module.

## Future Work

- **Expiring suppressions**, with a review date that turns the suppression back into a finding once passed. The highest-value governance addition, and deferred only because it cannot ship until someone owns the policy question of what expiry does — break the build, or report.
- **Structured justification fields** — a ticket reference, an approver, a review date — replacing free text where a team wants them enforced rather than conventional.
- **Per-rule exemption from the justification requirement**, for teams that want a reason on security findings but not on maintainability ones.
- **An aggregated suppression report.** A convenience view over data already present in the SARIF output, so nothing is blocked without it.
- **Stale directives reported as a finding** rather than a warning, so suppression hygiene can be gated on. Deferred until the gate exists, since a gate is what a team would act on it with.
- **An option to list suppressed findings on the console**, if the divergence between the console listing and the saved report proves unhelpful in practice.
- IDE quick fix to insert a directive, and rule-identifier validation as you type.
- Migration tooling from project-wide exclusions to in-source directives, for the case where a rule was disabled globally because of a handful of accepted findings.
- A fuller audit mode that also disregards rule selection, closing the gap where a project-wide exclusion hides findings that the suppression audit run cannot reveal.

## References

- [Ballerina Language Specification §9.1 — Annotations](https://ballerina.io/spec/lang/master/#section_9.1) — attachment points; the basis for the annotation alternative
- [SARIF 2.1.0](https://docs.oasis-open.org/sarif/sarif/v2.1.0/sarif-v2.1.0.html) — `suppression` object, `kind: "inSource"`
- NIST SP 500-268 SCSA-RO-2 — suppression as an analyzer capability requirement
