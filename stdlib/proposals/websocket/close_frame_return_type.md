# Close frame retun type support for ballerina/websocket
- Authors
  - Mohamed Sabthar, Ayesh Almeida
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

2. - 16. // TODO: Add the ballerina record mapping


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
