# Data service generation for bal persist

- Author: @niveathika
- Reviewers: 
- Created: 2026-09-18
- Updated: 2026-10-21
- Issue: [#1503](https://github.com/ballerina-platform/ballerina-spec/issues/1503)
- Status: Submitted

## Summary

This proposal lets `bal persist` generate a data service over an existing persist model. The
user adds one options group to the existing `[[tool.persist]]` entry, naming the protocol, and
marks each entity to expose with `@dataservice:Expose` in the model. The tool then generates a
listener and a service alongside the persist client.

```
bal persist add --datastore postgresql --dataservice http
# write persist/model.bal and annotate the entities to expose, or bal persist pull
bal build                     # client and data service are generated
```

The service has a fixed CRUD shape: six operations per entity, grouped into four actions. This
proposal defines that shape, how the tool is configured and how it behaves. It does not define
how each protocol renders the shape. That is left to follow-up proposals for HTTP, GraphQL and
MCP, listed under [Future work](#future-work).

This is proposal 1 of 4.

Please add any comments to issue [#1503](https://github.com/ballerina-platform/ballerina-spec/issues/1503).

## Goals

- Generate a working data service from an existing persist model, with no hand-written service
  code.
- Define one protocol-neutral CRUD shape that every protocol renders.
- Configure the service through the existing `[[tool.persist]]` entry and existing commands. No
  new `bal persist` command.
- Let the model choose which entities are exposed and what each allows, using annotations that
  are checked at compile time.
- Leave persist's behaviour unchanged when no data service is configured.
- Fix the parts of the contract that later features (query options, auth, relations) would
  otherwise break: the response envelope, the action names, the addressing scheme, the write
  results and the error categories.

## Non-goals

- Query options: filtering, sorting, paging, field selection and count.
- Relations: embedded reads, relation routes and nested writes.
- Authentication and authorization.
- Write operations the persist client does not provide: upsert, full replace, and update or
  delete by filter.
- Exposing several protocols from one entry.
- A data service in a module other than the package's default module, or over more than one
  persist model.
- OData and SOAP.

All of these are in the roadmap under [Future work](#future-work). The design below reserves
room for each so that adding them does not break v1 services.

## Motivation

A persist model already describes the entities, their keys and their types, and the generated
persist client already implements create, read, update and delete for each one. What is
missing is the service layer: today a user who wants an API over their data writes an HTTP,
GraphQL or MCP service by hand, resource by resource, wiring each one to the client and mapping
its errors.

Comparable tools generate this layer:

| Tool | Source of truth | Protocols generated |
|---|---|---|
| [Azure Data API builder](https://learn.microsoft.com/azure/data-api-builder/) | `dab-config.json` | REST, GraphQL and MCP, from one process |
| [ZenStack](https://zenstack.dev/) | ZModel schema | REST (RPC style and JSON:API); MCP through a community package |
| [PostgREST](https://docs.postgrest.org/) | The database | REST; GraphQL and MCP only through separate products |

All three expose the same per-entity operation set: list, get by key, create, update and
delete. All three also control access in the same four actions: create, read, update and
delete. That is the shape adopted here.

For a single entity, the operations each tool offers compare with the persist client as
follows:

| Operation | ZenStack | Data API builder | PostgREST | persist client |
|---|---|---|---|---|
| List | yes | yes | yes | yes |
| Get by key | yes | yes | yes | yes |
| Create, including bulk | yes | yes | yes | yes, bulk only |
| Partial update by key | yes | yes | yes | yes |
| Delete by key | yes | yes | yes | yes |
| Upsert | yes | yes | yes | no |
| Update or delete by filter | yes | no | yes | no |

Everything the persist client supports is in scope. The last two rows are future work, and
depend on the persist client first.

## Design

### Overview

| Piece | Owner | Contents |
|---|---|---|
| `Ballerina.toml` | user | Whether a data service exists, its protocol and its base path |
| `persist/model.bal` | user | The entities, and a `@dataservice:Expose` annotation on each entity to expose, naming its operations |
| `ballerina/dataservice` | new library | The annotations, their compiler-plugin validation, and the runtime types generated services share |
| `generated/` | persist tool | The persist client, as today, plus the data service |

#### Where a setting goes

`persist/model.bal` is the complete definition of what a data service exposes: which entities,
and which actions on each. `Ballerina.toml` says only how the service is generated, and
`Config.toml` says where it runs. Each setting has one home, and no setting in one file changes
the meaning of another:

| A setting that | Goes in | For example |
|---|---|---|
| Describes an entity or a field: whether it is exposed, what it allows, what it shows | An annotation in the model | Exposure and actions; later hidden and read-only fields, scopes per action, page limits, relations |
| Describes how the service is generated, so it would change if the same model were served another way | `options.dataservice` in `Ballerina.toml` | Protocol and base path; later several protocols, API descriptions |
| Varies by environment at runtime | A configurable in `Config.toml` | Port and listener settings such as TLS; later auth provider settings |

One home means:

- **One place to read.** What an entity allows is read from its annotation alone.
- **No defaults across files.** There is no precedence between files to specify, validate or
  remember.
- **The same model gives the same service,** whether it is generated by `bal build` from the
  `[[tool.persist]]` entry or by `bal persist generate`, which has no entry.
- **The compiler sees all of it.** The compiler plugin and the IDE check exposure as it is
  written; neither reads `Ballerina.toml`.
- **Exposure changes are reviewed with the model.** Allowing `delete` on an entity is a change
  next to that entity, not in a build file.

A setting that applies to one protocol but describes an entity, such as a path or type name, is
still an annotation field, grouped under the protocol's name.

### `Ballerina.toml`

The data service is an options group on the existing `[[tool.persist]]` entry.

```toml
[[tool.persist]]
id = "generate-db-client"
targetModule = "hr"
filePath = "persist/model.bal"
options.datastore = "postgresql"
options.dataservice.protocol = "http"
options.dataservice.basePath = "/api"
```

| Key | Required | Default | Meaning |
|---|---|---|---|
| `options.dataservice.protocol` | yes | — | The protocol the service is generated for: `http`, `graphql` or `mcp` |
| `options.dataservice.basePath` | no | `/api` for `http`, `/graphql` for `graphql`, `/mcp` for `mcp` | The service's base path |

When `options.dataservice` is absent, no service is generated and persist behaves exactly as it
does today. When it is present, `protocol` must be set.

Which entities are exposed, and what each allows, is said in the model with
[`@dataservice:Expose`](#dataserviceexpose), as [Where a setting goes](#where-a-setting-goes)
requires.

#### Protocol values

Each value names the Ballerina module that implements the service:

| Value | Generated service | Listener |
|---|---|---|
| `http` | `http:Service` | `http:Listener` |
| `graphql` | `graphql:Service` | `graphql:Listener` |
| `mcp` | `mcp:StreamableHttpService` | `mcp:StreamableHttpListener` |

`http` is used rather than `rest` because it names the protocol and the module, where `rest`
names a design style. GraphQL and MCP are also carried over HTTP; the value selects the service
type, not the transport.

`odata` and `soap` are reserved for later proposals. Passing them now is an error that lists
the supported values.

`protocol` takes a single string. A later proposal may also accept an array, generating one
service per protocol on a shared listener. A string stays valid when that happens.

### CLI

No new command is added. Two flags are added.

| Flag | Commands | Meaning |
|---|---|---|
| `--dataservice <protocol>` | `add`, `pull`, `generate` | Enables the data service for the given protocol. `add` and `pull` write `options.dataservice.protocol`; `generate` generates the service once |
| `--expose-tables <table,...>` | `pull` | The tables whose entities are exposed. Requires `--dataservice` |

`basePath` has no flag. It has a default and is edited in `Ballerina.toml`, or in the generated
source after `generate`.

| Command | Behaviour with `--dataservice` |
|---|---|
| `bal persist add` | Writes the `[[tool.persist]]` entry as today, and adds the `options.dataservice` keys to it. The model it writes is empty, so the user annotates each entity to expose as they write it |
| `bal persist pull` | Introspects the database and writes the model as today, with `@dataservice:Expose` on each entity to expose and the `ballerina/dataservice` import. Then records the `options.dataservice` keys in the existing `[[tool.persist]]` entry, creating the entry as `add` would if none exists |
| `bal persist generate` | Generates the client once, as today, and the data service next to it. See below |
| `bal build` | Generates the client and, when `options.dataservice` is present, the data service |

`init`, `migrate` and `push` are unchanged.

`generate` is the one-time generation path that predates `add`: it does not read
`[[tool.persist]]`, and writes the client into the source tree for the user to own. With
`--dataservice`, it also writes the data service into the default module, from the model's
annotations. The service is then the user's code like the client: it is not regenerated on
build, can be edited, and is replaced if `generate` runs again. The same restrictions as
`add --dataservice` apply: `--module`, `--model` and `--with-init-params` cannot be combined
with it. Without `--dataservice`, an annotated model generates only the client, and the tool
says that `--dataservice` would also generate a service.

`pull` takes table names because that is what a user knows before the model exists. Without
`--expose-tables`, every pulled entity is annotated. With it, only the entities of the named
tables are annotated, and each name must be a pulled table. `--tables` keeps its current
meaning, so a user can pull more tables than they expose. When an entity's name differs from
its table's, `pull` prints the mapping. From then on the model is the source of truth: the
annotations can be edited like the rest of it, and a later `pull` replaces them along with the
model.

### The `ballerina/dataservice` module

The module holds:

- the annotations a model uses to expose an entity and restrict what it allows,
- a compiler plugin that validates them, and
- the protocol-neutral runtime types that generated services share: the error body and its
  error codes.

Keeping the runtime types in a library rather than in generated code means the generated code
stays thin, and fixes ship as library updates without regeneration. The library does not depend
on any protocol module. Types that are specific to an entity, such as the `<Entity>List`
envelope, or to a protocol, such as an HTTP status code record, are generated.

A model with a data service imports the module with a prefix:

```ballerina
import ballerina/persist as _;
import ballerina/dataservice;

@dataservice:Expose
type Employee record {|
    readonly int id;
    string name;
    string email;
|};

@dataservice:Expose {operations: [dataservice:READ]}
type Department record {|
    readonly int id;
    string name;
|};

type AuditLog record {|
    readonly int id;
    string entry;
|};
```

Here `Employee` allows every action, `Department` only reads, and `AuditLog` is not exposed.

Whether a service is generated is decided by `options.dataservice` in `Ballerina.toml`; the
annotations only select what it exposes. The persist tool's model validation accepts this
import alongside the ones it accepts today.

#### `@dataservice:Expose`

```ballerina
public enum Operation {
    READ = "read",
    CREATE = "create",
    UPDATE = "update",
    DELETE = "delete"
}

public type ExposeConfig record {|
    [Operation, Operation...] operations = [READ, CREATE, UPDATE, DELETE];
|};

public const annotation ExposeConfig Expose on source type;
```

Exposure is opt-in. An entity is exposed only when it has the annotation, and it allows the
actions in `operations`, which are every action by default:

| Annotation | Exposed | Actions |
|---|---|---|
| none | no | — |
| `@dataservice:Expose` | yes | `read, create, update, delete` |
| `@dataservice:Expose {operations: [dataservice:READ, dataservice:UPDATE]}` | yes | `read, update` |

`Expose` is a constant annotation. Its value is evaluated at compile time, which is when the
compiler plugin and the persist tool read it, and is not kept at runtime. The type requires at
least one operation, so an empty list is a compile error: an entity that allows nothing is left
unannotated. A service that exposes no entity is an error, and the error lists the model's entities so that a
user enabling a service on an existing model sees what to annotate.

Persist does not generate a client API for an entity whose fields include an unsupported data
type. Annotating such an entity is an error.

`EXECUTE` is reserved for custom operations in a later proposal.

#### Validation

The compiler plugin checks the annotation where it is written. The persist tool checks what
needs the whole model when it generates.

| Check | Where | Severity |
|---|---|---|
| `@dataservice:Expose` is on a record type that is a persist entity | compiler plugin | error |
| `operations` is non-empty and has only `Operation` values | compiler, through the type | error |
| `operations` has no duplicates, including through a constant | compiler plugin | error |
| An annotated entity has no unsupported data types | persist tool | error |
| At least one entity is annotated | persist tool | error |

Diagnostic codes and messages are left to the implementation.

### The service shape

#### Actions and operations

Each exposed entity gets up to six operations, enabled in four groups called actions:

| Action | Operation | Persist client call |
|---|---|---|
| `read` | Get many | `get <entities>()` |
| `read` | Get one | `get <entities>/[key]()` |
| `create` | Create one | `post <entities>([value])`, then get one by the returned key |
| `create` | Create many | `post <entities>(values)`, then get one for each returned key |
| `update` | Patch one | `put <entities>/[key](value)` |
| `delete` | Delete one | `delete <entities>/[key]()` |

##### Why four actions and not a switch per operation

An action is a capability: what a caller may see or change. An operation is one way to use that
capability. The model enables capabilities, and every operation that uses an enabled capability
is generated.

- **A switch must protect something.** Get many and get one return the same rows: a caller who
  can get one record by key can find the keys by trying them, and one who can list records has
  every key. Create one and create many write the same records: many is one repeated. Turning
  one of a pair off would look like a restriction without being one.
- **Operations grow; capabilities do not.** Later proposals add query options, related reads,
  replace and bulk writes, each inside one of the four actions. With a switch per operation,
  every addition would add a switch, and a v1 model would not say whether it allows the new
  operation. With actions, it already does.
- **Protocols render operations differently.** HTTP serves both creates from one `POST`, GraphQL
  and MCP have a field or tool for each, and OData writes many records in a batch. Actions mean
  the same in every protocol; operations do not.
- **Authorization is granted per action.** SQL privileges (`SELECT`, `INSERT`, `UPDATE`,
  `DELETE`), Data API builder and ZenStack's access policies use the same four, so scopes per
  action can be added later without remapping.

A new action is added only for a capability that none of the four grants. `EXECUTE` is reserved
for custom operations for that reason.

The persist client's `put` is a partial update: fields left out of the value are not changed.
It is exposed as a patch.

#### Addressing

- **Collection name:** the resource name the persist client already uses for the entity, for
  example `employees` for `Employee`.
- **Key:** the entity's `readonly` fields, in declaration order. Every persist entity has a key,
  so get one, patch one and delete one exist for every entity whose actions allow them.
- **Composite keys:** take one value per key field, in that order.

These are reserved for later proposals and are not used for anything else:

- a third path segment after an entity's key (`<entities>/[key]/<relation>`), for relations;
- names starting with `$`, for query and metadata operations such as count.

#### Types

The shape is defined in terms of the types persist already generates. The HTTP and MCP services
use them directly; the GraphQL service generates equivalent input and output types, because
`ballerina/graphql` does not accept the persist types as they are (see the GraphQL proposal).

| Type | Used as |
|---|---|
| `<Entity>` | The result of every operation that returns a record |
| `<Entity>Insert` | The input to create one and create many |
| `<Entity>Update` | The input to patch one |

Get many and create many return an envelope rather than a bare array:

```ballerina
public type EmployeeList record {|
    Employee[] items;
|};
```

The envelope exists so that paging and count can add fields such as a next-page cursor and a
total later, without changing the result type. MCP also requires a tool's structured result to
be an object, so a bare array could not be used there in any case.

#### Results

| Operation | Returns |
|---|---|
| Get many | `<Entity>List` holding every record |
| Get one | `<Entity>` |
| Create one | The created `<Entity>`, read back after insert so that generated fields are included |
| Create many | `<Entity>List` holding the created records |
| Patch one | The updated `<Entity>`, as returned by the persist client |
| Delete one | The deleted `<Entity>`, as returned by the persist client |

Creates return records rather than keys because changing a result type later would break
clients.

#### Errors

Errors fall into protocol-neutral categories. `ballerina/dataservice` defines one error body
and an error code per category:

```ballerina
public enum ErrorCode {
    NOT_FOUND,
    CONFLICT,
    CONSTRAINT_VIOLATION,
    INVALID_INPUT,
    INTERNAL
}

public type DataserviceError record {|
    ErrorCode code;
    string message;
|};
```

Each protocol proposal maps the categories to its own form: an HTTP status code, an entry in
the GraphQL `errors` array, or an MCP tool result with `isError` set.

| Category | `code` | Raised when | Source |
|---|---|---|---|
| Not found | `NOT_FOUND` | No record has the given key | `persist:NotFoundError` |
| Conflict | `CONFLICT` | A record with the key or a unique value already exists | `persist:AlreadyExistsError` |
| Constraint violation | `CONSTRAINT_VIOLATION` | A write violates a foreign key | `persist:ConstraintViolationError` |
| Invalid input | `INVALID_INPUT` | The input cannot be bound to the operation's type | The protocol module's binding error |
| Internal | `INTERNAL` | Any other failure | `persist:Error` and others |

The message is written by the generated service, not taken from the persist error, because the
SQL datastores put driver text, such as table and constraint names, in their error messages:

| Category | Message |
|---|---|
| Not found | `A record with the key '<key>' does not exist for the entity '<Entity>'.` |
| Conflict | `A record that conflicts with an existing record of the entity '<Entity>' already exists.` |
| Constraint violation | `The operation violates a constraint of the entity '<Entity>'.` |
| Internal | `An internal error occurred.` |

A composite key is written as its values joined by `/`, in key order. The persist error's own
detail for a constraint violation or an internal error is logged and not returned to the
caller.

A disabled operation is not generated at all, so it does not exist rather than being refused.
Which protocol error a caller sees when calling one is protocol-specific: a 404 or 405 for HTTP,
a validation error for GraphQL, an unknown tool for MCP.

### Generated code

- **Location:** the data service is generated only into the package's default module. When
  `options.dataservice` is present, `targetModule` must be the package name, which is persist's
  default when `--module` is not passed. Any other `targetModule` is an error.
- **Why the default module:** a service in the default module is started without the user
  importing anything.
- **Files:** the service is generated next to the persist client, in `persist_dataservice.bal`
  and `persist_dataservice_config.bal`. From the `[[tool.persist]]` entry, they go into
  `generated/` and, like the client, are regenerated on every build and must not be edited. From
  `generate`, they go into the package root, where the client also goes, and are the user's.
- **Names:** generated module-level names share the default module's namespace with the user's
  own code, as the persist client's generated names already do. The service follows the same
  convention: type names are derived from entity names, such as `<Entity>List`, and other
  module-level names start with `dataservice`.
- **Client construction:** the service creates the persist client with `new ()`, so
  `options.withInitParams = true` cannot be used together with `options.dataservice`.
- **One service per package:** a package has one persist model and at most one data service.
  Persist's `--model` option for several models is not supported together with
  `options.dataservice`.

#### Runtime configuration

Runtime settings follow the database connection settings. Persist generates the database host,
port, user, password and database name as configurable values in `persist_db_config.bal`, and
the user sets them in `Config.toml`. The data service does the same: the tool generates
`persist_dataservice_config.bal` holding the listener port as a configurable value.

```ballerina
configurable int dataservicePort = 9090;
```

The port has a default, unlike the database settings, so the service runs without any
`Config.toml` entry. The name is not `port` because the database configuration already declares
`port` in the same module.

Other listener settings, such as TLS, are left to the protocol proposals.

### Datastore support

The six operations use only client calls that every persist datastore implements: MySQL, MSSQL,
PostgreSQL, H2, in-memory, Google Sheets and Redis. The CRUD shape is therefore available on all
of them.

Whether each field type can be represented in each protocol is defined by the protocol
proposals. For example, persist's `time:*` record types and `byte[]` need a GraphQL mapping.

### Backward compatibility

- Without `options.dataservice`, nothing changes: the client, its files and all commands
  behave as today.
- `persist-options-schema.json` currently sets `additionalProperties: false`. It gains a
  `dataservice` object; existing entries still validate.
- Models that do not import `ballerina/dataservice` are unaffected. Without
  `options.dataservice`, `@dataservice:Expose` annotations in a model have no effect.

## Alternatives

### A hand-written service spec file

A separate file, `persist/service.bal`, would declare the API as a service object type, kept in
step with the model by a new `bal persist expose` command. It can express more than annotations:
per-resource query capability, renamed operations, custom SQL-backed operations.

It is not adopted for this proposal because it adds a second hand-maintained artifact and a new
command to deliver a CRUD shape the model already determines. It remains an option for later
features that cannot be expressed as annotations.

### Selecting entities in `Ballerina.toml`

For example, `options.dataservice.entities = ["Employee", "Department"]`, with every entity
exposed when the list is omitted. This splits what is exposed across two files, and a misspelled entity name is caught only when the tool runs, while an annotation sits
on the type it exposes and is checked by the compiler plugin as it is written. Exposing every
entity by default also exposes an entity added to the model later without anyone choosing to.

Per-entity operations in `Ballerina.toml`, such as `options.dataservice.entities.Department =
["read"]`, have the same split and cannot express field-level rules such as a hidden field.
`Ballerina.toml` is kept for how the service is generated; the model holds what is exposed and
what each entity allows.

### Default operations in `Ballerina.toml`

For example, `options.dataservice.operations = ["read"]`, as the actions of every exposed entity
whose annotation does not set them, so that a read-only service is one line. It is not adopted
because it gives an entity's actions two homes. A bare `@dataservice:Expose` would mean nothing
on its own, the precedence between the two files would have to be specified and validated, the
compiler plugin could not tell what an entity allows, and the same model would give a different
service from `bal persist generate`, which has no `Ballerina.toml` entry. Writing `operations` on
each entity that differs from the default keeps the model complete.

### Exposing every entity by default with a switch

For example, `options.dataservice.exposeAll = true`, under which an unannotated entity is
exposed with every action. It saves annotating each entity when a service is added to an
existing model.

It is not adopted because it makes exposure depend on two places and three states. Excluding an
entity under the switch needs a second annotation, such as `@dataservice:Hidden`, because
`@dataservice:Expose` only names actions. Whether an entity is exposed then depends on the
switch, on which of the two annotations it carries, and on how they combine, and every
combination has to be specified, validated and kept consistent across protocols. An entity
added to the model later is also exposed without anyone choosing to. With opt-in, the
annotation on the entity is the whole answer. The cost is annotating each entity once, which
`pull --dataservice` does for a database-backed model.

### A `readOnly` flag, or one switch per operation

A `readOnly` flag cannot express a common case such as "create and update, but not delete". A
switch per operation adds configuration without adding control; see
[Why four actions and not a switch per operation](#why-four-actions-and-not-a-switch-per-operation).

### `rest` as the protocol value

See [Protocol values](#protocol-values).

### Several protocols from one entry

The listeners of `ballerina/graphql` and `ballerina/mcp` both accept an `http:Listener`, so
several services can share one port. This is deferred so that each protocol's rendering can be
specified and settled on its own first. `protocol` is a string that can later also accept an
array.

## Testing

- **Options schema:** `options.dataservice` with valid and invalid values; required
  `protocol`; reserved protocol values.
- **CLI:** `add`, `pull` and `generate` with and without `--dataservice`; `pull` with and without
  `--expose-tables`, including unknown tables; `pull` into a project with and without an
  existing `[[tool.persist]]` entry.
- **Annotation validation:** each compiler-plugin rule; the bare annotation and its default
  operations; a model with no annotated entity.
- **Code generation:** expected-output tests for each protocol, with single and composite keys,
  every action combination, and the default and custom base path.
- **Compilation:** the generated package compiles on every persist datastore.
- **Behaviour:** an end-to-end CRUD round trip per protocol against the in-memory and H2
  datastores, including each error category.
- **Backward compatibility:** existing persist tests pass unchanged without
  `options.dataservice`.

## Risks and Assumptions

- **Unbounded reads.** Get many returns every record until paging is added. On large tables
  this is slow and memory-heavy. The envelope lets paging be added without breaking clients,
  but until then the risk stays with the user.
- **Exposure without auth.** Until auth is added, every caller can perform every enabled
  action. A bare `@dataservice:Expose` enables all four, including delete, and `pull
  --dataservice` annotates every pulled entity this way, saying so when it does. Users must set
  `operations` in the annotations, or protect the listener themselves.
- **Creates are not atomic with their read-back.** A create is followed by a separate read. A
  concurrent delete between the two can return a not-found error for a record that was
  created.
- **Name clashes in the default module.** Generated names share the user's namespace, as the
  persist client's already do. A user type named, for example, `EmployeeList` fails to
  compile alongside the generated one.
- **Assumption:** the persist client's resource names, keys and generated types are stable
  enough for the service to build on them.

## Dependencies

- `persist-tools`: options schema, CLI flags, model validation, code generation.
- `ballerina/persist` and the persist datastore clients.
- `ballerina/dataservice`: a new library.
- `ballerina/http`, `ballerina/graphql` and `ballerina/mcp`, through the protocol proposals.

## Future work

### Follow-up proposals

Each protocol proposal defines how the CRUD shape in this proposal is rendered. Each covers the
same points: the listener and service type, how each operation maps to a resource, query,
mutation or tool, how keys and types map, how the error categories map, the base path, and the
listener configuration.

| Proposal | Scope |
|---|---|
| 2. [HTTP](NNNN_data_service_http.md) | `http:Service`: collection and key paths, methods, status codes, request and response bodies |
| 3. [GraphQL](NNNN_data_service_graphql.md) | `graphql:Service`: queries and mutations, input and output types, type mappings for persist's time types and `byte[]`, error mapping |
| 4. [MCP](NNNN_data_service_mcp.md) | `mcp:StreamableHttpService`: tool names, input and output schemas, descriptions from doc comments, tool annotations such as read-only hints, error results |

### Roadmap

| Area | Adds | Fits into v1 through |
|---|---|---|
| Query options | Filtering, sorting, paging, field selection, count | The `read` action; fields added to the `<Entity>List` envelope; the reserved `$` names |
| Auth | Authentication at the listener; scopes per action in `@dataservice:Expose`; later, row-level rules | The action names; annotations that only narrow |
| Relations | Embedded reads, relation routes, nested writes | The reserved path segment after an entity's key |
| Field rules | Hidden fields and read-only fields, as field annotations | The model holding what the data allows |
| More write operations | Upsert, full replace, update or delete by filter, once the persist client supports them | The `create`, `update` and `delete` actions |
| Custom operations | Named queries exposed as operations | The reserved `EXECUTE` action |
| Several protocols | Several services from one entry, on a shared listener | `protocol` also accepting an array |
| More protocols | OData, SOAP | The reserved `odata` and `soap` values |
| API descriptions | OpenAPI, GraphQL schema, MCP tool descriptions | Generated alongside the service |
