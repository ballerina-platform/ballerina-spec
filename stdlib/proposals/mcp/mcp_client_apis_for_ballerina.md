# MCP Client APIs for Ballerina

- Author: @AzeemMuzammil
- Reviewers: TBD
- Created: 2025-05-28
- Updated: 2025-05-28
- Issue: [#1355](https://github.com/ballerina-platform/ballerina-spec/issues/1355)
- Status: Submitted

## Summary
The MCP Client APIs for Ballerina enable developers to build applications that act as clients using the [Model Context Protocol (MCP)](https://modelcontextprotocol.io/). MCP is an open standard that defines how LLM applications interact with external tools and data sources. This library provides a standardized, idiomatic way to build MCP clients in Ballerina, using streamable HTTP transport for integration with remote MCP servers.

## Goals
- Provide a first-class MCP client library for Ballerina
- Support communication over streamable HTTP transport
- Implement core client operations: initialization, capability negotiation, tool invocation, and prompt handling

## Non-Goals
- Supporting any MCP resource-related operations, such as `resources/list`, `resources/read`, or resource subscriptions
- Supporting any prompt-related operations, such as `prompts/list`, `prompts/get`, or prompt subscriptions
- Implementing an MCP server (to be proposed separately)
- Supporting advanced features like session resumption, resource subscriptions, or OAuth2 auth (initially out of scope)

## Motivation
MCP allows structured interaction between language models and external systems. While SDKs for other languages exist, Ballerina's strength in networking, concurrency, and structured data processing makes it ideal for implementing an MCP client. This implementation will empower Ballerina developers to build intelligent AI-driven applications by integrating external capabilities into LLM workflows.

## Architecture Overview

### Transport: Streamable HTTP
MCP uses JSON-RPC over HTTP with support for server-streaming only. The Ballerina implementation fully adopts this transport mechanism by separating communication into two primary flows, each mapped to a specific HTTP method:

MCP defines two HTTP endpoints to enable bidirectional communication between clients and servers:

to enable bidirectional communication between clients and servers:

#### 1. Client → Server Communication
This interaction occurs over HTTP POST and is responsible for:
- Sending JSON-RPC requests from the client to the server
- Receiving either a synchronous HTTP response or an asynchronous response via an SSE stream

```ballerina
CallToolResult result = check mcpClient->callTool({
    name: "summarizeText",
    arguments: {"text": "The quick brown fox..."}
});
```

The server may respond:
- Immediately with `Content-Type: application/json`
- Or open a Server-Sent Events (SSE) stream using `Content-Type: text/event-stream`

This channel is stateless and one-shot — each request must be sent via a new POST. There is no long-lived connection from the client side.

#### 2. Server → Client Communication
This flow is enabled by the client as part of the overall protocol lifecycle, allowing the server to push messages asynchronously to the client. This includes:
- Notifications
- Server-initiated requests (e.g., sampling prompts), as declared by server capabilities

The client does not explicitly manage the SSE connection but is expected to handle incoming server messages according to its declared capabilities.

When server messages require a response (e.g., sampling), the client must respond using the client → server channel (i.e., via `POST`). The MCP client library will internally route and handle such responses.
This interaction supports features such as:
- Server notifying tools or prompts have changed (if client supports list updates)
- The server triggering sampling requests when the client declares `sampling` support

This dual-channel structure:
- Uses `POST` (with optional SSE response) for **client** → **server** messages
- Uses **SSE** for **server** → **client** pushes as part of the response to a client POST or through a separate SSE stream
- Ensures full compatibility with the MCP spec’s streamable HTTP transport model

## Design Strategy
- Stateless HTTP POSTs for all client messages
- SSE-based streaming for server messages
- Strict adherence to JSON-RPC
- Reusable `mcp:Client` abstraction
- Ballerina-native concurrency and error handling

## Supported Operations

### `initialize`
Establishes a session with the server.

```ballerina
check mcpClient->initialize();
```

### `tools/list`
Lists all available tools exposed by the server.

```ballerina
ListToolsResult tools = check mcpClient->listTools();
```

### `tools/call`
Invokes a tool with given parameters.

```ballerina
CallToolResult result = check mcpClient->callTool({
    name: "summarizeText",
    arguments: {"text": "The quick brown fox..."}
});
```

## Example Usage (Main Function)

```ballerina
import ballerina/mcp;

public function main() returns error? {
    mcp:Client mcpClient = new (
        "http://localhost:3000/mcp",
        info = {
            "name": "MCP Client",
            "version": "1.0.0"
        },
        capabilityConfig = {
            capabilities: {
                roots: {
                    listChanged: true
                }
            }
        }
    );

    check mcpClient->initialize();

    CallToolResult result = check mcpClient->callTool({
        name: "summarizeText",
        arguments: {"text": "Ballerina is an open-source language designed for integration."}
    });

    io:println(result);
}
```

## Future Plans
- Operations related to resources
- MCP server implementation in Ballerina
- OAuth2 and token-based auth support
- Session resumption with state tracking

## Conclusion
This proposal establishes a solid foundation for MCP support in Ballerina, focusing on client-side integration over streamable HTTP. With standardized protocol interactions, idiomatic design, and Ballerina’s strong integration capabilities, this library will unlock AI-enabled workflows for modern application developers.
