# Application specific content type support in Ballerina WebSubHub

- Authors
  - Ayesh Almeida
- Reviewed by
  - Shafreen Anfar, Danesh Kuruppu, Thisaru Guruge
- Created date
  - 2025-06-02
- Issue
  - [1358](https://github.com/ballerina-platform/ballerina-spec/issues/1358)
- State
  - Submitted

## Summary

This proposal introduces support for application-specific content types in the Ballerina `websubhub` library, enabling more flexible content 
handling during WebSub content distribution. The [WebSub specification](https://www.w3.org/TR/websub/) allows a `topic` to declare any 
`Content-Type` for its content and does not restrict it to common MIME types such as `application/json`, `application/xml`, or `text/plain`.

This enhancement focuses on supporting custom media types under the `application/*` top-level MIME type. These include structured and 
vendor-specific types such as `application/secevent+jwt`, `application/vnd.example+json`, and others. By treating such types as first-class 
citizens, Ballerina will be able to interoperate more effectively in real-world WebSub ecosystems that rely on non-standard content types.

## Goals

* Enable handling and distribution of custom `Content-Type` values (under `application/*`) in the WebSubHub message flow.

## Motivation

In the WebSub model, content updates related to a `topic` are distributed from the `hub` to its `subscribers`. The specification allows for 
flexible use of MIME types to describe the nature of the content associated with a topic. Real-world WebSub implementations often use 
application-specific content types for domain-specific data formats (e.g., JWT-secured payloads, vendor-specific schemas).

To accommodate this, the Ballerina `websubhub` implementation must go beyond just standard MIME types and correctly support content delivery 
for any `application/*` type — ensuring both correct processing and distribution.

## Description

To enable proper support for custom content types, enhancements are required in two main areas of the WebSubHub flow:

### 1. Receiving Content Updates from Publishers

The `hub` must accept content updates with both standard and custom MIME types. The content type will guide how the message payload is interpreted and stored for subsequent distribution.

* Standard types will continue to be mapped as follows:

  | Content-Type                        | Ballerina Type |
  | ----------------------------------- | -------------- |
  | `application/json`                  | `json`         |
  | `application/xml`                   | `xml`          |
  | `text/plain`                        | `string`       |
  | `application/octet-stream`          | `byte[]`       |
  | `application/x-www-form-urlencoded` | `map<string>`  |

* For all other types under `application/*` (e.g., `application/secevent+jwt`, `application/x.custom-type`), the payload will be treated as `byte[]`.

### 2. Distributing Content to Subscribers

When relaying the content to subscribers, the `hub` must preserve the original `Content-Type` (including custom ones). The payload will be passed along as `byte[]` to ensure fidelity, allowing the subscriber to decode and process it appropriately based on the content type.

This approach maintains transparency and flexibility in message processing without requiring schema-level parsing at the hub.

## Dependencies

* This support must also be incorporated into the Ballerina `websub` subscriber service to ensure seamless end-to-end support for custom content types across the entire publish-subscribe workflow.

## Testing

* Unit tests will be added to cover various standard and custom `Content-Type` values and to verify correct content mapping and distribution behavior.
