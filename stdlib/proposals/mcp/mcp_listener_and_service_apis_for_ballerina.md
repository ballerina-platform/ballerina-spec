# MCP Listener and Service APIs for Ballerina

- Author: @AzeemMuzammil
- Reviewers: TBD
- Created: 2025-06-30
- Updated: 2025-06-30
- Issue: [#1367](https://github.com/ballerina-platform/ballerina-spec/issues/1367)
- Status: Submitted

## Summary
The MCP Listener and Service APIs for Ballerina enable developers to build robust MCP servers using the [Model Context Protocol (MCP)](https://modelcontextprotocol.io/). This implementation provides a complete server-side framework that handles JSON-RPC 2.0 communication over streamable HTTP transport and automatic tool discovery. The server implementation complements the existing MCP client APIs to provide a full-stack MCP solution in Ballerina.

## Goals
- Provide a first-class MCP server implementation for Ballerina
- Support streamable HTTP transport
- Implement automatic tool discovery and schema generation
- Support core MCP server operations: initialization, tool execution and listing tools

## Non-Goals
- Supporting advanced MCP features like resource subscriptions or sampling (initially out of scope)
- OAuth2 authentication support (initially out of scope)

## Motivation
The Model Context Protocol represents a paradigm shift in how AI applications interact with external systems. While MCP client APIs enable Ballerina applications to consume MCP services, there's an equally important need for Ballerina developers to create MCP servers that expose their business logic and tools to AI applications. Ballerina's strengths in service-oriented architectures, type safety, and built-in HTTP capabilities make it ideal for building production-ready MCP servers.

## Architecture Overview

### Transport: Streamable HTTP
Similar to the client implementation, the MCP server uses streamable HTTP transport with bidirectional communication:

#### 1. Client → Server Communication
- HTTP POST requests for all client-initiated operations
- Support for both synchronous JSON responses and asynchronous SSE streams
- Stateless request handling with session context management

#### 2. Server → Client Communication  
- Server-Sent Events (SSE) for server-initiated notifications
- Capability-based message routing
- Automatic content negotiation between JSON and SSE responses

### Core Components

#### MCP Listener
The `mcp:Listener` wraps Ballerina's HTTP listener with MCP-specific functionality:

```ballerina
listener mcp:Listener mcpListener = check new (9090, 
    serverInfo = {
        name: "Weather MCP Server", 
        version: "1.0.0"
    }
);
```

#### Service Types
Two distinct service patterns accommodate different development preferences:

**Basic Service** - Uses automatic tool discovery:
```ballerina
isolated service mcp:Service /mcp on mcpListener {
    @mcp:McpTool {
        description: "Get current weather conditions"
    }
    remote function getCurrentWeather(string city) returns Weather|error {
        // Implementation
    }
}
```

**Advanced Service** - Manual tool management:
```ballerina
isolated service mcp:AdvancedService /mcp on mcpListener {
    remote isolated function onListTools() returns ListToolsResult|ServerError;
    remote isolated function onCallTool(CallToolParams params) returns CallToolResult|ServerError;
}
```

## Design Strategy
- Stateless HTTP POSTs for all client messages
- Automatic tool discovery from service methods
- Type-safe schema generation from Ballerina types
- Concurrent request handling using Ballerina's actor model
- Ballerina-native concurrency and error handling

## Supported Operations

### `tools/list`  
Returns available tools based on service analysis.

```ballerina
// Basic Service: Automatically discovered from remote functions
// Advanced Service: Manual implementation required
remote isolated function onListTools() returns ListToolsResult|ServerError;
```

### `tools/call`
Executes a specific tool with provided parameters.

```ballerina
// Basic Service: Direct function invocation
// Advanced Service: Routed through onCallTool method
remote isolated function onCallTool(CallToolParams params) returns CallToolResult|ServerError;
```

## Example Usage (Main Function)

### Basic Weather Server
```ballerina
import ballerinax/mcp;

public type Weather record {
    string location;
    decimal temperature;
    string conditions;
};

listener mcp:Listener mcpListener = check new (9090, 
    serverInfo = {
        name: "Weather MCP Server",
        version: "1.0.0"
    }
);

isolated service mcp:Service /mcp on mcpListener {
    
    @mcp:McpTool {
        description: "Get current weather conditions for a location"
    }
    remote function getCurrentWeather(string city, string? country) returns Weather|error {
        return {
            location: city,
            temperature: 22.5,
            conditions: "Sunny"
        };
    }
}
```

### Advanced File System Server
```ballerina
import ballerinax/mcp;
import ballerina/io;

isolated service mcp:AdvancedService /mcp on mcpListener {
    
    remote isolated function onListTools() returns mcp:ListToolsResult|mcp:ServerError {
        return {
            tools: [
                {
                    name: "readFile",
                    description: "Read contents of a file",
                    inputSchema: {
                        "type": "object",
                        "properties": {
                            "path": {"type": "string"}
                        },
                        "required": ["path"]
                    }
                }
            ]
        };
    }
    
    remote isolated function onCallTool(mcp:CallToolParams params) returns mcp:CallToolResult|mcp:ServerError {
        string|error path = (params.arguments["path"]).cloneWithType();
        if path is error {
            return error("Invalid argument: " + path.message());
        }
        match params.name {
            "readFile" => {
                string|io:Error content = io:fileReadString(path);
                if content is io:Error {
                    return error mcp:ServerError("Failed to read file");
                }
                return {
                    content: [{"type": "text", "text": content}]
                };
            }
            _ => {
                return error mcp:ServerError(string `Unknown tool: ${params.name}`);
            }
        }
    }
}
```

## Future Plans
- Resource management operations (resources/list, resources/read)
- Prompt template operations (prompts/list, prompts/get)
- Advanced transport support (stdio, WebSocket)
- OAuth2 authentication and session persistence
- Enhanced monitoring and development tooling

## Conclusion
This proposal establishes a comprehensive foundation for MCP server development in Ballerina. The dual service model accommodates different development preferences while the automatic tool discovery reduces boilerplate code. Combined with Ballerina's type safety and HTTP capabilities, this implementation positions Ballerina as an ideal platform for building AI-enabled services and tools in enterprise environments.
