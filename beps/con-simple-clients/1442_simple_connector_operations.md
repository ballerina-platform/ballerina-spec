# 1442: Simple Connector Operations for Ballerina

- Authors
  - Thisaru Guruge
- Reviewed by
  - Danesh Kuruppu
  - Sameera Jayasoma
  - Hasitha Aravinda
- Created date
  - 2026-03-23
- Updated date
  - 2026-03-23
- Issue
  - [1442](https://github.com/ballerina-platform/ballerina-spec/issues/1442)
- State
  - Draft

## Summary

This proposal introduces a simplified connector client pattern for Ballerina connectors, alongside a mechanism to
annotate curated, high-level remote methods for tooling discoverability. The goal is to reduce the cognitive load of
working with connectors that expose tens to hundreds of auto-generated resource functions, by providing a separate
operation client with a small set of well-known, commonly-used operations. This pattern directly improves the
experience in low-code environments (Ballerina Integrator), Ballerina Workflows, and even the traditional code-first
development.

## Motivation

Ballerina currently has approximately 500 connectors, most of which are generated from OpenAPI specifications using the
Ballerina OpenAPI tool. For each resource defined in the OpenAPI specification, a corresponding Ballerina resource
(or remote) function is generated in the connector client. While this approach provides comprehensive API coverage, it
introduces significant complexity:

1. **Discoverability** -- Connector clients expose 10-100+ resource functions. Developers must sift through all of them
   to find the operation they need. For example, the Gmail connector exposes 32 resource functions with verbose paths
   like `/users/[userId]/messages/[id]/modify`, while most users only need a handful of operations such as send, list,
   read, and reply.

2. **Low-code experience** -- In Ballerina Integrator, the visual designer presents all resource functions in a flat
   list. Resource function signatures with embedded path segments (e.g.,
   `users/[string userId]/messages/[string id]/trash`) render poorly in graphical environments and are difficult to
   scan or search.

3. **Workflow integration** -- Ballerina Workflows require atomic, well-defined operations. A curated set of operations
   with clear names and simplified parameters is far more suitable for workflow steps than raw API endpoints.

4. **Documentation** -- Auto-generated documentation for connectors with 50+ functions is hard to navigate. Users
   struggle to identify which function to call for common tasks.

5. **AI and tooling** -- AI assistants and IDE tooling perform better when the operation surface is small and
   semantically clear, rather than a flat list of REST-style resource paths.

### How Other Integration Platforms Solve This

Leading integration platforms address this problem by curating a finite set of named operations for each connector,
rather than exposing the full underlying API surface.

#### MuleSoft (Anypoint Connectors)

MuleSoft uses the term **Operations** for outbound actions and **Sources** for inbound/event-driven endpoints.
Connector developers explicitly define each operation as a Java method registered via the `@Operations` annotation on
a configuration class. Each operation can carry metadata annotations such as `@DisplayName`, `@Summary`, `@Alias`, and
`@Throws` to control how it appears in Anypoint Studio.

Operations are not auto-generated from the full API -- the connector developer curates which API endpoints become
operations, providing user-friendly names and simplified parameter sets.

- [MuleSoft Operations SDK](https://docs.mulesoft.com/mule-sdk/latest/operations)
- [MuleSoft Sources SDK](https://docs.mulesoft.com/mule-sdk/latest/sources)
- [MuleSoft Module Structure](https://docs.mulesoft.com/mule-sdk/latest/getting-started)

#### Workato (Connector SDK)

Workato uses the terms **Actions** (outbound operations) and **Triggers** (inbound events). Each action is defined
as a structured block with explicit metadata fields: `title`, `subtitle`, `description`, `help`, `input_fields`,
`output_fields`, `execute`, and `sample_output`. Actions are typically named following a verb-noun pattern
(e.g., "Create record", "Search records", "Update record").

Connector authors hand-craft which operations to expose, with user-friendly labels, help text, and pick lists.
There is no automatic import of an entire API surface.

- [Workato Connector SDK](https://docs.workato.com/developing-connectors/sdk.html)
- [Workato Actions Reference](https://docs.workato.com/developing-connectors/sdk/cli/reference/actions.html)
- [Workato Triggers Reference](https://docs.workato.com/developing-connectors/sdk/cli/reference/triggers.html)

#### Boomi (AtomSphere)

Boomi uses the term **Connector Operation** paired with a standardized **Action** type. Each connector supports a
subset of a fixed set of action verbs: **Get**, **Send**, **Query**, **Create**, **Update**, **Upsert**, **Delete**,
and **Execute**. The connector developer implements which of these standard actions are available, constraining the
operation surface to a predictable, uniform set across all connectors.

Object types are typically discovered dynamically via "Browse" functionality where the user selects an object type
(e.g., "Account", "Contact") and the connector auto-generates the profile/schema.

- [Boomi Connectors Overview](https://help.boomi.com/docs/atomsphere/integration/connectors/c-atm-connectors_bb305b35-0b8b-4e5b-82e5-3e05011b1557)
- [Boomi Connector Operations](https://help.boomi.com/docs/atomsphere/integration/connectors/c-atm-connector_operations_e767ada2-537e-4710-9498-06ac6b6e08e7)

#### Microsoft Power Automate (Custom Connectors)

Power Automate uses **Actions** (outbound operations) and **Triggers** (inbound events). Connectors are defined using
OpenAPI 2.0 specifications. Each action has metadata including `Summary`, `Description`, `Operation ID`, and notably a
`Visibility` property that controls how the action appears in the designer:

- `important` -- always shown first to the user
- `none` -- displayed normally
- `advanced` -- hidden under an "advanced" menu
- `internal` -- hidden from the user entirely

This visibility-based curation mechanism lets connector authors prioritize common operations while still exposing the
full API surface for advanced users.

- [Power Automate - Create from Blank](https://learn.microsoft.com/en-us/connectors/custom-connectors/define-blank)
- [Power Automate - Create from OpenAPI](https://learn.microsoft.com/en-us/connectors/custom-connectors/define-openapi-definition)

#### Summary of Industry Approaches

| Aspect                  | MuleSoft                   | Workato                   | Boomi                        | Power Automate      |
| ----------------------- | -------------------------- | ------------------------- | ---------------------------- | ------------------- |
| **Outbound ops term**   | Operations                 | Actions                   | Connector Operations         | Actions             |
| **Inbound/event term**  | Sources                    | Triggers                  | Scheduled processes          | Triggers            |
| **Definition approach** | Java annotations           | Ruby hash structure       | Standard action verbs        | OpenAPI + wizard UI |
| **Curation mechanism**  | Developer codes operations | Developer defines actions | Fixed verb set per connector | Visibility property |
| **Metadata**            | `@DisplayName`, `@Summary` | `title:`, `description:`  | Action type enum             | Summary, Visibility |

## Goals

- Define a standard pattern for creating simplified connector clients with curated operations alongside existing
  full-API clients.
- Introduce an annotation mechanism to mark remote methods as curated connector operations, enabling tooling, IDE,
  and low-code environments to filter and prioritize them.
- Ensure backward compatibility -- existing connectors and their full-API clients remain unchanged and available for
  advanced use cases.
- Enable AI-driven automated generation of operation clients as an additional step in the existing connector generation
  workflow.

## Non-Goals

- Replacing or deprecating the existing OpenAPI-generated clients. The full client remains the "advanced" client for
  users who need complete API access.
- Defining a fixed set of standard operation verbs (unlike Boomi). Operation names are connector-specific and chosen by
  the connector author to best represent the service's domain.
- Introducing triggers or event sources as part of this proposal. This proposal focuses solely on outbound operations.

## Design

### Overview

The simple connector operations pattern consists of three parts:

1. **Operations Client** -- A new client class (e.g., `gmail:Operations`) that exposes a curated set of remote methods
   representing the most commonly used operations.
2. **Operation Annotation** -- An annotation mechanism applied to each curated remote method, enabling tooling to
   discover and filter operations from regular methods.
3. **Advanced Client Access** -- The operations client provides an `advanced()` method that returns the underlying
   full-API client for advanced use cases.

### Why a Separate Client? (Two-Client Approach)

The decision to introduce a _separate_ operations client alongside the existing generated client is deliberate and
addresses two fundamental issues that simpler approaches cannot solve. See the [Alternatives](#alternatives) section
for the rejected approaches and detailed reasoning.

In summary, the two-client approach is chosen because:

- **Preserves remote-ness** -- Operations are `remote` methods on a client object, maintaining Ballerina's core
  philosophy that network calls are always visible in the code and in diagrams.
- **Isolates generated code from hand-crafted code** -- The existing `Client` is auto-generated from OpenAPI specs and
  can be regenerated without risk of overwriting curated operations. The operations client lives in a separate file and
  is maintained independently.
- **Clean separation for tooling** -- The Language Server and other tools do not need special logic to differentiate
  curated operations from raw API methods. All methods on the operations client are curated; all methods on the
  advanced client are generated.

### Annotating Operations

Curated remote methods on the operations client need to be annotated so that tooling (Ballerina Integrator, Workflows,
IDEs, AI assistants) can programmatically identify and surface them. Two approaches were evaluated for this.

#### Approach 1: Extend the `@display` Annotation

The existing `@display` annotation already provides UI metadata for Ballerina symbols. Its current definition is:

```ballerina
public const annotation record {
    string label;
    string iconPath?;
    "text"|"password"|"file" kind?;
} display on source type, source class,
      source function, source return, source parameter, source field,
      source listener, source var, source const, source annotation,
      source service, source external, source worker;
```

This approach extends `@display` with an additional field to classify the role of the annotated symbol:

```ballerina
public const annotation record {
    string label;
    string iconPath?;
    "text"|"password"|"file" kind?;
    # The role of this symbol in integration tooling.
    # - "operation": A curated connector operation surfaced in low-code and workflow environments.
    "operation" role?;
} display on source type, source class,
      source function, source return, source parameter, source field,
      source listener, source var, source const, source annotation,
      source service, source external, source worker;
```

Usage:

```ballerina
    # Sends an email message.
    @display {label: "Send Email", role: "operation"}
    isolated remote function send(
            @display {label: "To"}
            string|string[] to,
            @display {label: "Subject"}
            string subject
    ) returns Message|error {
        // ...
    }
```

**Advantages:**

- No new annotation -- reuses an existing, well-understood mechanism.
- `@display` is already about how tooling presents symbols; classifying a method's role is a natural extension.
- Tooling already reads `@display`; adding `role` support is incremental.
- The `role` field is a string union, making it extensible for future roles (e.g., `"trigger"`) without additional
  annotations.

**Disadvantages:**

- `@display` is fundamentally about _presentation_ (labels, icons, input widget types). Adding a `role` field that
  controls _filtering and inclusion_ (i.e., whether a method is surfaced at all) stretches its responsibility.
- The `kind` field already serves a classification purpose (input widget type), and adding `role` as a second
  classification axis may cause confusion about when to use which.
- If operations need richer metadata in the future (e.g., categories, tags, idempotency hints), the `@display` record
  would accumulate fields unrelated to its original purpose.

#### Approach 2: Introduce a New `@operation` Annotation

This approach introduces a dedicated annotation type in `ballerina/lang.annotations`:

```ballerina
# Marks a remote method as a curated connector operation.
#
# Methods annotated with `@operation` are surfaced prominently in low-code environments,
# workflow step selectors, and IDE action lists. They represent the most common and
# well-understood actions a connector provides.
public const annotation Operation on source function;
```

The annotation is a simple marker with no fields. Presentation metadata (`label`, `iconPath`) is provided via the
existing `@display` annotation, which composes naturally:

```ballerina
    # Sends an email message.
    @operation
    @display {label: "Send Email"}
    isolated remote function send(
            @display {label: "To"}
            string|string[] to,
            @display {label: "Subject"}
            string subject
    ) returns Message|error {
        // ...
    }
```

When `@display` is omitted, tooling derives the label from the method name and the description from the Ballerina doc
comment.

**Advantages:**

- Clear separation of concerns: `@operation` answers _"should tooling surface this?"_ (semantic classification),
  while `@display` answers _"how should tooling render this?"_ (presentation).
- Simple marker annotation (like `@deprecated`) -- no fields to configure, no room for misuse.
- Naturally extensible: future annotations like `@Trigger` can follow the same pattern without overloading a single
  annotation.
- Industry alignment: MuleSoft uses `@Operations`, Boomi uses "Connector Operation". The term is well understood in
  the integration domain.

**Disadvantages:**

- Introduces a new platform-level annotation, increasing the annotation surface area.
- In Ballerina, every remote method on a client already performs an "operation" -- annotating some with `@operation`
  is somewhat tautological. The annotation's meaning is "this is a _curated_ operation," but the name does not
  explicitly convey curation.
- Requires tooling to recognize a new annotation rather than extending existing `@display` handling.

**A note on `@action` as an alternative name:** Ballerina's language specification already uses "action" to refer to
remote method call expressions and resource access expressions (e.g., `client->method()` is an "action expression").
Using `@action` as an annotation would create terminology confusion between the language-level concept and the
connector-level concept. `@operation` avoids this ambiguity.

#### Recommendation

Both approaches are viable. The recommendation is to use **Approach 2 (`@operation` as a standalone marker
annotation)** for the following reasons:

1. **Separation of concerns** -- Keeping semantic classification (`@operation`) separate from presentation (`@display`)
   is a cleaner design. Each annotation has a single, well-defined purpose.
2. **Precedent** -- Ballerina already has marker annotations (`@deprecated`) that classify symbols without carrying
   presentation data. `@operation` follows this established pattern.
3. **Future-proofing** -- When triggers, event sources, or other integration concepts need annotation support, each
   gets its own focused annotation rather than accumulating as values in a `@display` field.
4. **Industry clarity** -- "Operation" is an unambiguous term in the integration domain. It works naturally in UI
   contexts: "Select an operation", "Available operations", "Gmail operations".

### Operations Client Pattern

Each connector that adopts this pattern provides two client classes:

1. **`Client`** (existing) -- The full-API client generated from the OpenAPI specification. This uses resource functions
   and provides complete coverage of the underlying API.
2. **`Operations`** (new) -- The simplified client with curated remote methods, each annotated with `@operation`.

#### Client Structure

```ballerina
public isolated client class Operations {
    private final Client advancedClient;

    # Initializes the operations client.
    #
    # + config - Authentication configuration
    public isolated function init(*AuthConfig config) returns error? {
        self.advancedClient = check new ({auth: {...config}});
    }

    # Returns the advanced client for uncommon or complex use cases.
    #
    # Use this when you need access to the full API surface that is not covered
    # by the curated operations.
    #
    # + return - The underlying full-API client
    @display {label: "Advanced Client"}
    public isolated function advanced() returns Client {
        return self.advancedClient;
    }

    # Sends an email message.
    #
    # Use this function to send plain text or HTML emails, with optional CC, BCC, and file attachments.
    # The sender is automatically determined by the authenticated Google account.
    @operation
    @display {label: "Send Email"}
    isolated remote function send(
            @display {label: "To"}
            string|string[] to,
            @display {label: "Subject"}
            string subject,
            @display {label: "Text Body"}
            string? textBody = (),
            @display {label: "HTML Body"}
            string? htmlBody = ()
    ) returns Message|error {
        // Implementation delegates to self.advancedClient
    }

    // ... other curated operations
}
```

### Simplified Configuration

A key benefit of the operations client is a drastically simplified configuration. The existing generated `Client`
typically accepts a `ConnectionConfig` record that exposes the full HTTP client configuration surface -- often 15+
fields covering HTTP versions, compression, circuit breakers, retry policies, proxy settings, and more. Most users
never need to configure these.

The operations client accepts only the fields that are absolutely required for authentication and connection:

```ballerina
// Full ConnectionConfig for the advanced Client -- 15+ fields
@display {label: "Connection Config"}
public type ConnectionConfig record {|
    http:BearerTokenConfig|OAuth2RefreshTokenGrantConfig auth;
    http:HttpVersion httpVersion = http:HTTP_2_0;
    http:ClientHttp1Settings http1Settings = {};
    http:ClientHttp2Settings http2Settings = {};
    decimal timeout = 30;
    string forwarded = "disable";
    http:FollowRedirects followRedirects?;
    http:PoolConfiguration poolConfig?;
    http:CacheConfig cache = {};
    http:Compression compression = http:COMPRESSION_AUTO;
    http:CircuitBreakerConfig circuitBreaker?;
    http:RetryConfig retryConfig?;
    http:CookieConfig cookieConfig?;
    http:ResponseLimitConfigs responseLimits = {};
    http:ClientSecureSocket secureSocket?;
    http:ProxyConfig proxy?;
    http:ClientSocketConfig socketConfig = {};
    boolean validation = true;
    boolean laxDataBinding = true;
|};

// Simplified AuthConfig for the Operations client -- only essential fields
@display {label: "Auth Config"}
public type AuthConfig record {|
    @display {label: "Client ID"}
    string clientId;
    @display {label: "Client Secret"}
    string clientSecret;
    @display {label: "Refresh Token"}
    string refreshToken;
|};
```

The operations client constructs the full `ConnectionConfig` internally from the simplified config, using sensible
defaults for all other fields. The `advanced()` method returns this internally created `Client` instance -- it does
not allow reconfiguring the connection parameters after initialization. Users who need to customize HTTP-level settings
(e.g., timeouts, circuit breakers, proxy configuration) should create a separate `Client` instance directly with the
full `ConnectionConfig`. The `advanced()` method is intended for accessing API operations not covered by the curated
set, not for reconfiguring the underlying connection.

This simplification extends to how the client appears in low-code environments: instead of a form with 15+ fields
(most of which are irrelevant), the user sees only the 2-4 fields they actually need to fill in.

### Operation Naming Convention

Consistent naming across connectors is critical for usability, especially in low-code and workflow environments where
users frequently switch between connectors. The following rules govern operation naming:

#### Rules

1. **MUST be a verb or verb phrase.** Operations represent actions. Use imperative verbs: `send`, `list`, `create`,
   `get`, `update`, `delete`, `search`, `markAsRead`.

2. **MUST NOT repeat the domain entity when it is obvious from the connector context.** The connector module already
   establishes the domain. Repeating the entity is redundant and creates longer, harder-to-scan names.

   | Connector  | Correct  | Incorrect      |
   | ---------- | -------- | -------------- |
   | Gmail      | `send`   | `sendMail`     |
   | Gmail      | `list`   | `listMails`    |
   | Salesforce | `create` | `createRecord` |
   | Slack      | `send`   | `sendMessage`  |
   | S3         | `upload` | `uploadFile`   |

   **Exception:** When a connector operates on multiple entity types, the entity name SHOULD be included to
   disambiguate: e.g., `createContact` vs `createDeal` in a CRM connector that manages both.

3. **SHOULD use consistent verbs across connectors for equivalent actions.** The following standard verbs are
   recommended:

   | Action                     | Standard Verb | Avoid                                    |
   | -------------------------- | ------------- | ---------------------------------------- |
   | Create a new entity        | `create`      | `add`, `insert`, `new`, `make`           |
   | Retrieve a single entity   | `get`         | `fetch`, `retrieve`, `find`, `read`      |
   | Retrieve multiple entities | `list`        | `getAll`, `fetchMany`, `search`, `query` |
   | Update an existing entity  | `update`      | `modify`, `edit`, `patch`, `set`         |
   | Delete an entity           | `delete`      | `remove`, `destroy`, `drop`              |
   | Send a message/payload     | `send`        | `post`, `push`, `emit`, `publish`        |
   | Search with criteria       | `search`      | `find`, `query`, `lookup`, `filter`      |
   | Upload a file/blob         | `upload`      | `put`, `push`, `store`                   |
   | Download a file/blob       | `download`    | `get`, `fetch`, `pull`, `retrieve`       |

   **Note:** `read` is acceptable as an alias for `get` when the domain uses "read" as the standard term (e.g.,
   email: `read` a message). Domain conventions take precedence over this table when the domain term is unambiguous.

4. **SHOULD use camelCase for multi-word operations.** Follow Ballerina's naming conventions: `markAsRead`,
   `moveToTrash`, `replyAll`.

5. **MUST NOT use HTTP-verb-based names.** Operations abstract away the transport layer: `send` not `postMessage`,
   `update` not `patchRecord`.

### Cross-Connector Operation Patterns

To ensure consistency across the connector ecosystem, the following recommended operation sets are defined for common
connector domains. Connector authors SHOULD follow these patterns unless the service's API has strongly established
alternative terminology.

#### Email Connectors (Gmail, Outlook, SendGrid)

| Operation       | Description                           |
| --------------- | ------------------------------------- |
| `send`          | Send an email                         |
| `list`          | List/search messages                  |
| `read`          | Get a single message by ID            |
| `reply`         | Reply to the sender of a message      |
| `replyAll`      | Reply to all recipients of a message  |
| `createDraft`   | Create a draft email                  |
| `markAsRead`    | Mark a message as read                |
| `markAsUnread`  | Mark a message as unread              |
| `moveToTrash`   | Move a message to trash               |
| `getAttachment` | Download an attachment from a message |

#### CRM Connectors (Salesforce, HubSpot, Dynamics 365)

| Operation | Description                                         |
| --------- | --------------------------------------------------- |
| `create`  | Create a new record (contact, lead, account, etc.)  |
| `get`     | Retrieve a single record by ID                      |
| `update`  | Update an existing record                           |
| `delete`  | Delete a record                                     |
| `search`  | Search records with criteria                        |
| `list`    | List records (with optional filters and pagination) |

#### Messaging/Queue Connectors (Slack, Teams, Twilio)

| Operation | Description                             |
| --------- | --------------------------------------- |
| `send`    | Send a message                          |
| `list`    | List messages in a channel/conversation |
| `reply`   | Reply to a specific message             |
| `update`  | Update a sent message                   |
| `delete`  | Delete a message                        |

#### Cloud Storage Connectors (S3, GCS, Azure Blob)

| Operation  | Description                       |
| ---------- | --------------------------------- |
| `upload`   | Upload a file/object              |
| `download` | Download a file/object            |
| `list`     | List files/objects in a container |
| `delete`   | Delete a file/object              |
| `copy`     | Copy a file/object                |

#### Calendar Connectors (Google Calendar, Outlook Calendar)

| Operation | Description                   |
| --------- | ----------------------------- |
| `create`  | Create a calendar event       |
| `get`     | Get event details by ID       |
| `list`    | List events (with date range) |
| `update`  | Update an existing event      |
| `delete`  | Delete an event               |

#### Database Connectors (MySQL, PostgreSQL, DynamoDB)

| Operation      | Description                                |
| -------------- | ------------------------------------------ |
| `query`        | Execute a query and return results         |
| `execute`      | Execute a statement (INSERT/UPDATE/DELETE) |
| `batchExecute` | Execute a batch of statements              |

These patterns are guidelines, not mandates. Connector authors should adapt them when the service's API has strongly
established alternative terminology that would be more recognizable to users of that service.

### Operation Selection Criteria

Deciding which operations to include in an operations client is a deliberate curation process. The following criteria
guide the selection:

#### Target Count

An operations client SHOULD expose **5 to 15 operations**.

- **Below 5** suggests the connector's API surface is already simple enough that an operations client adds little
  value, or the curation is too aggressive. Consider whether the connector warrants an operations client at all.
- **Above 15** dilutes the simplification benefit. If more than 15 operations are needed, consider whether some can
  be served by the advanced client, or whether the connector should be split into multiple focused modules.

#### Coverage Heuristic

Operations SHOULD cover at least **80% of typical use cases** for the connector's domain. The selection is informed by:

1. **API documentation prominence** -- Operations featured in quickstart guides, getting-started tutorials, and
   API overview pages are strong candidates.
2. **Community usage patterns** -- Stack Overflow questions, GitHub issues, and forum discussions reveal which
   endpoints users interact with most.
3. **CRUD coverage** -- The operations client MUST cover the basic create/read/update/delete lifecycle for the
   connector's primary entity (e.g., messages for Gmail, records for Salesforce).
4. **Parameter complexity** -- Endpoints with deeply nested request bodies or complex query parameters are high-value
   targets for simplification, as the operations client can flatten and default them.

#### AI-Assisted Scoring

The AI agent in the generation workflow scores candidate operations on three axes:

- **Popularity** (0-10) -- How frequently is this endpoint referenced in documentation, tutorials, and community Q&A?
- **Simplification potential** (0-10) -- How much can the operation's parameters be simplified compared to the raw
  endpoint? Endpoints with many optional parameters, nested objects, or path segments score higher.
- **Domain essentiality** (0-10) -- Is this operation part of the core workflow for the connector's domain? (e.g.,
  `send` is essential for an email connector; `exportToPDF` is not.)

#### Selection Process

1. **Score threshold** -- Only endpoints scoring **50% or higher** (15+ out of 30) are considered as candidates.
   Endpoints below this threshold are unlikely to justify inclusion in the curated set.

2. **Rank and select** -- From the qualifying candidates, select the top-scoring operations. The number of operations
   selected is proportional to the total number of resource methods in the advanced client:

   | Resource methods in advanced client | Target operations count |
   | ----------------------------------- | ----------------------- |
   | 1-10                                | 3-5                     |
   | 11-25                               | 5-8                     |
   | 26-50                               | 8-12                    |
   | 51-100                              | 10-15                   |
   | 100+                                | 12-15 (cap)             |

   The ratio is intentionally sublinear: a connector with 100 resource methods should not expose 50 operations.
   The purpose of the operations client is simplification, not proportional coverage. This is not a hard rule but a
   generic guide on how to pick a number of operations.

3. **Human review** -- The AI-generated candidate list is reviewed and finalized by a connector maintainer.
   Maintainers may add operations the AI undervalued (e.g., domain-specific operations with low documentation
   frequency but high real-world importance) or remove operations that are too niche for the curated set.

### Design Principles for Operation Methods

1. **Simplified parameters** -- Operation methods should flatten nested request objects into direct parameters. For
   example, instead of accepting a `MessageRequest` record, the `send` operation accepts `to`, `subject`, `textBody`,
   etc. as individual parameters.

2. **Sensible defaults** -- Parameters that have obvious defaults for the common case should use default values. For
   example, `maxResults` defaults to `10` rather than requiring explicit specification.

3. **Domain-specific naming** -- Method names should follow the [Operation Naming Convention](#operation-naming-convention)
   defined above.

4. **Composite operations** -- A single operation may orchestrate multiple underlying API calls to deliver a
   complete result. For example, the Gmail `list` operation first calls the messages list endpoint to retrieve
   message IDs, then calls the message get endpoint for each ID to return full message content. This is a key
   advantage of the operations client over the advanced client: it encapsulates multi-step API workflows into a
   single, atomic remote method call, hiding the orchestration complexity from the user.

5. **Minimal surface area** -- An operations client should expose only the 5-15 most commonly used operations as
   defined by the [Operation Selection Criteria](#operation-selection-criteria). The full API remains accessible via
   `advanced()`.

6. **`@display` annotations** -- All parameters should carry `@display` annotations for proper rendering in low-code
   environments, consistent with existing Ballerina conventions.

7. **Documentation** -- Each operation method should have comprehensive Ballerina doc comments explaining the purpose,
   parameters, and return values in user-friendly, and low-code friendly language.

### Usage Examples

#### Simple Usage (Operations Client)

```ballerina
import ballerinax/googleapis.gmail;

public function main() returns error? {
    gmail:Operations gmail = check new ({
        clientId: "...",
        clientSecret: "...",
        refreshToken: "..."
    });

    // Send an email -- simple, discoverable
    gmail:Message sent = check gmail->send(
        to = "recipient@example.com",
        subject = "Hello from Ballerina",
        textBody = "This is a test email."
    );

    // List recent unread messages
    gmail:Message[] messages = check gmail->list(query = "is:unread", maxResults = 5);

    // Reply to a message
    _ = check gmail->reply(messageId = messages[0].id ?: "", textBody = "Got it, thanks!");

    // Mark as read
    check gmail->markAsRead(messageId = messages[0].id ?: "");
}
```

#### Advanced Usage (Advanced Client Fallback)

```ballerina
import ballerinax/googleapis.gmail;

public function main() returns error? {
    gmail:Operations gmail = check new ({
        clientId: "...",
        clientSecret: "...",
        refreshToken: "..."
    });

    // Use curated operations for common tasks
    _ = check gmail->send(to = "user@example.com", subject = "Test", textBody = "Hello");

    // Fall back to advanced client for uncommon operations
    gmail:Client advanced = gmail.advanced();
    gmail:ListLabelsResponse labels = check advanced->/users/me/labels();
    gmail:ListHistoryResponse history = check advanced->/users/me/history(
        queries = {startHistoryId: "12345"}
    );
}
```

#### Low-Code / Workflow Usage

In Ballerina Integrator and Ballerina Workflows, the operations client surfaces as a clean list of operations:

```
Gmail Operations:
  - Send Email
  - List Messages
  - Read Message
  - Reply
  - Reply All
  - Mark as Read
  - Mark as Unread
  - Move to Trash
  - Create Draft
  - Get Attachment
```

This is in contrast to the advanced client which would display 32 resource functions with complex path signatures.

### Connector Module Structure

A connector module adopting this pattern will have the following structure:

```
ballerina/
  client.bal              # Existing full-API client (generated from OpenAPI)
  operations_client.bal   # New operations client with curated methods
  types.bal               # Shared types
  ...
```

Both clients share the same type definitions. The operations client delegates to the advanced client internally.

### AI-Driven Operation Generation

The existing connector generation workflow already includes an AI-driven pipeline that processes OpenAPI specifications
to generate Ballerina connectors. This pipeline currently handles tasks such as type flattening, documentation
generation, and code quality improvements. This proposal adds an **additional module** to that existing workflow -- not
a separate pipeline -- to generate the operations client.

The updated workflow:

```
OpenAPI Spec
    |
    v
[Existing AI Pipeline]
    |-- [OpenAPI Tool] --> Full Client (client.bal)
    |-- [AI Flattening & Docs] --> Improved types, documentation
    |-- [AI Operations Module] --> Operations Client (operations_client.bal)   <-- NEW
```

The AI operations module performs the following:

1. **Analyze the OpenAPI specification** -- Score each endpoint against the
   [Operation Selection Criteria](#operation-selection-criteria) to identify candidates.

2. **Curate operations** -- Select 5-15 operations that cover the most common use cases, following the
   [Cross-Connector Operation Patterns](#cross-connector-operation-patterns) for the connector's domain.

3. **Generate the operations client** -- Produce `operations_client.bal` with:
   - Simplified remote methods with `@operation` and `@display` annotations
   - Flattened parameters with `@display` annotations
   - Simplified configuration record (authentication-only)
   - Comprehensive doc comments
   - Delegation to the advanced client

4. **Human review** -- The generated operations client is reviewed by a connector maintainer before publishing.

### Rollout Strategy

Operation clients will be introduced incrementally rather than all at once:

1. **Phase 1: High-impact connectors** -- Start with the most-downloaded connectors from Ballerina Central (e.g.,
   Gmail, Slack, Salesforce, GitHub, Google Sheets, Twilio). These connectors have the largest user base and the
   most to gain from simplification. Download counts from Ballerina Central are the primary signal for prioritization.

2. **Phase 2: Expand based on demand** -- Add operations clients for connectors based on user requests, community
   feedback, and download trends. Connectors with fewer than 10 resource functions may not need an operations client.

3. **Phase 3: Community-contributed operations** -- Establish a contribution process for community members to propose
   and submit operations clients for connectors not yet covered.

This incremental approach allows the team to validate the pattern, refine the naming conventions, and iterate on
tooling support before scaling to the full connector ecosystem.

## Alternatives

### Architectural Alternatives

The following alternatives were considered for the overall approach before settling on the two-client pattern.

#### Alternative 1: Simple Functions as APIs

Expose simplified operations as regular (non-remote) module-level functions rather than remote methods on a client.

```ballerina
// Module-level function approach
public function sendEmail(AuthConfig auth, string to, string subject, string body) returns Message|error {
    Client client = check new ({auth});
    return client->/users/me/messages/send.post({to: [to], subject, bodyInText: body});
}
```

**Why rejected:**

- **Breaks the Ballerina philosophy.** A core principle of Ballerina is that network calls are always visible -- the
  `remote` keyword and the `->` call syntax signal that a function performs a remote invocation. Simple (non-remote)
  functions cannot be `remote` functions, so callers cannot tell whether a given function includes a remote call.
- **Breaks the diagram.** Ballerina's sequence diagram view relies on remote method calls to show interactions with
  external services. Simple functions calling remote methods internally would appear as local operations in the
  diagram, hiding the actual network interactions and producing misleading visualizations.
- **No client lifecycle.** Without a client object, there is no natural place to hold connection state, credentials, or
  configuration. Each function call would need to re-initialize or accept connection parameters explicitly.

#### Alternative 2: Simple Operations Within the Existing Client

Add curated remote methods directly to the existing auto-generated `Client` alongside the generated resource functions.

```ballerina
public isolated client class Client {
    // Generated resource functions (32 methods for Gmail)
    resource isolated function get users/[string userId]/messages(...) returns ...;
    resource isolated function post users/[string userId]/messages/send(...) returns ...;
    // ... 30 more generated methods

    // Hand-crafted simple operations added to the same class
    @operation
    isolated remote function send(string to, string subject, string body) returns Message|error { ... }
    @operation
    isolated remote function list(string? query = ()) returns Message[]|error { ... }
}
```

**Why rejected:**

- **Maintenance burden and regeneration conflicts.** The client code is almost always generated from the OpenAPI
  specification using the Ballerina OpenAPI tool. When the OpenAPI spec is updated and the client is regenerated, any
  hand-crafted simple operations added to the same file would be overwritten, requiring manual intervention after
  every regeneration.
- **Increased complexity for tooling.** The Language Server, code completion, and other developer tools would need to
  be smart enough to differentiate simple operations from the generated resource functions within the same client.
  This adds significant complexity to tooling implementations.
- **Cluttered API surface.** Mixing 10 curated operations with 30+ generated resource functions in a single client
  defeats the purpose of simplification. Users would still see all methods in autocomplete and documentation.

#### Why the Two-Client Approach

The chosen two-client approach solves both problems:

- Operations are `remote` methods on a proper `client class`, preserving Ballerina's remote-ness philosophy and
  diagram support.
- The operations client lives in a separate file (`operations_client.bal`) from the generated client (`client.bal`),
  so regeneration of the OpenAPI-based client never touches the curated operations.

### Annotation Alternatives

#### Alternative 3: Visibility-Based Filtering (Power Automate Approach)

Instead of a separate client, mark existing resource functions with visibility levels (e.g., `important`, `advanced`,
`internal`) and let tooling filter the display.

**Why rejected:**

- Does not solve the parameter simplification problem. Resource functions with complex path segments and nested
  request types remain complex.
- Resource function signatures (e.g., `/users/[userId]/messages/[id]/modify`) still render poorly in low-code
  environments regardless of visibility.
- Does not provide a clean, intent-based API for workflows.

#### Alternative 4: Standardized Action Verbs (Boomi Approach)

Define a fixed set of standard operation types (Get, Send, Create, Update, Delete) that all connectors must implement.

**Why rejected:**

- Too restrictive for the diversity of APIs Ballerina connects to. A Gmail connector needs `send`, `reply`,
  `markAsRead` -- these do not map cleanly to generic CRUD verbs.
- Loses domain-specific semantics that make operations self-documenting.
- Would require significant rework of existing connectors.

#### Alternative 5: Using `@action` Instead of `@operation`

Use `@action` as the annotation name, aligning with Workato and Power Automate terminology.

**Why rejected:**

- Ballerina's language specification already uses "action" to refer to remote method call expressions and resource
  access expressions (e.g., `client->method()` is an "action expression"). Using `@action` as an annotation would
  create terminology confusion between the language-level concept and the connector-level concept.
- "Operation" is unambiguous in the Ballerina context and aligns with MuleSoft and Boomi.

#### Alternative 6: Extending `@display` with a `role` Field

Extend the existing `@display` annotation with a `role` field instead of introducing a new `@operation` annotation.
See the [Annotating Operations](#annotating-operations) section for a detailed evaluation of this approach.

**Why not chosen as the primary recommendation:**

- Mixes semantic classification (what role does this method play?) with presentation metadata (how should it be
  rendered?), stretching `@display`'s responsibility.
- However, this remains a viable option if the team prefers to minimize the annotation surface area. The two
  approaches are not mutually exclusive -- `@display` extension could serve as a fallback if introducing a new
  platform-level annotation faces adoption barriers.

## Testing

- **Unit tests** -- Each operations client method should have unit tests verifying correct delegation to the advanced
  client, parameter mapping, and error handling. Each operation should be testable against both the actual endpoint
  and a mock server.
- **Low-code rendering tests** -- Verify that operations clients render correctly in Ballerina Integrator's visual
  designer, including proper display labels, parameter forms, and operation selection lists.
- **Backward compatibility tests** -- The existing connector tests should remain intact for testing the
  advanced client.

## Risks and Assumptions

- **Curation subjectivity** -- Deciding which operations to include in the simplified client is inherently subjective.
  Different users may have different expectations of what constitutes a "common" operation. This is mitigated by:
  - Starting with well-known, high-traffic connectors (Gmail, Slack, Salesforce, etc.) where common operations are
    well-established.
  - Using AI-driven analysis of API documentation and usage patterns to inform curation decisions.
  - Allowing the advanced client as a fallback for any operation not in the curated set.

- **Maintenance overhead** -- Each connector now has two clients to maintain. This is mitigated by:
  - The operations client delegates to the advanced client, so underlying API changes only need to be reflected in the
    generated advanced client.
  - AI-assisted generation reduces the manual effort of creating and updating operations clients.

- **Naming consistency** -- Operation names and parameter names should be consistent across connectors for similar
  functionality (e.g., `send` for email/message sending, `list` for enumeration). The
  [Operation Naming Convention](#operation-naming-convention) and
  [Cross-Connector Operation Patterns](#cross-connector-operation-patterns) sections establish guidelines to be
  enforced during review.

- **Annotation adoption** -- The operation annotation (whether `@operation` or `@display` with `role`) should be
  handled in the tooling including the Language Server.

## Dependencies

- **`ballerina/lang.annotations`** -- Either a new `@operation` annotation will be added, or the existing `@display`
  annotation will be extended with a `role` field. Both options require a platform release.
- **Existing AI-based connector generation workflow** -- The current pipeline already handles OpenAPI-to-Ballerina
  generation, type flattening, and documentation improvements. This proposal adds an operations client generation
  module to that existing workflow.
- **Ballerina Integrator** -- The low-code designer needs to be updated to recognize operation-annotated methods
  and surface them prominently.
- **Ballerina Workflows** -- The workflow runtime needs to support operation-annotated methods as workflow steps.
- **Ballerina Central** -- The operations client (`Operations`) should be displayed with **primary priority** on
  connector pages and search results. The advanced client (`Client`) should remain accessible but presented as a
  secondary option for advanced use cases. This ensures new users discover the simplified experience first.

## Future Work

- **Inbound event support** -- Ballerina uses listeners for inbound event handling, which serve a different
  architectural role than the outbound operations addressed in this proposal. Whether curated, trigger-like
  annotations could complement listeners to improve the low-code experience for event-driven integrations is a
  potential direction for exploration, but the mapping between listener-based and trigger-based models is not
  straightforward and requires separate analysis.
- **Operation categories** -- Introduce optional categorization of operations (e.g., "Messaging", "Management",
  "Analytics") for connectors with more than ~15 operations, to support grouping in UI.
- **Connector quality scoring** -- Develop metrics for operations client quality, such as coverage of common use cases,
  parameter simplicity, and documentation completeness.
- **Auto-generation improvements** -- Evolve the AI agent to learn from user feedback and usage analytics, improving
  operation curation over time.

## References

- [Ballerina Integrator Documentation](https://bi.docs.wso2.com/)
- [Ballerina Workflows](https://central.ballerina.io/ballerina/workflow/latest)
- [MuleSoft Operations SDK](https://docs.mulesoft.com/mule-sdk/latest/operations)
- [Workato Connector SDK](https://docs.workato.com/developing-connectors/sdk.html)
- [Boomi Connector Operations](https://help.boomi.com/docs/atomsphere/integration/connectors/c-atm-connector_operations_e767ada2-537e-4710-9498-06ac6b6e08e7)
- [Power Automate Custom Connectors](https://learn.microsoft.com/en-us/connectors/custom-connectors/define-blank)
- [Gmail Connector - Operations Client (Reference Implementation)](https://github.com/ballerina-platform/module-ballerinax-googleapis.gmail)

[]: # Please add any comments to issue [#1442](https://github.com/ballerina-platform/ballerina-spec/issues/1442)
