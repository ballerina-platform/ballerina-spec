# Introduce `onError` method for `jms:Service`

- Authors
  - Ayesh Almeida
- Reviewed by
  - Danesh Kuruppu, Thisaru Guruge
- Created date
  - 2025-07-04
- Issue
  - [#1371](https://github.com/ballerina-platform/ballerina-spec/issues/1371)
- State
  - Submitted

## Summary

Introduce an `onError` method for the `jms:Service` in Ballerina to handle runtime errors that may occur during message reception or while dispatching messages to the `onMessage` method. This will improve the observability and fault tolerance of JMS-based service implementations by enabling users to define custom error-handling logic.

## Goals

* Provide a standard mechanism to notify the user about message reception and dispatch failures in a `jms:Service`.
* Allow developers to implement graceful error handling and logging strategies.
* Make JMS listener-service based message consumption model consistent with other message broker connectors.

## Motivation

In the current `jms:Service` model, errors occurring during message retrieval (e.g., deserialization failures, connection-level errors) and message dispatching error (e.g., data-binding errors ) are not explicitly handled by the service. This limits the developer’s ability to respond to such errors in a predictable manner.

Other Ballerina service models built for message brokers, such as `kafka:Service` and `rabbitmq:Service`, already support an `onError` method to notify runtime failures during message receiving or dispatching. Introducing a similar mechanism in `jms:Service` ensures a consistent experience across message-broker-based services and enables developers to build more reliable and fault-tolerant systems.

## Description

Add support for an optional `onError` remote method in `jms:Service`, which will be invoked by the runtime when:

* An error occurs while receiving a message from the JMS broker.
* An error occurs while dispatching the message to the `onMessage` method (e.g., data-binding errors, runtime exceptions).

### Syntax

```ballerina
listener jms:Listener jmsListener = check new(...);

service "consumer" on jms:Listener {

    remote function onMessage(jms:Message message) returns error? {
        // message handling logic
    }

    remote function onError(jms:Error err) returns error? {
        // error handling logic
    }
}
```

### Semantics
.
* The `onError` method is **optional**. If not implemented, the runtime will log the error.

## Testing

The following scenarios will be covered under the test suite:

1. Service with and without `onError` method.
