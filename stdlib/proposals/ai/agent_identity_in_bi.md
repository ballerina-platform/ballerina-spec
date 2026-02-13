# Agent Identity in BI
- Authors
    - @kalaiyarasiganeshalingam
- Reviewed by
    - @shafreenAnfar, @MohamedSabthar
- Created date
    - 2026-02-05
- Issue
    - [1425](https://github.com/ballerina-platform/ballerina-spec/issues/1425)
- State
    - Submitted

## Summary

This document proposes introducing Agent Identity as a first-class concept in Ballerina AI Agents. By assigning each agent a distinct digital identity, agents can be authenticated, authorized, governed, and audited independently of applications or users. This enables secure autonomous operation, aligns agent behavior with enterprise security and compliance requirements, and allows organizations to apply consistent identity and access management practices to AI agents in the same way they do for applications, services, and human users.

## Goals

The primary goal of this proposal is to enable secure, governed, and auditable autonomous execution of Ballerina AI Agents through a first-class Agent Identity model. Specifically, this design aims to:
- Establish unique, first-class identities for AI agents, distinct from applications, services, or human users.
- Enable agent-specific authentication and authorization when accessing protected resources.
- Support fine-grained, least-privilege access control aligned with Zero Trust security principles.

## Motivation

As AI agents evolve from assistive tools to autonomous actors, the lack of a robust identity model poses a significant risk. Today, Ballerina AI Agents rely on shared or application-level credentials, making it difficult to distinguish agent actions from those of applications or human users. This blurs security boundaries and limits effective governance.

Shared credentials often lead to over-privileged access and increase the impact of security incidents. They also prevent organizations from enforcing agent-specific policies or clearly tracking agent behavior. As a result, logs cannot reliably attribute actions to individual agents, complicating audits, investigations, and compliance efforts.

Without strong identity, authentication, and authorization guarantees, enabling autonomous agent execution is inherently unsafe. Introducing Agent Identity addresses these challenges by providing clear accountability, controlled access, and improved visibility into agent actions, thereby laying the foundation for secure, reliable, enterprise-grade AI agents in Ballerina.

## Key Concepts

### Understanding Agent Identity vs Application Identity

Traditional systems treat access as originating from either a human user or an application. AI agents do not fit cleanly into either category. Unlike applications, agents can reason, make decisions, and invoke tools dynamically. Unlike users, they can operate continuously without an active session.
Agent Identity introduces a distinct identity model that allows AI agents to be treated as first-class security principals, separate from users and applications. It supports two primary execution models:
- Autonomous Agents: These agents operate independently and use their own identity and permissions. They authenticate using their own credentials and are authorized based on agent-specific scopes.
- Delegated Agents:These agents act on behalf of a human user and use delegated authorization flows. Their actions are constrained by the user’s permissions, and a human remains in the loop.

#### High-Level Architecture for Agent Identity

##### Autonomous Agent
![](../../images/autonomus_agent.png)

##### Delegated Agent
![](../../images/delegated_agent.png)

#### Core Components

##### Agent Identity Provider (AIP): Issue an identity token to an AI agent

When an AI agent starts or requires access to protected resources, it requests an identity token from the Agent Identity Provider. The AIP validates the agent’s registration and issues a short-lived, scoped token representing the agent’s identity.
- Manages agent identities
- Issues credentials
- Handles lifecycle operations

##### Authentication Layer: Verify agent identity on every request (Zero Trust).

Each request from an agent must include its identity token. The authentication layer validates the cryptographic signature, issuer, and expiration. Requests without valid credentials are rejected.
- Validates agent credentials
- Supports short-lived tokens

##### Authorization Engine:  Enforce least-privilege access.

After authentication, the authorization engine evaluates whether the agent is allowed to perform the requested action. Policies are resolved from the policy store and evaluated using contextual attributes such as resource, action, environment, and delegation scope.
- Policy-based access control
- Context-aware authorization
- Enforces least privilege

##### Target Service Invocation & Auditing Flow: Ensure traceability and compliance

All successful and failed operations are recorded by the audit layer, ensuring that every action is attributable to a specific agent identity.
- Stores agent access policies
- Supports conditional rules
- Logs agent actions
- Supports compliance reporting

### Why Agent-Specific Identity?
Using shared or application-level credentials for AI agents introduces several risks and limitations:
- Loss of Accountability: When agents share credentials with applications or other agents, it becomes impossible to determine which agent performed a specific action. This makes audits, investigations, and compliance reporting unreliable. Agent Identity ensures that:
  - Each action can be traced to a specific agent
  - Agent behavior can be monitored independently
  - Responsibility is clearly defined
- Over-Privileged Access: Shared credentials typically require broad permissions to support multiple use cases. This violates least-privilege principles and increases the impact of security incidents. With Agent Identity:
  - Each agent receives only the permissions it needs
  - Access can be restricted to specific services or tools
  - The blast radius of a compromised agent is minimized
- Unsafe Autonomous Execution: Autonomous agents can execute actions without continuous human oversight. Without strong identity, authentication, and authorization guarantees, such autonomy is unsafe. Agent Identity provides the necessary controls to:
  - Authenticate agents explicitly
  - Authorize each action based on scopes
  - Enforce Zero Trust principles for every request

### BI Agent Execution Flow

A BI agent executes actions via tools that abstract different execution mechanisms. As shown in the diagram, a single agent can invoke multiple types of executable functions depending on how the tool is defined.

![](../../images/execution_flow.png)

### Autonomous Agent Identity in BI

The Ballerina Agent Identity model is protocol-independent and applies uniformly across all agent interaction patterns supported by Ballerina, including MCP integration, local tools, external endpoint integrations, chat agents, and agent toolkits. Regardless of how an agent interacts with a system, identity and authorization are enforced consistently.

![](../../images/bi_agent_identy_flow.png)

When acting on its own, the AI agent uses its Agent ID and Agent Secret to authenticate with the authorization server and obtain an access token.

![](../../images/authentication_flow.png)

### Token Management

To enforce least-privilege access, the agent does not use a single, broad token for all tools. Instead, the agent obtains tool-scoped access tokens and manages them using a Token Manager.
#### Token Acquisition per Tool
- When the agent needs to execute a tool, it requests an access token only with the scopes required by that specific tool.
- This ensures the agent has no additional permissions beyond what the tool needs.
- The obtained token is stored in the Token Manager, indexed by the tool and its required scopes.

#### Token Reuse and Expiry Handling
- If the same tool is executed again, the agent first checks the Token Manager.
- If a valid (non-expired) token for that tool already exists, the agent reuses the existing token.
- If the token has expired:
  - The agent requests a new token with the same tool scopes.
  - The Token Manager updates the stored token.
  - This avoids unnecessary token requests while preserving security.

## Design

### Agent Configuration

To support secure, autonomous operation, a new AuthConfiguration is introduced. 

```
# Represents the auth configuration of an autonomous agent.
@display {label: "Auth Configuration"}
public type AuthConfig record {|

   # The OAuth 2.0 token endpoint of the authorization server
   @display {label: "Token URL"}
   string tokenUrl;

   # The unique identifier of the agent used for authentication
   @display {label: "Agent ID"}
   string agentId;

   # The secret associated with the agent identity
   @display {label: "Agent Secret"}
   string agentSecret;

   # The redirect URI registered for the agent client
   # and used in authorization code–based OAuth flows.
   @display {label: "Redirect URI"}
   string redirectUri;
|};
```

The existing AgentConfiguration is optionally extended to include agent identity configuration. This enables the agent runtime to determine whether OAuth-based authentication is required when interacting with secured resources.

```
# Provides a set of configurations for the agent.
@display {label: "Agent Configuration"}
public type AgentConfiguration record {|


   # ...
   # Existing agent configuration fields
   # …


   # Defines the authentication configuration that represents
   # the OAuth 2.0 identity used by the agent at runtime.
   @display {label: "Authentication Configuration"}
   AuthConfig auth?;
|};
```

### AgentTool

Introduces an optional scopes parameter in the ToolAnnotationConfig to define the OAuth 2.0 scopes required to invoke a tool.

```
# Defines the configuration of the Tool annotation.
public type ToolAnnotationConfig record {|
  # ...
  # Existing agent configuration fields
  # …
 
  # Scopes required to invoke this tool
  @display {label: "Required Scopes"}
  string|string[] scopes?;
|};
```
### Token Management

The Ballerina cache module is used for token management by caching access tokens per tool to avoid unnecessary token requests.
A cache instance is initialized with a capacity equal to the number of tools:
cache:Cache cache = new(capacity = toolSize);

Key: Tool name
Value: Token metadata object
```
{
  "access_token": "<token>",
  "scope": "openid",
  "token_type": "Bearer",
  "expires_in": 3600
}
```

### MCP

#### client

The MCP client includes an access token in each request to the MCP server using the **Authorization: Bearer <token>** header. 

#### Server

The MCP Server enforces authentication and authorization for incoming requests using OAuth2 token introspection or JWKS. The `mcp:ServiceConfig` already uses `http:HttpServiceConfig`. Since this configuration supports `http:ListenerAuthConfig`, we will use it to handle the security requirements.

#### Tool

Introduces an optional scopes parameter in the McpToolConfig. The scopes field defines the OAuth scopes required to invoke a specific tool.

```
# Represents a tool configuration that can be used to define tools available in the MCP service.
public type McpToolConfig record {|
   # ...
   # Existing agent configuration fields
   # …


   # Scopes required to invoke this tool
   @display {label: "Required Scopes"}
   string|string[] scopes?;
|};

```

Use existing tool annotation for MCP
```
# Annotation to mark a function as an MCP tool configuration.
public annotation McpToolConfig Tool on object function;
```

### Audit & Logging (Log agent actions)

Operational logs will be handled using the Ballerina log module.

```
[ballerina.log]
level = "INFO"
format = "logfmt"

[[ballerina.log.destinations]]
path = "./logs/app.log"

# Configure root logger with TIME_BASED rotation
# Logs will rotate based on file age
[ballerina.log.destinations.rotation]
policy = "TIME_BASED"
maxAge = 86400
maxBackupFiles = 5
```

#### Log Definitions for Agent Identity

##### INFO
Use INFO for expected, successful, and traceable agent operations.
```
log:printInfo(
  "Agent tool executed successfully",
  agentId = "agent-123",
  toolName = "createUser",
  scopes = "user:create",
  authResult = "allowed"
);
```

##### WARN
Use WARN for unexpected but recoverable situations that do not immediately break execution.
```
log:printWarn(
  "Agent authorization denied",
  agentId = "agent-123",
  toolName = "deleteUser",
  requiredScopes = "user:delete",
  authResult = "denied",
  reason = "missing_scope"
);
```

##### ERROR
Use ERROR for critical failures where the agent cannot proceed.
```
log:printError(
"Agent identity enforcement failed",
agentId = "agent-123",
toolName = "createUser",
error = "token_validation_failed"
);
```

## Example 

#### MCP Service
```aidl
import ballerina/mcp;
import ballerina/http;

// MCP listener
listener mcp:Listener securedMcpListener = check new (9091);

// MCP service with auth (introspection + scope)
@ServiceConfig {
   info: {
       name: "Secured Weather Server",
       version: "1.0.0"
   },
   httpConfig: {
      auth: [
          {
              OAuth2IntrospectionConfigWithScopes: {
                  oauth2IntrospectionConfig: {
                    url : "https://localhost:9445/oauth2/introspect"
                  },
                  scopes: ["weather:read", "weather:update"]
              }
          }
      ]
  }
}
service mcp:Service /mcp on securedMcpListener {

   @mcp:Tool {
       description: "Get current weather for a city",
       scopes: "weather:xxxx"
   }
   remote function getCurrentWeather(string city) returns json|error {
       return {
           location: city,
           temperature: 28.0,
           condition: "Clear"
       };
   }
}

```
#### Agent with MCP tools

```aidl
import ballerina/ai;
import ballerina/io;

final ai:McpToolKit weatherMcpConn = check new ("http://localhost:9090/mcp");

final ai:Agent weatherAgent = check new (
  systemPrompt = {
      role: "Weather-aware AI Assistant",
      instructions: string `You are a smart AI assistant that can assist
          a user based on accurate and timely weather information.`
  },
  tools = [weatherMcpConn],
  model = check ai:getDefaultModelProvider(),
  auth = {
      tokenUrl: "https://localhost:9445/oauth2/token",
      clientId: "weather-agent",
      clientSecret: "weather-agent-secret",
      redirectUri: "https://localhost:8001/callback"
  }
);

public function main() returns error? {
   while true {
       string userInput = io:readln("User (or 'exit' to quit): ");
       if userInput == "exit" {
           break;
       }
       string response = check weatherAgent.run(userInput);
       io:println("Agent: ", response);
   }
}
```