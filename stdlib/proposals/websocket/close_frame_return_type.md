# Close frame retun type support for ballerina/websocket
- Authors
  - Mohamed Sabthar, Ayesh Almeida, Chathushka Ayash
- Reviewed by
    - Bhashinee Nirmali, 
- Created date
    - 2025-01-31
- Issue
    - [#1333](https://github.com/ballerina-platform/ballerina-spec/issues/1333)
- State
    - Submitted

## Summary
Introduce dedicated close frame return types in the Ballerina WebSocket module to simplify the process of sending close frames. This enhancement aims to improve code conciseness and facilitate the generation of AsyncAPI documentation.

## Goals
- Simplify the process of sending WebSocket close frames in Ballerina services.
- Enhance code readability and maintainability by reducing verbosity.
- Facilitate accurate and efficient generation of AsyncAPI documentation.

## Non-Goals
- This proposal does not aim to modify the existing WebSocket protocol implementation in Ballerina.
- It does not address enhancements related to non-control frames or other WebSocket functionalities.

## Motivation
In the current Ballerina WebSocket module, sending a close frame requires explicitly invoking the `close()` method on the `caller` object, optionally specifying the status code and reason for closure, as shown below:

```ballerina
service class WsServiceUser {
    *websocket:Service;
    
    remote function onSubscribe(websocket:Caller caller, types:Subscribe sub) returns types:Response|error? {
        string? id = sub.id;
        if id is () {
            check caller->close(); // Send the close frame.
            return;
        }
        return {message: "System: Welcome to the chat!", event:"subscribe"};
    } 
}
``` 

This approach introduces several challenges:

1. Complexity in Generating AsyncAPI Documentation: Identifying instances where the connection is closed necessitates traversing the syntax tree. The dynamic nature of setting status codes and reasons increases the complexity, leading to potential edge cases and maintenance difficulties.

2. Verbosity and Reduced Code Intuitiveness: Requiring explicit passing of the `caller` parameter to dispatcher functions for invoking `close()` results in verbose code. This verbosity detracts from the intuitiveness and readability of the code.

By introducing dedicated close frame return types, we can streamline the process of sending close frames, resulting in cleaner code and more straightforward generation of AsyncAPI documentation.

## Design 
We propose the introduction of specific record types to represent WebSocket close frames. When a service returns one of these types, the WebSocket module will automatically send the corresponding close frame and terminate the connection. This approach eliminates the need for explicit invocation of the `close()` method and passing of the `caller` parameter.

### Close Frame Record Design

#### Base Close Frame Definition
Define a `CloseFrameBase` record to encapsulate common fields:

```ballerina
type CloseFrameBase record {|
    readonly object {} 'type;
    readonly int status;
    string reason?;
|};
```

#### Custom Close Frame
Allows users to define custom close frames with any status code (1000–4999).

```ballerina
public readonly distinct class CustomCloseFrameType {
};

public final CustomCloseFrameType CUSTOM_CLOSE_FRAME = new;

public type CustomCloseFrame record {|
    *CloseFrameBase;
    readonly CustomCloseFrameType 'type = CUSTOM_CLOSE_FRAME;
|};
```
#### Predefined Close Frames

The status code of the close frame can vary between the range of 1000 to 4999. However, there are 8 commonly used status codes for which we are proposing the following predefined status code records in the WebSocket module. These can be directly inferred and used by the user.

Predefined close frames extend CloseFrameBase and use PredefinedCloseFrameType.

```ballerina
public readonly distinct class PredefinedCloseFrameType {
};

public final PredefinedCloseFrameType PREDEFINED_CLOSE_FRAME = new;
```

1. Normal Closure - 1000

```ballerina
public type NormalClosure record {|
    *CloseFrameBase;
    readonly PredefinedCloseFrameType 'type = PREDEFINED_CLOSE_FRAME;
    readonly 1000 status = 1000;
|};

public final readonly & NormalClosure NORMAL_CLOSURE = {};
```

2. Going Away - 1001

```ballerina
public type GoingAway record {|
    *CloseFrameBase;
    readonly PredefinedCloseFrameType 'type = PREDEFINED_CLOSE_FRAME;
    readonly 1001 status = 1001;
|};

public final readonly & GoingAway GOING_AWAY = {};
```

3. Protocol Error - 1002

```ballerina
public type ProtocolError record {|
    *CloseFrameBase;
    readonly PredefinedCloseFrameType 'type = PREDEFINED_CLOSE_FRAME;
    readonly 1002 status = 1002;
    string reason = "Connection closed due to protocol error";
|};

public final readonly & ProtocolError PROTOCOL_ERROR = {};
```

4. Unsupported Data - 1003

```ballerina
public type UnsupportedData record {|
    *CloseFrameBase;
    readonly PredefinedCloseFrameType 'type = PREDEFINED_CLOSE_FRAME;
    readonly 1003 status = 1003;
    string reason = "Endpoint received unsupported frame";
|};

public final readonly & UnsupportedData UNSUPPORTED_DATA = {};
```

> **Note:** We already support sending `error: data binding failed: {ballerina}ConversionError: Status code: 1003` when a data binding failure occurs.

5. Invalid Payload - 1007

```ballerina
public type InvalidPayload record {|
    *CloseFrameBase;
    readonly PredefinedCloseFrameType 'type = PREDEFINED_CLOSE_FRAME;
    readonly 1007 status = 1007;
    string reason = "Payload does not match the expected format or encoding";
|};

public final readonly & InvalidPayload INVALID_PAYLOAD = {};
```

6. Policy Violation - 1008

```ballerina
public type PolicyViolation record {|
    *CloseFrameBase;
    readonly PredefinedCloseFrameType 'type = PREDEFINED_CLOSE_FRAME;
    readonly 1008 status = 1008;
    string reason = "Received message violates its policy";
|};

public final readonly & PolicyViolation POLICY_VIOLATION = {};
```

7. Message Too Big - 1009

```ballerina
public type MessageTooBig record {|
    *CloseFrameBase;
    readonly PredefinedCloseFrameType 'type = PREDEFINED_CLOSE_FRAME;
    readonly 1009 status = 1009;
    string reason = "The received message exceeds the allowed size limit";
|};

public final readonly & MessageTooBig MESSAGE_TOO_BIG = {};
```

8. Internal Server Error - 1011

```ballerina
public type InternalServerError record {|
    *CloseFrameBase;
    readonly PredefinedCloseFrameType 'type = PREDEFINED_CLOSE_FRAME;
    readonly 1011 status = 1011;
    string reason = "Internal server error occurred";
|};

public final readonly & InternalServerError INTERNAL_SERVER_ERROR = {};
```

#### `CloseFrame` Type Definition
Defines a union type that includes both predefined and custom close frames.
```ballerina
public type CloseFrame NormalClosure|GoingAway|ProtocolError|UnsupportedData|
    InvalidPayload|PolicyViolation|MessageTooBig|InternalServerError|CustomCloseFrame;
```

### Service Implementation with Close Frame Types
Utilizing the new close frame return types, the service code can be refactored as follows:

```ballerina
service class MyService {
    *websocket:Service;

    remote function onSubscribe(websocket:Caller caller, types:Subscribe sub) returns types:Response|websocket:CloseFrame {
        // ... omitted for brevity
        return websocket:NORMAL_CLOSURE; // Automatically sends the close frame and closes the connection.
    }
}
```

## Future Enhancements
- Currently, the `onClose` dispatch function of the service optionally takes `statusCode` and `reason` values. We could try to reuse the above-defined `CloseFrame` type as its parameter. However, this doesn't add much value apart from reusing the same defined record. If needed, we can consider adding it later. 
