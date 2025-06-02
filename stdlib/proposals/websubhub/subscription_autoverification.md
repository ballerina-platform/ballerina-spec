# Custom Content Type Support in Ballerina WebSubHub

- Authors
  - Ayesh Almeida
- Reviewed by
  - Shafreen Anfar, Danesh Kuruppu, Thisaru Guruge
- Created date
  - 2025-06-02
- Issue
  - [1336](https://github.com/ballerina-platform/ballerina-spec/issues/1336)
- State
  - Submitted

## Summary

This proposal introduces an enhancement to the Ballerina `websubhub` library to support custom content types in the content distribution 
flow. According to the WebSub specification, a topic can define a `Content-Type` for its content, and this is not limited to standard MIME 
types such as `application/json`, `application/xml`, or `text/plain`. This proposal specifically targets support for custom content types 
that fall under the `application/*` media type, including vendor-specific and structured syntax suffix types like `application/vnd.example
+json` or `application/secevent+jwt`. Providing first-class support for such types is essential for broader interoperability and 
specification compliance.

## Goals

* Support custom `Content-Type` values in the WebSub content distribution flow.

## Motivation

In WebSub, content distribution refers to the process by which a `hub` distributes content updates about a `topic` to its `subscribers`. The specification allows a topic to define any `Content-Type` for its content, without restricting it to well-known standard types. Therefore, the Ballerina `websubhub` implementation must be able to handle and distribute content with arbitrary custom MIME types — in addition to standard ones — to support broader and more flexible use cases.

## Description

To support custom content types in the WebSub flow, two key processing paths need to be enhanced:

1. **Publisher to Hub Notification**:
   When the publisher sends a content update to the `hub`, the `hub` must accept content with both standard and custom content types.

2. **Hub to Subscriber Distribution**:
   When the `hub` distributes the content to a `subscriber`, it must be able to deliver the content using the same `Content-Type` originally received (including custom types).

The scope of this proposal is limited to content types under the `application/*` top-level media type. This includes both standard types (e.g., `application/json`) and custom types such as `application/vnd.example+json` or `application/x.custom-format`. 

### Handling Custom Content Types When Receiving Content Updates at the Hub

For standard content types, the content should be mapped to corresponding Ballerina types as shown below:

| Content-Type                        | Mapped Ballerina Type |
| ----------------------------------- | --------------------- |
| `application/json`                  | `json`                |
| `application/xml`                   | `xml`                 |
| `text/plain`                        | `string`              |
| `application/octet-stream`          | `byte[]`              |
| `application/x-www-form-urlencoded` | `map<string>`         |

For custom content types with the structure `application/*` (e.g., `application/secevent+jwt`), the content will be mapped to a Ballerina `byte[]`.

### Content Distribution to Subscribers

When distributing content with custom content types, the same MIME type must be preserved, and the payload should be sent as a `byte[]`.

This ensures that subscribers can handle the content using appropriate logic for their domain-specific content type.

## Dependencies

* This support must also be incorporated into the Ballerina `websub` subscriber service to ensure seamless end-to-end support for custom content types across the entire publish-subscribe workflow.

## Testing

* Unit tests will be added to cover various standard and custom `Content-Type` values and to verify correct content mapping and distribution behavior.
