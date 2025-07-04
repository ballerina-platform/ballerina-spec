# Improve `jms:Message` record to support a union-typed `content` field

- Authors
  - Ayesh Almeida
- Reviewed by
  - Danesh Kuruppu, Thisaru Guruge
- Created date
  - 2025-07-04
- Issue
  - TBA
- State
  - Submitted

## Summary

This proposal aims to enhance the `jms:Message` record in the Ballerina `java.jms` module by introducing a union-typed `content` field. Currently, separate records such as `TextMessage`, `BytesMessage`, and `MapMessage` are used to represent different JMS message types, each extending the base `jms:Message` record and including a type-specific `content` field. This proposal suggests unifying these into a single `Message` record that contains a polymorphic `content` field capable of holding `string`, `byte[]`, or `map<anydata>`. This change leverages Ballerina's union type system to simplify the API and improve developer ergonomics.

## Goals

* Consolidate multiple message types into a single, unified `jms:Message` record.
* Improve the developer experience when consuming or processing JMS messages.

## Motivation

The current JMS message model in Ballerina mirrors the Java JMS API by defining separate message record types for each message variant:

```ballerina
public type TextMessage record {|
    *Message;
    string content;
|};

public type BytesMessage record {|
    *Message;
    byte[] content;
|};

public type MapMessage record {|
    *Message;
    map<anydata> content;
|};
```

Each of these records includes all metadata fields from the base `jms:Message` using record inclusion. While this approach is structurally sound, it results in API fragmentation. Consumers of JMS messages are forced to perform type discrimination manually or rely on utility functions to access the message payload.

Ballerina supports union types natively, which allows us to represent multiple possible types in a single field in a type-safe way. By redesigning `jms:Message` to include a single union-typed `content` field, we can simplify the message model and make it more idiomatic for Ballerina users.

## Description

### Current Structure

```ballerina
public type Message record {|
    string messageId?;
    map<string> properties?;
    // other fields...
|};

public type TextMessage record {|
    *Message;
    string content;
|};

public type BytesMessage record {|
    *Message;
    byte[] content;
|};

public type MapMessage record {|
    *Message;
    map<anydata> content;
|};
```

### Proposed Change

Merge all specific message types into a single `Message` record with a union-typed `content` field:

```ballerina
public type Message record {|
    // other fields
    string|byte[]|map<anydata> content;
|};
```

The module logic will populate the `content` field based on the underlying JMS message type:

* `TextMessage` → `string`
* `BytesMessage` → `byte[]`
* `MapMessage` → `map<anydata>`

### Example Usage

```ballerina
jms:Message msg = jms:receive(...);

// to retrieve the string content
string content = check msg.content.ensureType();
```

This pattern is more concise and Ballerina-idiomatic, and it eliminates the need for multiple message record types or type assertions.

### Compatibility

This change will require deprecating or removing the existing `TextMessage`, `BytesMessage`, and `MapMessage` types.

## Testing

* **Unit Tests**:

  * Validate correct deserialization of JMS message types into the unified `content` field.

* **Integration Tests**:

  * Ensure interoperability with standard JMS brokers for all supported message types.

* **Negative Tests**:

  * Handle and test unsupported or malformed message payloads gracefully.
