# Messaging Pipeline in Ballerina

- Authors
  - Tharmigan Krishnananthalingam
- Reviewed by
  - Shafreen Anfar, Danesh Kuruppu
- Created date
  - 2025-06-24
- Updated date
  - 2025-06-27
- Issue
  - [#1363](https://github.com/ballerina-platform/ballerina-spec/issues/1363)
- State
  - Submitted

## Summary

This proposal introduces a new `xlibb/pipeline` package that defines a messaging channel concept in Ballerina. A channel acts as an orchestrator, enabling developers to define a complete message processing pipeline. Messages pushed into a channel will undergo a series of transformations and validations by "processors" in a defined sequential order, followed by parallel delivery to multiple "destinations". The channel also provides built-in mechanisms for robust error handling, including a configurable failure store for failed messages and a replay listener for automatic or on-demand re-processing, significantly simplifying the development of reliable and resilient message-driven applications.

## Motivation

Building message-driven applications often involves complex tasks: transforming data, routing messages, and reliably delivering them to multiple systems. Developers frequently write repetitive code for common patterns like retries, error handling, and parallel delivery. This leads to increased development time, inconsistent implementations, and systems that are harder to maintain and evolve.

The proposed `xlibb/pipeline` package simplifies these challenges. It offers a standardized, declarative way to define message pipelines, reducing boilerplate code and making it easier to build resilient, fault-tolerant applications. By centralizing message flow management, it improves developer experience and promotes consistent, reliable integration patterns across Ballerina projects.

## Goals

- Introduce a Ballerina messaging pipeline for streamlined message handling.
- Implement message replay capabilities within the pipeline.
- Establish a failure store for persistent storage of failed messages.
- Enable replay of failed messages via a dedicated replay listener.

## Design

This proposal introduces a new `xlibb/pipeline` package that provides a structured and opinionated way to handle message processing and delivery through a "pipeline" concept. A pipeline orchestrates the flow of messages through a configurable series of processors and destinations, allowing for flexible, reliable, and fault-tolerant message handling.

### Core Components

The pipeline concept in Ballerina is built upon the following fundamental components:

- **Message (`pipeline:Message`):** This represents the fundamental unit of data flowing through the pipeline. It is an internal container that holds the actual message content (payload) along with a unique identifier (id) and any other relevant internal metadata managed by the pipeline.

- **Message Context (`pipeline:MessageContext`):** This is the single, mutable container that holds everything about the current message being processed. It encapsulates the Message itself, along with any additional dynamic data, properties, or state that processors and destinations need to share, update, or pass along during the message's journey through the pipeline.

- **Processor (`pipeline:Processor`):** These are the idempotent functional units of your message processing pipeline. A Processor takes the Message Context (and thus the Message within it) and performs an action that transforms the message's content, modifies its metadata, adds data to the Context, or filters the message. Because they are designed to be idempotent, running them multiple times with the same input Context will always produce the same result, making replay safe and predictable. If a processor determines a message should not continue through the pipeline (e.g., a validation failure), it can signal this, effectively acting as a filter that prevents further processing or delivery.

- **Destination (`pipeline:Destination`):** These are the final delivery points for your processed messages. A Destination takes a copy of the Message Context and is responsible for delivering the message contained within to an external system, a database, another message queue, an HTTP endpoint, or any other final recipient. Unlike Processors, these functions do not strictly need to be idempotent, as they represent terminal actions that send data outwards. However, designing destinations to be idempotent where possible is a good practice for resilience.

- **Failure Store (`msgstore:MessageStore`):** This is a crucial safety net for the pipeline. The Failure Store is an instance of `ballerina/msgstore:MessageStore` (as defined in the linked proposal) where messages are automatically sent if they fail at any point during processing within a Processor or during delivery to a Destination within a HandlerChain. It intelligently captures the original message content and a snapshot of the Message Context at the time of failure, allowing for later inspection, debugging, and potential replay.

- **Message Flow:** This concept defines the sequence and structure of processing within the pipeline:

  - **Source Flow (`pipeline:SourceFlow`):** This is a sequential chain of Processors that a message traverses before being considered ready for delivery.

  - **Destinations Flow (`pipeline:DestinationsFlow`):** This defines the set of Destinations where the fully processed message will be delivered, typically in parallel.

- **Replay Listener:** This is an optional, but highly powerful, component that can be configured within the HandlerChain. It automatically listens for failed messages stored in the Failure Store or a dedicated Replay Store (for on-demand manual replay). It then attempts to re-process these messages through the HandlerChain's defined pipeline. It includes retry policies and can route messages that consistently fail replay attempts to a Dead Letter Store for manual intervention.

- **HandlerChain (`pipeline:HandlerChain`):** This is the central orchestrator. A HandlerChain defines and manages a complete message flow, encompassing the SourceFlow (sequence of Processors) and DestinationsFlow (set of Destinations). It handles error propagation, integrates with the Failure Store, and can leverage the Replay Listener. The HandlerChain ensures that messages are processed in the defined sequential order by processors and then delivered concurrently to destinations.

### Component Interaction

The flow of a message through a `pipeline:HandlerChain` is meticulously orchestrated to ensure reliability and flexible processing:

1. **Message Ingress:** A raw message content (e.g., a string, json, byte[], or any anydata) enters the HandlerChain through its `execute` method. This content typically originates from an external source (e.g., an HTTP request, a message queue subscription, a file read, or a direct function call).

2. **Context Creation:** The HandlerChain immediately wraps this incoming raw content into a Message object. This Message is then encapsulated within a new Message Context instance. This Message Context becomes the central, dynamic container for all subsequent operations, allowing processors and destinations to share and update state throughout the message's journey. A unique identifier is assigned to the Message and stored within the Context.

3. **Sequential Processing (Source Processors):**

    - The HandlerChain iteratively processes the Message Context through its configured `pipeline:SourceFlow` (a sequence of Processor functions) in the defined order.
    - Each Processor receives the Message Context as input. It can access and modify the message's content, update its internal metadata, or add new properties to the Message Context itself.

    - **Filtering:** If a Filter processor returns false (indicating the message should be dropped) or an error, the HandlerChain immediately stops further processing for that message within the current pipeline. The message is considered successfully handled (dropped) and is not passed to subsequent processors or destinations.

    - **Routing:** If a ProcessorRouter returns a target Processor, the HandlerChain will dynamically route the message to that specific Processor, effectively jumping or branching within the SourceFlow instead of simply proceeding to the next sequential processor. If ProcessorRouter returns `()`, the pipeline proceeds to the next sequential processor.

    - **Error Handling (Processors):** If any Processor encounters an error and returns an error type, the HandlerChain catches this exception. It then persists the original Message and the Message Context (as it existed at the point of failure) into the configured Failure Store (if enabled). This ensures that the state leading to the failure is preserved for later inspection and potential replay.

4. **Parallel Delivery (Destinations):**

    - If the message successfully traverses all Source Processors (i.e., it wasn't dropped and no processor returned an unhandled error), the HandlerChain proceeds to its DestinationsFlow.

    - The Destinations configured in the DestinationsFlow are executed in parallel.

    - Crucially, each Destination receives a copy of the Message Context (which includes the fully processed Message). This ensures isolation; actions performed by one destination (e.g., external API calls, logging specific to that destination) do not unintentionally interfere with the Message Context being used by other concurrently executing destinations.

    - **Routing to Destinations:** A DestinationRouter can dynamically select which DestinationFlow (or individual Destination) to send the message to based on criteria within the Message Context.

    - **Error Handling (Destinations):** If any Destination fails to deliver the message (returns an error), the HandlerChain intercepts this. Similar to processor failures, the original Message and the Message Context (as it stood just before the destination phase began, or at the exact point of failure) are sent to the Failure Store (if configured).

    - **Execution Result:** If all Destinations succeed, the execute method returns a `pipeline:ExecutionResult` containing a map of results from each destination, keyed by the destination's name.

5. **Failure Store Interaction:**

    - The Failure Store is an optional but highly recommended configuration for the HandlerChain.

    - When enabled, it acts as the central repository for messages that encounter an error during either the Processor phase or the Destination phase.

    - The HandlerChain serializes and persists the Message and the state of its Message Context into the Failure Store. This comprehensive capture is vital for debugging, re-analyzing failure causes, and enabling the replay mechanism.

6. **Replay Mechanism:**

    - The HandlerChain can be configured with an optional Replay Listener (leveraging ballerina/msgstore:Listener) that automatically monitors the Failure Store for failed messages.

    - The replayListener will poll the Failure Store at a configured pollingInterval for new failed messages.

    - When a failed message is retrieved by the replayListener, it triggers a re-processing attempt through the original HandlerChain's execute method, but with an intelligent re-entry point and context.

    - **Intelligent Replay:** During replay, the HandlerChain inspects the Message Context captured at the time of the original failure. If the Message Context contains information about destinations that already successfully processed the message in previous attempts (e.g., through internal tracking), the HandlerChain will intelligently skip those already successful Destinations. This prevents redundant deliveries to systems that have already received the message, ensuring idempotency at the destination level where possible and preventing unintended side effects.

    - If a replayed message consistently fails even after the configured number of maxRetries, it can be sent to a Dead Letter Store (another `msgstore:MessageStore` instance) for manual inspection or further automated handling outside the main pipeline flow.

![HandlerChain Flow Diagram](https://raw.githubusercontent.com/TharmiganK/ballerina-spec/pipeline-proposal/stdlib/proposals/pipeline/resources/channel_flow.png)

### Components Overview

#### Message Context

The `pipeline:MessageContext` is a central container that holds all information related to the message being processed. It includes the original content, any metadata, and additional state that processors and destinations can share or update during processing.

The following methods are available on the `pipeline:MessageContext`:

| Method                                   | Description                                                        |
|-------------------------------------------|--------------------------------------------------------------------|
| `getContent()`                           | Returns the message content as `anydata`.                          |
| `getContentWithType()`                    | Returns the message content as a specific type.                    |
| `getId()`                                 | Returns the unique identifier of the message.                      |
| `setProperty(string key, anydata value)`  | Sets a property in the context.                                    |
| `getProperty(string key)`                 | Gets a property from the context.                                  |
| `getPropertyWithType(string key)`         | Gets a property from the context with a specific type.             |
| `hasProperty(string key)`                 | Checks if a property exists in the context.                        |
| `removeProperty(string key)`              | Removes a property from the context.                               |
| `toRecord()`                             | Converts the context to a record type for easier inspection and debugging. |

#### Processors

The message processors are just Ballerina functions that are annotated to indicate their type and purpose. All processors are assumed to be *idempotent*, meaning that running them multiple times with the same input will always produce the same result. This is crucial for safe message replay. It is developer's responsibility to ensure that the logic within these processors adheres to this principle.

The package provides four types of processors:

- **Filter**: A processor that can drop messages based on a condition. This accepts the *Context* and returns a boolean indicating whether the message should continue processing.
- **Transformer**: A processor that modifies the message content or metadata. It accepts the *Context* and returns a modified message content.
- **ProcessorRouter**: A processor that can route messages to different processors based on some criteria. It accepts the *Context* and returns the target processor to which the message should be routed. This allows for dynamic routing of messages based on their content or metadata.
- Generic Processor: A processor that can perform any action on the *Context*. It accepts the *Context* and returns nothing.

##### Filter Processor

Defintion:
```ballerina
# Represents a filter function that checks the message context and returns a boolean indicating 
# whether the message should be processed further.
public type Filter isolated function (MessageContext msgCtx) returns boolean|error;
```

Example:
```ballerina
@pipeline:Filter {name: "filter"}
isolated function filter(pipeline:MessageContext context) returns boolean|error {
    // Check some condition on the message
}
```

##### Transformer Processor

Defintion:
```ballerina
# Represents a transformer function that processes the message content and returns a modified 
# message content.
public type Transformer isolated function (MessageContext msgCtx) returns anydata|error;
```

Example:
```ballerina
@pipeline:Transformer {name: "transformer"}
isolated function transformer(pipeline:MessageContext context) returns anydata|error {
    // Modify the message content or metadata
    // Return the modified message content
}
```

#### Processor Router

Defintion:
```ballerina
# Represents a processor router function that processes the message context and returns a processor.
# An error can be returned if the routing fails, or nil if it wants to stop processing the message.
public type ProcessorRouter isolated function (MessageContext msgCtx) returns Processor|error?;
```

Example:
```ballerina
@pipeline:ProcessingRouter {name: "processorRouter"}
isolated function processorRouter(pipeline:MessageContext context) returns pipeline:Processor|error {
    // Determine the target processor based on some criteria
    // Return the target processor to which the message should be routed
}
```

#### Generic Processor

Defintion:
```ballerina
# Represents a generic message processor that can process the message and return an error if the 
# processing fails.
public type GenericProcessor isolated function (MessageContext msgCtx) returns error?;
```

Example:
```ballerina
@pipeline:Processor {name: "generic"}
isolated function generic(pipeline:MessageContext context) returns error? {
    // Perform any action on the context
}
```

#### Source Flow

The source flow of a message is created as a sequence of processors that the message goes through before being delivered to any destinations. You can define the source flow by creating a sequence of processors and configuring them in the pipeline.

```ballerina
pipeline:SourceFlow sourceFlow = [
    filter, // a filter processor
    transformer, // a transformer processor
    processorRouter, // a processor router
    generic // a generic processor
];
```

Defintion:
```ballerina
# Represents a processor that can be a filter, transformer, or processor and can be attached to a 
# pipeline for processing messages. Processors should be idompotent i.e. repeating the execution 
# should not change the outcome or the pipeline state.
public type Processor GenericProcessor|Filter|Transformer|ProcessorRouter;

# Represents a source flow that processes the message context. The pipline can consist a single 
# processor or an array of processors. The source pipline will run in the configured order and the 
# result of the last processor will be used as the message content for the next step in the pipeline 
# flow.
public type SourceFlow Processor|[Processor...];
```

#### Destination

A destination is similar to a generic processor but is used to deliver the message to an external system or endpoint. It accepts a copy of the *Context* and returns an error if the delivery fails. Additionally, it can return any result that is relevant to the delivery operation, such as a confirmation or status.

```ballerina
@pipeline:Destination {name: "destination"}
isolated function destination(pipeline:MessageContext context) returns any|error {
    // Deliver the message to an external system or endpoint
}
```

Defintion:
```ballerina
# Represents a destination function that processes the message context and returns a result or an 
# error if it failed to send the message to the destination. Destinations are typically contains a 
# sender or a writer that sends or writes the message to a specific destination.
public type Destination isolated function (MessageContext msgCtx) returns any|error;
```

#### Destination Flow

A single destination can be configured as a destination flow, or it can be included with preprocessors which are executed before the destination is called.

```ballerina
// A single destination flow
pipeline:DestinationFlow destinationFlow = destination;

// A destination flow with preprocessors
pipeline:DestinationFlow destinationWithPreprocessors = [
    [
        filter, // a filter processor
        transformer // a transformer processor
    ],
    destination // a destination
];
```

Definition:
```ballerina
# Represents a destination with processors that processes the message context and sends the message
# to a destination. The flow can consist of an array of processors followed by a destination. The
# processors in the flow will run in the configured order and the result of the last processor will
# be used as the message content for the destination.
public type DestinationWithProcessors [[Processor...], Destination];

# Represents a destination flow that processes the message context and sends the message to a
# destination. The flow can consist of a single destination or an array of processors followed by a
# destination. The processors in the flow will run in the configured order and the result of the last
# processor will be used as the message content for the destination.
public type DestinationFlow Destination|DestinationWithProcessors;
```

#### Destination Router

A destination router is a special type of processor that can route messages to different destinations based on some criteria. It accepts the *Context* and returns the target destination flow to which the message should be routed.

```ballerina
@pipeline:DestinationRouter {name: "destinationRouter"}
isolated function destinationRouter(pipeline:MessageContext context) returns pipeline:DestinationFlow|error {
    // Determine the target destination based on some criteria
    // Return the target destination to which the message should be routed
}
```

Defintion:
```ballerina
# Represents a destination router function that processes the message context and returns a 
# destination or an error if the routing fails, or nil if it wants to stop processing the message.
public type DestinationRouter isolated function (MessageContext msgCtx)
    returns DestinationFlow|error?;
```

#### Destinations Flow

The destinations flow of a message can be a single destination router or a set of destination flows. The destination flows are executed in parallel, meaning that all destinations will receive a copy of the message and the context at the same time.

```ballerina
// A destination router as the destinations flow
pipeline:DestinationsFlow destinationsFlow = destinationRouter;

// A set of destinations as the destinations flow
pipeline:DestinationsFlow destinationsFlow = [
    destination, // a destination
    destinationWithPreprocessors // a destination with preprocessors
];
```

Definition:
```ballerina
# Represents the flow of destinations that can be used to send the message to multiple
# destinations. The flow can consist of a single destination router or a single destination flow, 
# or an array of destination flows. The destination flows will run in parallel and the results will 
# be collected.
public type DestinationsFlow DestinationRouter|DestinationFlow|DestinationFlow[];
```

#### Failure Store

The failure store is a message store that stores the messages and provide APIs to retrieve and acknowledge the messages. For more information on the message store, refer to the proposal: [Message Stores and Store Listener in Ballerina](https://github.com/TharmiganK/ballerina-spec/blob/master/stdlib/proposals/msg-store/message_store_store_listener.md)

#### Replay Listener

The replay listener is an optional component that can be attached to the failure store or a replay store to replay the failed messages. It listens for failed messages and attempts to replay them through the pipeline. The replay listener can be configured with a retry policy and a dead letter store to handle messages that cannot be replayed after a certain number of retries. For more information on the replay listener, refer to the proposal: [Message Stores and Store Listener in Ballerina](https://github.com/TharmiganK/ballerina-spec/blob/master/stdlib/proposals/msg-store/message_store_store_listener.md)

#### HandlerChain

To create a pipeline, you need to define the processors and destinations that will be part of the message processing pipeline. You can configure the pipeline with a sequence of processors and a set of destinations.

```ballerina
pipeline:HandlerChain pipeline = check new ({
    sourceFlow: [
        filter, // a filter processor
        transformer, // a transformer processor
        processorRouter, // a processor router
        generic // a generic processor
    ],
    destinationsFlow: [
        destination, // a destination
        destinationWithPreprocessors // a destination with preprocessors
    ],
    failureConfig: {
        failureStore: failureStore,
        replayListenerConfig: {
            replayStore: replayStore, // a replay store to replay the failed messages
            pollingInterval: 10, // interval in seconds to poll for failed messages
            maxRetries: 2, // maximum number of retries for replay
            retryInterval: 2 // interval in seconds between retries
            deadLetterStore: deadLetterStore // a dead letter store to store the messages that cannot be replayed
        }
    }
});
```

HandlerChain configuration is defined as follows:
```bal
# Represents the failure handler configuration for the pipeline.
# 
# + failureStore - The store to use for storing messages that failed to process
# + replayListenerConfig - The configuration for replaying messages in the pipeline
public type ChannelFailureHandlerConfig record {|
    msgstore:MessageStore failureStore;
    ReplayListenerConfiguration replayListenerConfig?;
|};

# Represent the configuration for a pipeline.
#
# + sourceFlow - The source flow that processes the message context
# + destinationsFlow - The destinations flow that processes the message context and sends the 
# message to one or more destinations
# + failureConfig - The configuration for handling failures in the pipeline
public type ChannelConfiguration record {|
    SourceFlow sourceFlow;
    DestinationsFlow destinationsFlow;
    ChannelFailureHandlerConfig failureConfig?;
|};
```

> **Note:** When replay listener is configured in the pipeline initialization, the listener will be automatically created and started. So, the channels with replay listener configuration should be used as global variables and initializing the pipeline again and again will result in multiple instances of the replay listener being created.

## HandlerChain Execution

To execute a pipeline, you can call the `execute` method with the raw message content. The pipeline will process the message through its configured processors and destinations.

```ballerina
pipeline:ExecutionResult|pipeline:ExecutionError result = pipeline.execute("raw message content");
```

A successful execution will return a `pipeline:ExecutionResult` containing the final context after processing. If an error occurs during processing or delivery, it will return a `pipeline:ExecutionError` with details about the failure. The `ExecutionError` error details will include a snapshot of the context at the time of failure, allowing you to inspect the message and replay it if necessary.

## HandlerChain Replay

To replay a message manually, you can use the `replay` method of the pipeline. This method accepts a failed message and attempts to reprocess it through the configured processors and destinations. The replay will intelligently skip any destinations that have already successfully processed the message in previous attempts.

```ballerina
pipeline:ExecutionResult|pipeline:ExecutionError result = pipeline.execute("raw message content");

if result is pipeline:ExecutionError failure {
    Message failedMessage = failure.detail().message;
    pipeline:ExecutionResult|pipeline:ExecutionError replayResult = pipeline.replay(failedMessage);
}
```

## Alternatives

In the current design, the processors and destinations are indetified using specific function types and annotations. This makes all the processors and destinations to have only the `pipeline:MessageContext` as the input parameter. However, this design requires the developer to do manual conversion of the message content to the specific type they want to work with. This can be improved by allowing content with the specified type to be passed directly to the processor or destination function along with the optional `pipeline:MessageContext` parameter. This would allow the developer to work with the content directly without manual conversion, improving the developer experience.

```ballerina
// Current design
@pipeline:Processor {name: "processor"}
isolated function processor(pipeline:MessageContext context) returns error? {
    // The context will contain the message content as `anydata`
    // The developer needs to manually convert the content to the specific type they want to work with
    MyType myContent = check context.getContentWithType();
    // Process the content
}

// Alternative design
@pipeline:Processor {name: "processor"}
isolated function processor(MyType myContent) returns error? {
    // The content is passed directly to the processor function
    // The developer can work with the content directly without manual conversion
    // Process the content
}
```

But, this design requires compiler validation and the processor or destination function invocation should be done using the different function signatures which reuires the invocation to be done from the Java side.

## Risks and Assumptions

- **Assumption of Idempotency:** The proposal assumes that all processors are idempotent, meaning they can be safely retried without side effects. This is crucial for the replay mechanism to function correctly.

- **Performance Overhead:** The abstraction layers (context management, dynamic function invocation, failure storage serialization) might introduce a measurable performance overhead compared to highly optimized, hand-crafted pipelines. This will be mitigated through careful design and profiling.

## Dependencies

- **Ballerina Message Store and Store Listener:** This proposal is heavily dependent on the `ballerina/msgstore` package, specifically its MessageStore interface and Listener implementation, for handling failure storage and replay mechanisms.

- **Ballerina Language and Runtime:** Relies on core Ballerina language features, including isolated functions, records, objects, and the concurrent execution model.

## Future Work

- **Metrics and Observability:** Integrate with Ballerina's observability framework to provide detailed metrics on pipeline throughput, message processing latency, processor execution times, destination success/failure rates, retry counts, and DLQ volumes.

## References

[1] [Message Stores and Store Listener in Ballerina](https://github.com/TharmiganK/ballerina-spec/blob/master/stdlib/proposals/msg-store/message_store_store_listener.md)

[2] [[WSO2 Integrator MI] Guaranteed Delivery](https://mi.docs.wso2.com/en/latest/learn/enterprise-integration-patterns/messaging-channels/guaranteed-delivery/)
