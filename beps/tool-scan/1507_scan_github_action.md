# Introduce a GitHub Action to Run `bal scan` in CI/CD Pipelines

- Authors - Charana Manawathilake
- Reviewed by - TBD
- Created date - 2026-10-12
- Updated date - 2026-10-15
- Issue - [1507](https://github.com/ballerina-platform/ballerina-spec/issues/1507)
- State - Submitted

## Summary

This proposal introduces `ballerina-platform/scan-ballerina`, a versioned GitHub Action that runs `bal scan` on the Ballerina packages in a repository and gets its findings to the code scanning tool a team prefers: GitHub code scanning, SonarQube, or any other platform that reads SARIF.

The action's core job is to produce one correct SARIF 2.1.0 file. It prepares the toolchain, runs `bal scan` once per package, and merges the reports into that file, which any SARIF consumer can upload with its own tooling. Two destinations are built in because a generic upload step cannot cover them well: GitHub code scanning, which needs the merged file uploaded under a category, and SonarQube, which receives findings through the scan tool's own platform plugin during the scan.

The action hides the setup that blocks adoption today: installing Ballerina and the scan tool, passing SonarQube settings and credentials to the scan, and fixing SARIF paths. It leaves a user's files as they were: any file it changes during a scan is restored when that scan ends. A team should go from zero to findings on its pull requests with about five lines of workflow YAML.

## Motivation

Wiring Ballerina static analysis into CI today takes a lot of hand-maintained YAML per repository and knowledge of several toolchains. The friction falls into three areas.

- **Toolchain setup.** A runner needs Ballerina and the scan tool from Ballerina Central (`bal tool pull scan`), plus Java and the SonarScanner CLI for SonarQube, and the workflow has to keep their versions compatible as each one is released independently.
- **Configuration.** A SonarQube run needs a token, and the SonarScanner properties `sonar.host.url`, `sonar.projectKey` and `sonar.projectName`, usually set in the package's `sonar-project.properties`. Teams need a simple way to set them per workflow without editing committed files.
- **SARIF fixes.** `bal scan` writes one report per package, with file URIs relative to that package. GitHub code scanning accepts one run per category and maps results to files relative to the repository root, so in a repository with several packages, or a package outside the root, the reports must be rewritten and merged before upload.

Platforms differ in how they take results. GitHub code scanning imports SARIF. A SonarQube server with the Ballerina language plugin takes results through the scan tool's platform plugin, which keeps the rules manageable in quality profiles. DefectDojo and JFrog each have their own upload tooling. An action that tries to upload everywhere has to track every one of these APIs, permission models and outages. An action that produces a correct SARIF file, and passes settings to the scan tool's own SonarQube support, covers all of them with far less to maintain.

## Goals

- Run `bal scan` in GitHub Actions in one step, with about five lines of YAML for the common case.
- Route findings to a preferred platform, such as GitHub code scanning or SonarQube.
- Produce a normalized SARIF 2.1.0 file on every successful run that scans at least one package, which GitHub code scanning accepts as is and other SARIF consumers can use. A run that finds no package passes as `skipped` without a SARIF file.
- Hide the toolchain setup for Ballerina and the scan tool.
- Pass SonarQube settings and credentials to the scan without editing any committed file.
- Provide an opt-in gate and a job summary, and expose the result and counts as outputs.
- Distribute the action as a versioned, Marketplace-listed repository that users can pin.

## Non-Goals

- **Managing the SonarQube server.** Installing or upgrading the Ballerina language plugin on the server is for its administrators.
- **Other CI systems.** GitLab and Bitbucket integrations are future work. The scan and SARIF normalization are kept in scripts that those integrations can reuse.
- **New rules.** The action uses whatever rules `bal scan` and its plugins provide.

## Design

### Overview

The action is a composite action whose logic is in shell, `jq` and `yq` scripts in the `scripts/` directory of the repository, as in [`setup-ballerina`](https://github.com/ballerina-platform/setup-ballerina). The scripts read their inputs from environment variables, can be run locally, and can be reused by integrations for other CI systems.

`bal scan` runs once per package to write the SARIF report, whatever platforms are selected. With `sonarqube` selected, a second run per package sends the findings to SonarQube, since the scan tool writes no SARIF report while a platform is active.

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

**SonarQube server with the Ballerina plugin.** The action installs SonarScanner and passes the server URL, token and project key to the scan.

```yaml
steps:
  - uses: actions/checkout@v4
  - uses: ballerina-platform/scan-ballerina@v1
    with:
      platforms: sonarqube
      platform-config: |
        sonarqube:
          host-url: ${{ vars.SONAR_HOST_URL }}
          token: ${{ secrets.SONAR_TOKEN }}
          project-key: my-project
```

The job needs `packages: read`, since the default platform plugin is downloaded from GitHub Packages. Settings left out of `platform-config` are read from the package's `sonar-project.properties`. See [Platform configuration](#platform-configuration) and [SonarQube](#sonarqube).

**Any other SARIF consumer**, such as DefectDojo, takes the `sarif-file` output with its own upload step.

```yaml
steps:
  - uses: actions/checkout@v4
  - id: scan
    uses: ballerina-platform/scan-ballerina@v1
  - run: ./upload-to-defectdojo.sh "${{ steps.scan.outputs.sarif-file }}"
```

**Saving the SARIF file.** With `artifacts: true`, the action saves the merged SARIF file as a workflow artifact named after `category`. It is the same file as the `sarif-file` output, so saving it takes no extra `bal scan` run.

```yaml
steps:
  - uses: actions/checkout@v4
  - uses: ballerina-platform/scan-ballerina@v1
    with:
      artifacts: true
```

### Execution flow


1. **Validate inputs** and fail with a message naming the input and its accepted values. These checks need only the inputs themselves. Every path in `paths` must exist. `platform-config` must parse as a mapping that matches the [schema](#platform-configuration). A platform or field the action does not know fails the step, so a typo such as `tokn` is caught. Settings for a platform that is not in `platforms` are ignored with a warning. `include-rules` and `exclude-rules` cannot both be set. With `sonarqube` selected:
    - If the run is a `pull_request` run from a fork or from Dependabot and any SonarQube `token` is empty, skip `sonarqube` with a warning and continue without it. Secrets are not available to these runs.
    - Otherwise check that every `token` that is set is not empty, that every `host-url` set at the platform level or under `packages` is a valid `https` URL, since every URL is used with a token, and that every `packages` item that sets `host-url` also sets `token`.
2. **Find packages.** Each entry in `paths` is a package or a directory searched for `Ballerina.toml`, skipping `target`, `build` and `.git`. A workspace is scanned once from its root. Packages matching `exclude-paths` are dropped and overlapping paths are deduplicated, so each package is scanned once. When no package is found, the result is `skipped`, a warning is written and the step passes. For each package, and each workspace member, whose `[scan] configPath` in `Ballerina.toml` is an `https` URL, download that `Scan.toml` into the work directory. Whatever platforms are selected, fail when a package's `Scan.toml` cannot be used: when `configPath` is a non-`https` URL, an `https` URL that cannot be downloaded or is not valid TOML, a form the action cannot change, or a file that does not exist, or the `[scan]` table has no `configPath`. See [`Scan.toml`](#scantoml).
3. **Resolve SonarQube settings** (`sonarqube` only). For each package, read its properties file and combine it with `platform-config` in the order given in [Platform configuration](#platform-configuration). Fail with a message naming the package, the missing setting and how to provide it, when:
    - the resolved plugin path is absolute, or is neither an existing file nor an `https` URL,
    - a properties file path is set and the file does not exist,
    - a package has no server URL, or its URL is not a valid `https` URL, including a URL from the properties file, since the token is sent to it,
    - a package has no token, from its `packages` item or the platform level,
    - a package has no project key, two packages on the same server resolve to the same key, or the platform-level `project-key` or `project-name` is set when more than one package is scanned, or is also set in the one package's item,
    - an item under `packages` matches no package found in step 2, or two items have the same `path`,
    - a workspace was found, since SonarQube is not supported for workspaces yet.

   See [SonarQube](#sonarqube).
4. **Set up Ballerina.** If `bal` is already on the path, for example from an earlier `setup-ballerina` step, use it. Otherwise install `ballerina-version` with `setup-ballerina`. Each action release records the minimum Ballerina version its pinned scan tool needs. If the Ballerina in use is older, fail with a message naming both versions.
5. **Install the scan tool.** Use `tool-version` if given, otherwise the version pinned by the action release. The tool is pulled only when it is missing or a different version is active, so the action can run more than once in a job. With `sonarqube`, also download the platform plugin when it is resolved to a version, from GitHub Packages, and the SonarScanner CLI. See [SonarQube](#sonarqube).
6. **Scan each package** from the package directory with `bal scan --format=sarif`, and `--include-rules` and `--exclude-rules` when set. Any old report is deleted first, so a report from an earlier run is never read. The scan tool writes no SARIF report while any `[[platform]]` entry in `Scan.toml` is active, so the action hides those entries, with their sub-tables, during this run and restores the file byte for byte as soon as it ends, including when it fails. With `sonarqube`, a second run with `--platforms=sonarqube` sends the findings to SonarQube with the package's resolved settings. See [SonarQube](#sonarqube). If `bal scan` fails for a package, for example on compilation errors or because SonarQube rejects the analysis, the remaining packages are still scanned so that every failure is reported, and the step then fails without producing a SARIF file.
7. **Normalize and merge** the package reports into one SARIF file, and set the outputs.
8. **Upload to code scanning** (`github-code-scanning` only) with `github/codeql-action/upload-sarif` under `category`. On a `pull_request` run from a fork or from Dependabot, the default `GITHUB_TOKEN` is read-only and cannot have `security-events: write`, so the action skips the upload with a warning and keeps the SARIF file as the `sarif-file` output. The workflow can save it with `artifacts: true` and upload it from a trusted `workflow_run` workflow. SonarQube already received its findings in step 6. Both happen before the gate, so findings reach the platforms even when the gate fails.
9. **Save the SARIF file** (`artifacts: true` only) as a workflow artifact named after `category`, with `actions/upload-artifact`. This step runs even when the upload to code scanning failed, so the SARIF file is still saved. When a scan failed, there is no SARIF file and nothing is saved.
10. **Report.** Write annotations, when enabled, and the job summary.
11. **Apply the gate** and fail the step if it fails.

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
| `exclude-rules` | empty | Comma separated rule IDs to leave out, such as `ballerina:1,ballerina:10`. Passed to `bal scan --exclude-rules`. Cannot be combined with `include-rules`. |
| `fail-on-severity` | `none` | Fail when findings are at or above `low`, `medium` or `high`. `none` turns the gate off. |
| `max-findings` | `0` | Findings at or above `fail-on-severity` allowed before the step fails. |
| `annotations` | `false` | Show each counted finding as a file and line annotation, up to GitHub's limit. See [Annotations and job summary](#annotations-and-job-summary). |
| `job-summary` | `true` | Write the result and the high, medium and low counts to the job summary. |
| `artifacts` | `false` | `true` saves the merged SARIF file as a workflow artifact named after `category`, holding `<category>.sarif`. Characters that artifact names cannot hold, such as `/` and `:`, are replaced with `_`. |
| `platform-config` | empty | YAML mapping, keyed by platform, with the settings and credentials each selected platform needs. JSON is accepted, since it is valid YAML. See [Platform configuration](#platform-configuration). |
| `github-token` | `github.token` | Token for installing Ballerina, downloading the SonarQube platform plugin from GitHub Packages and uploading to code scanning. |

### Platform configuration

`platform-config` holds the settings of every platform in one structured input, so a new platform adds fields to it rather than new inputs. GitHub passes inputs as strings, so the value is a YAML block that the action parses with `yq`. Each top-level key is a platform from `platforms`, and its value is that platform's settings:

```yaml
platform-config: |
  sonarqube:
    host-url: https://sonar.example.com
    token: ${{ secrets.SONAR_TOKEN }}
    packages:
      - path: services/orders
        project-key: orders
        project-name: Orders Service
      - path: services/payments
        host-url: https://sonar.payments.example.com
        token: ${{ secrets.PAYMENTS_SONAR_TOKEN }}
        project-key: payments
```

`github-code-scanning` takes no settings.

**`sonarqube` fields**

The fields at the platform level are the defaults for every scanned package. A repository can hold unrelated packages that report to different SonarQube servers or organizations, so an item under `packages` can set any of these fields for one package, including its own `host-url` and `token`. A package that has no item under `packages` uses the platform-level fields only.

| Field | Type | Required | Description |
| --- | --- | --- | --- |
| `plugin-path` | string | No | Platform plugin JAR, as a path relative to the repository root or an `https` URL. Overrides `path` in `Scan.toml`. Cannot be used with `plugin-version`. |
| `plugin-version` | string | No | Platform plugin version to download, or `latest`. Overrides `path` in `Scan.toml`. `latest` warns, since it may not match the pinned scan tool. |
| `properties-file` | string | No | Properties file, relative to the repository root. Overrides `sonarProjectPropertiesPath` in `Scan.toml`. |
| `host-url` | string | Yes, unless set under `packages` or in the properties file | SonarQube server URL. Overrides `sonar.host.url`. |
| `token` | string | Yes, unless set under `packages` | Token for submitting analyses. Pass it from a secret. |
| `project-key` | string | Yes, unless set under `packages` or in the properties file | Project key. Overrides `sonar.projectKey`. Since project keys must be unique, at the platform level it can be used only when one package is scanned, counted after `exclude-paths`, and not also in that package's item. |
| `project-name` | string | No | Project name. Overrides `sonar.projectName`. Like `project-key`, at the platform level it can be used only when one package is scanned, and not also in that package's item. |
| `packages` | list | No | Per-package settings. Each item has a `path`, relative to the repository root, and any of the fields above. Platform level only. |

Each setting of a package is resolved field by field: the field in the package's `packages` item, then the platform-level field, then `Scan.toml` and the properties file. The validation rules are:

- A `path` that matches no scanned package, or that is listed twice, fails the step.
- A platform-level `project-key` or `project-name` fails the step when more than one package is scanned, since it would name one project for all of them, and when the one scanned package also sets the same field in its item.
- An item that sets `host-url` must also set `token`. A token is never sent to a server other than the one it was configured with, so a package on another server does not inherit the platform-level token.
- `plugin-path` and `plugin-version` cannot both apply to one package. A `plugin-path` or `plugin-version` in an item replaces both platform-level fields for that package.

See [SonarQube](#sonarqube) for how each setting is resolved.

### Outputs

| Output | Description |
| --- | --- |
| `result` | `passed` or `failed` from the gate, `skipped` when no package was found, or `error` when the step failed before the gate, for example on invalid input or a failed scan or upload. |
| `sarif-file` | The merged, normalized SARIF file. Empty when no package was found or a scan failed. |
| `high-count`, `medium-count`, `low-count`, `total-count` | Counted findings, after the test and path filters. `total-count` is the sum of the other three and does not include `INFO` findings. `0` when no package was found, and empty when the findings were not counted, such as when a scan failed. |
| `packages-scanned` | Number of packages scanned, with each member of a workspace counted. Set once every package was scanned: `0` when no package was found, and empty when a scan failed or did not run. |
| `uploads` | JSON object with one entry per platform the findings were sent to, and an `artifact` entry when the SARIF file was saved as an artifact, such as `{"github-code-scanning": {"sarif-id": "…"}, "sonarqube": [{"package": "…", "project-key": "…", "dashboard-url": "…", "task-id": "…"}], "artifact": {"name": "…", "id": "…", "url": "…"}}`. `sonarqube` holds one item per package. A platform that was not selected or failed to upload has no entry; `{}` when nothing was uploaded. Read a value with `fromJSON(steps.scan.outputs.uploads)['github-code-scanning']['sarif-id']`. |

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

**One project per package.** Each package is a separate SonarQube analysis, so each package needs its own project key. In a repository with several packages, each package sets its key under `packages` in `platform-config`, or as `sonar.projectKey` in its own `sonar-project.properties`. The platform-level `project-key` and `project-name` fields can be used only when one package is scanned. Validation fails if a package has no project key, or if two packages on the same server resolve to the same key, since each analysis would replace the previous one.

**Workspaces.** SonarQube is not supported for workspaces yet, and a workspace found in step 2 fails the step when `sonarqube` is selected. `bal scan` runs a workspace's members one by one, each with its own `Scan.toml`, and the platform plugin runs SonarScanner once per member. The action passes one set of settings to the `bal scan` process, so every member would report to the same project key and each analysis would replace the previous one, leaving only the last member's findings in SonarQube. The action also changes only the `Scan.toml` at the root, which the members do not read. A team lists the member packages in `paths` and leaves the workspace out with `exclude-paths`. The SARIF file is not affected: `bal scan` merges the findings of every member into one report.

**Packages on different servers.** Unrelated packages in one repository can report to different SonarQube servers, or to the same server with different tokens. Each such package sets `host-url` and `token` in its `packages` item. Packages without an item, or whose item sets neither field, use the platform-level `host-url` and `token`. Each package is analysed with its own resolved server and token, so one action step covers all of them.

**Resolving settings.** `platform-config` overrides the package's `Scan.toml` and properties file, which stay the defaults so that local runs and CI share them. Paths in `platform-config` are relative to the repository root, and paths in `Scan.toml` are relative to the package. For each package:

1. **Platform plugin.** `plugin-path` or `plugin-version` from `platform-config`. Otherwise the `path` of the `sonarqube` `[[platform]]` entry in `Scan.toml`, which must be a relative path or an `https` URL. Otherwise the plugin version pinned by the action release, which the action downloads from GitHub Packages. GitHub Packages needs a token with `read:packages` even for public packages, so the job needs `packages: read` unless the plugin is set with `plugin-path` or `Scan.toml`. An absolute path fails, since it points to a developer's machine.
2. **Properties file.** `properties-file` from `platform-config`. Otherwise `sonarProjectPropertiesPath` from `Scan.toml`. Otherwise `sonar-project.properties` in the package root, if it exists. A path that is set but does not exist fails.
3. **Settings.** Each setting is taken from the package's `packages` item if set, then from the platform level of `platform-config`, and from the properties file otherwise.
4. **Validation.** The step fails if the host URL, project key or token is missing, or a URL is not a valid `https` URL. The token always comes from `platform-config`, never from a file.

**Passing settings.** The resolved settings reach SonarScanner through the `SONAR_HOST_URL`, `SONAR_TOKEN` and `SONAR_SCANNER_JSON_PARAMS` environment variables of each package's `bal scan` process, which SonarScanner gives precedence over the properties file. The scan tool reads the platform plugin only from `Scan.toml`, so for the SonarQube run the action points the package's `sonarqube` `[[platform]]` entry to the resolved plugin, keeping the rest of the file, or creates a `Scan.toml` when the package has none. The file is restored, or deleted, as soon as that run ends. So are the results file the platform plugin writes in the package directory and the `.scannerwork` directory of SonarScanner, unless they were there before the run. When `[scan] configPath` in `Ballerina.toml` points to another file in the repository, the action changes that file instead, and when it points to a URL, the action changes a local copy and points `configPath` to it. See [`Scan.toml`](#scantoml).

**Detecting the outcome.** The platform plugin does not fail `bal scan` when SonarScanner fails. The action counts a package's SonarQube run as successful only when `bal scan` succeeds and SonarScanner writes `report-task.txt`, which it does once the server has accepted the analysis. The file also gives the dashboard URL and task ID for the `uploads` output.

**SonarScanner.** The platform plugin runs the `sonar-scanner` command, so the action installs the SonarScanner CLI at the version pinned by the action release and puts it on the path of the scan process. It uses the scanner distribution for the runner's operating system, which bundles its own Java runtime, so the job needs no Java or scanner setup step. The scanner is downloaded only once per job, so the action can run more than once.

### `Scan.toml`

`bal scan` reads a package's settings from `Scan.toml` in the package root, or, when `Ballerina.toml` has a `[scan]` table, from the file its `configPath` names, relative to the package or absolute. A `configPath` that is not an existing file is treated as a URL, which the scan tool downloads and caches in the package's `target` directory, and a `[scan]` table without `configPath` is an error. A workspace has no `Scan.toml` of its own: each member reads its own.

The action changes this file during each scan, as described in [Execution flow](#execution-flow) and [SonarQube](#sonarqube): it hides the `[[platform]]` entries for the SARIF run, since the scan tool writes no SARIF report while any is active, and points the `sonarqube` entry to the resolved plugin for the SonarQube run.

**Remote `Scan.toml`.** A file at a URL cannot be changed, so the action works on a local copy:

1. When packages are found, the action downloads each remote `Scan.toml` once into its work directory, and checks that it is valid TOML.
2. For each run, it writes a changed copy of that file, without the `[[platform]]` entries for the SARIF run, or with the `sonarqube` entry pointing to the resolved plugin for the SonarQube run. It then points `configPath` in the package's `Ballerina.toml` to the copy, as an absolute path, which the scan tool reads as a local file.
3. It restores `Ballerina.toml` byte for byte as soon as the run ends, including when it fails, as it does for a local `Scan.toml`.

So a remote `Scan.toml` takes part in [Resolving settings](#sonarqube) like a local one: its `sonarqube` entry's `path` is used unless `platform-config` sets `plugin-path` or `plugin-version`, and either of those replaces it. Paths in the remote file are relative to the package, as the scan tool reads them. The scan tool reads the copy, so it does not download the file itself or cache it in `target`. Only a `configPath = "..."` line directly under the `[scan]` table is changed. Other forms, such as an inline table, fail the step.

The URL must be `https`. The scan tool loads the platform plugin JAR of every `[[platform]]` entry, and the action keeps the entries other than `sonarqube` for the SonarQube run, so a file changed in transit could make it load any JAR.

**Failures.** Whatever platforms are selected, the step fails after packages are found, before the tools are downloaded, for each package or workspace member that:

- sets `configPath` to a URL that is not `https`.
- sets `configPath` to an `https` URL that cannot be downloaded, or whose file is not valid TOML.
- sets `configPath` in a form the action cannot change, such as an inline table.
- sets `configPath` to a file that does not exist, which the scan tool would try to download as a URL.
- has a `[scan]` table without `configPath`, which the scan tool rejects.

### Gate

The gate uses both `fail-on-severity` and `max-findings`. `fail-on-severity` is evaluated first and selects the findings at or above that severity. `max-findings` is evaluated second, and the step fails when the number of selected findings is greater than it. For example, `fail-on-severity: medium` with `max-findings: 5` fails the step on six or more medium or high findings.

The defaults are `none` and `0`, so the gate is off until a team sets `fail-on-severity`, and then a single finding at or above that severity fails the step.

### Annotations and job summary

With `annotations`, each counted finding becomes an `error`, `warning` or `notice` annotation for `high`, `medium` and `low`, on its file and start line, titled with the rule ID.

GitHub shows at most 10 annotations of each level per step and 50 per job, and drops the rest without notice. So the action annotates at most the first 10 findings of each severity, fewer where the gate's error takes a slot, and when findings are left out it writes a warning, and a line in the job summary, saying how many of them were annotated. The SARIF file and the platforms it was sent to always have every finding.

With `job-summary`, the action writes the result, any failure reasons and the number of findings at each severity: high, medium and low. This keeps results visible where a team has no code scanning platform, such as a private repository without GitHub Code Security.

### Failure behaviour

Findings never fail the step unless the user asks. Problems with the setup or the scan do.

| Situation | Result |
| --- | --- |
| Invalid or unknown input, a `platform-config` that does not match the schema, or a path that does not exist | Fail before packages are searched or anything is downloaded |
| A package that reads its `Scan.toml` from a non-`https` URL, an `https` URL that cannot be downloaded, or a missing file, or has a `[scan]` table without `configPath`, with any platforms | Fail after packages are found, before the tools are downloaded |
| Missing or invalid SonarQube settings, missing or duplicate project keys, a `packages` item that matches no package or repeats a path, or a workspace with `sonarqube` | Fail after packages are found, before anything is downloaded |
| Ballerina older than the pinned scan tool needs | Fail before the scan tool is installed |
| No package found | Pass with a warning, result `skipped` |
| `bal scan` fails for a package, including when SonarQube is unreachable or rejects the analysis | Scan the remaining packages, then fail without a SARIF file |
| Upload to code scanning fails | Fail, after the SARIF file is written |
| Saving the artifact fails, such as when another scan in the run used the same `category` | Fail, after the findings are uploaded |
| Findings with `fail-on-severity: none` | Pass, with counts in the job summary |
| Findings over the gate | Fail, after the SARIF file is written and uploaded |
| `pull_request` run from a fork or Dependabot with no SonarQube token | Skip `sonarqube` with a warning, and still produce the SARIF file |
| `pull_request` run from a fork or Dependabot with `github-code-scanning` | Skip the upload with a warning, and keep the SARIF file as the `sarif-file` output, and in the artifact when `artifacts` is `true`, for a trusted follow-up upload |

### Security

A security scanning action is itself part of the supply chain.

- **Pinned dependencies.** The scan tool is pulled from Ballerina Central at the pinned version, and its integrity relies on Central. Ballerina is installed by `setup-ballerina`, at `latest` unless `ballerina-version` is set, so teams that need reproducible runs should pin it. Actions the composite action uses, such as `setup-ballerina`, `github/codeql-action/upload-sarif` and `actions/upload-artifact`, are pinned by commit SHA. The SonarQube platform plugin is downloaded at the version pinned by the action release unless the team overrides it. The SonarScanner CLI is downloaded from SonarSource at the version pinned by the action release, and its checksum is verified.
- **Least privilege.** The action needs only `contents: read`. With `github-code-scanning`, it also needs `security-events: write`, and `actions: read` on private repositories. With `sonarqube` and the default platform plugin, it also needs `packages: read`. Saving an artifact needs no extra permissions.
- **Secrets.** Credentials in `platform-config` should come from secrets, which GitHub masks in logs. The action also masks every credential field, such as `token` at the platform level and under each `packages` item, with `::add-mask::`, never prints `platform-config`, and hands each package's SonarQube token to that package's scan only, never on the command line. A `packages` item that sets its own `host-url` must set its own `token`, so a token is never sent to a server it was not configured for.
- **Input injection.** Inputs reach the scripts as environment variables, never interpolated into `run:` blocks.
- **Remote `Scan.toml`.** A `Scan.toml` that a package reads from a URL names the platform plugin JARs the scan tool loads, so the action downloads it only over `https`.
- **Fork pull requests.** Secrets are not available to `pull_request` runs from forks or Dependabot. Their `GITHUB_TOKEN` is also read-only. The action skips `sonarqube` and the code scanning upload with a warning rather than failing. `pull_request_target` runs in the base repository with its secrets and a writable token, so the action treats it as a trusted run, but does not recommend it, since it would scan code from the fork with those credentials.

### Multiple scans in a workflow

The action can run more than once in a job, for example for package groups with different thresholds. Work files are kept per run, the scan tool is pulled only once, and each SARIF file can be uploaded under its own code scanning category. Artifact names are unique within a workflow run, so each scan that saves an artifact, including each job of a matrix, needs its own `category`.

## Alternatives

SonarQube could import the SARIF file with `sonar.sarifReportPaths`, but imported findings cannot be managed in quality profiles, so the action uses the scan tool's platform plugin. Producing SARIF only, or adding a scan option to `setup-ballerina`, would either bring back most of the setup the action removes or mix toolchain setup with code analysis.

## Testing

The action repository has a test workflow that runs the action against sample Ballerina packages, to check that it scans, gates, reports and uploads as expected.

## Dependencies

- `bal scan` with SARIF output (scan tool 0.12.0 or later, from the production Central) and its SonarQube platform plugin.
- [`ballerina-platform/setup-ballerina`](https://github.com/ballerina-platform/setup-ballerina).
- For SonarQube: the scan tool's SonarQube platform plugin, published to GitHub Packages, the SonarScanner CLI pinned by the action release, and the Ballerina language plugin on the server.

## Future Work

- Hand gating, baselines, changed-file scanning, metadata and suppression to `bal scan` as the related proposals land.
- Move SARIF normalization and merging into `bal scan`. See [Alternatives](#alternatives).
- Let `bal scan` take the platform plugin path as an option and write a SARIF report while a platform is active, so the action no longer changes `Scan.toml` or `Ballerina.toml` during a scan.
- Create equivalent integrations for other CI/CD systems, such as GitLab and Bitbucket.

## References

- [`ballerina-library` `scan-ballerina` action](https://github.com/ballerina-platform/ballerina-library/tree/main/.github/actions/scan-ballerina)
- [GitHub: Uploading a SARIF file to GitHub](https://docs.github.com/en/code-security/code-scanning/integrating-with-code-scanning/uploading-a-sarif-file-to-github)
- [GitHub: SARIF support for code scanning](https://docs.github.com/en/code-security/code-scanning/integrating-with-code-scanning/sarif-support-for-code-scanning)
- [SARIF 2.1.0 specification](https://docs.oasis-open.org/sarif/sarif/v2.1.0/sarif-v2.1.0.html)
