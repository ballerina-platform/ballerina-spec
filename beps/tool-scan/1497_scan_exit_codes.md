# Introduce Build Gating and an Exit Code Contract for `bal scan`

- Authors - Charana Manawathilake
- Reviewed by - Tharmigan Krishnananthalingam
- Created date - 2026-10-26
- Updated date - 2026-11-03
- Issue - [1497](https://github.com/ballerina-platform/ballerina-spec/issues/1497)
- State - Submitted

## Summary

This proposal gives `bal scan` a documented set of exit codes and an opt-in gate, so whatever runs the scan, such as a script, a Git hook or a CI/CD pipeline, can fail on findings and on configuration errors and tool failures.

- `bal scan` uses the standard exit codes of Ballerina CLI tools: `0` for success, `1` for a runtime error, `2` for a usage error, `3` for an invalid target and `130` for an interrupt. A tripped gate exits with `1`.
- Every failure other than an interrupt is reported on standard error with a message that says what went wrong.
- Two new options, `--fail-on-severity <BLOCKER|HIGH|MEDIUM|LOW|INFO|NONE>` and `--fail-on-count <n>`, also settable in `Scan.toml`, define the gate. The scan fails when the number of issues at or above the severity reaches the count.

By default no gate is set, so findings never fail the scan and it exits with `0`. Errors, however, always exit with a non-zero code, so a broken `Scan.toml` no longer passes silently.

## Motivation

Today `bal scan` exits with `0` for almost every outcome, including real failures. A caller cannot tell a clean scan from a broken one without parsing standard output. The table lists what `ScanCmd.execute()` and `executeProject()` do in scan tool 0.12.0.

| Situation | What the scan tool does | Exit code |
| --- | --- | --- |
| Scan finished with no issues | Prints the results and returns | `0` |
| Scan finished with issues of any severity, `BLOCKER` included | Prints the results, writes `scan_results.json` or SARIF, and returns | `0` |
| Invalid project path, or a file inside a package | Prints a message to standard output and returns `Optional.empty()` | `0` |
| Project load diagnostics, such as an invalid `Ballerina.toml` | Prints the errors to standard output and returns | `0` |
| Empty package (`ERROR_002`) | Prints an error and returns, or skips the package in a workspace | `0` |
| `Scan.toml` cannot be read, or a remote configuration or JAR download fails (`ERROR_003` to `ERROR_007`) | `loadScanTomlConfigurations` returns empty and the scan stops | `0` |
| An external analyzer (compiler plugin) fails to load (`ERROR_008`) | Prints a message and returns | `0` |
| Both include and exclude rules are given (`ERROR_016`) | Prints an error and returns | `0` |
| A platform named in `--platforms` is missing | Prints a message and continues | `0` |
| Compilation errors (`ERROR_019`) | Throws `BLauncherException` | `1`, from the launcher |
| Writing the workspace report fails with an `IOException` | Wraps it in a `RuntimeException` | `1`, from the launcher's `catch (Throwable e)` |

Three gaps follow from this.

- **Issues never fail the scan.** There is no way to say "fail on any `BLOCKER`" or "fail on ten or more issues". The `Severity` enum (`BLOCKER`, `HIGH`, `MEDIUM`, `LOW`, `INFO`) already exists, but nothing reads it when the tool exits.
- **Tool and configuration errors look like success.** Errors are printed to `outputStream` (standard output), not `errorStream`, and the method returns normally. A typo in `Scan.toml` gives a successful run that scanned nothing.
- **Failures are not reported consistently.** Errors are written in different forms, mostly to standard output, so a caller cannot reliably tell a usage error or an invalid project from a successful run.

Anything that runs `bal scan` and acts on the result needs this contract to fail for the right reason and to report it clearly. CI/CD integrations, such as the [`scan-ballerina` GitHub Action](1507_scan_github_action.md), are one example.

## Goals

- Define a stable, documented exit code for every outcome of `bal scan`, using the standard exit codes of Ballerina CLI tools.
- Keep the scan exiting with `0` on findings unless a gate is set, so existing scripts and pipelines keep passing.
- Let users fail the scan on a number of issues, on issues at or above a severity, or on both, from the command line or from `Scan.toml`.
- Make every tool, configuration and project error exit with a non-zero code.
- Write errors and the gate result to standard error, as text.

## Non-Goals

- **New-code gating.** Gating only on issues introduced since a baseline or a commit is [future work](#future-work).
- **Per-severity count limits.** One gate, a severity and a count, applies to the whole scan. Different counts for different severities are [future work](#future-work).
- **Platform quality gates.** When the scan runs from inside a platform, such as SonarQube, that platform's quality gate decides whether the analysis fails.
- **Changes to reports.** Console output, `scan_results.json`, SARIF, the HTML report and platform uploads keep every issue, whatever the gate is set to.

## Design

The design has three parts: the standard exit codes for each failure, an opt-in gate made of a severity and a count, and errors that always exit with a non-zero code.

### Exit codes

`bal scan` uses only the following codes.

| Code | Name | When | Today |
| --- | --- | --- | --- |
| `0` | Success | The scan completed, and no gate is set or the gate was not tripped | `0` |
| `1` | Runtime error | The gate was tripped, or the scan could not be completed: a configuration, plugin, compilation, suppression or report error, or an unexpected exception | `0`, or `1` for compilation errors and report write failures |
| `2` | Usage error | Invalid command-line input: more than one package or source file (`ERROR_001`), an invalid option value, such as an unknown `--format` (`ERROR_017`) or an invalid `--fail-on-severity` or `--fail-on-count` value (`ERROR_031`), both include and exclude rules (`ERROR_016`), a rule option that, together with the `[rule]` table of `Scan.toml`, would both include and exclude rules (`ERROR_050`), or an unknown rule ID (`ERROR_032`) | `0` |
| `3` | Invalid target | The path is not a Ballerina package, workspace or source file (`ERROR_033`), the path is a `.bal` file inside a package (`ERROR_034`), or the project cannot be loaded or has load diagnostics, such as an invalid `Ballerina.toml` (`ERROR_035`) | `0` |
| `130` | Interrupted | The scan was interrupted with SIGINT | `130` |

### Failures

Every failure other than an interrupt writes an error report to standard error and exits with the code below. An interrupt exits with `130` and writes no error report.

| Failure | Exit code |
| --- | --- |
| Invalid command-line input, as listed for code `2` | `2` |
| An invalid project, as listed for code `3` | `3` |
| The gate was tripped: the number of counted issues at or above `--fail-on-severity` is at least `--fail-on-count`, for the package or, in a workspace, for any package | `1` |
| `Scan.toml` cannot be read or has errors: a TOML syntax error, a missing `configPath`, a table written in another form, such as `[[gate]]`, an invalid value or an unknown key, a `[rule]` table that sets both `include` and `exclude`, a `[suppression]` setting that is not a boolean, or a `[[platform]]` table in a workspace `Scan.toml` (`ERROR_003`, `ERROR_005`, `ERROR_016`, `ERROR_025`, `ERROR_026`, `ERROR_028`, `ERROR_036` to `ERROR_038`, `ERROR_044` to `ERROR_046`) | `1` |
| A rules JSON file of an analyzer plugin cannot be read or is invalid (`ERROR_009` to `ERROR_012`, `ERROR_020`) | `1` |
| A remote configuration cannot be loaded (`ERROR_004`), the `path` of a `[[platform]]` table is neither a file nor a URL (`ERROR_006`), or a platform JAR cannot be downloaded (`ERROR_007`) | `1` |
| The dependencies of a package are not locked in `Dependencies.toml` (`ERROR_027`) | `1` |
| The package has compilation errors (`ERROR_019`), including a malformed rule ID or an empty rule list in a `@scan:Suppress` annotation (`SCAN_SUPPRESS_101`, `SCAN_SUPPRESS_107`) | `1` |
| The package has no sources to scan (`ERROR_002`). An empty package in a workspace is skipped with a warning instead | `1` |
| An analyzer plugin fails to load (`ERROR_008`) | `1` |
| A platform named in `--platforms` is not declared in `Scan.toml` (`ERROR_039`), or its plugin does not provide it (`ERROR_049`). In a workspace, a package that does not declare the platform is not reported to it, with a warning, and the scan fails only when no package declares it | `1` |
| A `@scan:Suppress` annotation names a rule that does not exist (`ERROR_024`), gives no reason while `requireReason` or `--require-suppression-reason` is set, or names no rule while `requireRuleId` or `--require-suppression-rule-id` is set (`ERROR_023`). Never reported with `--ignore-suppressions` or `enabled = false` | `1` |
| A report or the target directory cannot be written (`ERROR_014`, `ERROR_040`, `ERROR_051`) | `1` |
| A platform plugin throws in `init` or `onScan` (`ERROR_047`, `ERROR_048`) | `1` |
| An unexpected exception | `1` |

A platform plugin that fails does so after the results are printed and saved, so a failed upload does not hide them. Every selected platform runs, at the same time, and the error report lists each platform that failed.

```
bal scan: error: 2 platforms failed to report the issues
pkg-a: error: platform 'sonarqube' failed: <reason>
pkg-b: error: platform 'sonarqube' failed: <reason>
```

A script can test `== 0` for "the scan passed", and any other code for "the scan did not pass". The error message on standard error says which failure occurred.

### Error reports

Error reports follow a text format, described below, and are written to standard error. Scan tool 0.12.0 prints errors as plain text on standard output. Standard output carries only the issues printed to the console, so that it stays valid JSON or SARIF. Progress messages, report locations, the issue summary, warnings and the error report go to standard error. A machine-readable form, such as JSON, is [future work](#future-work), pending a standard output format for Ballerina CLI tools.

An error report is `bal scan: error: <message>`. The message names the path, option or value involved, is one line, starts in lowercase (a number, path or name stays as written), and has no trailing period or stack trace.

```
bal scan: error: 6 issues at or above MEDIUM, limit 5 (BLOCKER: 1, HIGH: 2, MEDIUM: 3)
```

A problem in a file, such as `Scan.toml` or a rules JSON file, is a diagnostic. It is written as `<path>:<line>:<col>: error: <message>`, under the error report. A diagnostic for `Scan.toml` names the key, not the option.

```
bal scan: error: Scan.toml has 1 error
Scan.toml:2:18: error: invalid value 'CRITICAL' for 'failOnSeverity'; expected BLOCKER, HIGH, MEDIUM, LOW, INFO or NONE
```

A `@scan:Suppress` annotation that fails a check is a diagnostic at the annotation, under one error report.

```
bal scan: error: 2 invalid suppressions
main.bal:23:5: error: unknown rule 'ballerina/http:9': 'ballerina/http' does not define this rule
main.bal:41:1: error: suppression has no reason; requireReason is set in Scan.toml
```

A usage error is followed by a one-line synopsis and a pointer to the help, and not by the full help.

```
bal scan: error: invalid value '0' for --fail-on-count; expected a whole number of 1 or more
Usage: bal scan [OPTIONS] [<package>|<source-file>]
Try 'bal scan --help' for more information.
```

An unknown rule ID is a usage error that names every unknown ID, with a suggestion to run `bal scan --list-rules`. The scan never suggests or guesses a near-match rule ID.

```
bal scan: error: unknown rules 'ballerina:98' and 'ballerina:99'
  Run 'bal scan --list-rules' to see the available rules.
Usage: bal scan [OPTIONS] [<package>|<source-file>]
Try 'bal scan --help' for more information.
```

Warnings, such as a command-line option that overrides a `Scan.toml` setting, are reported in the same format as error reports, as `bal scan: warning: <message>`. A warning never changes the exit code.

```
bal scan: warning: --fail-on-severity=NONE overrides [gate] failOnSeverity = "HIGH" in Scan.toml
```

### Gate

The gate has two settings.

- `--fail-on-severity <severity>` selects the issues the gate counts: those at or above the severity. The values are `BLOCKER`, `HIGH`, `MEDIUM`, `LOW`, `INFO` and `NONE`, and are case-insensitive, so `high` and `High` are the same as `HIGH`.
- `--fail-on-count <n>` is the number of selected issues at which the scan fails. It is a whole number of `1` or more.

The scan fails with exit code `1` when the number of selected issues is greater than or equal to the count. The settings combine as follows.

| `--fail-on-severity` | `--fail-on-count` | Fails when |
| --- | --- | --- |
| Not set | Not set | Never. The gate is off |
| Not set | `n` | There are `n` or more issues of any severity |
| `X` | Not set | There is at least one issue at or above `X` |
| `X` | `n` | There are `n` or more issues at or above `X` |
| `NONE` | Any | Never. The gate is off |

In other words, a count without a severity counts every severity, as if the severity were `INFO`, and a severity without a count uses a count of `1`.

```bash
# Fail on one or more BLOCKER or HIGH issues
bal scan --fail-on-severity=HIGH

# Fail on 10 or more issues of any severity
bal scan --fail-on-count=10

# Fail on 5 or more BLOCKER, HIGH or MEDIUM issues
bal scan --fail-on-severity=MEDIUM --fail-on-count=5

# Never fail on issues, overriding Scan.toml
bal scan --fail-on-severity=NONE
```

The same settings can be given in a new `[gate]` table in `Scan.toml`, next to the existing `[[platform]]`, `[[analyzer]]` and `[rule]` sections.

```toml
[gate]
failOnSeverity = "MEDIUM"        # BLOCKER | HIGH | MEDIUM | LOW | INFO | NONE
failOnCount = 5                  # 1 or more
```

A workspace can have a `Scan.toml` of its own, found the same way as the `Scan.toml` of a package: at the workspace root, or at the `configPath` set in the `[scan]` table of the workspace `Ballerina.toml`. It holds the defaults for the packages of the workspace, and accepts every table a package `Scan.toml` does except `[[platform]]`, since each package reports to a project of its own on a platform. A `[[platform]]` table in it is a configuration error (exit code `1`) that gives the location of the table.

A package uses its own `Scan.toml` as a whole, or the workspace `Scan.toml` when it has none. The two files are never merged. When a package has a `Scan.toml` of its own, the settings of the workspace `Scan.toml` that it does not repeat with the same value are not applied, and the scan writes a warning that names them, such as `bal scan: warning: pkg-b/Scan.toml overrides Scan.toml for pkg-b; not applied: [gate] failOnSeverity = "HIGH"`. For example, with `failOnSeverity = "HIGH"` and `failOnCount = 3` in the workspace `[gate]` table, a package whose own `Scan.toml` sets only `failOnCount = 5` is gated on five issues of any severity, not five issues at or above `HIGH`, and a package with an empty `Scan.toml` of its own has no gate.

The gate follows these rules.

1. **Order.** Severities follow the existing `Severity` enum: `BLOCKER` > `HIGH` > `MEDIUM` > `LOW` > `INFO`. An issue is at or above `X` when its severity is `X` or more severe.
2. **Count.** The count is a threshold, not an allowance: `--fail-on-count=5` fails on the fifth issue, and allows four. The name says when the scan fails, matching `--fail-on-severity`.
3. **Precedence.** Each command-line option replaces only its own setting of the `[gate]` table of `Scan.toml` for that run, and a setting that is not given on the command line is still read from `Scan.toml`. So a `Scan.toml` that sets `failOnSeverity = "HIGH"`, run with `--fail-on-count=3`, fails on three or more issues at or above `HIGH`. `--fail-on-severity=NONE` turns off a gate set in `Scan.toml`. `--fail-on-count` alone does not turn on a gate that `failOnSeverity = "NONE"` in `Scan.toml` turns off; `--fail-on-severity` must be given as well. When an option gives a setting a different value from the one written in `Scan.toml`, the scan writes a warning that names the option, the replaced setting and the file it came from, such as `bal scan: warning: --fail-on-count=3 overrides [gate] failOnCount = 5 in Scan.toml`. The same value in both places, or a setting that `Scan.toml` does not write, gives no warning.
4. **Validation.** Severity values are case-insensitive. An invalid severity, or a count that is not a whole number of `1` or more, is a usage error (exit code `2`) on the command line. In `Scan.toml`, an invalid value or an unknown key in the `[gate]` table is a configuration error (exit code `1`) reported as a diagnostic at its line and column.
5. **Exit code only.** The gate changes only the exit code and the error report. Console output, `scan_results.json`, SARIF, the HTML report and platform uploads always contain every issue.
6. **Counted issues.** The gate counts the issues left after `--include-rules`, `--exclude-rules` and `@scan:Suppress` annotations ([proposal 1496](1496-in-source-scan-suppression.md)). Excluded and suppressed issues never count, unless `--ignore-suppressions` or `enabled = false` in `[suppression]` disregards the annotations, in which case suppressed issues count.
7. **Rules without a severity.** A plugin rule can have no severity (`rule.severity() == null`). Such a rule uses the same fallback as `resolveSarifLevel`: `BUG` counts as `HIGH`, `VULNERABILITY` as `MEDIUM` and `CODE_SMELL` as `LOW`. One mapping serves both SARIF and the gate.
8. **Errors win.** When both a tool error and a tripped gate occur, the error is reported instead of the gate failure. No gate setting, `NONE` included, hides an error.
9. **Workspaces.** In a workspace, every package that has sources is scanned, and an empty package is skipped with a warning, such as `bal scan: warning: pkg-c has no sources to scan and is skipped`. If any package had an error, the scan writes one error report and exits with `3` if any package is an invalid target, and `1` otherwise. The message gives the number of failing packages, and the error of each failing package is a diagnostic that names the package. Otherwise each package is checked against its own gate, counting only its own issues; the issues of different packages are never counted together. A package's gate is resolved as in rule 3, from the `[gate]` table of the `Scan.toml` it uses, its own or the workspace one, and each command-line option replaces its own setting in every package, with one warning for each `Scan.toml` that writes the setting differently. A package with no gate is not gated. The scan fails with exit code `1` if any package trips its gate, and exits with `0` otherwise. The message gives the number of failing packages, and each failing package is a diagnostic that names it.

   ```
   bal scan: error: 2 packages failed the gate
   pkg-a: error: 2 issues at or above HIGH, limit 1 (BLOCKER: 1, HIGH: 1)
   pkg-b: error: 12 issues at or above LOW, limit 10 (HIGH: 2, MEDIUM: 4, LOW: 6)
   ```

10. **Platform-triggered scans.** When an analysis platform, such as SonarQube, triggers the scan (`--platform-triggered`), the gate is off and the gate settings are ignored without a warning, since the platform applies its own quality gate.
11. **Standard error.** Every error diagnostic moves from `outputStream` to `errorStream`, and the error report is the last thing written to standard error.

A run that trips the gate looks like a run without a gate, followed by the gate error on standard error and exit code `1`. The issues on standard output and the report locations on standard error are unchanged.

```bash
$ bal scan --fail-on-severity=MEDIUM --fail-on-count=5
# Standard output: the issues, as without a gate
...
# Standard error: progress, report locations and the summary, as without a gate, then the gate error, last
bal scan: error: 6 issues at or above MEDIUM, limit 5 (BLOCKER: 1, HIGH: 2, MEDIUM: 3)
$ echo $?
1
```

### Execution order

Each stage of a scan can stop it with its own exit code. The gate is evaluated last, after the reports are written, so a scan that fails the gate still leaves a full report behind. An error, by contrast, stops the scan before anything is reported.

1. Parse the command-line options. Fails with `2` on an invalid option value, more than one package or source file, or both include and exclude rules.
2. Load the project. Fails with `3`. Then check that the dependencies of each package are locked in `Dependencies.toml`. Fails with `1`.
3. Outside a workspace, fail with `1` on an empty package. In a workspace, load the workspace `Scan.toml`, failing with `1` on a configuration error, and skip each empty package with a warning.
4. Prepare each package: load the `Scan.toml` it uses, with its remote configuration, apply the command-line options with their override warnings, load the analyzer plugins and their rule files, resolve the rules, and resolve the platforms named in `--platforms` and their plugins. Fails with `1` on a configuration, download, plugin or platform error, and with `2` on a rule option that conflicts with the `[rule]` table. In a workspace, every package is prepared before any is scanned, a usage error stops the scan at once, and any other error is recorded for the package.
5. Check that the rule IDs given on the command line exist in the rules of every prepared package. Fails with `2`. In a workspace, this check is skipped when a package failed to prepare, and the package failures are reported instead.
6. Resolve the gate of each package (rule 3), compile the package and run the analysis. Fails with `1` on compilation errors, an analyzer error or an unexpected exception.
7. Apply the rule selection and the `@scan:Suppress` annotations, check that the rules they name exist, and check the `[suppression]` requirements. Fails with `1` on an invalid suppression, before any issue is printed, saved or sent to a platform. In a workspace, nothing is reported until every package has been scanned without an error.
8. Print the issues, write the reports and print the summary. Fails with `1` on a report error.
9. Send the results to every selected platform, at the same time. Fails with `1` after every platform has run, if any failed. A failed platform wins over the gate.
10. Evaluate the gate. Fails with `1`, or exits with `0`.

### Compatibility

- Findings still exit with `0` by default, because no gate is set.
- Scripts and pipelines that relied on a `0` exit when the project path is invalid, `Scan.toml` is broken, a plugin fails to load or a package is empty will start failing. This is the intent of the change.
- Compilation errors and report write failures keep exiting with `1`.
- Progress messages and report locations move to standard error with the errors and warnings, so standard output holds only the issues.
- A scan started by a rule test runner, through the protected `ScanCmd` constructor, has the gate off, so that the issues of a fixture can be inspected whatever its `[gate]` table sets. Its failures are thrown as a `ScanToolException`, which carries the diagnostics behind the failure, instead of a `BLauncherException`.

## Alternatives

**One exit code per severity.** The exit code would be the highest severity found, for example `1` for `INFO` up to `5` for `BLOCKER`. This is not possible under the Ballerina CLI Tool Design Guide.

- The guide's exit code table is closed, and a tool must not define other codes (section 8). Codes `2` and `3` already mean a usage error and an invalid target in every `bal` tool, `4` means overwrite refused, and `5` is not allowed at all.
- The design does not need it either. The scan report already says which severities were found and how many of each, and `--fail-on-severity` sets the fail point in the tool and in `Scan.toml`, where it is versioned and reviewed.

**A separate exit code for each type of failure.** A tripped gate, a configuration error, a plugin error and an internal error would each get their own code. This is not possible under the Ballerina CLI Tool Design Guide.

- The guide's exit code table is closed, and a tool must not define other codes (section 8). Every failure that is not a usage error, an invalid target, a refused overwrite or an interrupt exits with `1`, so a tripped gate, a configuration error, a plugin error and an internal error all share it.
- The design does not need it either. Shells, build tools and CI/CD systems act on zero and non-zero, and the error report on standard error says which failure occurred.

**Keep errors exiting with `0`.** This is not adopted. A broken `Scan.toml`, a failed JAR download or an empty package would keep giving a green run that scanned nothing, which is the problem the proposal fixes. A caller that wants to ignore every outcome can still do so itself, for example with `|| true` in a shell, or the equivalent setting of a CI/CD system.

**A bitmask exit code.** Each bit would stand for a severity, a category or a type of failure, so several outcomes could be combined in one code. This is not possible under the Ballerina CLI Tool Design Guide.

- The guide's exit code table is closed, and a tool must not define other codes (section 8). Combined codes such as `5` or `6` are not in the table, and single bits would reuse `1`, `2` and `4`, which already mean a runtime error, a usage error and a refused overwrite.
- The design does not need it either. The report and the severities are already there, and the gate provides the fail point, so the exit code only has to say pass or fail.

## Testing

- **Exit codes.** Unit tests replace the exit handler and assert the exit code and the error report for each situation in the [failures](#failures) table: invalid options, too many arguments, an invalid path, a `.bal` file inside a package, load diagnostics, unlocked dependencies, each `Scan.toml` and remote configuration error, a failed download, compilation errors, an empty package, a plugin that fails to load, a missing platform, a rule option that conflicts with `Scan.toml`, and a report write failure. A platform plugin that throws in `init` or `onScan` exits with `1` after the results are saved and every other platform has run, and the error report names each failed platform. An interrupt exits with `130` and writes no error report.
- **Gate.** Tests cover each row of the [gate](#gate) table against packages with issues of each severity, including counts just below, at and above the limit. They also cover each command-line option replacing only its own `[gate]` setting, so that `--fail-on-count` alone keeps `failOnSeverity` from `Scan.toml`; the override warning when a setting differs and its absence when it is the same or not written; `--fail-on-severity=NONE` turning off a `Scan.toml` gate and `--fail-on-count` alone keeping off a gate that `failOnSeverity = "NONE"` turns off; case-insensitive severities; invalid severities and counts (`0`, negative and non-numeric) from both sources, and unknown `[gate]` keys, reported at their location; issues excluded by `--include-rules`, `--exclude-rules` and inline suppressions; plugin rules without a severity; and the gate being off for a platform-triggered scan.
- **Suppressions.** An unknown rule in an annotation, a missing reason with `requireReason` or `--require-suppression-reason`, and a missing rule list with `requireRuleId` or `--require-suppression-rule-id` each exit with `1` before any issue is reported, and win over a tripped gate. None of them fails the scan with `--ignore-suppressions` or `enabled = false`, and then suppressed issues count toward the gate. A malformed rule ID or an empty rule list exits with `1` as a compilation error, and a non-boolean `[suppression]` setting exits with `1` as a configuration error. Suppression warnings, such as an unmatched or unverifiable rule, leave the exit code unchanged.
- **Default.** A scan with issues of every severity and no gate exits with `0`.
- **Errors win.** A scan with both a tripped gate and an error reports the error, not the gate failure, including with `--fail-on-severity=NONE`.
- **Workspaces.** A workspace with a mix of clean packages, packages with issues, empty packages and packages with errors scans every package with sources, skips each empty package with a warning, and reports every failing package in the error report, exiting with `3` if any package is an invalid target and `1` otherwise. Gate tests cover each package checked against its own gate with its own issues, including packages without a gate and the per-package error report; a command-line gate applied to every package, never counting issues across packages, with one override warning for each `Scan.toml` that writes a setting differently; a package without a `Scan.toml` using the workspace one, and a package `Scan.toml` used instead of it as a whole, with a warning that names the workspace settings it does not apply; an empty package `Scan.toml` turning the gate off; a platform that only some packages declare; and a `[[platform]]` table in the workspace `Scan.toml` failing with `1`.
- **Reports.** A scan that fails on the gate still writes `scan_results.json`, SARIF and the HTML report with every issue.
- **Error reports.** Error reports follow the `bal scan: error: <message>` form, `Scan.toml` problems are reported as `<path>:<line>:<col>` diagnostics, and usage errors print the synopsis and help pointer but not the full help. Warnings follow the same format, as `bal scan: warning: <message>`.
- **Output streams.** Standard output holds only the issues, as valid JSON or SARIF, and progress messages, report locations, warnings, error diagnostics and the error report are written to standard error, with the error report last.

## Risks and Assumptions

- Scripts and pipelines that pass today because errors exit with `0` will start failing after the upgrade. The release notes list the affected situations and their exit codes.
- A tripped gate and a tool error share exit code `1`. Until a machine-readable error output is added, a caller that treats them differently can only tell them apart from the error message, which is not a stable interface. The documentation must make this clear.
- Until the launcher can carry an exit code, the scan tool calls `Runtime.getRuntime().exit`, which bypasses the launcher's own exit handling. This assumes the launcher does no work after a tool command returns that the scan tool would skip.
- Some tools and wrappers may parse `bal scan` standard output for errors or report locations. Moving them to standard error changes what they see.
- A failed platform upload now fails the scan. A pipeline that must keep passing when a platform is down has to handle the exit code itself.
- Many tools use a "maximum allowed" count, which fails above the number. `--fail-on-count` fails at the number. The name and the documentation must make this clear to avoid off-by-one gates.

## Dependencies

- The scan tool's existing `Severity` enum and the `resolveSarifLevel` fallback.
- [Proposal #1496: In-source suppression of scan findings](1496-in-source-scan-suppression.md), for the `@scan:Suppress` annotation, the `[suppression]` settings and their diagnostics. The suppression failures and the suppression step of the execution order apply once it is in place.
- The `bal` launcher in ballerina-lang, to let `BLauncherException` carry an exit code, as the guide expects (OUT-4). Until then the scan tool exits on its own.

## Future Work

- **Machine-readable error output.** An option, such as `--output-format json`, that writes error reports and warnings as JSON, once the Ballerina CLI Tool Design Guide settles the format. Each error would carry a stable identifier for the failure, so a caller can tell a tripped gate from a tool error without parsing the message.
- **Per-severity count limits.** A table in `Scan.toml` with a separate count for each severity, for example failing on one `BLOCKER` or on ten `MEDIUM` issues.
- **New-code gating.** A baseline file, or a `--new-code-since <commit>` option, so a team can gate on the issues a change introduces without first fixing every existing issue.
- **Per-rule severity overrides** in `Scan.toml`, so a team can raise or lower the severity of a rule for gating and reports.

## References

- [Issue #1497: Build gating and the exit code contract for Ballerina scan tool](https://github.com/ballerina-platform/ballerina-spec/issues/1497)
- [Proposal #1496: In-source suppression of scan findings](1496-in-source-scan-suppression.md)
- [Proposal #1507: Introduce a GitHub Action to run `bal scan` in CI/CD pipelines](1507_scan_github_action.md)
- [Ballerina scan tool documentation](https://ballerina.io/learn/scan-tool/)
- [ballerina-lang launcher `Main.java`](https://github.com/ballerina-platform/ballerina-lang/blob/master/cli/ballerina-cli/src/main/java/io/ballerina/cli/launcher/Main.java)
