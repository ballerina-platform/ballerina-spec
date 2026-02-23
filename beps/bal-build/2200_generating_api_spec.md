# Introduce a Build-Time Flag for Service Information Extraction and Relevant Specification Generation

- Authors - Niduni Kasige
- Reviewed by - Bhashinee Nirmali 
- Created date - 2026-02-11
- Updated date - 2026-02-23
- Issue - [#1437](https://github.com/ballerina-platform/ballerina-spec/issues/1437)
- State - Submitted

## Summary
This proposal introduces a new capability to the `bal build` command that enables cloud platforms, such as Devant, to automatically discover and consume service and endpoint metadata directly from a Ballerina project during the build process.Currently, Devant requires users to manually provide configuration details such as base paths, ports, protocol types, and protocol-specific specifications (e.g., GraphQL schemas, gRPC proto definitions) when deploying services. The proposed enhancement adds a new build flag that enables analysing the service information and relevant spec generation from the protocol relevant tool.

## Motivation
The current `bal build` command does not provide a mechanism to extract server and service metadata for service types such as GraphQL, gRPC, WebSocket, MCP, and others, forcing developers to manually define endpoint configuration details like base paths, ports, and protocol-specific settings when deploying their services to platforms such as Devant. Additionally, there is no standardized way to programmatically identify and extract information about service methods for these service types such as GraphQL operations, gRPC service definitions, WebSocket resources, or MCP tools, making it difficult for cloud platforms to fully automate service deployment. This manual and repetitive process increases the likelihood of configuration mismatches, and adds unnecessary effort during build and deployment, highlighting the need for a build-time metadata extraction capability to enable seamless automation and a better developer experience.

## Goals

- Automate the extraction of endpoint configuration details such as base paths, ports, listener configurations, and service types directly from the source code without requiring manual user input.

- Automate the extraction of service level metadata, including resource methods, remote methods, schema definitions, and protocol-specific constructs (e.g., GraphQL operations, gRPC RPC methods).

- Generate and export the extracted metadata during compile time in a structured and standardized format that can be consumed by external platforms such as Devant.


## Design
To extract core service details such as base paths, ports, and protocols, this proposal introduces a generic build-time mechanism in Ballerina to automatically extract and export endpoint details for all service types. This approach is conceptually similar to how OpenChoreo requires component endpoint details to describe a workload.
The proposed enhancement introduces a new CLI flag to bal build command.

```shell
--export-endpoints
```

#### Proposed Build-Time Artifact Generation

When the flag is enabled, the build process will:
- Analyze all defined services and listeners.

- Extract endpoint metadata (base paths, ports, protocols etc.) and generate protocol-specific schema artifacts using the respective tooling support.

- Produce standardized `endpoint.yaml` files per endpoint.

- Dump all generated schemas and metadata artifacts into the `target/` directory.

 ### Endpoint configuration information extraction

When the flag is enabled, the endpoint details will be extracted and serialized into a .yaml file. This file is generated for each endpoint, which is similar to workload.yaml which is committed in openchoreo. 

A sample `endpoint.yaml` file:

```yaml
# Endpoints define the network interfaces that this workload exposes to other services
endpoints:
    basePath: "/probes"
    port: 9090
    # Allowed values: REST, GraphQL, gRPC, TCP, UDP, HTTP, Websocket
    type: REST
    schemaFile: openapi.yaml
```

 ## Targeted Protocol Specification Extraction

 In addition to endpoint metadata, protocol-specific schema will also be exported in their respective standard formats (GraphQL schema or gRPC proto definitions, etc.) using the ballerina standard library support of each protocol.

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

And the following Ballerina standard libraries will be affected.
- ballerina/http
- ballerina/graphql
- ballerina/websocket
- ballerina/grpc

## Future Work
Future work includes,
- ntegrate the new build flag capability into the standard library implementations of all newly supported protocols (in Devant).
