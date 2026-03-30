# Improve `jms:Message` record to be compliant with JMS specification

- Authors
  - Ayesh Almeida
- Reviewed by
  - Danesh Kuruppu, Thisaru Guruge
- Created date
  - 2025-07-04
- Issue
  - [#1372](https://github.com/ballerina-platform/ballerina-spec/issues/1372)
- State
  - Submitted

## Summary

This proposal aims to improve the `jms:Message` record in the Ballerina `java.jms` module by unifying the different JMS message types—`TextMessage`, `BytesMessage`, and `MapMessage`—into a single record with a polymorphic `content` field. By leveraging Ballerina’s union type system, the `content` field can represent either a `string`, `byte[]`, or a `map<ValueType>`, where `ValueType` includes only types permitted by the JMS specification: `boolean`, `int`, `byte`, `float`, `string`, and `byte[]`. Similarly, the `properties` field is redefined as `map<PropertyType>`, restricting values to `boolean`, `int`, `byte`, `float`, or `string`, in alignment with JMS constraints. This change simplifies the API, reduces the need for type-specific message records, and provides a more idiomatic and type-safe developer experience when working with JMS in Ballerina.

## Goals

* Consolidate multiple message types into a single, unified `jms:Message` record.
* Make the message content and metadata type-safe and aligned with JMS spec.
* Improve the developer experience when consuming or processing JMS messages.

## Motivation

The current design of the Ballerina JMS module defines separate record types to represent different JMS message types—such as `TextMessage`, `BytesMessage`, and `MapMessage`—each extending a common `Message` base. While this structure closely follows the Java JMS API, it introduces fragmentation in the Ballerina API, requiring developers to perform type discrimination and manage multiple record types manually. Furthermore, the current `MapMessage` implementation allows a `map<anydata>` for its content, which is **not compliant** with the JMS specification. According to JMS, only a restricted set of value types—`boolean`, `int`, `byte`, `float`, `string`, and `byte[]`—are allowed in a map message. 

Similarly, the `properties` field in the `jms:Message` record currently uses `map<anydata>`, which is also overly permissive. JMS message properties must only contain values of primitive types (`boolean`, `int`, `byte`, `float`, `string`). These inconsistencies could lead to runtime issues or incompatibilities when interacting with standard JMS brokers. Addressing these issues by unifying the message representation and constraining value types will improve correctness, type safety, and the overall developer experience in Ballerina.

## Description

### **New Unified `jms:Message` Record**

```ballerina
public type PropertyType boolean|int|byte|float|string;
public type ValueType PropertyType|byte[];

public type Message record {|
    string messageId?;
    map<PropertyType> properties?;
    string|byte[]|map<ValueType> content;
    // other metadata fields like timestamp, correlationId, etc.
|};
```

### **Mapping from JMS Types**

| JMS Type       | `content` Type   |
| -------------- | -----------------|
| `TextMessage`  | `string`         |
| `BytesMessage` | `byte[]`         |
| `MapMessage`   | `map<ValueType>` |

### **Notes:**

* The `map` key is always `string`, as per JMS.
* Both `content` and `properties` use constrained value types that align with the JMS specification.
* `JMSMapValue` includes `byte[]`, but `JMSPropertyValue` does **not**.

### Example Usage

```ballerina
jms:Message msg = jms:receive(...);

// to retrieve the string content
string content = check msg.content.ensureType();
```

This pattern is more concise and Ballerina-idiomatic, and it eliminates the need for multiple message record types or type assertions.

### Compatibility

* The distinct types `TextMessage`, `BytesMessage`, and `MapMessage` will be **removed or deprecated**, as their functionality is now unified within the enhanced `jms:Message` record.
* The type of the `properties` field in the `jms:Message` record will be changed from `map<anydata>` to `map<PropertyType>`, where `PropertyType` is a constrained union type (`boolean|int|byte|float|string`) to comply with the JMS specification.

## Testing

* **Unit Tests**:

  * Validate correct deserialization of JMS message types into the unified `content` field.

* **Integration Tests**:

  * Ensure interoperability with standard JMS brokers for all supported message types.

* **Negative Tests**:

  * Handle and test unsupported or malformed message payloads gracefully.
