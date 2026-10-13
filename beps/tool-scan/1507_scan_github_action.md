# Introduce a GitHub Action to Run `bal scan` in CI/CD Pipelines

- Authors - Charana Manawathilake
- Reviewed by - TBD
- Created date - 2026-10-12
- Updated date - 2026-10-13
- Issue - [1507](https://github.com/ballerina-platform/ballerina-spec/issues/1507)
- State - Submitted

## Summary

This proposal introduces `ballerina-platform/scan-ballerina`, a versioned GitHub Action that runs `bal scan` on the Ballerina packages in a repository and gets its findings to the code scanning tool a team prefers: GitHub code scanning, SonarQube, or any other platform that reads SARIF.

The action's core job is to produce one correct SARIF 2.1.0 file. It prepares the toolchain, runs `bal scan` once per package, and merges the reports into that file, which any SARIF consumer can upload with its own tooling. Two destinations are built in because a generic upload step cannot cover them well: GitHub code scanning, which needs the merged file uploaded under a category, and SonarQube, which receives findings through the scan tool's own platform plugin during the scan.

The action hides the setup that blocks adoption today: installing the scan tool, provisioning Java and SonarScanner, placing the SonarQube platform plugin and its `Scan.toml` entry, and fixing SARIF paths. Any change it makes to a user's files is temporary and is reverted. A team should go from zero to findings on its pull requests with about five lines of workflow YAML.

## Motivation

Wiring Ballerina static analysis into CI today takes a lot of hand-maintained YAML per repository and knowledge of several toolchains. The friction falls into three areas.

- **Toolchain setup.** A runner needs Ballerina and the scan tool from Ballerina Central (`bal tool pull scan`), and the workflow has to keep their versions compatible as each one is released independently.
- **Configuration.** A SonarQube run needs a `[[platform]]` entry in `Scan.toml` that registers the platform plugin, and SonarScanner properties. In a workflow these values differ from a developer's machine: the plugin JAR and properties file live at runner paths, and the server URL and token come from secrets. Teams need a simple way to set them per workflow without editing committed files, and teams that already keep a `Scan.toml` for rule selection risk losing it if a script overwrites it.
- **SARIF fixes.** `bal scan` writes one report per package, with file URIs relative to that package. GitHub code scanning accepts one run per category and maps results to files relative to the repository root, so in a repository with several packages, or a package outside the root, the reports must be rewritten and merged before upload.

Platforms differ in how they take results. GitHub code scanning imports SARIF. A SonarQube server with the Ballerina language plugin takes results through the scan tool's platform plugin, which keeps the rules manageable in quality profiles. DefectDojo and JFrog each have their own upload tooling. An action that tries to upload everywhere has to track every one of these APIs, permission models and outages. An action that produces a correct SARIF file, and sets up the scan tool's own SonarQube support, covers all of them with far less to maintain.

## Goals

- Run `bal scan` in GitHub Actions in one step, with about five lines of YAML for the common case.
- Route findings to a preferred platform, such as GitHub code scanning or SonarQube.
- Produce a normalized SARIF 2.1.0 file on every successful run that GitHub code scanning accepts as is, and that other SARIF consumers can use.
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

The action is a composite action whose logic is in shell, `jq` and `yq` scripts at the root of the repository, next to `action.yml`, as in [`setup-ballerina`](https://github.com/ballerina-platform/setup-ballerina). The scripts read their inputs from environment variables, can be run locally, and can be reused by integrations for other CI systems.

`bal scan` runs once per package whatever platforms are selected. With `sonarqube` selected, the same run writes the SARIF report and sends the findings to SonarQube.

### Usage

**GitHub code scanning.** The action uploads the SARIF file to code scanning itself.

```yaml
steps:
  - uses: actions/checkout@v4
  - uses: ballerina-platform/scan-ballerina@v1
    with:
      platforms: github-code-scanning
```

The job needs `security-events: write`, and `actions: read` on private repositories.

**SonarQube server with the Ballerina plugin.** Once the required SonarQube settings are provided, the findings are reported to SonarQube.

```yaml
steps:
  - uses: actions/checkout@v4
    with:
      fetch-depth: 0   # SonarQube needs history for blame and new-code detection
  - uses: ballerina-platform/scan-ballerina@v1
    with:
      platforms: sonarqube
      platform-config: |
        sonarqube:
          host-url: ${{ vars.SONAR_HOST_URL }}
          token: ${{ secrets.SONAR_TOKEN }}
          project-key: my-project
```

Settings left out of `platform-config` are read from the package's `sonar-project.properties`. See [Platform configuration](#platform-configuration) and [SonarQube](#sonarqube).

**Any other SARIF consumer**, such as DefectDojo, takes the `sarif-file` output with its own upload step.

```yaml
steps:
  - uses: actions/checkout@v4
  - id: scan
    uses: ballerina-platform/scan-ballerina@v1
  - run: ./upload-to-defectdojo.sh "${{ steps.scan.outputs.sarif-file }}"
```

### Execution flow

1. **Validate inputs** and fail with a message naming the input and its accepted values, before anything is downloaded. Every path in `paths` must exist. `platform-config` must parse as a mapping that matches the [schema](#platform-configuration). A platform or field the action does not know fails the step, so a typo such as `tokn` is caught. Settings for a platform that is not in `platforms` are ignored with a warning. If a platform plugin JAR or properties file path is set, the file must exist. With `sonarqube` selected:
    - If the run is a pull request from a fork or from Dependabot and the SonarQube token is empty, skip `sonarqube` with a warning and continue without it. Secrets are not available to these runs.
    - Otherwise check that the server URL is a valid `http` or `https` URL and that the token is not empty. Fail with a message naming the missing setting and where it can be set. See [SonarQube](#sonarqube).
2. **Set up Ballerina.** If `bal` is already on the path, for example from an earlier `setup-ballerina` step, use it. Otherwise install `ballerina-version` with `setup-ballerina`. Each action release records the minimum Ballerina version its pinned scan tool needs. If the Ballerina in use is older, fail with a message naming both versions.
3. **Install the scan tool.** Use `tool-version` if given, otherwise the version pinned by the action release. The tool is pulled only when it is missing or a different version is active, so the action can run more than once in a job.
4. **Find packages.** Each entry in `paths` is a package or a directory searched for `Ballerina.toml`, skipping `target`, `build` and `.git`. A workspace is expanded into its member packages. Packages matching `exclude-paths` are dropped and overlapping paths are deduplicated, so each package is scanned once. When no package is found, the result is `skipped`, a warning is written and the step passes.
5. **Prepare SonarQube** (`sonarqube` only). Install Java and SonarScanner, download the platform plugin, and resolve the settings of each package. Check that each package has a project key and that no two packages share one. See [SonarQube](#sonarqube).
6. **Scan each package** with `bal scan --format=sarif`, plus `--platforms=sonarqube` when selected, and `--include-rules` and `--exclude-rules` when set. Any old report is deleted first, so a report from an earlier run is never read. With `sonarqube`, the findings are sent to SonarQube during this step. If `bal scan` fails for a package, for example on compilation errors or because SonarQube rejects the analysis, the remaining packages are still scanned so that every failure is reported, and the step then fails without producing a SARIF file.
7. **Normalize and merge** the package reports into one SARIF file, and set the outputs.
8. **Upload to code scanning** (`github-code-scanning` only) with `github/codeql-action/upload-sarif` under `category`. SonarQube already received its findings in step 6. Both happen before the gate, so findings reach the platforms even when the gate fails.
9. **Report.** Write annotations, when enabled, and the job summary.
10. **Apply the gate** and fail the step if it fails.

Whatever the outcome, the workspace is restored when the action exits: any `Scan.toml` the action created or changed is reverted, so later steps see the original files. The scripts register the restore with a shell `trap` as soon as they change a file, so it also runs when a step fails.

### Inputs

| Input | Default | Description |
| --- | --- | --- |
| `ballerina-version` | `latest` | Ballerina version to install when Ballerina is not already installed. Pin a version for reproducible runs. |
| `tool-version` | pinned per release | `bal scan` tool version. |
| `platforms` | empty | Comma separated platforms to send the findings to: `github-code-scanning`, `sonarqube`. Empty produces the SARIF file only. |
| `paths` | `.` | Newline or comma separated paths to scan. Every package and workspace in these paths, including their subdirectories, is scanned. The findings of all of them are merged into one SARIF file, given as the `sarif-file` output. A path that does not exist fails the step. |
| `exclude-paths` | empty | Newline or comma separated globs, relative to the repository root, for packages and files to leave out. A directory excludes everything below it. `*` stays within one directory and `**` crosses directories. |
| `exclude-tests` | `true` | Drop findings in `tests/` and `modules/*/tests/`. |
| `category` | `bal-scan` | Name for this scan. Labels the uploaded findings, the job summary and messages. Use a different one for each scan in a job. |
| `include-rules` | empty | Comma separated rule IDs to report, such as `ballerina:1,ballerina/crypto:1`. Passed to `bal scan --include-rules`. Empty reports every rule. |
| `exclude-rules` | empty | Comma separated rule IDs to leave out, such as `ballerina:1,ballerina:10`. Passed to `bal scan --exclude-rules`. |
| `fail-on-severity` | `none` | Fail when findings are at or above `low`, `medium` or `high`. `none` turns the gate off. |
| `max-findings` | `0` | Findings at or above `fail-on-severity` allowed before the step fails. |
| `annotations` | `false` | Show each counted finding as a file and line annotation. |
| `job-summary` | `true` | Write the result and the high, medium and low counts to the job summary. |
| `platform-config` | empty | YAML mapping, keyed by platform, with the settings and credentials each selected platform needs. JSON is accepted, since it is valid YAML. See [Platform configuration](#platform-configuration). |
| `github-token` | `github.token` | Token for installing Ballerina and uploading to code scanning. |

`fail-on-severity` defaults to `none`, so adding the action never breaks a build until a team chooses to gate. `annotations` defaults to `false` because GitHub limits annotations per step, and code scanning already annotates the diff once the SARIF is uploaded.

### Platform configuration

`platform-config` holds the settings of every platform in one structured input, so a new platform adds fields to it rather than new inputs. GitHub passes inputs as strings, so the value is a YAML block that the action parses with `yq`. Each top-level key is a platform from `platforms`, and its value is that platform's settings:

```yaml
platform-config: |
  sonarqube:
    host-url: https://sonar.example.com
    token: ${{ secrets.SONAR_TOKEN }}
    plugin-path: tools/sonar-platform-plugin.jar
    packages:
      - path: services/orders
        project-key: orders
        project-name: Orders Service
      - path: services/payments
        project-key: payments
```

`github-code-scanning` takes no settings today. It uses `github-token` and `category`.

**`sonarqube` fields**

| Field | Type | Required | Description |
| --- | --- | --- | --- |
| `host-url` | string | Yes, unless set in the properties file | SonarQube server URL. Overrides `sonar.host.url`. |
| `token` | string | Yes | Token for submitting analyses. Pass it from a secret. |
| `project-key` | string | Yes, unless set in the properties file or under `packages` | Project key. Overrides `sonar.projectKey`. Can be used only when one package is scanned. |
| `project-name` | string | No | Project name. Overrides `sonar.projectName`. Can be used only when one package is scanned. |
| `plugin-path` | string | No | Path to the scan tool's SonarQube platform plugin JAR. Overrides `path` in the `Scan.toml` `[[platform]]` entry. Empty uses the JAR the action downloads. |
| `properties-path` | string | No | Path to the SonarScanner properties file, relative to each package. Overrides `sonarProjectPropertiesPath` in the `Scan.toml` `[[platform]]` entry. Empty uses `sonar-project.properties` in the package root. |
| `packages` | list | No | Per-package settings for repositories with several packages. Each item has a `path`, relative to the repository root, and a `project-key`, and may have a `project-name`. A `path` that matches no scanned package fails the step. |

A field under a `packages` item overrides the same field at the platform level, which overrides the properties file.

### Outputs

| Output | Description |
| --- | --- |
| `result` | `passed` or `failed` from the gate, `skipped` when no package was found, or `error` when the step failed before the gate, for example on invalid input or a failed scan or upload. |
| `sarif-file` | The merged, normalized SARIF file. Empty when no package was found or a scan failed. |
| `high-count`, `medium-count`, `low-count`, `total-count` | Counted findings, after the test and path filters. `total-count` is the sum of the other three and does not include `INFO` findings. |
| `packages-scanned` | Number of packages scanned. |
| `uploads` | JSON object with one entry per platform the findings were sent to, such as `{"github-code-scanning": {"sarif-id": "…"}, "sonarqube": [{"package": "…", "project-key": "…", "dashboard-url": "…", "task-id": "…"}]}`. `sonarqube` holds one item per package. A platform that was not selected or failed to upload has no entry; `{}` when nothing was uploaded. Read a value with `fromJSON(steps.scan.outputs.uploads)['github-code-scanning']['sarif-id']`. |

### SARIF output

The action, not each destination, owns the correctness of the SARIF file, so every SARIF consumer gets the same file. It is produced from the reports of `bal scan --format=sarif`:

| Concern | Rule | Why |
| --- | --- | --- |
| File paths | Prefix each `artifactLocation.uri` with the package path, so it is relative to the repository root. Applied for every platform. | Consumers such as code scanning cannot map package-relative paths in a repository with several packages, or a package outside the root. |
| Test and excluded files | Drop findings in test sources (with `exclude-tests`) and in files matching `exclude-paths`. | Keeps out findings the team has chosen not to see. |
| Multiple packages | Merge all packages into one run, deduplicate rules by ID and recompute each result's `ruleIndex`. | Code scanning accepts one run per category, and GitHub rejects uploads with several runs in the same category. |

SonarQube does not read this file. It receives each package's findings from the platform plugin during the scan, before the test and path filters are applied, so the SonarQube dashboard can show findings that the SARIF file, counts and gate leave out. Teams that need the same exclusions in SonarQube set them with `sonar.exclusions` and `sonar.test.inclusions` in the properties file or in the SonarQube project settings.

### Severity mapping

The gate, counts and annotations read the severity of each result from its SARIF level:

| Ballerina severity | SARIF `level` | Action severity |
| --- | --- | --- |
| `BLOCKER` | `error` | `high` |
| `HIGH` | `error` | `high` |
| `MEDIUM` | `warning` | `medium` |
| `LOW` | `note` | `low` |
| `INFO` | `none` | Not counted |

As SARIF defines, a result without a `level` takes its rule's `defaultConfiguration.level`, and is treated as `warning` when the rule has none either.

### SonarQube

With `platforms: sonarqube`, the action reports the findings to a SonarQube server that has the Ballerina language plugin installed. `bal scan --platforms=sonarqube` sends them through the scan tool's SonarQube platform plugin, so the rules can be managed and activated per project in quality profiles.

**One project per package.** Each package is a separate SonarQube analysis, so each package needs its own project key. In a repository with several packages, each package sets its key under `packages` in `platform-config`, or as `sonar.projectKey` in its own `sonar-project.properties`. The platform-level `project-key` and `project-name` fields can be used only when one package is scanned. Validation fails if a package has no project key, or if two packages resolve to the same key, since each analysis would replace the previous one.

**Settings.** Each setting is resolved per package, from the `sonarqube` fields of `platform-config` first and then from the package's files. See [Platform configuration](#platform-configuration) for the fields and their order.

**How the settings reach the scan.** The action never edits `sonar-project.properties`. For each package, it writes a copy of the properties file to the runner's temporary directory, with the project key and name overrides applied, and points the `[[platform]]` entry at that copy. The server URL and token reach SonarScanner as the `SONAR_HOST_URL` and `SONAR_TOKEN` environment variables of the scan process, never as command-line arguments. The `Scan.toml` of each package is handled as follows, and every change is reverted when the action exits:

| Package's `Scan.toml` | What the action does |
| --- | --- |
| Missing | Creates one with a `sonarqube` `[[platform]]` entry, and deletes it afterwards. |
| Present, without a `sonarqube` `[[platform]]` entry | Backs up the file to the runner's temporary directory, appends the entry and keeps the rest of the file as is. Restores the backup afterwards. |
| Present, with a `sonarqube` `[[platform]]` entry | Backs up the file and replaces only the `path` and `sonarProjectPropertiesPath` of that entry with the resolved values. Restores the backup afterwards. |

**Toolchain.** The action installs the Java version SonarScanner needs with `actions/setup-java`, unless a suitable Java is already on the path. It downloads the SonarScanner CLI and the platform plugin JAR at the versions pinned by the action release, and verifies their checksums.

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
| Invalid or unknown input, a `platform-config` that does not match the schema, a path that does not exist, or missing SonarQube settings | Fail before anything is downloaded |
| Ballerina older than the pinned scan tool needs | Fail before the scan tool is installed |
| Missing or duplicate SonarQube project keys | Fail before any package is scanned |
| Checksum mismatch on a download | Fail |
| No package found | Pass with a warning, result `skipped` |
| `bal scan` fails for a package, including when SonarQube is unreachable or rejects the analysis | Scan the remaining packages, then fail without a SARIF file |
| Upload to code scanning fails | Fail, after the SARIF file is written |
| Findings with `fail-on-severity: none` | Pass, with counts in the job summary |
| Findings over the gate | Fail, after the SARIF file is written and uploaded |
| Fork or Dependabot pull request with no SonarQube token | Skip `sonarqube` with a warning, and still produce the SARIF file |

### Security

A security scanning action is itself part of the supply chain.

- **Pinned, verified downloads.** The SonarScanner CLI and the platform plugin JAR, which the action downloads itself, have pinned versions and SHA-256 checksums stored in the action repository. A mismatch fails the run. The scan tool is pulled from Ballerina Central at the pinned version, and its integrity relies on Central. Ballerina is installed by `setup-ballerina`, at `latest` unless `ballerina-version` is set, so teams that need reproducible runs should pin it. Actions the composite action uses, such as `setup-ballerina`, `actions/setup-java` and `github/codeql-action/upload-sarif`, are pinned by commit SHA.
- **Least privilege.** The action needs only `contents: read`. With `github-code-scanning`, it also needs `security-events: write`, and `actions: read` on private repositories.
- **Secrets.** Credentials in `platform-config` should come from secrets, which GitHub masks in logs. The action also masks every credential field, such as `token`, with `::add-mask::`, never prints `platform-config`, and hands the SonarQube token to SonarScanner as the `SONAR_TOKEN` environment variable, never on the command line.
- **Input injection.** Inputs reach the scripts as environment variables, never interpolated into `run:` blocks.
- **Fork pull requests.** Secrets are not available to `pull_request` runs from forks or Dependabot. The action skips `sonarqube` with a warning rather than failing, and does not recommend `pull_request_target`.

### Multiple scans in a workflow

The action can run more than once in a job, for example for package groups with different thresholds. Work files are kept per run, the scan tool is pulled only once, and each SARIF file can be uploaded under its own code scanning category.

## Alternatives

SonarQube could import the SARIF file with `sonar.sarifReportPaths`, but imported findings cannot be managed in quality profiles, so the action uses the scan tool's platform plugin. Producing SARIF only, or adding a scan option to `setup-ballerina`, would either bring back most of the setup the action removes or mix toolchain setup with code analysis.

## Testing

The action repository has a test workflow that runs the action against sample Ballerina packages, to check that it scans, gates, reports and uploads as expected.

## Dependencies

- `bal scan` with SARIF output (scan tool 0.12.1 or later, from the production Central) and its SonarQube platform plugin.
- [`ballerina-platform/setup-ballerina`](https://github.com/ballerina-platform/setup-ballerina).
- For SonarQube: Java and the SonarScanner CLI on the runner, which the action installs, and the Ballerina language plugin on the server.

## Future Work

- Hand gating, baselines, changed-file scanning, metadata and suppression to `bal scan` as the related proposals land.
- Move SARIF normalization and merging into `bal scan`. See [Alternatives](#alternatives).
- Create equivalent integrations for other CI/CD systems, such as GitLab and Bitbucket.

## References

- [`ballerina-library` `scan-ballerina` action](https://github.com/ballerina-platform/ballerina-library/tree/main/.github/actions/scan-ballerina)
- [GitHub: Uploading a SARIF file to GitHub](https://docs.github.com/en/code-security/code-scanning/integrating-with-code-scanning/uploading-a-sarif-file-to-github)
- [GitHub: SARIF support for code scanning](https://docs.github.com/en/code-security/code-scanning/integrating-with-code-scanning/sarif-support-for-code-scanning)
- [SARIF 2.1.0 specification](https://docs.oasis-open.org/sarif/sarif/v2.1.0/sarif-v2.1.0.html)
