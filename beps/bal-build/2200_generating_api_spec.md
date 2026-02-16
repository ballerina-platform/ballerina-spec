# Introduce a Build-Time Flag for Service Information Extraction and Relevant Specification Generation

- Authors - Niduni Kasige
- Reviewed by - Bhashinee Nirmali 
- Created date - 2026-02-11
- Updated date - 2026-02-14
- Issue - [#1437](https://github.com/ballerina-platform/ballerina-spec/issues/1437)
- State - Submitted

## Summary
This proposal introduces a new capability to the `bal build` command that enables cloud platforms, such as Devant, to automatically discover and consume service and endpoint metadata directly from a Ballerina project during the build process.Currently, Devant requires users to manually provide configuration details such as base paths, ports, protocols, and protocol-specific specifications (e.g., GraphQL schemas, gRPC proto definitions) when deploying services. The proposed enhancement adds a new build flag that analyzes project source code and extracts relevant service metadata, including protocol types (HTTP, GraphQL, gRPC, WebSocket, MCP, etc.), exposed ports, and base paths. This information will be generated in YAML format as part of the build output. Additionally, the corresponding protocol specifications will be emitted to the target directory to support service visualization and testing.

## Motivation
The current `bal build` command does not provide a mechanism to extract server and service metadata for service types such as GraphQL, gRPC, WebSocket, MCP, and others, forcing developers to manually define endpoint configuration details like base paths, ports, and protocol-specific settings when deploying their services to platforms such as Devant. Additionally, there is no standardized way to programmatically identify and extract information about service methods for these service types such as GraphQL operations, gRPC service definitions, WebSocket resources, or MCP tools, making it difficult for cloud platforms to fully automate service deployment. This manual and repetitive process increases the likelihood of configuration mismatches, adds unnecessary effort during build and deployment, and creates duplication between application code and infrastructure configuration, highlighting the need for a build-time metadata extraction capability to enable seamless automation and a better developer experience. 

## Goals

- Automate the extraction of endpoint configuration details such as base paths, ports, listener configurations, and service types directly from the source code without requiring manual user input.

- Automate the extraction of service level metadata, including resource methods, remote methods, schema definitions, and protocol-specific constructs (e.g., GraphQL operations, gRPC RPC methods).

- Generate and export the extracted metadata during compile time in a structured and standardized format that can be consumed by external platforms such as Devant.

## Design
To achieve the above goals, the following build flag is proposed 

```shell 
--export-service-spec
```

To extract core service details such as base paths, ports, and protocols, this proposal introduces a new compiler plugin along with compile-time specification generation support in the standard libraries of each protocol. These components are activated when the new flag is provided to the bal build command. 

The compiler plugin introduced, will analyze the Ballerina syntax tree and semantic model to identify service declarations and listeners. The extraction logic will rely on the ballerina compiler API (for syntax tree nodes and semantic analysis) to ensure accuracy and consistency with the actual compiled program.

In addition, protocol-specific standard libraries (e.g., GraphQL, gRPC) will be enhanced to generate the relevant specifications at compile time, such as GraphQL schemas or gRPC proto definitions, so they can be included in the build output. 

 ### Endpoint configuration information extraction

When the flag is enabled, endpoint-related information such as base paths, ports, and protocol types will be extracted and dumped into a YAML file (e.g., service-spec.yaml). The newly introduced compiler plugin, will inspect service declarations and associated listener instantiations to derive these information.

Example Ballerina source:

``` ballerina
import ballerina/websocket;
import ballerina/io;

int port = 8094;

service /basic/ws on new websocket:Listener(port) {
  resource function get .() returns websocket:Service|websocket:Error {
      return new WsService();
  }
}
 
service class WsService {
   *websocket:Service;
  
   remote function onTextMessage(websocket:Caller caller, string data) returns websocket:Error? {
       io:println(data);
       check caller->writeTextMessage(data);
   }
}
```

From the above source, the following server metadata will be extracted:

```yaml
services:
- basePath: "/basic/ws"
  port: 8094
  type: "websocket"

```

 ## Targeted Protocol Specification Extraction

 In addition to endpoint metadata, protocol-specific service information will also be extracted and exported in their respective standard formats (GraphQL schema or gRPC proto definitions, etc.) using the ballerina standard library support.

#### GraphQL

For GraphQL services, schema-related information such as queries, mutations, subscriptions, input types, output types, and documentation strings will be derived from the source code and emitted as a .graphql schema file.

Example exported GraphQL schema:

```graphql
type Query {
  """
  A resource for generating greetings
  Example query:
  query GreetWorld{ 
  greeting(name: "World") 
  }
  Curl command: 
  curl -X POST -H "Content-Type: application/json" -d '{"query": "query GreetWorld{ greeting(name:\"World\") }"}' http://localhost:8090
  """
  greeting(
    "the input string name"
    name: String!
  ): String!
}

type Mutation {
  createUser(name: String!): String!
}
```

#### gRPC

For gRPC services, service definitions including RPC methods and message types will be extracted from the generated proto descriptors and exported as a .proto file. 

Example exported .proto file:

``` proto
syntax = "proto3";

package helloworld2;

service Greeter {
  rpc sayHello(HelloRequest) returns (HelloReply);
}

service User {
  rpc getUser(UserName) returns (UserReply);
}

message HelloRequest {
  string name = 1;
}

message HelloReply {
  string message = 1;
}

message UserName {
  string name = 1;
}

message UserReply {
  string userMsg = 1;
}
```
#### Other Service Types

A similar approach will be applied to other service types such as WebSocket, etc. Support for additional protocols will be introduced iteratively, following a consistent extraction and export pattern. The overall design ensures extensibility so that new service types can be integrated without modifying the external interface of the feature.

## Testing
- Manual testing will be done to verify the functionality of the newly introduced flag.


## Dependencies
The implementation of the compiler plugin, is dependent on
- Jackson YAML - Used to serialize extracted endpoint and service metadata into a structured YAML file format.
- Google Protocol Buffers Java library (com.google.protobuf) - Used to parse and process the proto descriptor strings.

And the following Ballerina standard libraries will be affected.
- ballerina/http
- ballerina/graphql
- ballerina/websocket
- ballerina/grpc

## Future Work
Future work includes,
- Extending support of the compiler plugin to additional protocol types (e.g., TCP, UDP, and other protocol-based services).
- Add compile-time specification generation and dumping support to the standard library of each newly supported protocol.
