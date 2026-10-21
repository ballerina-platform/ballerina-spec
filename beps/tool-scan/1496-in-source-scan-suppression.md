# 1496: In-source suppression of scan findings

- Authors - @TharmiganK
- Reviewed by - TBD
- Created date - 2026-09-04
- Updated date - 2026-10-21
- Issue - [#1496](https://github.com/ballerina-platform/ballerina-spec/issues/1496)
- State - Draft

## Summary

Allow a developer to suppress an individual `bal scan` finding at the point in the source where it occurs, with a justification, recorded in the output so suppressions remain auditable rather than invisible. The justification is optional by default and a team can require it, failing the scan when one is missing.

The mechanism is a source-only annotation, `@scan:Suppress`, attached to the construct that contains the finding. Because it lives in the source, each suppression is reviewed in the diff that introduces it and attributed through version control, and an audit run can disregard suppressions entirely to show the unfiltered picture. Because it is an annotation, its attachment is defined by the grammar and comments keep meaning nothing; and the package that defines it ships a compiler plugin that checks every rule identifier against the rules `bal scan` can actually report, so the rule set can grow without the annotation changing.

## Motivation

A build gate is only adoptable if there is a sanctioned way to say "this one is fine, and here is why".

One mechanism exists today and it is not that. **Project-wide rule exclusion** turns a rule off everywhere: one accepted instance disables the rule for the whole project, including for code written next year. It is configured in the scan configuration file, and it is also what the IDE's exclusion action writes, so the finest exclusion reachable from the editor is still project-wide.

It has nowhere to record *why*. A reviewer reading an exclusion list cannot distinguish an accepted risk from a false positive from someone silencing a rule to get a build green. For a tool producing compliance evidence, an unexplained exception is worse than none: it is an audit finding. What is missing is not only a finer granularity but somewhere to put the reason, and a way for a team that needs one to insist on it.

Without this, a team adopting the gate has two options — fix everything first, or disable the rule globally. Most choose the second, and the gate stops meaning anything.

## Goals

- Suppress a single finding at the construct that contains it, for every rule the tool ships.
- Every suppression can carry a justification, and a team that requires one can make the scan fail without it.
- Rule identifiers are validated at compile time against the rules available to the package, including rules added later and rules from third-party analyzers.
- No runtime footprint.
- No new meaning given to comments, and no change to the language grammar.
- Suppressions are visible in the output without reading the source.
- Every suppression records **what** was accepted, and **why** wherever a justification is given.
- **Who** accepted it and **when** are answerable from version control, without the annotation carrying them.
- The true unsuppressed picture is obtainable on demand, so a security review never has to take suppressions on trust.
- One coherent story alongside the existing rule exclusion, so it is clear which to reach for.

## Non-Goals

- **Removing project-wide rule exclusion.** It remains legitimate: a project with no HTTP services does not need HTTP rules.
- **Expiring suppressions.** Time-boxed suppressions need a policy owner before they need a syntax.
- **Bulk acceptance of an existing backlog.** Suppression handles individually reviewed exceptions, one at a time, each with a reason. Grandfathering in everything a codebase already has is the job of the [baseline work](https://github.com/ballerina-platform/ballerina-spec/issues/1498), and using suppression for it means hundreds of annotations carrying invented justifications — which destroys the value of requiring one.
- **Annotations on statements.** Widening the annotation attach points so that any statement can be annotated is not proposed. The two rules that cannot be suppressed at their own statement (see [Placement](#placement)) do not justify a language change driven by a lint concern.

## Design

### The annotation

Defined in a published package, `ballerina/scan`:

```ballerina
# Identifier of a `bal scan` rule: `ballerina:<number>` for a core rule, or `<org>/<package>:<number>` for a rule
# contributed by a package's analyzer.
public type RuleId string;

# Accepts `bal scan` findings reported within the annotated construct.
#
# + rules - The rules being accepted; every rule when absent
# + reason - Why the findings are accepted
public type SuppressConfig record {|
    [RuleId, RuleId...] rules?;
    string reason?;
|};

public const annotation SuppressConfig[] Suppress on source var, source const, source type, source class,
    source function, source parameter, source return, source field, source service, source listener,
    source worker, source external;
```

```ballerina
import ballerina/scan;

@scan:Suppress {rules: ["ballerina/crypto:2"], reason: "Legacy hash retained for migration, SEC-1042"}
string hashed = check crypto:hashBcrypt(password, 4);

@scan:Suppress {rules: ["ballerina/log:1"], reason: "values redacted upstream"}
var _ = log:printInfo(summary);

@scan:Suppress {rules: ["ballerina/http:2"]}
@http:ResourceConfig {cors: {allowOrigins: ["*"]}}
resource function get feed() returns string => "feed";

@scan:Suppress {reason: "generated block, reviewed once"}
function generatedMapping(Row[] rows) {
    ...
}
```

Both fields are optional, as the third and fourth examples show: omit the justification, omit the rule list, or omit both (`@scan:Suppress` alone). An annotation with no rule list suppresses **every** finding in the construct it is attached to; an annotation with no justification suppresses silently. The Justification section below covers how a team makes either of them required.

Every attach point is `source`, so the annotation is not present at runtime. `function` covers functions, methods, resource methods and remote methods.

`RuleId` is the identifier the tool already prints and already accepts in rule inclusion and exclusion — `ballerina:1` for a language rule, `ballerina/crypto:2` for a module rule — so a developer copies it from the finding rather than learning a second form. It is deliberately a `string` rather than a union of the known identifiers: the tool adds rules in every release and any package can contribute rules through its analyzer, so a closed type would have to change with every rule and could never list a third-party analyzer's rules. The content of each identifier is checked by the compiler plugin instead (see [Rule identifier validation](#rule-identifier-validation)).

**The annotation may be attached more than once to the same construct**, which is why its type is `SuppressConfig[]`, and the rule lists combine — necessary rather than incidental, since an annotation carries one justification and a construct may need two justifications for two rules:

```ballerina
@scan:Suppress {rules: ["ballerina/jwt:5"], reason: "Lab IdP hosts have drifting clocks, LAB-12"}
@scan:Suppress {rules: ["ballerina/jwt:6"], reason: "Lab JWKS endpoint uses a self-signed certificate, LAB-13"}
jwt:Payload payload = check jwt:validate(token, {
    clockSkew: 3600,
    signatureConfig: {jwksConfig: {url: labJwksUrl, clientConfig: {secureSocket: {disable: true}}}}
});
```

### Rule identifier validation

`ballerina/scan` ships a compiler plugin. Because it is a compiler plugin of a direct dependency, it runs on every package that imports `scan`, during `bal build`, `bal scan` and in the language server alike. For each `@scan:Suppress` annotation it resolves the identifiers against a rule catalog built the same way `bal scan` builds its own:

- **Core rules** (`ballerina:<number>`) ship with the scan tool, not with the package. The plugin checks only their format; the running tool checks them against its own rule list, under `bal scan` and in the language server, and an unknown one is an error that fails the scan. A core rule added to the tool therefore needs no release of `ballerina/scan`.
- **Analyzer rules** (`<org>/<package>:<number>`) come from the `rules.json` inside the compiler plugin of each direct dependency — exactly where `bal scan` reads them from. A rule added to `ballerina/http` is accepted as soon as the project depends on the version that defines it, with no change to `ballerina/scan`.
- **Analyzers declared only in the scan configuration file** are not dependencies during an ordinary build, because `bal scan` adds them as imports only when it runs. The plugin cannot see their rules during `bal build`, so it reports a warning rather than an error. Under `bal scan` they are dependencies, and the same identifiers are checked strictly: an unknown one is a compile error, and the scan does not run.

The rule list may hold string literals and references to string constants, or be a reference to a constant list. Any other expression, such as a string template, is reported as unverifiable, and it suppresses nothing: an identifier that does not resolve never turns the annotation into one that applies to every rule, and `bal scan` warns about it when it runs.

| Code | Severity | Diagnostic |
|---|---|---|
| `SCAN_SUPPRESS_101` | Error | `invalid rule ID 'http:1': expected 'ballerina:<number>' or '<org>/<package>:<number>'` |
| `SCAN_SUPPRESS_102` | Error | `unknown rule 'ballerina/http:9': 'ballerina/http' does not define this rule` |
| `SCAN_SUPPRESS_103` | Warning | `cannot verify rule 'acme/lint:1': 'acme/lint' is not a direct dependency with scan rules; it is checked again when 'bal scan' runs` |
| `SCAN_SUPPRESS_104` | Warning | `blank suppression reason; it is treated as absent` |
| `SCAN_SUPPRESS_105` | Warning | `rule 'ballerina:13' is listed more than once` |
| `SCAN_SUPPRESS_106` | Warning | `cannot verify rule '<expression>': use a string literal or a constant` |
| `SCAN_SUPPRESS_107` | Error | `empty rule list; omit 'rules' to suppress every rule` |

The empty-list check is needed in the plugin rather than the type: a list constructor `[]` against `[RuleId, RuleId...]` is completed with the `string` filler value and compiles. Beyond the plugin, the types reject a misspelled field and an annotation on a construct that is not an attach point, for every construct the parser keeps (see [Known defects](#known-defects)).

### Binding

An annotation binds to the **construct** it is attached to, as defined by the grammar. Formatting moves lines; it cannot detach an annotation from its construct, so the binding needs no rules of its own and no guard against formatter changes.

A finding is suppressed when its reported location falls **wholly within** the annotated construct and the annotation applies to its rule — because the rule is named, or because the annotation names none and so applies to all. Containment rather than overlap is what keeps an annotation from reaching a sibling. For a local or module variable declaration the construct is the whole statement, including a multi-line initializer; for a function it is the signature and the body. Annotating a declaration that encloses other constructs is legal and scopes to the whole body, which is worth being deliberate about: an annotation with no rule list on a function silences everything in it, including findings a later author introduces.

**A suppression on a service, class or object type does not reach into its members.** It covers the declaration's own header and metadata — for example, the `cors` field of an `@http:ServiceConfig` — but each resource, method or field is suppressed on its own. Without this, one service-level suppression would silently cover every resource added to the service later.

Where annotations nest, **the innermost annotation that applies to the rule wins**: it supplies the recorded justification and it is the one credited with the match. An annotation on an inner construct naming an unrelated rule does not cancel an accepted exception on an enclosing one — the stricter reading would make a declaration-scoped suppression stop applying the moment anyone added an unrelated annotation inside the body.

On one construct, when more than one annotation applies to the rule, **the annotation that names the rule wins over one that names none**, and among equally specific annotations the first in source order wins. A blanket annotation beside a rule-specific one therefore never takes the rule-specific one's justification or match: it is credited only with the findings no named annotation claims, and reported as unmatched when there are none.

### Placement

Of the 42 rules in `bal scan` 0.12.0, 40 are suppressed at the declaration that produces the finding or at the statement that contains it. The other two fall back to the enclosing function or resource.

| Rule | Reported at | Annotation on | Restructuring needed when |
|---|---|---|---|
| `ballerina:1` checkpanic | the `checkpanic` expression | local variable | used in `return` or a call statement |
| `ballerina:2` unused parameter | the parameter | parameter | — |
| `ballerina:3` non-isolated public function | the function | function | — |
| `ballerina:4` non-isolated public method | the method | method | — |
| `ballerina:5` non-isolated public class | the class | class | — |
| `ballerina:6` non-isolated public object | the type | type definition | — |
| `ballerina:7` always true | the binary expression | local variable | used as a condition |
| `ballerina:8` always false | the binary expression | local variable | used as a condition |
| `ballerina:9` always the same value | the binary expression | local variable | used as a condition |
| `ballerina:10` self-assignment | the assignment statement | **enclosing function** | cannot be restructured |
| `ballerina:11` unused private field | the field | object field | — |
| `ballerina:12` invalid range | the range expression | local variable | used directly in `foreach` |
| `ballerina:13` hard-coded secret | the literal | const, variable, field or parameter | used as a named argument in a call statement |
| `ballerina:14` non-configurable secret | the value | variable or field | used as a named argument in a call statement |
| `ballerina/crypto:1` insecure mode or padding | the call | local variable | used in `return` |
| `ballerina/crypto:2` fast hashing | the call | local variable | used in `return` |
| `ballerina/crypto:3` hard-coded IV | the call | local variable | used in `return` |
| `ballerina/file:1` world-writable directory | the `os:getEnv("TMP")` source | local variable | — |
| `ballerina/file:2` path injection | the call | local variable | call statement |
| `ballerina/http:1` default resource accessor | the `default` accessor | resource method | — |
| `ballerina/http:2` permissive CORS | the origin inside `@http:ServiceConfig` or `@http:ResourceConfig` | service or resource method | — |
| `ballerina/http:3` SSRF | the path segment of the client action | local variable | used in `return` |
| `ballerina/http:4` open redirect | the `Location` field of a returned literal | **enclosing resource method** | restructuring stops the rule from firing |
| `ballerina/io:1` path injection | the call | local variable | call statement |
| `ballerina/io:2` configurable printed | the argument | local variable | call statement |
| `ballerina/log:1` configurable logged | the argument | local variable | call statement |
| `ballerina/log:2` world-writable log file | the path literal | local variable | `log:setOutputFile` call statement |
| `ballerina/os:1` command argument injection | the call | local variable | used in `return` |
| `ballerina/os:2` environment variable injection | the call | local variable | call statement |
| `ballerina/os:3` shell interpreter | the call | local variable | used in `return` |
| `ballerina/os:4` command resolved through `PATH` | the executable literal | local variable | used in `return` |
| `ballerina/jwt:1` weak or no signing algorithm | the `jwt:issue` call | local variable | — |
| `ballerina/jwt:2` no signature configuration | the `jwt:validate` call | local variable | — |
| `ballerina/jwt:3` no issuer or audience | the `jwt:validate` call | local variable | — |
| `ballerina/jwt:4` long expiry | the `expTime` field | local variable | — |
| `ballerina/jwt:5` large clock skew | the `clockSkew` field | local variable | — |
| `ballerina/jwt:6` JWKS TLS disabled | the `disable` field | local variable | — |
| `ballerina/jwt:7` decode without verify | the `jwt:decode` call | local variable (list binding pattern) | — |
| `ballerina/email:1` hostname not verified | the `verifyHostName` field | local or module variable | assigned to a field in `init` |
| `ballerina/email:2` no TLS | the `security` field | local or module variable | assigned to a field in `init` |
| `ballerina/email:3` cleartext fallback | the `security` field | local or module variable | assigned to a field in `init` |
| `ballerina/email:4` weak TLS version | the version literal | local or module variable | assigned to a field in `init` |

The two fallbacks are acceptable:

- **`ballerina:10`** reports a self-assignment, which has no legitimate reason to be kept. The only realistic suppression is in generated code, where a function-level annotation is the right scope anyway.
- **`ballerina/http:4`** fires only when the redirect literal is returned directly; assigning it to a variable first makes the rule stop firing. A resource method typically issues at most one redirect, so a resource-level suppression covers exactly one finding in practice — the same reason service- and resource-level placement is right for `ballerina/http:2`, whose finding sits inside another annotation's value.

### Restructuring patterns

Where a finding sits in a statement that is not a declaration, one mechanical rewrite turns it into one:

| Statement | Rewrite | Notes |
|---|---|---|
| `return expr;` | `T result = expr; return result;` | |
| `check f(...);` or `f(...);` | `var _ = check f(...);` or `var _ = f(...);` | The finding stays on the call, inside the declaration. Use `var _`; an annotated typed wildcard such as `() _` crashes the compiler today (see [Known defects](#known-defects)) |
| `if cond { ... }` | `boolean c = cond; if c { ... }` | The finding moves to the declaration |
| `foreach int i in 9...0` | `var range = 9...0; foreach int i in range` | The finding moves to the declaration |
| `self.field = expr;` | `T value = expr; self.field = value;` | |

Extracting an **argument** into a variable does not work for rules that report at a sink call (`file:2`, `io:1`, `io:2`, `log:1`, `os:1`–`os:4`, `http:3`): the finding stays on the call, outside the annotated declaration. The call itself must be wrapped.

A rewrite is also able to change what a rule sees. If it makes a rule stop firing, the annotation matches nothing and is reported as unmatched (see [Reporting](#reporting)), so the change cannot pass silently. The IDE quick fix applies these rewrites itself, so a developer rarely writes one by hand.

### Justification

**`reason` is optional, and requiring it is opt-in.** By default an annotation without one suppresses and nothing is reported about it. A team that wants the justification guaranteed switches the requirement on, and then an annotation missing one is reported as an **error** — `bal scan` fails, naming the annotation and the file and line it sits on. The requirement is expressed in the scan configuration file, so it is a property of the project rather than of one invocation, with a command-line option to switch it on for a single run:

```toml
[suppression]
requireReason = true
```

**Requiring the reason does not make the annotation inert.** With the requirement on, an unjustified annotation still suppresses its finding; what fails the scan is the missing justification, reported at the annotation. The alternative — refusing to suppress until a reason is written — means switching the requirement on in an existing project floods the output with the accepted findings *and* the missing-reason errors at once, and a developer cannot tell which they are being asked to fix. Failing on the one thing that is actually wrong is the more useful behaviour.

**This is the prevailing shape, not a departure from it.** Suppression mechanisms in comparable analyzers treat the reason as optional and, where they enforce it at all, do so through a setting a team switches on. Some offer a justification field with no enforcement; several carry no reason at all. Keeping the field optional and the requirement configurable means a team with a compliance obligation gets it enforced, and a team without one gets a mechanism they will use rather than route around.

**Naming the rules is requirable on the same terms.** By default an annotation with no rule list suppresses every finding in its construct. `--require-suppression-rule-id`, or `requireRuleId` in the same table, reports an annotation that names no rule as an error and fails the scan, exactly as the justification requirement does.

The two requirements are independent, so a project can insist on one, both or neither. A team using suppression as compliance evidence will want both on; a team using it to quiet a handful of false positives may want neither, and the audit run tells them what they are carrying either way.

The requirements are checked by `bal scan` rather than by the compiler plugin, because they are scan configuration and a command-line option can switch them on for one run. The plugin's checks are the ones that hold regardless of configuration: an identifier that is given must exist.

**The annotation records what and why; version control supplies who and when.** An audit asks four questions of any accepted risk. For

```ballerina
@scan:Suppress {rules: ["ballerina/crypto:2"], reason: "Legacy hash kept for migration window, SEC-1042"}
string hashed = check crypto:hashBcrypt(password, 4);
```

the answers are:

| | Answer | Source |
|---|---|---|
| What was accepted | `ballerina/crypto:2`, in this declaration, in this file | the annotation's rule list and the construct it is attached to |
| Why | a legacy hash kept for a migration window, tracked as SEC-1042 | the `reason` field |
| By whom | the author of the line | version control |
| When | the commit date | version control |

The annotation deliberately does not carry an author or a date. Recording them in the source means two more fields to write, to keep accurate, and to lie in — while version control already answers both, and cannot be edited without leaving a trace. This division is the strongest argument for in-source suppression over an external suppression list, where the last two questions have no answer at all. Version control records who wrote and committed the change, not who approved it; approval lives in the code-review record of the hosting platform, and an audit that treats it as evidence relies on that platform's records, which this proposal does not define.

### Configuration

Suppression is controlled from the `[suppression]` table of the scan configuration file and from `bal scan` options. Every setting is opt-in, so a project that configures nothing gets suppressions applied, with no requirement enforced.

```toml
[suppression]
enabled = true        # false: disregard every annotation, as --ignore-suppressions does
requireReason = false # true: fail the scan when an annotation gives no reason
requireRuleId = false # true: fail the scan when an annotation names no rule
```

| `Scan.toml` key | `bal scan` option | Default | Effect |
|---|---|---|---|
| `enabled` | `--ignore-suppressions` (sets it to `false` for one run) | `true` | When `false`, every annotation is disregarded and every finding is reported, as in the audit run |
| `requireReason` | `--require-suppression-reason` | `false` | An annotation without a reason fails the scan |
| `requireRuleId` | `--require-suppression-rule-id` | `false` | An annotation that names no rule fails the scan |

**The command line can tighten the configuration for a run, but not loosen it.** An option can disable suppressions or switch a requirement on for a single invocation; it cannot re-enable suppressions or switch a requirement off when the configuration file sets them. A team that needs a guarantee therefore puts it in the configuration file, which is checked in and reviewed. Because the configuration file can be loaded from a URL through `[scan] configPath`, an organization can publish one file that every project's CI uses, for example to require reasons everywhere, or to set `enabled = false` so that a security pipeline always reports the unsuppressed results without depending on each pipeline passing a flag.

**`enabled = false` is the audit run made persistent.** It disregards annotations only: rule selection still applies, requirement violations are still reported, and unmatched suppressions are not, exactly as with `--ignore-suppressions`.

The language server reads the same table, so the editor shows the same active and suppressed findings as `bal scan`. It does not take command-line options.

### Reporting

**SARIF.** Each suppressed result carries a `suppressions` array (SARIF 2.1.0, §3.27.23) with one `suppression` object (§3.35):

```json
"suppressions": [
  {"kind": "inSource", "status": "accepted", "justification": "Legacy hash kept for migration window, SEC-1042"}
]
```

- `kind` is `inSource`, the value SARIF defines for a suppression expressed by a construct of the programming language, such as an attribute or annotation.
- `status` is `accepted`, because consumers that need a result's suppression state are required to read it from `status`.
- `justification` is the annotation's `reason`, omitted when the annotation gives none.
- SARIF requires the `suppressions` values of all results in a run to be either all present or all absent. Once any result of a run is suppressed, every other result therefore carries an empty array, which SARIF defines as "not suppressed". A run with no suppressed result omits the property everywhere, so its output is unchanged.

Suppressed results are present and marked, not omitted — that is what makes them auditable, and what the SARIF specification intends.

**JSON.** The same `suppressions` array, on suppressed findings only.

**Console.** Suppressed findings are not listed, so the console listing and the saved report no longer hold the same set — the report keeps them, the console does not. When anything is suppressed, a summary line follows the listing, for example `3 issue(s), 2 suppressed`. Diagnostics about the annotations themselves — unmatched suppressions, and unmet requirements — are printed with their location, for example `WARNING [main.bal:(23:5,23:71)] suppression of 'ballerina:7' did not match any issue`.

**HTML report and platforms.** The HTML report and the issues passed to static code analysis platform plugins contain unsuppressed findings only. Neither has a representation for a suppressed finding, and passing suppressed findings to a platform that does not understand them would report them as ordinary issues.

**Language server.** The response gains a `suppressedIssues` array, each entry carrying the issue, the rules the annotation named and the justification, and a `suppressionDiagnostics` array with the same diagnostics the console prints. `activeIssues` holds unsuppressed findings only.

**Gate.** Suppressed findings do not count toward severity or issue-count thresholds. The gate itself arrives with the gating work, so this becomes observable there rather than here.

**Unmatched suppressions are reported.** An annotation, or a rule in its list, that suppressed nothing is stale — the finding was fixed, the rule stopped firing after a rewrite, or the annotation is on the wrong construct. The compiler plugin catches misspelled identifiers, so this report is about placement and staleness rather than typos. It is also an audit control in its own right: accumulated stale suppressions are the clearest signal that a codebase's exceptions are no longer being maintained. The control is well established: comparable analyzers all report suppressions that no longer suppress anything.

**New suppressions appear in code review.** Because an annotation is part of the source, adding one shows up in the diff alongside the change that needed it. The exception is scrutinised at the moment it is created, by someone with the context to judge it — which is worth more than any report produced months later. An external suppression file achieves this only if reviewers happen to read it.

**An audit run reports the unsuppressed picture.** `--ignore-suppressions`, or `enabled = false` in the configuration file, runs the scan with every annotation disregarded, so the full set of findings is reported and gated as though no suppression existed. A security review's first question is what the codebase looks like without them, and "trust our suppressions" is not an answer. The flag changes nothing about the scan itself, only whether the suppression filter is applied.

The flag also silences the unmatched report, which would otherwise name every annotation in the project. Findings and warnings about the annotations themselves, an absent justification among them, describe the source rather than the suppression and are still reported.

### Relationship to the existing mechanisms

The two mechanisms are not variants of one another. **Rule selection** decides which rules apply at all; **finding acceptance** is where the rule applied, found something real, and a person accepted it. That distinction determines how they combine.

| Mechanism | Category | Granularity | Records why | Use |
|---|---|---|---|---|
| Project-wide rule inclusion/exclusion | Rule selection | Project | No | The rule does not apply to this project |
| `@scan:Suppress` | Finding acceptance | Declaration or statement | **Yes** | This specific occurrence is accepted |

A file-scoped exclusion, for the case where a rule genuinely does not apply to a whole file — generated code, test fixtures — would be a third entry in the rule-selection column. None exists today. If one is wanted it should be designed as rule selection, not as a way to accept a finding.

### Precedence

Rule selection is resolved first, then findings are produced, then suppressions are applied:

1. **Rule selection** — command-line options and scan configuration decide which rules can produce findings. Command line overrides configuration.
2. **Analysis** — the selected rules run and produce findings.
3. **In-source suppressions** — suppress individual findings.
4. **Gate** — evaluates what is left, and arrives with the gating work.

A file-scoped exclusion, were one added, would sit between analysis and suppressions.

Two consequences follow, and both are deliberate.

**Rule selection wins, because it acts earlier.** An annotation naming a rule that is excluded project-wide, or absent from an inclusion list, has nothing to suppress. It is reported as **unmatched** — which is the useful outcome: it tells a team they are carrying a justified exception for a rule that is not even running, usually because someone disabled the rule globally and forgot the annotation.

**Exclusion and suppression differ in what reaches the output.** An excluded finding is *absent*: no record, nothing to review. A suppressed finding is *present and marked*, with its justification. This is the whole reason both exist — exclusion says "not applicable", suppression says "applicable, and accepted". A team that wants an auditable trail must suppress rather than exclude, and the documentation should say so plainly.

Between annotations, the innermost one applying to the rule wins, and on one construct the one naming the rule, as described under Binding.

### Scope of the audit run

`--ignore-suppressions` disregards **annotations only**. Rule selection is configuration rather than accepted risk, so an audit run does not re-enable excluded rules.

This leaves an honest gap: a team can dodge findings by excluding a rule project-wide, and the audit run will not reveal it. Rule selection is visible in the checked-in configuration and in its diff, so it is not hidden — but it is not surfaced by the same command. A fuller audit mode that also disregards rule selection is worth considering, and is recorded in Future Work rather than resolved here.

### The IDE's exclusion action

What the IDE offers today writes a project-wide rule exclusion into the scan configuration file — putting a machine-edited array into a hand-edited file, and disabling the rule everywhere in response to one accepted finding.

**Proposed: the IDE's "suppress this finding" action inserts a `@scan:Suppress` annotation** on the innermost construct that can carry it, applying the restructuring pattern when the finding sits in a statement that is not a declaration, and adding the import if it is missing. Rule exclusion is retained for genuine whole-file and whole-project cases — generated code, test fixtures, rules that do not apply — but stops being the default response to a single finding. Deciding this here rather than in the IDE work is the point: otherwise the editor entrenches configuration editing as the normal way to accept a finding, and the IDE integration inherits the ambiguity.

### Consistency across entry points

The scan runs from two entry points, the command line and the language server, and they currently duplicate the filtering sequence rather than sharing it — they have already diverged. Suppression must behave identically from both, so **this work extracts the shared analyze-and-filter path** rather than waiting for the gating work to do it. The gating proposal leaves the placement of that extraction to review; it belongs here, because this is the first piece of work that would otherwise write the duplicate.

### Compatibility and migration

**Additive.** No existing configuration changes meaning, and there are no suppressions in the field to migrate.

**`ballerina/scan` is versioned on its own, starting at 1.0.0.** The package only declares the annotation and validates its rule identifiers, and neither depends on which rules exist: library rules are read from each dependency, and core rules are checked by the tool. It is therefore released as a stable 1.0.0 while the tool continues through prerelease versions, and is released again only when the annotation or its validation changes. Adding a field or an attach point is backward compatible and would be a minor release.

**One import.** A project that suppresses anything imports `ballerina/scan`. Its compiler plugin runs at compile time only.

**No runtime impact.** Every attach point is `source`, so the annotation is not retained in the compiled program.

**Formatting is safe by construction**, because the binding is a syntax node rather than the position of a comment.

**Output shape changes only where suppression is used.** A project that does not depend on `ballerina/scan` produces exactly the output it does today. Where suppression is used, SARIF and JSON findings gain `suppressions` entries, the console gains a summary line and suppression diagnostics, and the language-server response gains `suppressedIssues` and `suppressionDiagnostics`.

**New options, all opt-in.** `--ignore-suppressions`, `--require-suppression-reason` and `--require-suppression-rule-id`, with their `[suppression]` counterparts `enabled`, `requireReason` and `requireRuleId` (see [Configuration](#configuration)). None changes the behaviour of an existing invocation, and `[suppression]` is a new table, so no existing scan configuration changes meaning. In particular, a project that adopts suppression without switching a requirement on never sees a new failure.

**Additive API.** For platform plugins and other consumers of the scan tool's Java API, the changes are additions: a `SuppressedIssue` type, a `ScanResult` constructor and accessor for suppressed issues, and accessors on the scan configuration for the `[suppression]` settings.

## Known defects

Found while verifying this design against Ballerina 2201.14.1. Both need to be raised against the compiler.

1. **The parser silently drops an annotation placed before a call statement or an assignment statement.** `@scan:Suppress {...} log:printInfo(x);` and `@scan:Suppress {...} _ = f();` compile with no diagnostic, even when the annotation does not exist. The text is removed from the syntax tree, so the scan cannot see the annotation; every finding later in the same file is then reported at a shifted location; and `bal format` deletes the annotation from the source file. A developer would believe a finding was suppressed when it was not. The same construct with a `check` expression (`@a check f();`) is correctly rejected with "annotation not attached to a construct"; the call and assignment forms must produce the same error. **This must be fixed before the feature ships.**
2. **The compiler crashes on an annotated local variable declaration with a typed wildcard binding**, such as `@a () _ = f();` or `@a int _ = 1;` (`NullPointerException` in `BVarSymbol.addAnnotation`). `var _ = ...` is not affected, which is why the restructuring pattern uses it.

Rule defects observed in 0.12.0 that affect where suppressions go, to be raised against the rules:

- **`ballerina/http:4`** fires only when the redirect literal is returned directly. Assigning it to a typed variable first, or building the headers map separately, produces no finding.
- **`ballerina/os:1`** and **`ballerina/os:2`** do not treat resource method parameters as user input; they fire for public function parameters only.
- **`ballerina:9`**'s documented example, `x % 1`, does not trigger the rule. The rule fires for `a && true`, `a || false`, `a & -1` and `a | 0`.
- **`ballerina/file:1`** reports at the `os:getEnv("TMP")` call that produces the path, while **`ballerina/file:2`** reports the call that uses it; the rule documentation should say where each one reports.

## Alternatives

### A comment directive

```ballerina
// scan:suppress ballerina/crypto:2 reason="Legacy hash retained for migration, SEC-1042"
string hashed = check crypto:hashBcrypt(password, 4);

log:printInfo(summary);  // scan:suppress ballerina/log:1 reason="values redacted upstream"
```

A directive placed immediately before, or at the end of, the line that produced the finding — the previous revision of this proposal.

**In favour**

- Reaches any statement, so `ballerina:10` and `ballerina/http:4` could be suppressed at the statement rather than the enclosing function, and no restructuring is needed elsewhere.
- Needs no import and no published package.
- Familiar from languages without an annotation system.

**Against**

- **It gives comments semantics.** Ballerina already made documentation a syntax of its own rather than a comment convention, and provides `source` attach points precisely for compile-time metadata a tool reads. A directive comment works around both.
- **Binding has to be invented.** The parser treats comments as trivia, so which construct a directive binds to needs its own grammar and rules — leading and trailing forms that scope differently — and those rules must be guarded against every formatter change. The trailing form is ambiguous for multi-line statements, which is where the jwt and email rules report.
- **Nothing is validated at compile time.** A misspelled rule identifier compiles and silently suppresses nothing, and a malformed directive is at best a scan warning.
- **Its coverage advantage is two rules** in 0.12.0, both acceptable at function or resource level for the reasons given under [Placement](#placement).
- Languages that do have an annotation system use it for suppression: Java `@SuppressWarnings`, C# `[SuppressMessage]`, Kotlin `@Suppress`, Rust `#[allow]`. Java's has exactly the limitation proposed here — declarations, including local variables, but not statements.

**Assessment.** Rejected. The coverage it adds does not justify giving comments meaning in a language that has a typed mechanism for exactly this.

### A closed `RuleId` type

Declare `RuleId` as a union of the known identifiers, so that the type checker alone rejects unknown ones.

**In favour:** no compiler plugin.

**Against:** the type must change whenever any rule is added, an older `ballerina/scan` cannot name a newer rule, and a third-party analyzer's rules can never be listed.

**Assessment:** rejected, in favour of an open `string` checked by the plugin against the rules actually available.

### Widening the annotation attach points to statements

**In favour:** closes the two remaining placement gaps.

**Against:** a language change driven by a lint concern, with every future rule able to justify more attach points.

**Assessment:** rejected. Restructuring covers every statement form except self-assignment.

### Placing the annotation in `lang.annotations`

**In favour:** available without an import, alongside `@deprecated` and `@display`.

**Against:** lang-lib modules are built into the distribution rather than resolved as packages with compiler plugins, so rule identifiers could only be checked when `bal scan` runs, and the core rule list would version with the distribution rather than with the tool. It also needs a lang-lib change.

**Assessment:** rejected.

### A suppression file outside the source

**In favour:** no annotations in the code, and all suppressions visible in one place.

**Against:** entries drift on every edit so the file rots, and the justification sits far from the code it justifies.

**Assessment:** rejected.

### Per-file or per-line keys in the scan configuration file

**In favour:** reuses a format that already exists.

**Against:** the same drift problem, and it puts machine-maintained data into a hand-edited file. Anchoring an entry to a place in a file needs something to relocate it by — a symbol name, a line hash — which is a workaround for the drift rather than an answer to it, and the entry is still lost when the line is edited.

**Assessment:** rejected.

### Requiring every annotation to name a rule

**In favour:** an annotation with no rule list silences everything in its construct, including findings a later author introduces, and unlike a missing justification that cannot be spotted by reading the annotation.

**Against:** it is the same decision-for-everyone objection as the justification, and it removes the one form that makes the mechanism usable on generated or vendored code where the whole block is accepted. Whether specificity is required is a project's policy, not a property of the mechanism.

**Assessment:** rejected as unconditional, provided as `requireRuleId`. The reporting is the compensating control: a suppression entry records which rules it actually suppressed, so a blanket annotation's real effect is visible in the report rather than inferred from the source.

### A justification required unconditionally

**In favour:** the requirement is either absolute or it is advisory, and "required by convention" means "absent under deadline". Compliance evidence is the motivation for this work, so an unexplained suppression is the failure mode it exists to prevent. With an annotation it would cost nothing to enforce: `reason` would simply be a required field.

**Against:** it decides for every project a question only some of them have. It also adds friction exactly where the mechanism most needs adoption — a developer who cannot suppress a false positive without composing a sentence will reach for project-wide exclusion instead, which records nothing at all, and the outcome is worse than an unexplained suppression. And no comparable tool does it, so the behaviour would surprise.

**Assessment:** rejected, in favour of a requirement any project can switch on. The team with the compliance obligation gets enforcement; the team without one gets a mechanism they will actually use instead of routing around.

### Making the annotation inert when the justification is required but absent

**In favour:** the strictest reading of "required" — an annotation that does not meet the requirement does not take effect.

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

**Placement must be verified for every rule and guarded.** Every shipped rule must be triggered and suppressed at the construct given under [Placement](#placement), and this becomes a standing check so that a new rule reporting somewhere no annotation can reach is caught at review rather than by a user who cannot suppress it.

The check has two halves, because the rules do. For rules shipped in the tool, adding a rule without a suppression case must fail the build. For rules shipped by other modules, the check is published in the tool's test utilities and run by those modules — the only place it can live when the rule's source is elsewhere.

Beyond that:

- Rule identifier validation: a malformed identifier, an unknown core rule, an unknown rule of a direct dependency (literal or constant) and an empty rule list are compile errors; a duplicate identifier, a blank reason and an identifier of a provider that is not a dependency are warnings; valid core, dependency and constant identifiers, and a constant rule list, produce nothing; an identifier that does not resolve suppresses nothing and is reported by `bal scan`.
- Analyzers declared only in the scan configuration file: an identifier is a warning under `bal build`, accepted under `bal scan` when the analyzer defines it, and a compile error under `bal scan` when it does not.
- Core rules: a well-formed core identifier passes the plugin; under `bal scan` and in the language server, one the tool does not define is an error that fails the scan, and is not also reported as unmatched.
- Suppressing without a rule list: every finding in the annotated construct is suppressed, and nothing outside it.
- Each requirement, independently: off, the annotation suppresses silently; on, it still suppresses and the scan fails with an error naming the annotation's file and line. Both on together. A command-line option switches a requirement on, and cannot switch off one the configuration file sets.
- `enabled = false`: every finding is reported from both entry points, and requirement violations are still reported.
- Binding: a finding inside the annotated construct is suppressed; a finding outside it is not; a service, class or object-type annotation does not cover findings inside its members.
- Scoping: a nested annotation naming the same rule overrides an outer one; a nested annotation naming a different rule does not; no leakage to siblings; two annotations on one construct combine, each with its own justification; a rule-specific annotation beside a blanket one on the same construct supplies the justification and the match, whichever comes first.
- Restructuring patterns: each pattern keeps the finding inside the annotated declaration.
- Regression tests for both known compiler defects once fixed.
- Reporting: SARIF suppression entries carry `kind`, `status` and the justification; once a run has a suppressed result every other result carries an empty array, and a run without one carries none; JSON mirrors SARIF; console summary and unmatched diagnostics are correct; the HTML report and platform plugins receive unsuppressed findings only.
- Gate interaction: deferred with the gate itself.
- Audit mode: with `--ignore-suppressions`, every suppressed finding is reported. Findings from every other rule match a run with the annotations deleted; the annotations' own warnings do not, because deleting an annotation also deletes what there was to report about it.
- Identical behaviour from both entry points, asserted by shared fixtures.

## Risks and Assumptions

| Risk | Mitigation |
|---|---|
| An annotation before a call or assignment statement is dropped silently, so the developer believes the finding is suppressed | Compiler fix (Known defect 1) is a release blocker; until then the IDE quick fix only ever inserts the restructured form |
| A project names a core rule its installed scan tool does not define, for example one added in a later tool release | Core identifiers are checked by the running tool, so `bal scan` reports an error naming the rule; `bal build` accepts any well-formed core identifier |
| An analyzer declared only in the scan configuration file cannot be checked during `bal build` | Warning at build; strict check under `bal scan`, which is where the gate runs |
| Annotations proliferate as a way to get builds green | Each one surfaces in the pull request diff when added; visible counts; suppressed findings present in the output; `--ignore-suppressions` exposes the true picture on demand; a team can require the justification and fail the scan without it |
| An annotation with no rule list on a declaration silences findings a later author introduces | The suppression entry in the report names the rules actually suppressed, so the effect is visible rather than inferred; `requireRuleId` forbids the form outright for projects that want it forbidden; the audit run shows total exposure |
| A restructuring rewrite stops a rule from firing, hiding the finding instead of suppressing it | The annotation is then reported as unmatched; rule defects of this kind are fixed in the rule |
| A function-level fallback silences a second finding of the same rule added later | Limited to `ballerina:10` and `ballerina/http:4` today; the placement table is part of the rule review |
| Suppressions accumulate permanently, since nothing expires them | Unmatched counts show which have outlived their finding, and the audit run shows total exposure. A real fix needs expiry, which is deferred pending a policy owner — this is the known weakness of the GA scope |
| A new rule reports where no annotation can reach | Standing placement check; rule review asks "where does this report, and which construct carries the suppression?" |
| Suppression built twice across the two entry points | The shared filtering path is extracted as part of this work, and a parity test asserts both entry points agree |
| The IDE entrenches configuration editing as the way to accept a finding | The IDE action inserts an annotation; decided here rather than in the IDE work |
| Requiring the justification breaks a project that already carries unjustified annotations | Off by default and switched on per project, so it never fires on upgrade; and it fails on the missing reason only, never by resurfacing the suppressed findings |
| The justification stays optional in practice, so suppressions go unexplained | The field is there, it appears in the report, and the requirement is one setting away. Enforcing it for everyone was considered and rejected under Alternatives |
| The console listing and the saved report disagree, and someone reads the console as complete | The summary line states the suppressed count on every run; documented alongside the audit run |

**Assumptions.** That rules keep reporting at an expression, statement or declaration rather than at a position no declaration encloses. Every rule in 0.12.0 does.

## Dependencies

- **Rule severity and security standard metadata** — for the severity carried by the missing-justification error when the requirement is switched on.
- **Severity and security metadata in SARIF output** — for the suppression output surface.
- **Build gating and the exit code contract** — not a prerequisite. The shared filtering path is extracted by this work and the gate consumes it. Suppression is what makes the gate adoptable, so the two ship together.
- **Compiler fix for Known defect 1** — a release blocker.
- **Publishing `ballerina/scan` 1.0.0**, with its compiler plugin, once. Later tool releases do not republish it.

No change to the language grammar.

## Open questions

1. **Is a warning the right severity for analyzers declared only in the scan configuration file?** The alternative is for the plugin to read that file and resolve those analyzers itself during `bal build`, which duplicates the tool's resolution logic.

## Future Work

- **Expiring suppressions**, with a review date that turns the suppression back into a finding once passed. The highest-value governance addition, and deferred only because it cannot ship until someone owns the policy question of what expiry does — break the build, or report.
- **Structured justification fields** — a ticket reference, an approver, a review date — added to `SuppressConfig` where a team wants them enforced rather than conventional.
- **Per-rule exemption from the justification requirement**, for teams that want a reason on security findings but not on maintainability ones.
- **An aggregated suppression report.** A convenience view over data already present in the SARIF output, so nothing is blocked without it.
- **Stale suppressions reported as a finding** rather than a warning, so suppression hygiene can be gated on. Deferred until the gate exists, since a gate is what a team would act on it with.
- **An option to list suppressed findings on the console**, if the divergence between the console listing and the saved report proves unhelpful in practice.
- IDE quick fix to insert an annotation, including the restructuring rewrite.
- Migration tooling from project-wide exclusions to annotations, for the case where a rule was disabled globally because of a handful of accepted findings.
- A fuller audit mode that also disregards rule selection, closing the gap where a project-wide exclusion hides findings that the suppression audit run cannot reveal.
- **Rule selection in SARIF.** SARIF records a rule that is switched off for a run as a rule configuration (`invocations[].ruleConfigurationOverrides`, §3.20.5) rather than as a suppression. Emitting it would make project-wide exclusions visible in the same report as suppressions.
- **Suppressed findings in the HTML report**, shown with their justification, once the report has a view for them.

## References

- [Ballerina Language Specification §9.1 — Annotations](https://ballerina.io/spec/lang/master/#section_9.1) — attachment points and `source` annotations
- [bal scan rules](https://ballerina.io/learn/scan-rules/) — the rules shipped in 0.12.0
- [SARIF 2.1.0](https://docs.oasis-open.org/sarif/sarif/v2.1.0/sarif-v2.1.0.html) — `result.suppressions` (§3.27.23), `suppression` object (§3.35), `ruleConfigurationOverrides` (§3.20.5)
- [JLS §9.6.4.5 — `@SuppressWarnings`](https://docs.oracle.com/javase/specs/jls/se21/html/jls-9.html#jls-9.6.4.5) — declaration-scoped suppression, including local variables
- NIST SP 500-268 SCSA-RO-2 — suppression as an analyzer capability requirement
