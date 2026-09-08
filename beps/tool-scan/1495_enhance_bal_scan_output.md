# Enhance `bal scan` Output with Richer Rule Metadata for the SARIF and Ballerina JSON Formats

- Authors - Charana Manawathilake
- Reviewed by - Tharmigan Krishnananthalingam
- Created date - 2026-09-04
- Updated date - 2026-09-07
- Issue - [1495](https://github.com/ballerina-platform/ballerina-spec/issues/1495)
- State - Submitted

## Summary

This proposal enhances the `bal scan` output by enriching the rule metadata reported in both the SARIF and Ballerina JSON formats.

The current output carries only basic rule information. This proposal adds richer metadata — such as a full description, security severity, default configuration level, precision, and CWE/OWASP coverage tags — to both output formats, to provide more useful security findings and improve interoperability with existing code-reporting and security-analysis tools.

The design specifies, field by field, how this enriched rule metadata and the scan-result information are represented in each format, so that the two outputs stay consistent while each retains its format-specific characteristics.

## Motivation

`bal scan` supports SARIF and Ballerina JSON output formats for reporting static-analysis findings. The goal of this proposal is to make these outputs directly useful in external scan platforms such as SonarQube and CodeQL.

The current output provides only basic information such as the rule identifier, rule description, rule kind, and violation location. Several fields that these platforms rely on to present rich security findings — a detailed description, security severity, default configuration level, precision, and CWE/OWASP coverage — are missing from the output. In particular, important SARIF fields defined by the SARIF schema are not currently populated.

This proposal enhances both outputs so consumers can gauge the severity, reliability, and standards coverage of a finding directly from the tool output, and explains how the currently missing fields can be represented by adjusting the output JSON model. It does not attempt to match any single platform's model; instead it adds the fields needed to support a range of platforms.

## Design

### Overview

The enhancement adds richer rule metadata to the `bal scan` output in both the SARIF and Ballerina JSON formats. The design specifies how each new and existing field is represented in each format, so that the enriched information is delivered consistently across both outputs while each format keeps its own field naming and structure. The tables below cover both the existing fields and the newly added metadata for each format.

### Rule Metadata Fields

| Ballerina JSON (`rule`) | SARIF rule | Description | Example |
|---|---|---|---|
| `id` | `id` | Unique rule identifier. | `ballerina/file:2` |
| `numericId` | *(derived)* | Numeric portion of the rule identifier. Parsed from the numeric suffix of the rule `id`; not a distinct SARIF field. | `2` |
| `name` | `name` | Human-readable rule name. | `File function calls should not be vulnerable to path injection attacks` |
| `description` | `shortDescription.text` | Short, one-line description of the rule. | `Path injections occur when an application constructs a file path using untrusted data without first validating the path.` |
| `fullDescription` | `fullDescription.text` | Detailed description of what the rule detects. | `Path injections occur when an application constructs a file path using untrusted data ... where the user typically wouldn't have access.` |
| `helpUri` | `helpUri` | Link to the rule's documentation. | `https://ballerina.io/learn/scan-rules/#file-function-calls-should-not-be-vulnerable-to-path-injection-attacks` |
| `severity` | `defaultConfiguration.level` | Severity of the finding. One of: `BLOCKER`, `HIGH`, `MEDIUM`, `LOW`, `INFO`, mapped to the SARIF `level` set (`error`, `error`, `warning`, `note`, `none` respectively). The mapping is many-to-one, so the SARIF → Ballerina direction is not exact. | `MEDIUM` (Ballerina) / `warning` (SARIF) |
| `enabled` | `defaultConfiguration.enabled` | Whether the rule is enabled by default. | `true` |
| `tags` | `properties.tags` | Classification tags. In SARIF, this also carries CWE/OWASP coverage via `external/...` entries; in Ballerina JSON that coverage is moved to `standards`, so `tags` holds only general tags. | `["security"]` (Ballerina) / `["security", "external/cwe/cwe-22", "external/owasp/owasp-a01-2025"]` (SARIF) |
| `standards` | *(via `properties.tags`)* | Structured CWE/OWASP coverage as numbers. `cwe` is a list of weakness numbers; `owasp` is a list of `{ year, categories }` entries where `categories` are numbers. SARIF represents the same coverage through the `external/...` entries in `properties.tags`. | `{"cwe": [22], "owasp": [{"year": 2025, "categories": [1]}]}` |
| `standards.cwe` | *(from `external/cwe/*` tags)* | CWE weakness numbers the rule maps to. | `[22]` |
| `standards.owasp` | *(from `external/owasp/*` tags)* | OWASP categories grouped by edition year. | `[{"year": 2025, "categories": [1]}]` |
| `precision` | `properties.precision` | Confidence in the finding. One of: `low`, `medium`, `high`. | `medium` |
| `severityScore` | `properties.security-severity` | CVSS-style security severity score (0.0–10.0), represented as a string. | `"7.5"` |
| `ruleKind` | `properties.ruleKind` | Category of the rule. One of: `VULNERABILITY`, `CODE_SMELL`. No native SARIF field; carried as a custom entry in the SARIF `properties` bag (the schema's extension point). | `VULNERABILITY` |
| `remediation` | `properties.remediation` | Remediation cost model for the rule. `func` selects the cost function (`constant/issue`, `linear`, or `linear_offset`). No native SARIF field; carried in the SARIF `properties` bag. | `{"func": "Constant/Issue", "constantCost": "5min"}` |

> The CWE and OWASP coverage carried in the SARIF `external/...` tags is derived from the Ballerina `standards` field. SARIF also supports representing this coverage through its `taxonomies` and `relationships` constructs, which model CWE/OWASP as formal taxonomies referenced by each rule. The `external/...` tag convention is used here for simplicity and broad tool compatibility.

### Result / Location Fields

| Ballerina JSON | SARIF result | Description | Example |
|---|---|---|---|
| `rule.id` | `ruleId` | Identifier of the rule that produced the finding. | `ballerina/file:2` |
| *(embedded in result)* | `ruleIndex` | Reference to the rule definition. SARIF references the rule by index into the `rules` array; Ballerina JSON embeds the full rule within the result itself. | `0` (SARIF only) |
| `rule.severity` | `level` | Severity of this finding. | `MEDIUM` (Ballerina) / `warning` (SARIF) |
| `rule.description` | `message.text` | Message describing the finding. | `Path injections occur when an application constructs a file path using untrusted data without first validating the path.` |
| `location.filePath` | `locations[].physicalLocation.artifactLocation.uri` | File in which the finding occurs. SARIF uses the relative `uri`. | `file_io.bal` |
| `location.startLine` | `...region.startLine` | Line where the finding starts. Ballerina is zero-based, SARIF one-based (Ballerina = SARIF − 1). | `40` (Ballerina) / `41` (SARIF) |
| `location.endLine` | `...region.endLine` | Line where the finding ends. Ballerina = SARIF − 1. | `40` (Ballerina) / `41` (SARIF) |
| `location.startColumn` | `...region.startColumn` | Column where the finding starts. Ballerina = SARIF − 1. | `4` (Ballerina) / `5` (SARIF) |
| `location.endColumn` | `...region.endColumn` | Column where the finding ends. Ballerina = SARIF − 1. | `18` (Ballerina) / `19` (SARIF) |
| `location.startOffset` | `...region.charOffset` | Character offset of the finding's start from the beginning of the file. | `1688` |
| `location.length` | `...region.charLength` | Length of the finding in characters. | `14` |
| `location.snippet` | `...region.snippet.text` | The source text at the finding location. Ballerina JSON uses a plain string; SARIF wraps it in a `snippet.text` object. | `let count = 0;` |
| *(none)* | `partialFingerprints.primaryLocationLineHash` | Stable fingerprint used to track a finding across runs. SARIF-only. | `8b5fadf7b30060f688c7e7a10a39b8a7:1` |
| `source` | *(none)* | Origin of the rule (e.g. built-in vs external). Ballerina-only. | `BUILT_IN` |
| `fileName`, `filePath` | *(none)* | Absolute file name and path of the analyzed file. Ballerina-only; SARIF carries only the relative `uri`. | `<path>\file_io.bal` |

### Enhanced Output Example

The proposed SARIF rule representation is:

```json
{
  "id": "ballerina/file:2",
  "name": "File function calls should not be vulnerable to path injection attacks",
  "helpUri": "https://ballerina.io/learn/scan-rules/#file-function-calls-should-not-be-vulnerable-to-path-injection-attacks",
  "shortDescription": {
    "text": "Path injections occur when an application constructs a file path using untrusted data without first validating the path."
  },
  "fullDescription": {
    "text": "Path injections occur when an application constructs a file path using untrusted data without first validating the path. A malicious user can inject specially crafted values, like \"../\", to alter the intended path. This manipulation may lead the path to resolve to a location within the filesystem where the user typically wouldn't have access."
  },
  "defaultConfiguration": {
    "level": "warning",
    "enabled": true
  },
  "properties": {
    "tags": [
      "security",
      "external/cwe/cwe-22",
      "external/owasp/owasp-a01-2025"
    ],
    "precision": "medium",
    "security-severity": "7.5",
    "ruleKind": "VULNERABILITY",
    "remediation": {
      "func": "Constant/Issue",
      "constantCost": "5min"
    }
  }
}
```

The corresponding SARIF result representation is:

```json
{
  "ruleId": "ballerina/file:2",
  "ruleIndex": 0,
  "level": "warning",
  "message": {
    "text": "Path injections occur when an application constructs a file path using untrusted data without first validating the path."
  },
  "locations": [
    {
      "physicalLocation": {
        "artifactLocation": {
          "uri": "file_io.bal"
        },
        "region": {
          "startLine": 41,
          "startColumn": 5,
          "endLine": 41,
          "endColumn": 19,
          "charOffset": 1688,
          "charLength": 14,
          "snippet": {
            "text": "let count = 0;"
          }
        }
      }
    }
  ],
  "partialFingerprints": {
    "primaryLocationLineHash": "8b5fadf7b30060f688c7e7a10a39b8a7:1"
  }
}
```

The relevant Ballerina JSON representation is:

```json
{
  "location": {
    "filePath": "file_io.bal",
    "startLine": 40,
    "endLine": 40,
    "startColumn": 4,
    "endColumn": 18,
    "startOffset": 1688,
    "length": 14,
    "snippet": "let count = 0;"
  },
  "rule": {
    "id": "ballerina/file:2",
    "numericId": 2,
    "name": "File function calls should not be vulnerable to path injection attacks",
    "description": "Path injections occur when an application constructs a file path using untrusted data without first validating the path.",
    "fullDescription": "Path injections occur when an application constructs a file path using untrusted data without first validating the path. A malicious user can inject specially crafted values, like \"../\", to alter the intended path. This manipulation may lead the path to resolve to a location within the filesystem where the user typically wouldn't have access.",
    "helpUri": "https://ballerina.io/learn/scan-rules/#file-function-calls-should-not-be-vulnerable-to-path-injection-attacks",
    "severity": "MEDIUM",
    "enabled": true,
    "tags": [
      "security"
    ],
    "standards": {
      "cwe": [22],
      "owasp": [
        { "year": 2025, "categories": [1] }
      ]
    },
    "precision": "medium",
    "severityScore": "7.5",
    "ruleKind": "VULNERABILITY",
    "remediation": {
      "func": "Constant/Issue",
      "constantCost": "5min"
    }
  },
  "source": "BUILT_IN",
  "fileName": "<name>\\file_io.bal",
  "filePath": "<path>\\file_io.bal"
}
```

> Note: In the example above, the Ballerina JSON line/column values (`40`, `4`, `18`) are each one less than the SARIF values (`41`, `5`, `19`) because of the zero-based (Ballerina) vs one-based (SARIF) indexing convention. The offsets (`1688`, `14`) are shared across both formats.

## Testing

Testing covers both the tool's core rules and the rule extensions contributed by the standard libraries that depend on this output:

- Verify the enhanced SARIF and Ballerina JSON output for the tool's core library rules — confirming that every new and existing field (full description, security severity, default configuration level, precision, CWE/OWASP tags, and `ruleKind`) is populated and represented correctly in each format.
- Verify the output for the rules contributed by the dependent standard libraries — `http`, `file`, `log`, `jwt`, `crypto`, `os`, `io` and `email` — to confirm their rule extensions produce the enriched metadata correctly and that the changes do not break their existing rule reporting.
- Confirm cross-compatibility with existing Ballerina JSON consumers, ensuring existing fields are preserved and the format remains backward compatible.

## Dependencies

The standard libraries such as `http`, `file`, `log`, `jwt`, `crypto`, `os`, `io` and `email` depend on this output for their rule extensions. These changes must be implemented in a way that does not break those libraries, and the dependent libraries need to be updated and validated against the enhanced output.

## Future Improvements

Due to the current architecture of the Ballerina format, the full rule detail is repeated with every violation occurrence, so the same rule metadata is duplicated across results. Changing this would require a major release across all the dependent libraries, so we will stick to this format for the moment. In the future, a JSON referencing method — similar to how SARIF defines rules once and references them from each result — can be adopted to remove the per-result duplication.
