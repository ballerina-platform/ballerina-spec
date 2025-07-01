# Message Stores and Store Listener in Ballerina

- Authors
  - Tharmigan Krishnananthalingam
- Reviewed by
  - Shafreen Anfar, Danesh Kuruppu
- Created date
  - 2025-06-20
- Updated date
  - 2025-06-27
- Issue
  - [#1361](https://github.com/ballerina-platform/ballerina-spec/issues/1361)
- State
  - Submitted

## Summary

This proposal introduces a new Ballerina package(`ballerina/msgstore`) that provides a standardized interface for message stores and a robust message store listener. This package will enable Ballerina applications to interact with various message storage systems consistently, store messages, and listen for changes, simplifying development and enhancing flexibility.

## Motivation

Currently, Ballerina developers leverage diverse message brokers or database clients for message persistence and consumption. However, these systems expose distinct APIs, leading to fragmentation and complexity when switching between different message stores or utilizing multiple stores within a single application.

A common interface for message stores and a standardized message store listener offer significant advantages:

- **Consistency:** Developers will benefit from a unified API for storing and consuming messages, regardless of the underlying message store technology. This reduces the learning curve and promotes code reusability.
- **Flexibility:** The proposed approach allows for seamless switching between different message stores or the simultaneous use of multiple stores in the same application, without requiring extensive code modifications.
- **Advanced Features:** The standardized interface facilitates the consistent implementation of critical messaging patterns such as retry mechanisms, dead-letter queues (DLQs), and robust message processing failure handling across various message store implementations.
- **Extensibility:** Each message broker and database library can provide its own implementation of this common message store interface, fostering a rich ecosystem of compatible integrations. This eliminates the need for individual developers to reinvent the wheel for basic message store interactions.

This proposal addresses the current lack of a unified message persistence and consumption mechanism in Ballerina, thereby improving developer experience, promoting best practices in message-driven architectures, and enabling more resilient applications.

## Goals

- Introduce a common interface for message stores in Ballerina, providing a standardized contract for message persistence and retrieval.
- Introduce built-in message store implementations, such as an in-memory store and a RabbitMQ store, to provide immediate utility and examples for custom implementations.
- Introduce a message store listener that can poll and process messages from any compliant message store.
- Implement advanced failure handling mechanisms within the store listener, including configurable retry mechanisms, and dead-letter queue(DLQ) support.

## Design

This proposal introduces a new Ballerina package, `ballerina/msgstore`, which will define the message store interface and provide a robust implementation of a message store listener.

### Message Store Interface

The `MessageStore` interface will define the following core methods:

- `store`: This method will be used to persist a message in the message store. It accepts an `anydata` typed value as the message content. It returns an `error` if the message could not be stored, or `()` upon successful storage.
- `retrieve`: This method will be used to retrieve the top message from the message store without removing it. It returns a `Message` record if a message is available, a `()` if the store is empty, or an `error` if there was an issue retrieving the message. The `Message` record encapsulates the message content and a unique identifier.
- `acknowledge`: This method will be used to acknowledge the top message previously retrieved from the message store. It takes the unique string identifier of the message (matching the id from the `Message` record) and a boolean indicating whether the message was processed successfully. It returns an `error` if the acknowledgment fails, or `()` upon successful processing of the acknowledgment.

The proposed interface and associated types are as follows:

```ballerina
# Represents the message content with a unique consumer ID.
#
# + id - The unique identifier for the consumer
# + content - The actual message content
public type Message record {|
    string id;
    anydata content;
|};

# Represents a message store interface for storing and retrieving messages.
public type MessageStore isolated client object {

    # Stores a message in the message store.
    #
    # + message - The message to be stored
    # + return - An error if the message could not be stored, or `()`
    isolated remote function store(anydata message) returns error?;

    # Retrieves the top message from the message store without removing it.
    #
    # + return - The retrieved message, or () if the store is empty, or an error if an error occurs
    isolated remote function retrieve() returns Message|error?;

    # Acknowledges the top message retrieved from the message store.
    #
    # + id - The unique identifier of the message to acknowledge. This should be the same as the `id`
    # of the message retrieved from the store.
    # + success - Indicates whether the message was processed successfully or not
    # + return - An error if the acknowledgment could not be processed, or `()`
    isolated remote function acknowledge(string id, boolean success = true) returns error?;
};
```

### Message Store Listener

The `Listener` object will be responsible for orchestrating message consumption from a `MessageStore`. It must be initialized with an instance of a `MessageStore`:

```ballerina
msgstore:MessageStore msgStore = new msgstore:InMemoryMessageStore();

listener msgstore:Listener msgStoreListener = new(msgStore);
```

The listener can be configured with the following options:

```ballerina
# Represents the message store listener configuration,
#
# + pollingInterval - The interval in seconds at which the listener polls for new messages. This should be a positive decimal value
# + maxRetries - The maximum number of retries for processing a message. This should be a positive integer value
# + retryInterval - The interval in seconds between retries for processing a message. This should be a positive decimal value
# + dropMessageAfterMaxRetries - If true, the message will be dropped after the maximum number of retries is reached
# + deadLetterStore - An optional message store to store messages that could not be processed after the maximum number of retries.
# When set, `dropMessageAfterMaxRetries` option will be ignored
public type ListenerConfiguration record {|
    decimal pollingInterval = 1;
    int maxRetries = 3;
    decimal retryInterval = 1;
    boolean dropMessageAfterMaxRetries = false;
    MessageStore deadLetterStore?;
|};
```

#### The Message Store Service

A message store service, defined by the `msgstore:Service` type, can be attached to the `msgstore:Listener` to handle messages retrieved from the message store. This service will expose a single remote method, `onMessage`, which will be invoked upon message reception.

The service type definition is as follows:

```ballerina
# This service object defines the contract for processing messages from a message store.
public type Service distinct isolated service object {

    # This remote function is called when a new message is received from the message store.
    #
    # + content - The message content to be processed
    # + return - An error if the message could not be processed, or a nil value
    isolated remote function onMessage(anydata content) returns error?;
};
```

> **Note**: The `onMessage` function can be further enhanced to support data-binding for the message content, allowing for automatic type conversion. If implemented, a compiler plugin would be used to validate the `onMessage` function signature against the expected message type.

#### The Listener Lifecycle

- **Attach:** A `msgstore:Service` object can be attached to the `msgstore:Listener`. The listener supports attachment without a path since it's not relevant in this context. Only one service can be attached to a given listener instance.

- **Start:** When the listener is started, a scheduled task will be initiated. This task will periodically retrieve messages from the associated `MessageStore` at the `pollingInterval` defined in the `ListenerConfiguration`.

- **Scheduled Message Poll Task:** Upon successful retrieval of a message, its content will be extracted from the `Message` record and dispatched to the attached service's `onMessage` function for processing.

  - **Success:** If the `onMessage` function returns `()`, the message will be acknowledged as successfully processed in the `MessageStore`.
  - **Failure:** If the `onMessage` function returns an `error`, the message processing will be retried based on the configured `maxRetries` and `retryInterval`.
If the maxRetries is reached:
    - The message will be acknowledged as a **failure** if `dropMessageAfterMaxRetries` is `false` and `deadLetterStore` is not set. This typically means the message remains in the original store or its status is updated to "failed".
    - The message will be acknowledged as a **success** if `dropMessageAfterMaxRetries` is `true` and `deadLetterStore` is not set. This implies the message is discarded.
    - The message will be stored in the `deadLetterStore` (if configured) regardless of `dropMessageAfterMaxRetries`. This provides a mechanism for inspecting and reprocessing failed messages.

- **Detach:** The `msgstore:Service` can be programmatically detached from the `msgstore:Listener`. This action will stop the scheduled message polling task, preventing the listener from retrieving further messages.

- **Immediate Stop:** The listener can be stopped immediately. This will halt the scheduled task, and no further messages will be retrieved. Any messages currently in the process of being handled by `onMessage` will not be acknowledged.

- **Graceful Stop:** Graceful shutdown, which would ensure all in-flight messages are processed and acknowledged before stopping, is **not supported in the initial version of this proposal**. The immediate stop will be called instead.

### Example Usage

The following example demonstrates how to utilize the message store and the message store listener within a Ballerina application:

```ballerina
import ballerina/io;
import ballerina/msgstore;

msgstore:MessageStore msgStore = new msgstore:InMemoryMessageStore();

listener msgstore:Listener msgStoreListener = new(msgStore, {
    pollingInterval: 10,
    maxRetries: 2,
    retryInterval: 2
});

# Represents a message store service that processes messages from the message store
service on msgStoreListener {

    # This remote function is called when a new message is received from the message store.
    isolated remote function onMessage(anydata content) returns error? {
        io:println("Received message: ", content);
        # Simulate message processing
        if content is string && content == "fail" {
            return error("Message processing failed");
        }
    }
}
```

## Risks and Assumptions

### Risks

- **Performance Overhead:** The abstraction layer introduced by the `MessageStore` interface and the listener's polling mechanism might introduce some performance overhead compared to direct interaction with underlying message broker APIs.
- **Complexity of External Implementations:** Ensuring that external `MessageStore` implementations (e.g., for Kafka, JMS, etc.) correctly adhere to the `MessageStore` interface contract, especially regarding idempotency and exactly-once processing semantics (if supported by the underlying broker), could be challenging. Clear guidelines and robust testing will be crucial.
- **Error Handling Granularity:** The current `acknowledge` method has a single `success` boolean. Some advanced message brokers might offer more granular acknowledgment types (e.g., re-queue, reject with specific error codes). This proposal adopts a simpler success/failure model.
- **Thread Model and Concurrency:** Careful consideration is needed for how the listener's polling and message processing interact with Ballerina's concurrency model to avoid blocking the event loop and ensure efficient resource utilization.
- **Dead-Letter Queue Semantics:** The interaction between the listener's retry mechanism and the `deadLetterStore` needs to be carefully designed to avoid message loss or duplication, especially under failure conditions during the transfer to the DLQ.

### Assumptions

- **Message Order:** The retrieve method is expected to return the "top" message, implying an ordered queue in most message store implementations. For unordered stores, this means returning any available message. The consistency of this ordering across different `MessageStore` implementations is assumed to be handled by the specific implementation.
- **Message Uniqueness:** The `id` in the `Message` record is assumed to be **unique** and stable for a given message within the lifetime of its processing by the listener.
- **Atomic Operations:** It is assumed that the `retrieve` and `acknowledge` operations, particularly for external message stores, are designed to be atomic or effectively atomic to prevent message loss or duplicate processing in distributed environments.
- **Polling-based Listener Acceptability:** The initial design relies on a polling mechanism. While generally acceptable for many use cases, extremely low-latency requirements might necessitate push-based notification mechanisms, which are not part of this initial proposal.

## Dependencies

- Ballerina Language and Runtime: This proposal depends on core Ballerina language features and its runtime environment.
- Existing Ballerina Connectors: Specific `MessageStore` implementations (e.g., for RabbitMQ, Kafka) will depend on their respective Ballerina connector packages (e.g., `ballerinax/rabbitmq`, `ballerinax/kafka`).
- Standard Library Modules: `ballerina/log` for logging and potentially `ballerina/task` for scheduling.

## Future Work

- **Data-Binding for onMessage:** Enhance the `onMessage` function in `msgstore:Service` to support automatic data-binding for message content, allowing developers to define specific record as parameters. This would involve compiler plugin support for validation.
- **Graceful Shutdown:** Implement a graceful shutdown mechanism for the `msgstore:Listener` that ensures all in-flight messages are processed and acknowledged before the listener fully stops.
- **Batch Processing:** Add support for retrieving and processing messages in batches to improve throughput for high-volume scenarios.
- **Message Headers/Metadata:** Extend the `Message` record to include a mechanism for handling message headers or other metadata, beyond just the content.
- **Metrics and Observability:** Integrate with Ballerina's observability framework to provide metrics on message processing rates, retry counts, and DLQ activity.

## References

[1] [[WSO2 Integrator MI] About Message Stores and Processors](https://mi.docs.wso2.com/en/latest/reference/synapse-properties/about-message-stores-processors/)

[2] [[WSO2 Integrator MI] Guaranteed Delivery](https://mi.docs.wso2.com/en/latest/learn/enterprise-integration-patterns/messaging-channels/guaranteed-delivery/)
