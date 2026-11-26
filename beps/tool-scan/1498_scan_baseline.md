# Introduce Finding Fingerprints and Baseline Adoption for `bal scan`

- Authors - Charana Manawathilake
- Reviewed by - 
- Created date - 2026-11-23
- Updated date - 2026-11-26
- Issue - [1498](https://github.com/ballerina-platform/ballerina-spec/issues/1498)
- State - Draft

## Summary

This proposal gives every `bal scan` finding a stable identity, and uses it to let a team accept the findings that already exist and gate only on new ones.

- **Fingerprints.** Every finding gets a versioned fingerprint, `ballerinaScanHash/v1`, built from the rule ID, the package, the file path and the tokens of the flagged line, without whitespace or comments, but not from line numbers. It is written to SARIF `partialFingerprints` and to `scan_results.json`, and used by the baseline.
- **Baseline.** `bal scan --create-baseline` records the current findings in a file committed to the repository. When `[baseline]` is configured in `Scan.toml`, a scan matches findings against the file by fingerprint, and reports and gates only the findings that are not in it.
## Motivation

`bal scan` reports every finding on every run, and nothing in its output says that a finding in this run is the same finding as one in an earlier run.

On Monday, `bal scan` reports a hardcoded password.

```
ballerina:13  modules/db/client.bal  line 42  string password = "admin123";
```

On Tuesday, someone adds an import at the top of the file. The code is the same, but the report says:

```
ballerina:13  modules/db/client.bal  line 43  string password = "admin123";
```

Any tool that compares the two runs sees one finding fixed and one new. Two gaps follow from this.

- **The gate can't be turned on for an existing codebase.** The gate of [proposal 1497](1497_scan_exit_codes.md) counts every finding. On a codebase with 120 existing findings it fails the build on the first run, so a team either leaves the gate off, sets a count high enough to make it meaningless, or annotates 120 places with `@scan:Suppress` ([proposal 1496](1496-in-source-scan-suppression.md)).
- **Consumers can't track a finding across commits.** SARIF results carry only a rule ID, a path and a region. A consumer that receives the SARIF report has nothing stable to deduplicate on ([scan tool #113](https://github.com/ballerina-platform/static-code-analysis-tool/issues/113)).

The table lists what each result carries in scan tool 0.14.0, written by `ScanUtils.convertIssuesToSarifString` and `convertIssuesToJsonString`.

| Field | Value | Stable across commits? |
| --- | --- | --- |
| `ruleId` | e.g. `ballerina:1`, `ballerina/http:2` | Yes |
| `message.text` | The rule's description | Yes, but the same for every finding of the rule |
| `artifactLocation.uri` | Path relative to the project, with `/` separators | Yes, until the file is moved |
| `region` | Start and end line and column, offset and length | No. Shifts on any edit above it |
| `region.snippet.text` | The flagged text | Yes, until the flagged code is edited |
| `fingerprints`, `partialFingerprints` | Not written | Not applicable |

## What SARIF says

SARIF 2.1.0 separates the two kinds of fingerprint, and this proposal follows that split.

- **`partialFingerprints` (§3.27.17)** hold strings that each "contribute to the stable, unique identity" of a result. Each key is a versioned hierarchical string, such as `prohibitedWordHash/v3`. A producer SHOULD give its keys meaningful, documented names, and SHOULD use a new key, not change an existing one, when it changes how a value is computed. A result management system MAY combine the partial fingerprints with any algorithm, and SHOULD use the latest version present in both results.
- **`fingerprints` (§3.27.16)** hold the finished identity of a result: the same for logically identical results and different for logically distinct ones. "A direct SARIF producer SHOULD NOT populate this property." A converter MAY, and a result management system MAY when it ingests a report.
- **Hierarchical, versioned keys (§3.5.4).** A key is a hierarchical string: components joined by `/`, with no `/` inside a component. A last component of the form `v<n>` is the version `n`. A key without a version component is older than any versioned key with the same name.
- **`baselineState` (§3.27.24).** One of `new`, `unchanged`, `updated` or `absent`. When it's present on one result of a run, it SHALL be present on every result.

`bal scan` is a direct producer. So it writes its fingerprint to `partialFingerprints` only, and leaves SARIF `fingerprints` to the platforms that receive the report.

## Goals

- Define a fingerprint that stays the same when unrelated code changes, and is the same on every machine, operating system and line-ending style.
- Compute it in the scan tool for every finding, including the findings of external analyzer plugins, with no change to the plugin API.
- Write it to SARIF in the form the SARIF specification sets for a direct producer, under a key named by the specification's rules.
- Version it, so a later change to the algorithm can't silently turn every known finding into a new one.
- Let a team record the existing findings in a reviewable, committed baseline file, and gate only on new findings.
- Keep accepting findings an explicit act that shows up as a diff in review.

## Non-Goals

- **Tracking the history of a finding.** The scan tool stays stateless: it doesn't record when a finding was first seen, fixed or reopened. That is the job of the platform that receives the results, which can use the fingerprint to do it. Writing SARIF `provenance` and `baselineState: absent` from a previous report is [future work](#future-work).
- **SARIF `fingerprints`.** §3.27.16 leaves it to result management systems.
- **Fingerprints chosen by a rule.** A rule can't supply its own fingerprint, or part of one, through the `Reporter` API.
- **Matching across renames.** A finding in a renamed file or package gets a new fingerprint. This is a documented trade-off.

## Design

The design has two parts: the fingerprint of a finding, and the baseline that uses it.

### Fingerprints

Every finding gets one fingerprint, `ballerinaScanHash/v1`. It is a hash of the rule ID, the package, the file path and the tokens of the flagged line, with no line numbers. The same value is written to SARIF `partialFingerprints`, to `scan_results.json` and to the baseline.

```
rule ID, package, path, line tokens ──► ballerinaScanHash/v1 ──┬──► SARIF partialFingerprints
                                                               ├──► scan_results.json
                                                               └──► baseline file
```

It is computed once, in the scan tool, after every analyzer, core and external, has reported its issues, and before rule selection and `@scan:Suppress` are applied. So every plugin gets fingerprints without any change, and suppressing or excluding a finding doesn't change the fingerprint of another.

#### Choosing the inputs

A fingerprint input is worth adding when two findings that differ in it are different findings, and when it stays the same while the code around a finding changes. The table lists every input considered, what each one solves and what it doesn't.

| Candidate | What it solves | What it doesn't solve, or breaks | Decision |
| --- | --- | --- | --- |
| Line, column or offset | Tells findings apart by position | Changes on every edit above the finding. This is the problem being fixed | Rejected |
| Rule ID | Two rules flagging the same code are two findings | A renamed rule makes all its findings new | Included |
| File path | The same code in two files is two findings | A moved or renamed file makes its findings new | Included, relative to the package root |
| Package organization and name | Two packages of a workspace with a `main.bal` each don't collide, since the path is relative to the package | A renamed package makes all its findings new | Included |
| Package version | Nothing a finding depends on | A version bump would make every finding new | Rejected |
| Text of the tokens on the first flagged line, without their minutiae | Identifies the code. Indentation, spacing, line endings and a comment at the end of the line don't change it. String contents stay as written. The text of the tokens doesn't depend on how the parser splits them or attaches minutiae | Needs the syntax tree of the file at report time, which the scan tool already holds. Any edit of the code on the flagged line makes the finding new, which is intended: the changed code is reviewed again. Identical lines in one file get the same hash | Included |
| Raw text of the first flagged line | Identifies the code | Re-indenting or reformatting makes the finding new | Rejected in favour of the tokens |
| Text of the first flagged line, with whitespace removed | Ignores whitespace without the syntax tree | A comment added at the end of the flagged line makes the finding new. Removing whitespace inside string contents makes `"admin 123"` and `"admin123"` the same. Removing `//` comments from the text instead can't be done reliably without the tokens, since `//` also appears inside strings | Rejected in favour of the tokens |
| Enclosing construct | The same line in two functions of one file is two findings | Needs a definition of the construct for every kind of declaration. A renamed function, class, service or resource makes its findings new. The occurrence number already keeps identical lines in one file apart | Rejected |
| The whole flagged range | Captures all the flagged code | A rule that flags a whole function gets a new fingerprint on every edit inside it | Rejected |
| A window of the first flagged line and the lines after it | Tells apart identical lines with different code after them | An edit to the next two or three lines, or re-wrapping them, makes the finding new | Rejected |
| Message text | Tells apart findings of one rule with different messages | `bal scan` messages are the rule's description, the same for every finding of the rule. If messages later carry values, rewording a message would make every finding new | Rejected |
| Severity | Nothing the rule ID doesn't already give, since a rule has one severity | Changing a rule's severity would make all its findings new | Rejected |
| Semantic information, such as resolved types or symbols | Tells apart code that reads the same but means something else | Depends on compiled dependencies, so a dependency update could change every fingerprint. It also needs a full compilation for every finding | Rejected |
| Occurrence number in source order | Identical findings in one file get distinct values | Which of two identical findings is new can't be known, only how many are new | Added after the hash as `:<n>`, not hashed |

The selected inputs therefore don't solve the following.

- **Renames.** Renaming a file or a package, or a rule ID, makes the affected findings new. Renaming a function, class or service doesn't.
- **Edits to the flagged line.** Any change to the code on the first flagged line makes the finding new. Whitespace and comments don't. Wrapping the flagged line, or joining it with the next, changes which tokens are on it, so it makes the finding new too.
- **Identical findings.** For several identical findings in one file, the count of new ones is right, but not which ones are new. The same line in two functions of one file counts as the same finding.
- **Code moved to another file.** A finding that moves with its code to another file is new.

#### `ballerinaScanHash/v1`

The fingerprint hashes four inputs.

| Input | Value | Example |
| --- | --- | --- |
| Rule ID | The ID of the rule, as reported | `ballerina:13` |
| Package | The organization and name of the package in `Ballerina.toml` | `myorg/orders` |
| File path | The path of the file relative to the package root, with `/` separators | `modules/db/client.bal` |
| Flagged line | The text of the tokens on the first flagged line, as defined below | `stringpassword="admin123";` |

The path is relative to the package root, not to the project as in the SARIF report, so a package scanned alone and the same package scanned as part of a workspace give the same fingerprints.

The rule ID and the path are also in every SARIF result, so a result management system that combines the fingerprint with them, as §3.27.17 allows, gets them twice. That is harmless. Keeping them in the value lets the scan tool match on the value alone.

**Flagged line.** Take the tokens of the file's syntax tree that start on the line on which the flagged range starts, in source order, and join their text with nothing between them. The text of a token doesn't include its minutiae, so whitespace, comments and a byte order mark are left out. The text of the tokens is used as written, so string contents keep their spaces.

- All the tokens of the line are used, even when the range starts in the middle of it, so the value doesn't depend on columns.
- A zero-length range uses the line that holds its offset.
- A token that starts on the line and continues onto the next lines, such as a multi-line string template, is included in full. Every CRLF in its text is replaced by LF, so CRLF and LF checkouts give the same value.
- A line with no token, such as an empty line or a line that holds only a comment, is hashed as the empty string.

Only the text of the tokens is hashed, not their kinds, and nothing is put between them, so the value doesn't depend on how the parser splits tokens: `>>` read as one token or as two gives the same text. Since every minutia is left out, it doesn't depend on whether the parser attaches a comment to the token before it or the one after it either. A compiler release changes the value only if it changes which characters of the line belong to tokens.

Joining the tokens with nothing between them makes `string password` and `stringpassword` the same, which is harmless, since they are on the same line of the same file with the same rule.

**Hash.** Join the version `1` and the four inputs, in the order above, with the character U+001F between them, encode the result as UTF-8, and hash it with SHA-256. The fingerprint is the first 32 hexadecimal characters of the hash, in lowercase.

**Name.** The key follows the naming rules of SARIF for partial fingerprints.

| Rule | Source | How the key follows it |
| --- | --- | --- |
| The name is a hierarchical string: components joined by `/`, with no `/` inside a component | §3.5.4.1, §3.27.17 | `ballerinaScanHash` / `v1` |
| The last component is a version, `v` followed by a non-negative integer | §3.5.4.2, §3.27.17 | `v1` |
| The name is meaningful and documented | §3.27.17 | `ballerinaScanHash` names the tool and says the value is its hash of a finding. This proposal documents the algorithm |
| Components are camelCase | §3.8.1, and the examples of §3.27.16 and §3.27.17 | `ballerinaScanHash` |
| A different way of computing the value gets a new name, and existing names aren't removed | §3.27.17 | A change is published as `v2`, and `v1` is written next to it for at least one release |

The name starts with the tool, so the key can't collide with another tool's key when reports from several tools are merged. It has the shape of the examples of the specification, `stableResultHash/v2` and `prohibitedWordHash/v3`. The occurrence number is part of the value, not the name.

#### Occurrences

Two identical findings in one file, such as two calls of a deprecated function on one line, or the same line in two functions, get the same hash. Findings with the same hash are ordered by their start offset in the file and numbered from `1`, and the value carries the number after a colon, such as `9f2c51d0a4b87e13c6f0e2d9b1a47c58:2`. So each value is unique in a run.

The baseline stores the complete value, number included, and matches it as is, as described in [matching](#matching). The number follows source order, so a new identical finding added above a baselined one takes over its number, and the last one in source order is reported as new.

#### What changes the fingerprint

| Change | `ballerinaScanHash/v1` |
| --- | --- |
| Lines added or removed above the finding, or the enclosing function moved within the file | Unchanged |
| Re-indenting, spacing within the line, CRLF and LF checkouts | Unchanged |
| An edit or a comment on any line other than the first flagged line | Unchanged |
| A comment added at the end of the first flagged line, or edited | Unchanged |
| The enclosing function, class or service renamed | Unchanged |
| An identical line added elsewhere in the file | The hash is unchanged. The occurrence numbers of the identical findings after it go up by one, and the last one is new, as described in [matching](#matching) |
| An edit of the code on the first flagged line | Changed. The edited code is reviewed again |
| The first flagged line wrapped, or joined with the next | Changed, since different tokens are on it |
| The file or the package renamed | Changed |
| The rule ID changed | Changed |

#### Versioning

Any change to the inputs, the normalization or the hash is a new version, `ballerinaScanHash/v2`. The scan tool keeps computing every earlier version it supports, so it can match a baseline written with one, and writes the earlier key next to the new one for at least one release. Rule IDs are part of the fingerprint, so a rule keeps its ID once released.

#### Reports

- **SARIF.** Each result carries the fingerprint in `partialFingerprints`. The scan tool doesn't write `fingerprints`, as §3.27.16 asks of a direct producer.

  ```json
  "partialFingerprints": {
    "ballerinaScanHash/v1": "9f2c51d0a4b87e13c6f0e2d9b1a47c58:1"
  }
  ```

- **`scan_results.json` and JSON on standard output.** Each issue carries the same `partialFingerprints` object as in SARIF.

  ```json
  {
    "ruleId": "ballerina:13",
    "filePath": "modules/db/client.bal",
    "partialFingerprints": { 
      "ballerinaScanHash/v1": "9f2c51d0a4b87e13c6f0e2d9b1a47c58:1" 
    }
  }
  ```

- **HTML report.** Shows the fingerprint in the details of an issue, so a user can find it in the baseline.
- **Platforms.** A new default method on the public `Issue` interface, `partialFingerprints()`, returning a `Map<String, String>`, gives a platform plugin, such as the SonarQube one, the fingerprint to pass on. Default methods keep existing plugins working.

Issues are written in a stable order ([scan tool #193](https://github.com/ballerina-platform/static-code-analysis-tool/issues/193)), so two runs on the same code give identical reports.

### Baseline

A baseline is a file that lists the findings a team has accepted. A scan with a baseline reports and gates only the findings that are not in it.

#### Commands

```bash
bal scan --create-baseline       # record every current unsuppressed finding; never trips the gate
bal scan                         # with a baseline configured: reports and gates only new findings
bal scan --prune-baseline        # remove entries whose finding is gone; never adds entries
bal scan --ignore-baseline       # report everything, as --ignore-suppressions does for annotations
bal scan --baseline-path=<path>  # use this file instead of [baseline] path for this run
```

`--create-baseline`, `--prune-baseline` and `--ignore-baseline` select a mode, so at most one of them can be given. `--baseline-path` doesn't select a mode: it only names the file, and can be combined with any of them, or used alone with a plain `bal scan`.

The path is set in a new `[baseline]` table of `Scan.toml`.

```toml
[baseline]
path = "scan-baseline.json"   # relative to this Scan.toml
```

The rules are as follows.

1. **Configured, never discovered.** The baseline is used only when `[baseline] path` or `--baseline-path` names it. A file named `scan-baseline.json` that appears in the repository doesn't change what the gate counts.
2. **Accepting is explicit.** Only `--create-baseline` adds entries. It writes every current unsuppressed finding and replaces an existing file, so accepting new findings shows up as a diff in review. It never trips the gate, but errors still exit with a non-zero code.
3. **Pruning only removes.** `--prune-baseline` removes the stale entries, as defined in [matching](#matching). It rewrites the matched entries with the current fingerprint version, so it also migrates a baseline to a new version without accepting anything new. It reports the gate on new findings as a normal scan does.
4. **No path.** `--create-baseline` or `--prune-baseline` without `[baseline] path` or `--baseline-path` is a usage error (exit code `2`) that says how to set one.
5. **Missing file.** A configured baseline file that doesn't exist is a configuration error (exit code `1`), so a typo in the path doesn't turn the baseline off. A `--baseline-path` file that doesn't exist is a usage error (exit code `2`). With `--create-baseline`, neither is an error: the file is created, at either path.
6. **Conflicting options.** `--create-baseline`, `--prune-baseline` and `--ignore-baseline` can't be combined. Each pair is a usage error (exit code `2`). `--baseline-path` can be combined with any one of them.
7. **Ignoring reads nothing.** `--ignore-baseline` doesn't read or validate the file, so a missing or broken baseline can't block a run that is meant to ignore it.
8. **Platform-triggered scans.** With `--platform-triggered`, the baseline is ignored without a warning, since the platform tracks new code itself.
9. **Severity.** Findings of every severity can be baselined. The summary counts the baselined findings by severity, so they stay visible. A severity above which findings can't be baselined is [future work](#future-work).

#### What each mode does

Every mode writes the fingerprint, `ballerinaScanHash/v1`, in `partialFingerprints` of every result, in SARIF and in `scan_results.json`. The modes differ in what they read and write, and in the `baselineState` of the reports.

| Command | Reads the baseline | Writes the baseline | The gate counts | `baselineState` |
| --- | --- | --- | --- | --- |
| `bal scan`, no baseline configured | No | No | Every unsuppressed finding | Not written |
| `bal scan`, baseline configured | Yes | No | New findings | `new` or `unchanged` |
| `bal scan --create-baseline` | No | Yes, replaces the file | Never trips | `unchanged` on every unsuppressed finding |
| `bal scan --prune-baseline` | Yes | Yes, removes entries only | New findings | `new` or `unchanged` |
| `bal scan --ignore-baseline` | No | No | Every unsuppressed finding | Not written |

`--baseline-path=<path>` isn't a row of its own. It replaces `[baseline] path` for whichever mode it is used with.

- **`bal scan` with no baseline.** The scan behaves as it does today. The only addition to the reports is the fingerprint. No result carries `baselineState`.
- **`bal scan` with a baseline.** The file is loaded and validated, and findings are matched by fingerprint, as described in [matching](#matching). The console prints only new findings, the summary and any stale-entry warning. The gate counts only new findings. The file isn't changed.
- **`bal scan --create-baseline`.** The existing file isn't read. Every current unsuppressed finding is written to the file, which replaces it or is created. Once the file is written, every unsuppressed finding is in the baseline, so the run reports them as baselined, exactly as a plain `bal scan` straight afterwards would: the summary reads `0 new issues, 120 in baseline`, and every unsuppressed finding is `unchanged`. The gate is never tripped. A file that can't be written exits with `1`.
- **`bal scan --prune-baseline`.** The scan matches and reports as a scan with a baseline does, and new findings still trip the gate. It then rewrites the file: stale entries are removed, and entries of an earlier fingerprint version are rewritten as the current one. New findings are never added.
- **`bal scan --ignore-baseline`.** The file isn't read. The reports and the gate are the same as with no baseline configured.

#### Walkthrough

| Day | What happens | Command | Output | Build |
| --- | --- | --- | --- | --- |
| 1 | The team adopts the baseline | `bal scan --create-baseline` | The file is written with 120 entries and committed | Passes |
| 2 | Someone adds lines above an old finding | `bal scan` | `0 new issues, 120 in baseline`. The fingerprint is unchanged | Passes |
| 3 | A pull request adds a hardcoded password | `bal scan` | `1 new issue, 120 in baseline`, and the new finding is printed | Fails |
| 4 | The team fixes 5 old findings | `bal scan` | `0 new issues, 115 in baseline`, and a warning that 5 entries match no finding | Passes |
| 4 | The team cleans up | `bal scan --prune-baseline` | 5 entries removed. | Passes |

On day 3, the author of the pull request can't accept their own finding without running `--create-baseline` and committing the change, which a reviewer sees.

#### File format

The file is JSON, committed to the repository and written in a stable order: by package, file path, rule ID and fingerprint. Only `fingerprint` is used for matching. The other fields make the file reviewable in a pull request, and are never matched on.

```json
{
  "version": 1,
  "fingerprint": "ballerinaScanHash/v1",
  "balScanVersion": "0.15.0",
  "issues": [
    {
      "fingerprint": "9f2c51d0a4b87e13c6f0e2d9b1a47c58:1",
      "ruleId": "ballerina:13",
      "package": "myorg/orders",
      "filePath": "modules/db/client.bal",
      "snippet": "string password = \"admin123\";"
    }
  ]
}
```

| Field | Meaning |
| --- | --- |
| `version` | The version of the file format. `1` for this proposal |
| `fingerprint` | The fingerprint version of every entry |
| `balScanVersion` | The version of the scan tool that last wrote the file. Informational |
| `issues[].fingerprint` | The fingerprint, with its occurrence number, as written to `partialFingerprints`. Unique in the file |
| `issues[].ruleId`, `package`, `filePath` | The inputs of the fingerprint, for review |
| `issues[].snippet` | The first flagged line as written, with its whitespace, for review |

The file holds no line numbers and no dates, so an unrelated edit or a rerun doesn't change it. A file that isn't valid JSON, has an unknown `version` or field, or names a fingerprint version the scan tool doesn't support is a configuration error (exit code `1`), reported as a diagnostic at its line and column.

#### Matching

An unsuppressed finding is baselined when its fingerprint, occurrence number included, is the `fingerprint` of an entry, and new otherwise. An entry that matches no unsuppressed finding is stale.

The occurrence number is a finding's position among all the findings with the same hash in the file, suppressed or not, so adding or removing one of them shifts the numbers of those after it. When one is added, the last of them in source order is new, whichever was added. When one is removed, the entry with the highest number is stale, whichever was removed.

A baseline written with an earlier fingerprint version is matched with that version, and the scan writes a warning that suggests `--prune-baseline` to migrate it.

#### Order of filtering

The baseline is applied after the suppressions and before the gate.

1. Rule selection: `--include-rules`, `--exclude-rules` and the `[rule]` table.
2. `@scan:Suppress` annotations. The baseline holds only findings that are not suppressed in source. With `--ignore-suppressions`, a suppressed finding that isn't in the baseline is new.
3. The baseline.
4. The gate, which counts only new findings.

#### Results

- **Console.** Only new findings are printed. The summary counts the rest: `3 new issues, 120 in baseline, 2 suppressed`.
- **JSON and SARIF.** Baselined findings stay in the reports, and `baselineState` tells them apart from new ones. With a baseline, every SARIF result carries `baselineState`, as §3.27.24 requires it on all results or none. Every issue in `scan_results.json` and in JSON on standard output carries a top-level `baselineState` field, with the same values and the same all-or-none rule. Without a baseline, or with `--ignore-baseline`, no result carries it.

  | Finding | `baselineState` |
  | --- | --- |
  | Matches a baseline entry | `unchanged` |
  | Not in the baseline | `new` |
  | Suppressed with `@scan:Suppress` | `new`, since the baseline holds only unsuppressed findings |

  A baselined finding and a new finding in SARIF, in `runs[].results`:

  ```json
  [
    {
      "ruleId": "ballerina:13",
      "locations": [ ... ],
      "partialFingerprints": { "ballerinaScanHash/v1": "9f2c51d0a4b87e13c6f0e2d9b1a47c58:1" },
      "baselineState": "unchanged"
    },
    {
      "ruleId": "ballerina:13",
      "locations": [ ... ],
      "partialFingerprints": { "ballerinaScanHash/v1": "4be1a7c3f09d2e8b5a6c1f7e3d9b0a24:1" },
      "baselineState": "new"
    }
  ]
  ```

  The same findings in `scan_results.json`:

  ```json
  [
    {
      "ruleId": "ballerina:13",
      "filePath": "modules/db/client.bal",
      "partialFingerprints": { "ballerinaScanHash/v1": "9f2c51d0a4b87e13c6f0e2d9b1a47c58:1" },
      "baselineState": "unchanged"
    },
    {
      "ruleId": "ballerina:13",
      "filePath": "modules/db/config.bal",
      "partialFingerprints": { "ballerinaScanHash/v1": "4be1a7c3f09d2e8b5a6c1f7e3d9b0a24:1" },
      "baselineState": "new"
    }
  ]
  ```

  The scan tool writes only `new` and `unchanged`. It doesn't write `updated`, since a finding whose flagged line changed gets a new fingerprint and is `new`, or `absent`, since a baseline entry has no location to report. Entries that match nothing are reported as a warning instead. It doesn't write `run.baselineGuid`, since the baseline is a file, not an earlier run.
- **HTML report.** Lists baselined findings under their own status.
- **Platforms.** Every finding is sent to the platforms named in `--platforms`, as without a baseline. A platform tracks new code itself, as with `--platform-triggered`.
- **Stale entries.** Stale entries are reported as one warning, such as `bal scan: warning: 4 baseline entries match no finding; run 'bal scan --prune-baseline' to remove them`. A warning never changes the exit code.

#### Workspaces

There is one baseline for each `Scan.toml`. A package uses the baseline of the `Scan.toml` it uses, its own or the workspace one, as in [proposal 1497](1497_scan_exit_codes.md#gate). Every entry names its package, and the fingerprint includes it, so the entries of one package never match the findings of another, and each package is still gated on its own new findings.

#### Execution order

The baseline adds two steps to the [execution order of proposal 1497](1497_scan_exit_codes.md#execution-order).

- In step 4, preparing each package, load and validate its baseline. Fails with `1` on a missing or invalid file.
- After step 7, applying the suppressions, compute the fingerprints, match the findings against the baseline and, with `--create-baseline` or `--prune-baseline`, write the file. Fails with `1` when the file can't be written.

## Alternatives

**1. Match on line numbers.** Simple, but every edit above a finding makes it new, which is the problem this proposal fixes.

**2. Write the fingerprint to SARIF `fingerprints`.** §3.27.16 says a direct producer SHOULD NOT.

**3. A partial fingerprint without the rule ID and path, and a second fingerprint derived from it.** This is how CodeQL and GitHub code scanning split the work. CodeQL writes `primaryLocationLineHash`, a hash of the flagged line with no rule ID or path, and GitHub combines it with the rule ID and the path to identify an alert. The split has these benefits.

- Each side adds what only it knows. The tool knows the code. The platform knows the repository-relative path, the tool and the branch.
- The platform applies one identity policy to the results of every tool it receives.
- Either side can change its algorithm without the other, by publishing a new version.
- Several separate values let a platform match on some of them when others change, such as a renamed file with an unchanged line.
- The partial fingerprint doesn't repeat what the SARIF result already carries.

The split suits a tool whose results are matched only by a platform. `bal scan` matches findings against its baseline itself, on a developer's machine or in any CI, with no platform involved, so it needs the complete identity locally. `ballerinaScanHash/v1` therefore encodes every input in the partial fingerprint, and the baseline uses the value as is.

- One algorithm and one version to compute, document and migrate, where the split needs two, and the version of the second depends on the first.
- The baseline file, SARIF and `scan_results.json` carry the same hash, so a finding in a report can be found in the baseline.
- A consumer can deduplicate on the value alone. One that wants to combine it with other data, as §3.27.17 allows, still can, and gets the rule ID and path twice, which is harmless.
- The value uses the path relative to the package and the package name, so it is the same when a package is scanned alone or in a workspace, and when the [GitHub Action](1507_scan_github_action.md) rewrites SARIF paths. A platform combining the SARIF path doesn't get that.

The cost is that a consumer can't loosen the match, for example to match a finding across a file rename, since the value is one hash. Separate partial fingerprints, below, can add this later as new keys.

**4. Separate partial fingerprints for the path and the line.** A consumer could then still match a finding when its file is renamed and its line isn't, at the cost of a looser match. This can be added later as a new key without changing the existing ones.

**5. Include the enclosing construct.** Hashing the function, method, resource or service that holds the finding tells apart the same line in two functions of one file. It needs a defined value for every kind of declaration, and it makes a renamed function rebaseline all its findings. Identical lines in one file are already kept apart by the occurrence number, so the construct adds cost for a case that is already handled.

**6. Hash the text of the flagged line with its whitespace removed.** It needs no syntax tree, so the value can't depend on the parser at all. But a comment added at the end of a flagged line would make the finding new, and string contents would lose their spaces. The text of the tokens avoids both, depends on the parser only for which characters belong to tokens, and comes from a syntax tree the scan tool already holds.

**7. Hash the whole flagged range.** A rule that flags a whole function would get a new fingerprint on every edit inside the function.

**8. Store line numbers or dates in the baseline.** They change on unrelated edits and on reruns, so the file would change on every commit and the diff would hide the findings that were accepted.

**9. Compare with a git commit.** It needs the git history and a second scan in CI, and accepting a finding isn't recorded anywhere a reviewer sees.

**10. Suppress every existing finding with `@scan:Suppress`.** Noisy, and it puts hundreds of annotations into the source.

**11. Store the hash without the occurrence number, with a count.** One entry per hash, with the number of findings accepted. It baselines the same findings as the numbered values, but the baseline would no longer hold the value the reports carry, so a finding in a report couldn't be looked up in the baseline as is.

**12. Refuse to overwrite an existing baseline without `--force`.** `--create-baseline` exists to write the file, and its result is reviewed as a diff, so a second flag adds a step without adding safety.

## Testing

- **Fingerprint stability.** Each test scans a fixture, edits a copy, scans again and compares the values against the [table of changes](#what-changes-the-fingerprint): lines added above the finding, the enclosing function moved, the file re-indented, the next lines edited and re-wrapped, comments added on other lines, a comment added at the end of the flagged line, CRLF and LF checkouts, the flagged line edited, an identical line added elsewhere in the file, and the file, function, service, class, package and rule renamed.
- **Flagged line.** Spaces and tabs inside the line, a comment at the end of the line, a line that holds only a comment, spaces inside a string, a multi-line string template that starts on the line in CRLF and LF checkouts, a byte order mark, a range that starts in the middle of a line, a zero-length range and an empty line.
- **Workspace paths.** The same package scanned alone and in a workspace gives the same fingerprints.
- **Occurrences.** Identical findings in one file, on one line and in two functions, get `:1`, `:2` and so on, and every value in a run is unique.
- **Determinism.** Two runs on the same code give identical reports, on Windows and Linux.
- **Plugins.** A finding from an external plugin gets a fingerprint.
- **SARIF.** Every result has `partialFingerprints` with the key `ballerinaScanHash/v1`, and none has `fingerprints`. `baselineState` is on every result or none, in SARIF and in JSON.
- **Baseline commands.** `--create-baseline` writes every unsuppressed finding, reports each as `unchanged` and exits with `0` with a gate set; `--prune-baseline` removes stale entries, migrates an earlier version and never adds an entry; `--ignore-baseline` reports everything and doesn't read a missing or broken file; `--baseline-path` works with each mode; each conflicting pair and a missing path are usage errors.
- **Matching.** Fewer, as many and more identical findings than baselined entries for one hash, a new identical finding added above a baselined one, and a suppressed finding with and without `--ignore-suppressions`.
- **Files.** A missing configured file, a missing `--baseline-path` file, invalid JSON, an unknown version and an unsupported fingerprint version, each with its exit code and diagnostic. The written file is in a stable order and unchanged by a rerun.
- **Results.** Console, summary, JSON, SARIF, HTML report and platforms, as listed in [results](#results), and the stale-entry warning.
- **Workspaces.** A workspace baseline and a package baseline, the same file path in two packages, and each package gated on its own new findings.

## Risks and Assumptions

- A rename of a file or package makes its findings new. Teams that rename widely have to rerun `--create-baseline`, and the release notes must say so.
- A new identical finding in a file that already has baselined findings is matched by occurrence number, so the finding reported as new may be an older one. Likewise, when one of several identical findings is fixed, `--prune-baseline` removes the entry with the highest number, not the one that was fixed. The total is always right. Common lines, such as the same call in several resources of one service, make this more likely than with a fingerprint that includes the enclosing construct.
- Rule IDs become part of the fingerprint, so a renamed rule makes all its findings new. Rule IDs must stay stable once released.
- The fingerprints are computed from the syntax tree of each file at report time. This assumes every finding, including those of external plugins, is reported in a `.bal` file of the package, and that its syntax tree is still available after analysis.
- The value depends on the parser only for which characters of a line belong to tokens. A compiler release that changes this, for example by turning part of a comment into a token, would make the affected findings new, and needs a new fingerprint version.

## Dependencies

- [Scan tool #113](https://github.com/ballerina-platform/static-code-analysis-tool/issues/113), for the fingerprints. It must be released before, or with, the baseline, since a later change to the fingerprint would turn every baselined finding into a new one.
- [Scan tool #193](https://github.com/ballerina-platform/static-code-analysis-tool/issues/193), for a stable order of issues in the reports.
- [Proposal 1497](1497_scan_exit_codes.md), for the gate, the exit codes, the `Scan.toml` resolution in workspaces and the execution order.
- [Proposal 1496](1496-in-source-scan-suppression.md), for `@scan:Suppress` and `--ignore-suppressions`.

## Future Work

- **Finding history in SARIF.** An option to read the previous SARIF report and write `provenance` (`firstDetectionTimeUtc`, `lastDetectionTimeUtc`), `baselineState: absent` results for findings that are gone, and `run.baselineGuid`, for consumers without their own tracking.
- **Fingerprint hints from rules.** A way for a rule to give the parts of a finding that identify it.
- **Matching across renames.** A second pass that matches an unmatched finding to a stale entry with the same rule and flagged line in a renamed file, or a separate partial fingerprint for the line alone.

## References

- [Issue #1498: Introduce baseline adoption and changed-file scanning in ballerina scan tool](https://github.com/ballerina-platform/ballerina-spec/issues/1498)
- [Scan tool #223: Add a baseline to report and gate only new findings](https://github.com/ballerina-platform/static-code-analysis-tool/issues/223)
- [Scan tool #113: Add partialFingerprints to the results in the SARIF report](https://github.com/ballerina-platform/static-code-analysis-tool/issues/113)
- [Proposal #1497: Build gating and an exit code contract for `bal scan`](1497_scan_exit_codes.md)
- [Proposal #1496: In-source suppression of scan findings](1496-in-source-scan-suppression.md)
- [SARIF 2.1.0 Errata 01](https://docs.oasis-open.org/sarif/sarif/v2.1.0/errata01/os/sarif-v2.1.0-errata01-os-complete.html), sections 3.5.4 hierarchical strings, 3.27.16 `fingerprints`, 3.27.17 `partialFingerprints` and 3.27.24 `baselineState`
