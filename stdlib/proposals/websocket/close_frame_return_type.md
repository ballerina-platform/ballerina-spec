# Close frame retun type support for ballerina/websocket
- Authors
  - Mohamed Sabthar, Ayesh Almeida, Chathushka Ayash
- Reviewed by
    - Bhashinee Nirmali, 
- Created date
    - 2025-01-31
- Issue
    - TODO
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
Define a base `CloseFrame` record to encapsulate common fields:

```
public type Status distinct object {
    public int code; //  Constraint minValue: 1000, maxValue: 4999
};

type CloseFrame record {|
    readonly Status status;
    string reason?;
|};
```

The status code of the close frame can vary between the range of 1000 to 4999. However, there are 16 commonly used status codes for which we are proposing the following predefined status code records in the WebSocket module. These can be directly inferred and used by the user.

1. Normal Closure - 1000

```ballerina
public const NORMAL_CLOSURE_STATUS_CODE = 1000;

public readonly distinct class NormalClosureStatus {
    *Status;
    public int code = NORMAL_CLOSURE_STATUS_CODE;
}

public final NormalClosureStatus NORMAL_CLOSURE_STATUS_OBJ = new;

public type NormalClosure record {|
    *CloseFrame;
    readonly NormalClosureStatus status = NORMAL_CLOSURE_STATUS_OBJ;
|};

public final readonly & NormalClosure NORMAL_CLOSURE = {};
```

2. Going Away - 1001

```ballerina
public const GOING_AWAY_STATUS_CODE = 1001;

public readonly distinct class GoingAwayStatus {
    *Status;
    public int code = GOING_AWAY_STATUS_CODE;
}

public final GoingAwayStatus GOING_AWAY_STATUS_OBJ = new;

public type GoingAway record {|
    *CloseFrame;
    readonly GoingAwayStatus status = GOING_AWAY_STATUS_OBJ;
|};

public final readonly & GoingAway GOING_AWAY = {};
```

3. Protocol Error - 1002

```ballerina
public const PROTOCOL_ERROR_STATUS_CODE = 1002;

public readonly distinct class ProtocolErrorStatus {
    *Status;
    public int code = PROTOCOL_ERROR_STATUS_CODE;
}

public final ProtocolErrorStatus PROTOCOL_ERROR_STATUS_OBJ = new;

public type ProtocolError record {|
    *CloseFrame;
    readonly ProtocolErrorStatus status = PROTOCOL_ERROR_STATUS_OBJ;
    string reason = "Connection closed due to protocol error.";
|};

public final readonly & ProtocolError PROTOCOL_ERROR = {};
```

4. Unsupported Data - 1003

```ballerina
public const UNSUPPORTED_DATA_STATUS_CODE = 1003;

public readonly distinct class UnsupportedDataStatus {
    *Status;
    public int code = UNSUPPORTED_DATA_STATUS_CODE;
}

public final UnsupportedDataStatus UNSUPPORTED_DATA_STATUS_OBJ = new;

public type UnsupportedData record {|
    *CloseFrame;
    readonly UnsupportedDataStatus status = UNSUPPORTED_DATA_STATUS_OBJ;
    string reason = "Endpoint received unsupported frame.";
|};

public final readonly & UnsupportedData UNSUPPORTED_DATA = {};
```

> **Note:** We already support sending `error: data binding failed: {ballerina}ConversionError: Status code: 1003` when a data binding failure occurs.

5. Invalid Payload - 1007

```ballerina
public const INVALID_PAYLOAD_STATUS_CODE = 1007;

public readonly distinct class InvalidPayloadStatus {
    *Status;
    public int code = INVALID_PAYLOAD_STATUS_CODE;
}

public final InvalidPayloadStatus INVALID_PAYLOAD_STATUS_OBJ = new;

public type InvalidPayload record {|
    *CloseFrame;
    readonly InvalidPayloadStatus status = INVALID_PAYLOAD_STATUS_OBJ;
    string reason = "Payload does not match the expected format or encoding.";
|};

public final readonly & InvalidPayload INVALID_PAYLOAD = {};
```

6. Policy Violation - 1008

```ballerina
public const POLICY_VIOLATION_STATUS_CODE = 1008;

public readonly distinct class PolicyViolationStatus {
    *Status;
    public int code = POLICY_VIOLATION_STATUS_CODE;
}

public final PolicyViolationStatus POLICY_VIOLATION_STATUS_OBJ = new;

public type PolicyViolation record {|
    *CloseFrame;
    readonly PolicyViolationStatus status = POLICY_VIOLATION_STATUS_OBJ;
    string reason = "Received message violates its policy.";
|};

public final readonly & PolicyViolation POLICY_VIOLATION = {};
```

7. Message Too Big - 1009

```ballerina
public const MESSAGE_TOO_BIG_STATUS_CODE = 1009;

public readonly distinct class MessageTooBigStatus {
    *Status;
    public int code = MESSAGE_TOO_BIG_STATUS_CODE;
}

public final MessageTooBigStatus MESSAGE_TOO_BIG_STATUS_OBJ = new;

public type MessageTooBig record {|
    *CloseFrame;
    readonly MessageTooBigStatus status = MESSAGE_TOO_BIG_STATUS_OBJ;
    string reason = "The received message exceeds the allowed size limit.";
|};

public final readonly & MessageTooBig MESSAGE_TOO_BIG = {};
```

8. Internal Server Error - 1011

```ballerina
public const INTERNAL_SERVER_ERROR_STATUS_CODE = 1011;

public readonly distinct class InternalServerErrorStatus {
    *Status;
    public int code = INTERNAL_SERVER_ERROR_STATUS_CODE;
}

public final InternalServerErrorStatus INTERNAL_SERVER_ERROR_STATUS_OBJ = new;

public type InternalServerError record {|
    *CloseFrame;
    readonly InternalServerErrorStatus status = INTERNAL_SERVER_ERROR_STATUS_OBJ;
    string reason = "Internal server error occurred.";
|};

public final readonly & InternalServerError INTERNAL_SERVER_ERROR = {};
```

### Service Implementation with Close Frame Types
Utilizing the new close frame return types, the service code can be refactored as follows:

```ballerina
service class MyService {
    *websocket:Service;

    remote function onSubscribe(websocket:Caller caller, types:Subscribe sub) returns types:Response|websocket:NormalClosure {
        // ... omitted for brevity
        return websocket:NORMAL_CLOSURE; // Automatically sends the close frame and closes the connection.
    }
}
```

## Future Enhancements
- Currently, the `onClose` dispatch function of the service optionally takes `statusCode` and `reason` values. We could try to reuse the above-defined `CloseFrame` type as its parameter. However, this doesn't add much value apart from reusing the same defined record. If needed, we can consider adding it later. 
