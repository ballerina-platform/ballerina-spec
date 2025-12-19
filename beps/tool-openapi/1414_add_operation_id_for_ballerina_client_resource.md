# 1414: Proposal: Bring Operation ID Support to Ballerina Client Resource Function Generation

- Authors - @lnash94
- Reviewed by - @daneshk, @TharmiganK
- Created date - 2025/12/18
- Updated date - 2025/12/18
- Issue - https://github.com/ballerina-platform/ballerina-spec/issues/1414
- State - -

## Summary

This proposal introduces Operation ID support to the BI and MI connector space by promoting the OpenAPI operationId as first-class metadata in Ballerina resource functions. This enhancement improves low-code usability in BI and enables reliable conversion from Ballerina connectors to MI connectors.

## Motivation

Currently, most Ballerina connectors are generated with resource functions derived from protocol-level definitions (OpenAPI). While technically correct, these resource names are often not human-friendly and creating challenges for:

- Low-code user experience in BI
- Connector operation discoverability and usability
- Ballerina → MI connector conversion

OpenAPI already provides operationId as a unique, descriptive identifier, but it is not leveraged effectively across the connector lifecycle.

### Problem Statement

1\. Resource function names in Ballerina connectors are:
- Protocol-driven
- Not descriptive for low-code users

Example resource function:
```ballerina
resource isolated function post api/'3/issue(IssueUpdateDetails payload, map<string|string[]> headers = {}, *CreateIssueQueries queries) returns CreatedIssue|error {
        ...
        return self.clientEp->post(resourcePath, request, headers);
    }
```

2\. In BI:
- Operations appear unclear and not intuitive
- Users struggle to understand connector capabilities

3\. In MI connector conversion:
- MI connectors require explicit, human-readable operation names
- Mapping Ballerina resource functions to MI operations is challenging

There is no structured metadata to reliably represent an operation’s intent.

## Goals

- Enable clear and reliable operation identification in BI and MI by embedding OpenAPI operation metadata into generated Ballerina resource functions.

## Non-Goals
- Annotation fields such as examples and other metadata are excluded to keep the implementation focused, as they are out of scope for the current use case beyond `operationId`.

## Description

An existing implementation[1] already provides a resource-level annotation[2] mechanism to capture OpenAPI metadata (e.g., operationId, summary) in Ballerina resource methods.
This capability was originally designed to support the Ballerina code → OpenAPI definition generation flow, allowing OpenAPI metadata to be preserved when exporting a definition from Ballerina services.

However, this support is not available when generating Ballerina client code from an OpenAPI definition (OAS → Ballerina).

### Solution

With this proposal, the same resource-level annotation[2] mechanism with operation id should be enabled and extended for the client code generation flow.
Annotation generation will be enabled through a CLI option of the OpenAPI command.

1. OpenAPI definition example:
```yaml
...
/api/3/issue:
    post:
      operationId: createIssue
      parameters:
      - name: updateHistory
        in: query
        required: false
        style: form
        explode: true
        schema:
          type: boolean
          default: false
      requestBody:
        content:
          application/json:
            schema:
              $ref: '#/components/schemas/IssueUpdateDetails'
        required: true
      responses:
        "201":
          description: Returned if the request is successful
          content:
            application/json:
              schema:
                $ref: '#/components/schemas/CreatedIssue'
...
```

2. Expected generated ballerina client code

```ballerina
//usage
...
    @openapi:ResourceInfo {
        operationId: "createIssue"
    }
    resource isolated function post api/'3/issue(IssueUpdateDetails payload, map<string|string[]> headers = {}, *CreateIssueQueries queries) returns CreatedIssue|error {
        ...
        return self.clientEp->post(resourcePath, request, headers);
    }
}
...
```

## Testing
- Add unit test and integration test cases to cover the new functionality in the OpenAPI to Ballerina code generator module.


## References

[1] [Ballerina to OpenAPI metadata annotation support](https://github.com/ballerina-platform/openapi-tools/pull/1731#:~:text=As%20the%20first%20phase%2C%20we%20only%20support%20the%20below%20attribute%20metadata%20in%20suggested%20annotation)

[2] [OpenAPI ResourceInfo annotation definition](https://github.com/ballerina-platform/openapi-tools/blob/39737116ea05470dc6637af4b3f1a3b6cff021d7/module-ballerina-openapi/annotation.bal#L74)