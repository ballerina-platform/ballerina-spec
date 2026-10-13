# Introduce a GitHub Action to Run `bal scan` in CI/CD Pipelines

- Authors - Charana Manawathilake
- Reviewed by - TBD
- Created date - 2026-10-12
- Updated date - 2026-10-12
- Issue - [1507](https://github.com/ballerina-platform/ballerina-spec/issues/1507)
- State - Submitted

## Summary

This proposal introduces `ballerina-platform/scan-ballerina`, a versioned GitHub Action that runs `bal scan` on the Ballerina packages in a repository and gets its findings to the code scanning tool a team prefers: GitHub code scanning, SonarQube, or any other platform that reads SARIF.

The action does one thing, as GitHub recommends for actions. It prepares the toolchain, runs `bal scan` once per package, configured for the selected platforms, and outputs one SARIF 2.1.0. This gives users the freedom to choose where to upload it.

The action hides the setup that blocks adoption today: installing the scan tool, provisioning Java and SonarScanner, placing the SonarQube platform plugin, writing `Scan.toml`, and fixing SARIF paths. A team should go from zero to findings on its pull requests with about five lines of workflow YAML.

## Motivation

Wiring Ballerina static analysis into CI today takes a lot of hand-maintained YAML per repository and knowledge of several toolchains. The friction falls into three areas.

- **Toolchain setup.** A runner needs Ballerina and the scan tool from Ballerina Central (`bal tool pull scan`), and the workflow has to keep their versions compatible as each one is released independently.
- **Configuration.** A SonarQube run needs a `[[platform]]` entry in `Scan.toml` that registers the platform plugin, and SonarScanner properties. In a workflow these values differ from a developer's machine: the plugin JAR and properties file live at runner paths, and the server URL and token come from secrets. Teams need a simple way to set them per workflow without editing committed files, and teams that already keep a `Scan.toml` for rule selection risk losing it if a script overwrites it.
- **SARIF fixes.** `bal scan` writes one report per package, with file URIs relative to that package. GitHub code scanning accepts one run per category and maps results to files relative to the repository root, so in a repository with several packages, or a package outside the root, the reports must be rewritten and merged before upload.

Platforms differ in how they take results. GitHub code scanning imports SARIF. A SonarQube server with the Ballerina language plugin takes results through the scan tool's platform plugin, which keeps the rules manageable in quality profiles. DefectDojo and JFrog each have their own upload tooling. An action that tries to upload everywhere has to track every one of these APIs, permission models and outages. An action that produces a correct SARIF file, and sets up the scan tool's own SonarQube support, covers all of them with far less to maintain.

## Goals

- Run `bal scan` in GitHub Actions in one step, with about five lines of YAML for the common case.
- Route findings to a preferred platform, such as GitHub code scanning or SonarQube.
- Produce a normalized SARIF 2.1.0 file on every run that GitHub code scanning accepts as is, and that other SARIF consumers can use.
- Hide the toolchain setup: Ballerina, the scan tool, and for SonarQube, Java, SonarScanner, the platform plugin, and its `Scan.toml` entry when the package does not have one.
- Never lose a user's existing `Scan.toml` or SonarScanner properties.
- Provide an opt-in gate and a job summary, and expose the result and counts as outputs.
- Distribute the action as a versioned, Marketplace-listed repository that users can pin.

## Non-Goals

- **Managing the SonarQube server.** Installing or upgrading the Ballerina language plugin on the server is for its administrators.
- **Other CI systems.** GitLab and Bitbucket integrations are future work. The scan and SARIF normalization are kept in scripts that those integrations can reuse.
- **New rules.** The action uses whatever rules `bal scan` and its plugins provide.

## Design

### Overview

The action is a composite action whose logic is in shell and `jq` scripts at the root of the repository, next to `action.yml`, as in [`setup-ballerina`](https://github.com/ballerina-platform/setup-ballerina). The scripts read their inputs from environment variables, can be run locally, and can be reused by integrations for other CI systems.

`bal scan` runs once per package whatever platforms are selected.

### Usage

**GitHub code scanning.** The action uploads the SARIF file to code scanning itself.

```yaml
steps:
  - uses: actions/checkout@v4
  - uses: ballerina-platform/scan-ballerina@v1
    with:
      platforms: codeql
```

The job needs `security-events: write`, and `actions: read` on private repositories.

**SonarQube server with the Ballerina plugin.** Once the required SonarQube settings are provided, the action reports the findings to SonarQube.

```yaml
steps:
  - uses: actions/checkout@v4
    with:
      fetch-depth: 0   # SonarQube needs history for blame and new-code detection
  - uses: ballerina-platform/scan-ballerina@v1
    with:
      platforms: sonarqube
    env:
      SONAR_TOKEN: ${{ secrets.SONAR_TOKEN }}
```

**Any other SARIF consumer**, such as DefectDojo, takes `steps.scan.outputs.sarif-file` with its own upload step.

### Execution flow

1. **Validate inputs** and fail with a message naming the input and its accepted values, before anything is downloaded. With `sonarqube` selected, check that each required setting has a suitable value in its file field or environment variable: a server URL that is a valid `http` or `https` URL, a non-empty token, and a project key. If a platform plugin JAR or properties file path is set, check that the file exists. Fail with a message naming the missing setting, along with its file field and environment variable. See [SonarQube](#sonarqube).
2. **Set up Ballerina.** If `bal` is already on the path, for example from an earlier `setup-ballerina` step, use it. Otherwise install `ballerina-version` with `setup-ballerina`.
3. **Install the scan tool.** Use `tool-version` if given, otherwise the version pinned by the action release. The tool is pulled only when it is missing or a different version is active, so the action can run more than once in a job.
4. **Prepare SonarQube** (`sonarqube` only). See [SonarQube](#sonarqube).
5. **Find packages.** Each entry in `paths` is a package or a directory searched for `Ballerina.toml`, skipping `target`, `build` and `.git`. Packages matching `exclude-paths` are dropped and overlapping paths are deduplicated. When no package is found, the result is `skipped` and the step passes.
6. **Scan each package** with `bal scan --format=sarif`, plus `--platforms=sonarqube` when selected, and `--include-rules` and `--exclude-rules` when set. Any old report is deleted first, so a report from an earlier run is never read. If `bal scan` fails for a package, the step fails.
7. **Normalize and merge** the package reports into one SARIF file, and set the outputs.
8. **Upload the findings** to each selected platform with the upload method suited to it, for example `github/codeql-action/upload-sarif` under `category` for code scanning. This runs before the gate, so findings reach the platforms even when the gate fails.
9. **Restore the workspace.** Revert `Scan.toml` changes, so later steps see the original file.
10. **Report.** Write annotations, when enabled, and the job summary.
11. **Apply the gate** and fail the step if it fails.

### Inputs

| Input | Default | Description |
| --- | --- | --- |
| `ballerina-version` | `latest` | Ballerina version to install when Ballerina is not already installed. |
| `tool-version` | pinned per release | `bal scan` tool version. |
| `platforms` | `none` | Comma-separated platforms to send the findings to: `codeql`, `sonarqube`. |
| `paths` | `.` | Newline or comma separated paths to scan. Every package and workspace in these paths, including their subdirectories, is scanned. The findings of all of them are merged into one SARIF file, given as the `sarif-file` output. Missing paths are ignored. |
| `exclude-paths` | empty | Newline or comma separated globs, relative to the repository root, for packages and files to leave out. A directory excludes everything below it. `*` stays within one directory and `**` crosses directories. |
| `exclude-tests` | `true` | Drop findings in `tests/` and `modules/*/tests/`. |
| `category` | `bal-scan` | Name for this scan. Labels the uploaded findings, the job summary and messages. Use a different one for each scan in a job. |
| `include-rules` | empty | Comma separated rule IDs to report, such as `ballerina:1,ballerina/crypto:1`. Passed to `bal scan --include-rules`. Empty reports every rule. |
| `exclude-rules` | empty | Comma separated rule IDs to leave out, such as `ballerina:1,ballerina:10`. Passed to `bal scan --exclude-rules`. |
| `fail-on-severity` | `none` | Fail when findings are at or above `low`, `medium` or `high`. |
| `max-findings` | `0` | Findings at or above `fail-on-severity` allowed before the step fails. |
| `annotations` | `false` | Show each counted finding as a file and line annotation. |
| `job-summary` | `true` | Write the result and the high, medium and low counts to the job summary. |
| `github-token` | `github.token` | Token for installing Ballerina. |

`fail-on-severity` defaults to `none`, so adding the action never breaks a build until a team chooses to gate. `annotations` defaults to `false` because GitHub limits annotations per step, and code scanning already annotates the diff once the SARIF is uploaded.

### Outputs

| Output | Description |
| --- | --- |
| `result` | `passed`, `failed`, or `skipped` when no package was found. |
| `sarif-file` | The merged, normalized SARIF file. Empty when no package was found or a scan failed with compilation errors. |
| `high-count`, `medium-count`, `low-count`, `total-count` | Counted findings, after the test and path filters. |
| `packages-scanned` | Number of packages scanned. |
| `uploads` | JSON object with one entry per platform the findings were sent to, such as `{"codeql": {"sarif-id": "…"}, "sonarqube": {"dashboard-url": "…", "task-id": "…"}}`. A platform that was not selected or failed to upload has no entry; `{}` when nothing was uploaded. Read a value with `fromJSON(steps.scan.outputs.uploads).codeql.sarif-id`. |

### SARIF output

The action, not each destination, owns the correctness of the SARIF file, so every consumer gets the same file. It is produced from the reports of `bal scan --format=sarif`:

| Concern | Rule | Why |
| --- | --- | --- |
| File paths | Prefix each `artifactLocation.uri` with the package path, so it is relative to the repository root. Applied for every platform. | Consumers such as code scanning cannot map package-relative paths in a repository with several packages, or a package outside the root. |
| Test and excluded files | Drop findings in test sources (with `exclude-tests`) and in files matching `exclude-paths`. | Keeps out findings the team has chosen not to see. |
| Multiple packages | Merge all packages into one run, deduplicate rules by ID and recompute each result's `ruleIndex`. | Code scanning accepts one run per category, and GitHub rejects uploads with several runs in the same category. |

### Severity mapping

The gate, counts and annotations read the severity from each result's SARIF `level`:

| Ballerina severity | SARIF `level` | Action severity |
| --- | --- | --- |
| `BLOCKER` | `error` | `high` |
| `HIGH` | `error` | `high` |
| `MEDIUM` | `warning` | `medium` |
| `LOW` | `note` | `low` |
| `INFO` | `none` | Not counted |

A result without a `level` is treated as `warning`, as SARIF defines.

### SonarQube

With `platforms: sonarqube`, the action reports the findings to a SonarQube server that has the Ballerina language plugin installed. `bal scan --platforms=sonarqube` sends them through the scan tool's SonarQube platform plugin, so the rules can be managed and activated per project in quality profiles.

Each setting can come from `sonar-project.properties` and `Scan.toml`, or from an environment variable, so a workflow can configure SonarQube without committing either file. An environment variable overrides the file. The action passes the values to the scan without changing the user's files.

| Setting | File | Environment variable |
| --- | --- | --- |
| Server URL | `sonar.host.url` in `sonar-project.properties` | `SONAR_HOST_URL` |
| Token | | `SONAR_TOKEN` |
| Project key | `sonar.projectKey` in `sonar-project.properties` | `SONAR_PROJECT_KEY` |
| Project name | `sonar.projectName` in `sonar-project.properties` | `SONAR_PROJECT_NAME` |
| Platform plugin JAR | `path` in the `Scan.toml` `[[platform]]` entry. Defaults to the JAR the action downloads. | `SONAR_PLATFORM_PLUGIN_PATH` |
| Properties file | `sonarProjectPropertiesPath` in the `Scan.toml` `[[platform]]` entry. Defaults to the package's `sonar-project.properties`. | `SONAR_PROJECT_PROPERTIES_PATH` |

### Gate

The gate uses both `fail-on-severity` and `max-findings`. `fail-on-severity` is evaluated first and selects the findings at or above that severity. `max-findings` is evaluated second, and the step fails when the number of selected findings is greater than it. For example, `fail-on-severity: medium` with `max-findings: 5` fails the step on six or more medium or high findings.

The defaults are `none` and `0`, so the gate is off until a team sets `fail-on-severity`, and then a single finding at or above that severity fails the step.

### Annotations and job summary

With `annotations`, each counted finding becomes an `error`, `warning` or `notice` annotation for `high`, `medium` and `low`, on its file and start line, titled with the rule ID.

With `job-summary`, the action writes the result, any failure reasons and the number of findings at each severity: high, medium and low. This keeps results visible where a team has no code scanning platform, such as a private repository without GitHub Code Security.

### Failure behaviour

Findings never fail the step unless the user asks. Problems with the setup or the scan do.

| Situation | Result |
| --- | --- |
| Invalid or unknown input, or missing SonarQube settings | Fail before anything is downloaded |
| Checksum mismatch on a download | Fail |
| `bal scan` fails for a package | Fail |
| SonarQube is unreachable, or rejects the analysis | Fail, after the SARIF file is written |
| Findings with `fail-on-severity: none` | Pass, with counts in the job summary |
| Findings over the gate | Fail, after the SARIF file is written |
| Fork pull request with no `SONAR_TOKEN` | Skip `sonarqube` with a warning, and still produce the SARIF file |

### Security

A security scanning action is itself part of the supply chain.

- **Pinned, verified downloads.** Every binary the action downloads has a pinned version and a SHA-256 checksum stored in the action repository. A mismatch fails the run.
- **Least privilege.** The action needs only `contents: read`, plus `security-events: write` with `codeql`.
- **Secrets.** SonarScanner reads the token from the `SONAR_TOKEN` environment variable, never from the command line, and the action masks it with `::add-mask::`.
- **Input injection.** Inputs reach the scripts as environment variables, never interpolated into `run:` blocks.
- **Fork pull requests.** Secrets are not available to `pull_request` runs from forks. The action skips `sonarqube` with a notice rather than failing, and does not recommend `pull_request_target`.

### Multiple scans in a workflow

The action can run more than once in a job, for example for package groups with different thresholds. Work files are kept per run, the scan tool is pulled only once, and each SARIF file can be uploaded under its own code scanning category.

## Testing

The action repository has a test workflow that runs the action against sample Ballerina packages, to check that it scans, gates, reports and uploads as expected.

## Dependencies

- `bal scan` with SARIF output (scan tool 0.12.1 or later, from the production Central) and the SonarQube platform plugin.
- [`ballerina-platform/setup-ballerina`](https://github.com/ballerina-platform/setup-ballerina).
- The SonarScanner CLI and the Ballerina SonarQube language plugin on the server, for native mode.

## Future Work

- Hand gating, baselines, changed-file scanning, metadata and suppression to `bal scan` as the related proposals land.
- Create equivalent integrations for other CI/CD systems, such as GitLab and Bitbucket.

## References

- [`ballerina-library` `scan-ballerina` action](https://github.com/ballerina-platform/ballerina-library/tree/main/.github/actions/scan-ballerina)
- [GitHub: Uploading a SARIF file to GitHub](https://docs.github.com/en/code-security/code-scanning/integrating-with-code-scanning/uploading-a-sarif-file-to-github)
- [GitHub: SARIF support for code scanning](https://docs.github.com/en/code-security/code-scanning/integrating-with-code-scanning/sarif-support-for-code-scanning)
- [SARIF 2.1.0 specification](https://docs.oasis-open.org/sarif/sarif/v2.1.0/sarif-v2.1.0.html)
