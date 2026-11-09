# Data service generation for bal persist

- Author: @niveathika
- Reviewers: 
- Created: 2026-09-18
- Updated: 2026-11-01
- Issue: [#1503](https://github.com/ballerina-platform/ballerina-spec/issues/1503)
- Status: Draft

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

The service has a fixed CRUD shape: six operations per entity plus a get related per relation,
grouped into four actions. This
proposal defines that shape, how the tool is configured and how it behaves. It does not define
how each protocol renders the shape. That is left to follow-up proposals for HTTP, GraphQL and
MCP, listed under [Future work](#future-work).

A data service exposes the entities of one persist model as create, read, update and delete
operations over a protocol, with no code to write. It is meant for production APIs whose job is
CRUD over one database, such as internal, back-office and admin APIs, as well as for
prototypes. It is not a general way to front databases: an API with business logic, custom
operations, or data combined from several sources is a hand-written service, which can run
beside the data service on the same listener.

This is proposal 1 of 4. The offset proposal,
[#1515](https://github.com/ballerina-platform/ballerina-spec/issues/1515), is a prerequisite.

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
- Fix the parts of the contract that later features, such as `or` filters, a total count,
  row-level auth and nested writes, would otherwise break: the response envelope, the action
  names, the addressing scheme, the write results and the error categories.

## Non-goals

- A total count, and filters joined by `or`.
- The in-memory, Google Sheets and Redis datastores.
- Nested writes, filtering or sorting on related fields, and relations more than one hop away.
- Authorization beyond a scope per action, such as row-level rules or fields visible only to some scopes.
- Write operations the persist client does not provide: upsert, full replace, and update or
  delete by filter.
- Exposing several protocols from one entry.
- Optimistic concurrency control, such as `ETag` and `If-Match`. Concurrent patches of one
  record can overwrite each other.
- A data service in a module other than the package's default module, or over more than one
  persist model.
- OData and SOAP.

Those that are planned are in the roadmap under [Future work](#future-work). The design below reserves
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
delete. All three also control access through the same four actions: create, read, update and
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

Everything the persist client supports is in scope. The last two rows are future work and
first need support in the persist client.

## Design

### Overview

| Piece | Owner | Contents |
|---|---|---|
| `Ballerina.toml` | user | Whether a data service exists, its protocol and its base path |
| `persist/model.bal` | user | The entities, and a `@dataservice:Expose` annotation on each entity to expose, naming its operations |
| `ballerina/dataservice` and `ballerina/dataservice.<protocol>` | new libraries | The annotations and their compiler-plugin validation, and the runtime that generated services call |
| `generated/` | persist tool | The persist client, as today, plus the data service |

#### Where a setting goes

`persist/model.bal` is the complete definition of what a data service exposes: which entities,
and which actions on each. `Ballerina.toml` says only how the service is generated, and
`Config.toml` says where it runs. Each setting has one home, and no setting in one file changes
the meaning of another:

| A setting that | Goes in | For example |
|---|---|---|
| Describes an entity or a field: whether it is exposed, what it allows, what it shows | An annotation in the model | Exposure, actions and scopes per action; later hidden and read-only fields |
| Describes how the service is generated, so it would change if the same model were served another way | `options.dataservice` in `Ballerina.toml` | Protocol, base path, introspection and auth; later several protocols |
| Varies by environment at runtime | A configurable in `Config.toml` | Port, page sizes, listener settings such as TLS, and auth provider settings |

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

The data service is an options group on the existing `[[tool.persist]]` entry, written as a
`[tool.persist.options.dataservice]` table directly after the entry it belongs to.

```toml
[[tool.persist]]
id = "generate-db-client"
targetModule = "hr"
filePath = "persist/model.bal"
options.datastore = "postgresql"

[tool.persist.options.dataservice]
protocol = "http"
basePath = "/api"
```

The table is a TOML sub-table of the last `[[tool.persist]]` entry, so it must follow that entry
before any other table header. `bal build` passes it to the tool as part of the entry's
`options`, so `options.dataservice.protocol = "http"` written as a dotted key on the entry is
equivalent. This proposal refers to the keys by their dotted names.

| Key | Required | Default | Meaning |
|---|---|---|---|
| `options.dataservice.protocol` | yes | — | The protocol the service is generated for; see [Protocol values](#protocol-values) |
| `options.dataservice.basePath` | no | `/api` for `http`, `/graphql` for `graphql`, `/mcp` for `mcp` | The service's base path |
| `options.dataservice.auth` | no | `false` | Whether the service is generated with authentication and scopes; see [Auth](#auth) |
| `options.dataservice.introspection` | no | `true` | Whether the service publishes its own description; see [Documentation](#documentation) |

`basePath` must start with `/`. A trailing `/` is removed, and `/` alone serves the service at
the root. Each segment must be non-empty and contain only letters, digits, `_`, `-` and `.`.
Any other value is an error that names it.

`persist-options-schema.json` gains the group's keys. The values are checked by the tool rather
than the schema, so that its errors can list the supported values:

```json
"dataservice": {
  "type": "object",
  "properties": {
    "protocol": {"type": "string"},
    "basePath": {"type": "string"},
    "auth": {"type": "boolean"},
    "introspection": {"type": "boolean"}
  },
  "additionalProperties": false
}
```

Whether a service is generated depends on `Ballerina.toml` and the model together:

| `options.dataservice` | `protocol` | Annotated entities | Result |
|---|---|---|---|
| absent | — | none | No service; persist behaves exactly as it does today |
| absent | — | some | No service. The annotations have no effect, and the tool warns that `protocol` is not set |
| present | absent | any | Error: `protocol` is required |
| present | set | none | Error listing the entities that can be annotated |
| present | set | some | The service is generated over the annotated entities |

Which entities are exposed, and what each allows, is declared in the model with
[`@dataservice:Expose`](#dataserviceexpose), as [Where a setting goes](#where-a-setting-goes)
requires.

#### Protocol values

Each value names the Ballerina module that implements the service:

| Value | Generated service | Listener |
|---|---|---|
| `http` | `http:Service` | `http:Listener` |
| `graphql` | `graphql:Service` | `graphql:Listener` |
| `mcp` | `mcp:StreamableHttpService` | `mcp:StreamableHttpListener` |

`http` is used rather than `rest` because it names the protocol and the module, whereas `rest`
names a design style. GraphQL and MCP are also carried over HTTP; the value selects the service
type, not the transport.

Only `http` is implemented with this proposal, through #1513. `graphql` and `mcp` are listed
for their own proposals; until those are implemented, passing one is an error saying that the
protocol is not supported yet and listing the supported values. `odata` and `soap` are reserved
for later proposals, and passing them is the same error.

`protocol` takes a single string. A later proposal may also accept an array, generating one
service per protocol on a shared listener. A string stays valid when that happens.

### CLI

No new command is added. Two flags are added.

| Flag | Commands | Meaning |
|---|---|---|
| `--dataservice <protocol>` | `add`, `pull`, `generate` | Enables the data service for the given protocol. `add` and `pull` write `options.dataservice.protocol`; `generate` generates the service once |
| `--expose-tables <table,...>` | `pull` | The tables whose entities are exposed. Requires `--dataservice`, unless the entry already enables a data service |

`basePath` has no flag. It has a default and is edited in `Ballerina.toml`, or in the generated
source after `generate`.

| Command | Behaviour with `--dataservice` |
|---|---|
| `bal persist add` | Writes the `[[tool.persist]]` entry as today, and adds the `[tool.persist.options.dataservice]` table after it. The model it writes is empty, so the user annotates each entity to expose as they write it |
| `bal persist pull` | Introspects the database and writes the model as today, with `@dataservice:Expose` on each entity to expose and the `ballerina/dataservice` import. Then writes the `[tool.persist.options.dataservice]` table after the `[[tool.persist]]` entry, creating the entry as `add` would if none exists |
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
`--expose-tables`, every pulled entity is annotated, except an entity with an unsupported data
type, which `pull` names in a warning. With it, only the entities of the named tables are
annotated, and each name must be a pulled table whose entity has no unsupported data type.
`--tables` keeps its current meaning, so a user can pull more tables than they expose. From then
on, the model is the source of truth: the annotations can be edited like the rest of it, and a
later `pull` replaces them along with the model.

When the `[[tool.persist]]` entry already has `options.dataservice`, `pull` without
`--dataservice` annotates the pulled entities in the same way, using the entry's protocol, and
leaves the entry unchanged. A later `pull` therefore keeps the service, rather than writing a
model with no annotated entity, which would fail the next build. Without `--expose-tables`, it
exposes every pulled table, as `pull --dataservice` does, even one that the replaced model did
not expose. Keeping the replaced model's selection is deferred; see [Roadmap](#roadmap). When
the entry has no `options.dataservice` and the flag is not passed, `pull` behaves exactly as it
does today.

#### Flag combinations

| Case | Result |
|---|---|
| `add` or `generate` with `--dataservice` and `--module`, `--model` or `--with-init-params` | Error, with the message for the matching `Ballerina.toml` case in [Messages](#messages) |
| `pull` with `--dataservice` and `--model` | Error, with the message for a named model in [Messages](#messages) |
| `--dataservice` with a value other than `http` | The protocol error in [Messages](#messages) |
| `--expose-tables` without `--dataservice` | Error, unless the entry already enables a data service |
| `--expose-tables` naming a table that was not pulled, or one whose entity has an unsupported data type | Error naming the table. Names match as `--tables` matches them, exactly |
| `pull --dataservice` when the entry already has `options.dataservice` | Error, before the database is read: the user removes the entry's `options.dataservice` keys and runs the command again, or runs `pull` without `--dataservice` to keep them. `--dataservice` adds a group and never changes one the user has written |
| `pull --dataservice` when the entry has another `targetModule` or `withInitParams = true` | Error, as for the same `Ballerina.toml`, and nothing is written |
| `pull --dataservice` with several `[[tool.persist]]` entries | The entry whose `filePath` is `persist/model.bal` is used, and created if none is |

A command that ends in an error leaves the model and `Ballerina.toml` unchanged.

### Libraries

A data service uses two library packages:

| Package | Holds | Depends on | Imported by |
|---|---|---|---|
| `ballerina/dataservice` | The annotations and the compiler plugin that validates them. The protocol-neutral runtime: the query options and the SQL they build, the error body and codes, the mapping from persist errors to them, value conversions every protocol shares, and the runtime settings every protocol has | `ballerina/persist` and `ballerina/sql` | The model and the generated service |
| `ballerina/dataservice.<protocol>`, such as `ballerina/dataservice.http` | The protocol runtime, defined by each protocol proposal | `ballerina/dataservice` and the protocol module | The generated service |

Each protocol package is a separate package with its own release cycle, as persist's datastore
packages such as `ballerinax/persist.sql` are. A service over one protocol does not depend on
the others' modules, and a fix for one protocol is released without the core.

The generated service holds only what must be fixed at compile time: the resource or remote
function signatures, the types that are specific to an entity, and the typed persist client
calls. Everything else is a call to a library function, so a fix inside a library function is
released as a library update without regeneration. Changing the signature of such a function
needs regeneration, so the functions that generated code calls are a stable API: new behaviour
is added through new functions or optional parameters. Each library's specification lists the
functions and types that generated code uses, and they change only in a new major version of
the library.

A model with a data service imports `ballerina/dataservice` for its annotations, under any prefix
other than `_`:

```ballerina
import ballerina/persist as _;
import ballerina/time;
import ballerina/dataservice;

enum Status {
    ACTIVE,
    INACTIVE
}

@dataservice:Expose
type Employee record {|
    readonly int id;
    string name;
    string? email;
    time:Date hiredOn;
    Status status;
    @dataservice:Internal
    string? notes;
    Department department;
|};

@dataservice:Expose {operations: [dataservice:READ]}
type Department record {|
    readonly int id;
    string name;
    Employee[] employees;
|};

type AuditLog record {|
    readonly int id;
    string entry;
|};
```

Here `Employee` allows every action, `Department` only reads, and `AuditLog` is not exposed.
`Employee.notes` is stored but never returned or accepted by the service; see
[Field rules](#field-rules).
This proposal and #1513 use these entities in their examples.

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

public type Scopes record {|
    string[] read?;
    string[] create?;
    string[] update?;
    string[] delete?;
|};

public type ExposeConfig record {|
    [Operation, Operation...] operations = [READ, CREATE, UPDATE, DELETE];
    Scopes scopes?;
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
unannotated. A service that exposes no entity is an error, and the error lists the model's
entities so that a user enabling a service on an existing model sees what to annotate.

Persist does not generate a client API for an entity whose fields include an unsupported data
type. Annotating such an entity is an error.

`EXECUTE` is reserved for custom operations in a later proposal.

#### Validation

`persist/model.bal` is not compiled with the package. The file is compiled on its own, by the
IDE while it is edited and by the persist tool each time it generates, from `bal build` or
`bal persist generate`. The compiler plugin checks the annotations in both, so each check is
made once, in the plugin. When the persist tool compiles the model, a plugin error fails the
build and a plugin warning is printed. The checks that need the tool's options or more than
one entity are made by the persist tool.

The compiler plugin acts only on a single-file project whose file is in the package's
`persist` directory, `persist/<file>`, or in a named model's directory, `persist/<model>/<file>`,
and does nothing in any other source.

| Check | Made by | Severity |
|---|---|---|
| `@dataservice:Expose` is on a record type in the model | compiler plugin | error |
| `operations` is non-empty and has only `Operation` values | compiler, through the type | error |
| `operations` has no duplicates | compiler plugin | error |
| Each scope is non-empty and has no whitespace | compiler plugin | error |
| `scopes` names only actions in `operations` | compiler plugin | error |
| An annotated entity has no unsupported data types | persist tool | error |
| An annotated entity's key fields avoid the names the protocol's generated code uses | persist tool | error |
| No two annotated entities have the same collection name | persist tool | error |
| At least one entity is annotated | persist tool | error |
| `scopes` is set only when `options.dataservice.auth` is `true` | persist tool | warning |

The persist tool reads the annotation from the model's syntax tree, not from compiled values.
`operations` is a list literal whose members are `Operation` members, such as
`dataservice:READ`, or their string values, such as `"read"`. No other form can reach the
tool: persist accepts only record and enum definitions in a model, so a model cannot declare a
constant to use instead.

#### Messages

The persist tool's errors are printed with persist's `ERROR:` prefix, or reported as the build
tool's diagnostic in `bal build`, and fail the command or the build. Its warnings are printed with
`WARNING:` and do not. The compiler plugin's checks are reported as compiler diagnostics, with
their position in the model; their diagnostic codes are left to the implementation.

| Case | Severity | Message |
|---|---|---|
| `protocol` missing | error | `'options.dataservice.protocol' is required. Supported values: http.` |
| `protocol` is `graphql`, `mcp`, `odata` or `soap` | error | `the protocol '<value>' is not supported yet. Supported values: http.` |
| `protocol` is any other value | error | `invalid 'options.dataservice.protocol' '<value>'. Supported values: http.` |
| `basePath` without a leading `/` | error | `invalid 'options.dataservice.basePath' '<value>': the base path must start with '/'.` |
| `basePath` with an empty or invalid segment | error | `invalid 'options.dataservice.basePath' '<value>': each path segment must be non-empty and contain only letters, digits, '_', '-' and '.'.` |
| `targetModule` is not the package | error | `a data service is generated only into the default module '<package>'. Remove 'targetModule' or set it to '<package>'.` |
| `withInitParams = true` | error | `'options.withInitParams' cannot be used with a data service. Remove it or set it to false.` |
| A datastore that is not a SQL datastore | error | `the datastore '<datastore>' does not support a data service. Use mysql, mssql, postgresql or h2.` |
| A named model | error | `a data service is not supported for a named persist model. Use 'persist/model.bal' or remove 'options.dataservice'.` |
| No annotated entity | error | `the data service exposes no entity. Add the @dataservice:Expose annotation to the entities to expose: <Entity>, <Entity>.` |
| An annotated entity with an unsupported data type | error | `the entity '<Entity>' has an unsupported data type and cannot be exposed. Remove its @dataservice:Expose annotation.` |
| A key field named as a parameter or variable of the generated code | error | `the key field '<field>' of the entity '<Entity>' uses a name reserved by the data service. Rename the field, or remove the entity's @dataservice:Expose annotation.` |
| Two annotated entities with the same collection name | error | `the entities '<Entity>' and '<Entity>' map to the same collection '<collection>' in the data service. Rename one of them, or remove its @dataservice:Expose annotation.` |
| `Expose` on something other than a record type in the model | error | `the @dataservice:Expose annotation is allowed only on a record type in the persist model.` |
| `operations` empty | error | `'operations' in the @dataservice:Expose annotation of the entity '<Entity>' cannot be empty.` |
| `operations` not a list literal | error | `'operations' in the @dataservice:Expose annotation of the entity '<Entity>' must be a list of operations.` |
| An unknown operation | error | `invalid operation '<value>' in the @dataservice:Expose annotation of the entity '<Entity>'. Supported values: dataservice:READ, dataservice:CREATE, dataservice:UPDATE, dataservice:DELETE.` |
| A duplicate operation | error | `duplicate operation '<value>' in the @dataservice:Expose annotation of the entity '<Entity>'. Remove the duplicate.` |
| An empty scope or one with whitespace | error | `invalid scope '<value>' in the @dataservice:Expose annotation of the entity '<Entity>'. A scope must be a non-empty string without whitespace.` |
| Scopes for an action that is not enabled | error | `the @dataservice:Expose annotation of the entity '<Entity>' sets scopes for '<action>', which is not in 'operations'. Add it to 'operations', or remove its scopes.` |
| `scopes` set while `options.dataservice.auth` is not `true` | warning | `the @dataservice:Expose annotation of the entity '<Entity>' sets scopes, but 'options.dataservice.auth' is not true. Set it to true, or remove the scopes.` |
| Annotations without `options.dataservice` | warning | `the model has @dataservice:Expose annotations, but no data service is generated. Set 'options.dataservice.protocol' in the [[tool.persist]] entry to generate one.` |
| `pull` skips an entity | warning | `the table '<table>' has an unsupported data type, so its entity '<Entity>' is not exposed.` |
| `generate` without `--dataservice` on an annotated model | info | `the model has @dataservice:Expose annotations. Use the '--dataservice' option to also generate a data service.` |
| `add --dataservice` succeeds | info | The next steps ``2. Add the @dataservice:Expose annotation to each entity to expose.`` and ``3. Execute `bal build` to generate the persist client and the <PROTOCOL> data service during package build.`` |
| `pull --dataservice` when the entry already has `options.dataservice` | error | `the [[tool.persist]] entry of persist/model.bal already has an 'options.dataservice' group. Remove it from Ballerina.toml and run the command again, or run 'bal persist pull' without '--dataservice'.` |
| `pull --dataservice` succeeds | info | `enabled the <PROTOCOL> data service in the [[tool.persist]] entry of persist/model.bal in Ballerina.toml.` |

### The service shape

#### Actions and operations

Each exposed entity gets up to six operations plus a get related per relation, enabled in four
groups called actions:

| Action | Operation | Persist client call |
|---|---|---|
| `read` | Get many | `get <entities>()` |
| `read` | Get one | `get <entities>/[key]()` |
| `read` | Get related | `get <targets>()` filtered by the relation's foreign key; see [Relations](#relations) |
| `create` | Create one | `post <entities>([value])`, then a read of the created record, in one transaction |
| `create` | Create many | `post <entities>(values)`, then one read of the created records by their keys, in one transaction |
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
- **Operations grow; capabilities do not.** Later proposals add replace, upsert and bulk
  writes, each inside one of the four actions. With a switch per operation, every addition
  would add a switch, and a v1 model would not say whether it allows the new operation. With
  actions, it already does.
- **Protocols render operations differently.** HTTP serves both creates from one `POST`, GraphQL
  and MCP have a field or tool for each, and OData writes many records in a batch. Actions mean
  the same in every protocol; operations do not.
- **Authorization is granted per action.** SQL privileges (`SELECT`, `INSERT`, `UPDATE`,
  `DELETE`), Data API builder and ZenStack's access policies use the same four, so scopes per
  action map onto them without remapping.

A new action is added only for a capability that none of the four grants. `EXECUTE` is reserved
for custom operations for that reason.

The persist client's `put` is a partial update: fields left out of the value are not changed.
It is exposed as a patch.

#### Addressing

- **Collection name:** the entity name with its first word in lowercase and its last word
  pluralized as persist pluralizes resource names: `employees` for `Employee`,
  `projectAssignments` for `ProjectAssignment`, `people` for `Person` and `httpLogs` for
  `HTTPLog`. A new word starts at an uppercase letter after a lowercase letter or digit, and at
  the last uppercase letter of a run followed by a lowercase letter, so `HTTPLog` is `HTTP` and
  `Log`. This deviates from the persist client's resource name, which lowercases the whole name,
  as in `projectassignments`, so that a collection is spelled like the relation fields that
  name it; [ballerina-library#9434](https://github.com/ballerina-platform/ballerina-library/issues/9434) proposes the same rule for persist. The two names
  are the same for an entity whose name is one word.
- **Key:** the entity's `readonly` fields, in declaration order. Every persist entity has a key,
  so get one, patch one and delete one exist for every entity whose actions allow them.
- **Composite keys:** take one value per key field, in that order.
- **Float keys:** a `float` key value must be finite. `NaN` or `Infinity` is invalid input.
- **Relations:** get related is addressed by the relation field's name after the entity's
  full key, `<entities>/[key]/<relation>`.

Each protocol proposal reserves names of its own for later query and metadata operations, such
as count, in a form its protocol allows.

#### Types

The shape is defined in terms of the types persist already generates. A protocol uses them
directly where their JSON form suits a client, and generates wire types where it does not. The
HTTP proposal does this for entities with date, time or `byte[]` fields, which it sends as
ISO 8601 and base64 strings. The conversions are functions in `ballerina/dataservice`, so
every protocol uses the same formats.

| Type | Used as |
|---|---|
| `<Entity>` | The result of every operation that returns a record |
| `<Entity>Insert` | The input to create one and create many |
| `<Entity>Update` | The input to patch one |

A relation's foreign key fields are fields of these types, whether the model declares them with
`@sql:Relation` or persist infers them from the relation field, such as `departmentId` for
`Employee.department`. They are returned, filtered, sorted and written like any other field.

Get many and create many return an envelope rather than a bare array:

```ballerina
public type EmployeeList record {
    Employee[] items;
    boolean hasMore;
};
```

`hasMore` is `true` when records exist after this page; see [Query options](#query-options).
Create many sets it to `false`. The envelope is an open record, so a field added to it later,
such as a total, does not break a client; see
[Compatibility of the generated API](#compatibility-of-the-generated-api). MCP also requires a tool's structured result to be an object, so a
bare array cannot be used there in any case.

The service generates these types per exposed entity, each where an operation uses it:

| Type | Holds |
|---|---|
| `<Entity>List` | A page of `<Entity>` records, as above |
| `<Entity>Partial` | A record narrowed by `fields`; see [Fields](#fields) |
| `<Entity>PartialList` | A page of `<Entity>Partial` records, as an open record |
| `<Entity>RelatedPartial` | A related record in `fields`: the entity's own fields and no relation fields |
| `<Entity>RelatedPartialList` | A to-many relation in `fields`: `<Entity>RelatedPartial` records and `hasMore`, as an open record |
| `<Entity>Filter` | The `filter` option |
| `<Entity>Payload`, `<Entity>InsertPayload`, `<Entity>UpdatePayload` | The wire types of `<Entity>`, `<Entity>Insert` and `<Entity>Update`, where a protocol needs them |
| `<Entity>Created`, `<Entity>ListCreated` | The protocol's result of create one and create many, where the protocol needs one |

These names share the default module's namespace with the user's own code; see
[Generated code](#generated-code).

#### Results

| Operation | Returns |
|---|---|
| Get many | `<Entity>List` holding one page of the records that match the query options |
| Get one | `<Entity>` |
| Get related | `<Target>List` for a to-many relation, `<Target>` for a to-one relation |
| Create one | The created `<Entity>`, read back after insert so that generated fields are included |
| Create many | `<Entity>List` holding the created records |
| Patch one | The updated `<Entity>`, as returned by the persist client, or no record |
| Delete one | The deleted `<Entity>`, as returned by the persist client, or no record |

Creates return records rather than keys because changing a result type later would break
clients.

- **Atomic creates:** create one and create many run the insert and the read-back in one
  transaction, so either every record is created or none is. The created records are read back
  with one query, whose filter is `anyOf` their keys.
- **Order of created records:** create many returns the records in the order of the request, so
  the record at each position was created from the input at that position.
- **Batch size:** create many accepts at most `dataserviceConfig.maxPageSize` records. More is
  invalid input.
- **Patch and delete with `read`:** when the entity allows `read`, patch and delete return the
  record only to a caller who is also allowed to read the entity, and no record to any other
  caller. So `update` or `delete` alone does not reveal a record, for example through a patch
  that sets no field. [Auth](#auth) says how the caller is checked.
- **Patch and delete without `read`:** when the entity does not allow `read`, patch and delete
  return no record.
- **Update not read back:** when the persist client saves an update but cannot read the record
  back, it returns `persist:ReadBackError`. Patch then returns no record, because the update
  succeeded, and the error is logged.
- **Empty patch:** a patch that sets no field changes nothing. It is answered as get one when
  the record would be returned, and with no record, without reading, otherwise.

#### Field rules

Three annotations say what the API does with a field. A field without any of them is returned,
and accepted on create and update.

| Annotation | Returned | Accepted on create | Accepted on update | For example |
|---|:-:|:-:|:-:|---|
| `@dataservice:ReadOnly` | yes | no | no | `Order.status` set by a workflow, `Invoice.total`, `Account.balance` |
| `@dataservice:Immutable` | yes | yes | no | `Order.customerId`, `Invoice.number`, `Product.sku` |
| `@dataservice:Internal` | no | no | no | `User.passwordHash`, `Order.internalNotes`, `Product.costPrice` |

```ballerina
type Order record {|
    readonly int id;
    @dataservice:Immutable
    int customerId;
    @dataservice:ReadOnly {value: "pending"}
    string status;
    @dataservice:Internal
    string? internalNotes;
|};
```

```ballerina
public type FieldRuleConfig record {|
    anydata value?;
|};

public const annotation FieldRuleConfig ReadOnly on source record field;
public const annotation Immutable on source record field;
public const annotation FieldRuleConfig Internal on source record field;
```

The names follow the field behaviours of [Google AIP-203](https://google.aip.dev/203)
(`OUTPUT_ONLY`, `IMMUTABLE`) and OpenAPI's `readOnly`.

##### Values on create

A `ReadOnly` or `Internal` field is never sent by the caller, so the service sets it on create:
to `value` when the annotation gives one, and otherwise to `()`. A field that is neither
nullable nor `@sql:Generated` must give `value`, because the insert fails without it. Persist
does not accept default values on model fields, so the value is given in the annotation. It
must be a constant of the field's type.

##### A field sent anyway

| Annotation | Sent on create | Sent on update |
|---|---|---|
| `ReadOnly` | Ignored | Ignored |
| `Immutable` | Accepted | Rejected as invalid input |
| `Internal` | Rejected as invalid input | Rejected as invalid input |

The protocol proposal gives the response for a rejected field.

Ignoring a read-only field lets a client send back a record it has read, as AIP-203 requires.
AIP-203 also accepts an immutable field whose value is unchanged; that needs the record to be
read before every update, so it is not done; accepting it later does not break callers.

##### Fields that are not returned

An `Internal` field is left out of every response, of `fields`, filtering and sorting, of
get related, and of error messages. Filtering or sorting on it would reveal its value without
returning it.

##### Relation fields

A relation has two kinds of field, and each takes its own rules. Its foreign key fields hold
the data, so the field rules apply to them as to any field. Its relation fields, one on each
side, are directions of navigation, so only `Internal` applies to them:

| Annotation | Foreign key field, such as `Employee.departmentId` | Relation field, such as `Employee.department` or `Department.employees` |
|---|---|---|
| none | Returned and written | Get related and `fields` in this direction |
| `ReadOnly` | Returned, never written | Compile error |
| `Immutable` | Set on create, never changed | Compile error |
| `Internal` | Neither returned nor written; no get related or `fields` in either direction | No get related or `fields` in this direction; the foreign key is still returned and written |

```ballerina
type Employee record {|
    readonly int id;
    @dataservice:Immutable
    int departmentId;
    @sql:Relation {keys: ["departmentId"]}
    @dataservice:Internal
    Department department;
|};
```

Here an employee's department is set on create and never changed, and
`employees/[id]/department` is not offered, while `departments/[id]/employees` still is.

- **Inferred foreign keys:** a foreign key that persist infers has no field in the model to
  annotate. To give it a rule, declare it with `@sql:Relation`.
- **Composite foreign keys:** each foreign key field takes the rule and its own `value`. The
  foreign key fields of one relation have the same rule.
- **Internal foreign keys:** reading related records in either direction filters on the foreign
  key, so an `Internal` foreign key hides the relation from both sides.

##### Validation

Like the checks on `@dataservice:Expose`, the compiler plugin makes each check, in the IDE and
when the persist tool compiles the model.

| Check | Severity | Message |
|---|---|---|
| At most one of `ReadOnly`, `Immutable` and `Internal` on a field | error | `the field '<field>' of the entity '<Entity>' has more than one of @dataservice:ReadOnly, @dataservice:Immutable and @dataservice:Internal. Keep one.` |
| None of them on a key field, except `ReadOnly` on a `@sql:Generated` key | error | `the key field '<field>' of the entity '<Entity>' cannot have @dataservice:<rule>.` |
| A `ReadOnly` or `Internal` field that is neither nullable nor generated gives `value` | error | `the field '<field>' of the entity '<Entity>' needs a 'value' in @dataservice:<rule>.` |
| `value` matches the field's type | error | `the 'value' in @dataservice:<rule> of the field '<field>' of the entity '<Entity>' is not a '<type>'.` |
| No `ReadOnly` or `Immutable` on a relation field | error | `@dataservice:<rule> cannot be used on the relation field '<field>' of the entity '<Entity>'. Use it on the foreign key field, declared with @sql:Relation.` |
| The foreign key fields of one relation have the same rule | error | `the foreign key fields of the relation '<relation>' of the entity '<Entity>' must have the same field rule.` |
| No `ReadOnly` or `Internal` on the foreign key of a one-to-one relation when the entity allows `create`: the key is unique, so every create after the first would fail | error | `@dataservice:<rule> cannot be used on the field '<field>' of the entity '<Entity>', the foreign key of a one-to-one relation. Remove it.` |
| A field rule that the entity's actions make meaningless: `Immutable` without `update`, `ReadOnly` without `create` and `update`, `Internal` without `read`, `create` and `update`, and `Internal` on a relation field without `read` | warning | `@dataservice:<rule> on the field '<field>' of the entity '<Entity>' has no effect. Remove it, or add '<actions>' to 'operations'.`, where `<actions>` names each of those actions, joined by `' or '` |

##### Not field rules

- **Write-only fields,** such as AIP-203's `INPUT_ONLY`. Their usual purpose is a secret such as
  a password, which needs hashing, and the data service runs no user code. The service would
  store the value as sent.
- **Masked values,** such as returning `"password": ""`. The type then misdescribes the
  response, there is no masked value for most types, and a client that sends a read record back
  overwrites the real value. A field that must not be returned is `Internal`.
- **One annotation listing a field's actions,** such as
  `@dataservice:Field {operations: [dataservice:READ, dataservice:CREATE]}`. It covers the same
  cases, but each use has to be decoded; the named annotations say what they do.

#### Query options

Get many and get related on a to-many relation take the query options `filter`, `sort`,
`size`, `offset` and `fields`; get one and get related on a to-one relation take `fields`. They
are part of the `read` action, so they need no annotation:

| Option | Meaning |
|---|---|
| `filter` | Returns only the records that match every condition |
| `sort` | Orders the records by one or more fields, each ascending or descending. Without it, the records are ordered by key |
| `size` and `offset` | Returns one page of `size` records, skipping the first `offset` records |
| `fields` | Returns only the named fields of each record |

##### Which fields

The rules are fixed. There is no annotation to change them for a field:

| Field | `filter` | `sort` | `fields` |
|---|---|---|---|
| A field of a scalar, enum or `time:*` type | yes | yes | yes |
| A `byte[]` field | no | no | yes |
| A relation field | no | no | yes, one hop: the whole related record or chosen fields of it; see [Relations](#relations) |

A field that [field rules](#field-rules) hide from callers is never usable in a query option.

##### Filter

A filter is a list of conditions on fields, and a record matches when every condition holds.
Each condition is a field, an operator and a value in the field's wire form, such as an
ISO 8601 date:

| Operator | Meaning | Field types |
|---|---|---|
| `eq`, `ne` | equal, not equal | every filterable type |
| `lt`, `lte`, `gt`, `gte` | less than, at most, greater than, at least | numbers, `string`, `time:*` |
| `anyOf` | equal to any value in a list | every filterable type |
| `contains`, `startsWith` | the value occurs in, or starts, the field | `string` |
| `isNull` | `true` for null, `false` for not null | nullable fields |

- **Names:** the operator names are not Ballerina keywords, so each protocol can use them as
  they are. `anyOf` stands for `in`.
- **Strings:** comparisons, `contains`, `startsWith` and sorting follow the database's
  collation, so they ignore case on a database whose collation does, as MySQL's and MSSQL's
  defaults do. `%` and `_` in the value match themselves.
- **Nulls:** `ne` does not match a record whose field is null, as in SQL. Such records are
  matched with `isNull`.
- **Empty lists:** `anyOf` with an empty list matches no record.
- **Dates and times:** compare as the values they denote. A `time:Civil` value has no offset
  and compares as stored, so a filter value with an offset is invalid input. A `time:Utc` value
  may carry any offset, and is converted to UTC.
- **Or:** conditions joined by `or`, and nested groups, are left to a later proposal. The
  filter is represented as a tree in `ballerina/dataservice`, so adding them changes no type.

##### Sort and page

- **Sort:** a list of fields, each ascending or descending. The key fields are added at the end
  in ascending order, so the order is total. Without `sort`, the records are ordered by key. A
  field named more than once is invalid input.
- **Nulls:** sort last in ascending order and first in descending order, on every SQL datastore.
- **Size:** the page size. Without it, `dataserviceConfig.pageSize` applies. A size above
  `dataserviceConfig.maxPageSize` is reduced to it, and a size below 1 is invalid input.
- **Offset:** the number of records to skip, `0` by default. An offset below 0, or one for
  which `offset + size` exceeds the largest integer, is invalid input. Because the order is
  total, the same offset returns the same records while the data does not change.
- **More records:** the service reads `size + 1` records and returns `size`. `hasMore` is
  `true` when the extra record exists, and the next page is at `offset + size`. No count query
  is needed.
- **No total:** a total needs a second query and is left to a later proposal. The envelope
  leaves room for it.

##### Fields

`fields` names the fields to return; the others are left out of each record. The key fields
are always returned, so that every record can be addressed, and are required fields of every
`<Entity>Partial` and `<Entity>RelatedPartial` type. Without `fields`, every field is returned.

- **Repeats:** a field named twice counts once.
- **Empty:** an empty `fields` is invalid input.
- **Overlaps:** naming a whole relation and one of its fields, such as `department` and
  `department.name`, returns the whole relation.

`fields` narrows the result, not the query: the record is read in full, then narrowed. Reading
only the named fields needs a runtime projection in the persist client, which is later work.

##### Relations

A relation field is read in two ways, both under the `read` action:

| Way | Example | Returns |
|---|---|---|
| Get related | `employees/[4]/department`, `departments/[2]/employees` | The related records, with the query options of get many for a to-many relation |
| A relation in `fields` | `fields` naming `department`, `department.name`, `employees` or `employees.name` | Each record with the related record, or the chosen fields of it, included |

Persist models these kinds of relation, and each is read with the rules below:

| Kind | In the model | Foreign key | Read |
|---|---|---|---|
| One to many | `Employee.department` and `Department.employees` | On the many side: `Employee.departmentId` | To-one from `Employee`, to-many from `Department` |
| One to one | `Profile.employee` and the nullable `Employee.profile` | On the side whose relation field is not nullable: `Profile.employeeId`, which persist makes unique | To-one from both sides; from `Employee` it can be empty |
| From an entity to itself | Not supported by persist, which rejects it with `an entity cannot reference itself in a relation field` | — | — |
| Many to many | Not supported by persist; a join entity, such as `Assignment`, with a one-to-many relation to each side | On the join entity: `Assignment.employeeId` and `Assignment.projectCode` | Through the join entity, such as `assignments` filtered by `employeeId` with `fields` naming `project` |

- **Exposure:** get related and a relation in `fields` are offered only when both the entity and
  the related entity allow `read`, and neither the relation field nor the foreign key is
  `Internal`; see [Relation fields](#relation-fields). A relation needs no annotation to be
  offered: a caller who can read both entities can already reach the related records through
  the foreign key, so `Internal` on a relation field shapes the API rather than protecting
  data. When the related entity does not allow `read`, the foreign key fields are still
  returned as fields of the record.
- **Default:** without `fields`, or when `fields` names no relation, no related record is
  included, so a plain read costs one query.
- **One hop:** `fields` on get many or get one can name the entity's relations and their own
  fields, such as `department.name`, but not a relation of a related entity, such as
  `department.employees`. `fields` on get related names only the related entity's own fields.
- **Related type:** an included related record is a `<Target>RelatedPartial`, which has the
  related entity's own fields and no relation fields. Its key fields are always returned.
- **To-one in `fields`:** a to-one relation with no related record is included as `null`. This
  happens on the side of a one to one relation that does not hold the foreign key, and when a
  foreign key points at a missing record. A foreign key is never null: persist rejects a
  nullable relation field on the side that holds it.
- **To-many in `fields`:** an included to-many relation is a list envelope, `items` and
  `hasMore`, holding at most `dataserviceConfig.pageSize` records in key order. `hasMore` tells
  the caller to page through the rest with get related. Dotted fields, such as
  `employees.name`, narrow its records.
- **Missing records:** get related answers not found when the record with the given key does
  not exist, or when a to-one relation has no related record. A to-many relation with no
  related records returns an empty list.
- **Writes:** a relation is set by writing its foreign key fields under the owning entity's
  `create` or `update`. Nested writes are later work.

`ballerina/dataservice` reads related records with the query machinery of get many, not with
the persist client's relation loading, which runs one query per parent record and reads every
related record ([ballerina-library#9375](https://github.com/ballerina-platform/ballerina-library/issues/9375)):

| Read | Queries |
|---|---|
| Get related | One get many on the related entity, filtered by the foreign key, plus one get one when the record itself must be checked |
| A to-one relation in `fields` | One per page: the related records whose key is any of the page's foreign key values |
| A to-many relation in `fields` | One per record of the page: the related records whose foreign key is the record's key, limited to `dataserviceConfig.pageSize + 1` rows in key order |

A composite key matches as `or` over the key tuples, which the filter tree represents even
though callers cannot write `or` yet.

##### Where the query runs

The generated service passes the options and a description of the entity to
`ballerina/dataservice`, which validates them and builds the query. The query runs in the
database, through the persist SQL client's `whereClause`, `orderByClause`, `limitClause` and
`offsetClause` ([#1515](https://github.com/ballerina-platform/ballerina-spec/issues/1515)).
Values are bound as parameters; field and column names come only from the generated entity
description.

The entity description holds:

- **Entity:** its name, its collection name, its persist resource name and the datastore.
- **Fields:** per field, its name, column name and type, whether it is nullable, and whether it
  is a key field or generated.
- **Relations:** per relation, its field, the target entity, the cardinality, and the foreign
  key fields and their columns.

`ballerina/dataservice` writes the SQL for the datastore in the description:

| Rule | MySQL | MSSQL | PostgreSQL, H2 |
|---|---|---|---|
| Quoted identifiers | `` `name` `` | `[name]` | `"name"` |
| Nulls last ascending, first descending | `CASE WHEN … IS NULL` ordering | `CASE WHEN … IS NULL` ordering | `NULLS LAST`, `NULLS FIRST` |
| Escaped in `contains` and `startsWith` | `%`, `_` and the escape character | `%`, `_`, `[` and the escape character | `%`, `_` and the escape character |

The escaped characters are matched through an `ESCAPE` clause. `anyOf` with an empty list
writes no `IN ()`, and the condition matches no record.

Invalid options, and other input that `ballerina/dataservice` checks, are answered before the
persist client is called, with `INVALID_INPUT` unless the row says otherwise:

| Case | Message |
|---|---|
| An unknown field, or one that cannot be used for the option | `The field '<field>' of the entity '<Entity>' cannot be used in '<filter\|sort\|fields>'.` |
| An operator that does not apply to the field's type | `The operator '<operator>' cannot be used on the field '<field>' of the entity '<Entity>'.` |
| A value that does not parse | The value message in the protocol proposal |
| A relation of a related entity in `fields` | `The field '<field>' of the entity '<Entity>' cannot be used in 'fields'.` |
| An empty `fields` | `'fields' must name at least one field.` |
| A field named more than once in `sort` | `The field '<field>' is named more than once in 'sort'.` |
| A to-one relation with no related record | `The record with the key '<key>' of the entity '<Entity>' has no '<relation>'.`, with the code `NOT_FOUND` |
| A size below 1 | `The page size must be at least 1.` |
| An offset below 0 | `The offset must be at least 0.` |
| An offset for which `offset + size` exceeds the largest integer | `The offset and the page size together exceed the largest integer.` |
| A create with more than `dataserviceConfig.maxPageSize` records | `A create can hold at most <max> records.` |
| A `float` key that is `NaN` or infinite | `The key '<key>' of the entity '<Entity>' is not a finite number.` |

#### Errors

Errors fall into protocol-neutral categories. `ballerina/dataservice` defines one error body
and an error code per category, and every error the service answers uses that body, including
the errors the protocol module raises before the operation runs, such as auth and binding
errors:

```ballerina
public enum ErrorCode {
    NOT_FOUND,
    CONFLICT,
    CONSTRAINT_VIOLATION,
    INVALID_INPUT,
    UNAUTHENTICATED,
    FORBIDDEN,
    INTERNAL
}

public type DataserviceError record {|
    ErrorCode code;
    string message;
|};
```

The body is a closed record, so adding a code or a field to it is a breaking change of the
libraries, made in a new major version; see
[Compatibility of the generated API](#compatibility-of-the-generated-api).

Each protocol proposal maps the categories to its own form: an HTTP status code, an entry in
the GraphQL `errors` array, or an MCP tool result with `isError` set.

| Category | `code` | Raised when | Source |
|---|---|---|---|
| Not found | `NOT_FOUND` | No record has the given key | `persist:NotFoundError` |
| Conflict | `CONFLICT` | A record with the key or a unique value already exists | `persist:AlreadyExistsError` |
| Constraint violation | `CONSTRAINT_VIOLATION` | A write violates a foreign key | `persist:ConstraintViolationError` |
| Invalid input | `INVALID_INPUT` | The input cannot be bound to the operation's type, a value is not in its format, or a value breaks a constraint of the model | The protocol module's binding or validation error, or a `ballerina/dataservice` check or conversion |
| Unauthenticated | `UNAUTHENTICATED` | With `auth = true`, the caller has no credential, or one that no provider accepts | The protocol module's auth |
| Forbidden | `FORBIDDEN` | With `auth = true`, the caller holds no scope of the operation's action, or, for get related or a relation in `fields`, no `read` scope of the related entity; see [Auth](#auth) | The protocol module's auth, or its relation check |
| Internal | `INTERNAL` | Any other failure | `persist:Error` and others |

The message is written by `ballerina/dataservice`, not taken from the persist error, because the
SQL datastores put driver text, such as table and constraint names, in their error messages:

| Category | Message |
|---|---|
| Not found | `A record with the key '<key>' does not exist for the entity '<Entity>'.` |
| Conflict | `A record that conflicts with an existing record of the entity '<Entity>' already exists.` |
| Constraint violation | `The operation violates a constraint of the entity '<Entity>'.` |
| Invalid input, a constraint broken on a field of a wire type | `The field '<field>' of the entity '<Entity>' breaks its '<constraint>' constraint.` |
| Invalid input, raised by the protocol module's binding or validation | The protocol module's message |
| Unauthenticated | `The request needs a valid credential.` |
| Forbidden, a scope of the action | `The caller holds no scope that the operation needs.` |
| Forbidden, a relation | `The relation '<relation>' of the entity '<Entity>' needs a 'read' scope of the entity '<Target>'.` |
| Internal | `An internal error occurred.` |

A composite key is written as its values joined by `/`, in key order.

The service logs the persist error's own detail for an internal error or a constraint
violation at error level, with the entity and the operation, and does not return it to the
caller. Request bodies and query values are not logged.

A disabled operation is not generated at all, so it does not exist rather than being refused.
The error a caller sees when calling one is protocol-specific: a 404 or 405 for HTTP, a
validation error for GraphQL, and an unknown tool for MCP.

### Auth

Authentication is configured on the listener, and authorization is a scope per action. Both are
generated only when `options.dataservice.auth` is `true`:

- **Without auth:** with `auth = false`, the default, no auth code is generated and every
  caller can perform every enabled action. A model that sets `scopes` gets a build warning.
- **Providers:** with `auth = true`, the protocol proposal adds a required field under
  `dataserviceConfig` for the authentication providers, such as JWT validation, set in
  `Config.toml`. It has no default, so the service does not start when `Config.toml` does not
  set it, and an empty list also stops it at startup.
- **Scopes:** with `auth = true`, every operation requires a scope of its action. A caller
  needs any one scope of the list.
- **Order:** with `auth = true`, the caller is authenticated, and the scopes of the operation's
  action are checked, before the request is routed to an operation or its input is bound. A
  caller without a valid credential gets `UNAUTHENTICATED` whatever the request, so binding
  errors do not reveal the input types to it. The credential is checked once per request, and
  the checks below use the caller it gave.
- **Defaults:** an action not listed in `scopes` requires `<resource>:<action>`, where
  `<resource>` is the entity's collection name, as in `employees:read` and
  `projectAssignments:create`.
- **Authentication only:** an empty list, as in `read: []`, requires an authenticated caller
  and no scope.
- **Patch and delete results:** with `auth = true`, patch and delete return the record only
  when the caller is also allowed to read the entity. The service checks the caller against the
  `read` scopes when the request runs, and returns no record when the caller is not allowed to
  read.
- **Get related** and **a relation in `fields`** require the entity's own `read` scopes, like
  every read of the entity, and the caller must also be allowed to read the related entity. The
  service checks the caller against the related entity's `read` scopes when the request runs,
  and answers with `FORBIDDEN` when the caller is not allowed to read it.
- **Checks at runtime:** these checks run for every such request, whatever the scopes, rather
  than being left out when one entity's scopes seem to include another's. A protocol can give
  an empty list scopes at runtime, such as scopes that its providers require, so the scopes
  alone cannot tell which callers pass. Each check reuses the caller that the credential check
  gave. The
  protocol proposal says how the caller is checked.

```ballerina
@dataservice:Expose {scopes: {read: ["hr:read"], delete: ["hr:admin"]}}
type Employee record {| ... |};
// read: hr:read; create: employees:create; update: employees:update; delete: hr:admin
```

Scopes are per action, not per operation, for the same reason as actions: a scope is a
capability, and every operation of an action uses the same capability. Patch and delete return
the changed record without a `read` scope; see [Results](#results).

### Constraints

A model field can carry `ballerina/constraint` annotations, such as
``@constraint:String {maxLength: 50, pattern: re `[A-Z].*`}`` or `@constraint:Int {minValue: 0}`.
The service rejects a create or patch whose value breaks one as invalid input, and the protocol
proposal gives the response. Wire types copy the model's constraint annotations.

Today the persist tool keeps only `maxLength` in the generated types, and the persist client
checks no constraint on its own writes. Keeping every constraint in the generated types, and
checking them in the client's `post` and `put`, is a persist prerequisite
([ballerina-library#9376](https://github.com/ballerina-platform/ballerina-library/issues/9376)),
so that the same model rejects the same values whether they are written through the service or
the client. The tool does not warn about constraints in a model without a data service: like
other annotations, they take effect where they are checked, and `maxLength` already sets column
lengths today.

### Documentation

A data service is documented from the model. Each operation gets a generated one-line doc
comment, and the doc comments that the model gives an entity and its fields are added to the
generated resources and types:

```ballerina
# A person employed by the company.
@dataservice:Expose
type Employee record {|
    readonly int id;
    # The date the employee joined, in the company's time zone
    time:Date hiredOn;
|};
```

A foreign key field without a doc comment gets one that names its relation, such as
`The key of the related 'Department'.`, so the description shows the link also where the
relation itself is not offered.

The same doc comments describe the service in every protocol: as OpenAPI descriptions for HTTP,
as schema descriptions for GraphQL, and as tool and argument descriptions for MCP. A user adds
documentation the way they document any Ballerina type, with no annotation to learn.

The service publishes its own description at runtime, as each protocol expects:

| Protocol | Description | With `introspection = false` |
|---|---|---|
| HTTP | An OpenAPI definition, embedded at build time | Not published |
| GraphQL | Schema introspection | Disabled |
| MCP | The tool list | Published, because an MCP client needs it to use the service |

The description holds nothing a caller cannot learn by calling the service, so it is published
by default. With `auth = true`, it is published behind the service's auth, so only an
authenticated caller reads it; the protocol proposal says how. `introspection = false`
withholds it.

The persist tool does not keep the model's doc comments in the types it generates today, and a
data service uses those types for entities without wire types. Keeping them is a persist
prerequisite; see [Dependencies](#dependencies).

### Runtime configuration

Runtime settings follow the database connection settings. Persist generates the database host,
port, user, password and database name as configurable values in `persist_db_config.bal`, and
the user sets them in `Config.toml`. The data service does the same: the tool generates
`dataservice_config.bal`, which declares one configurable record, `dataserviceConfig`, holding
the listener and paging settings.

The record's type comes from the libraries, not from generated code. `ballerina/dataservice`
defines the fields every protocol has, and each protocol library defines its configuration type
by including them and adding its own fields:

```ballerina
// ballerina/dataservice
public type Config record {|
    int port = 9090;
    int pageSize = 100;
    int maxPageSize = 1000;
|};
```

```ballerina
// dataservice_config.bal, for HTTP
configurable dsHttp:Config dataserviceConfig = {};
```

The user sets only the fields to change:

```toml
[dataserviceConfig]
port = 8080
pageSize = 50
```

- **One table:** the settings are grouped under `[dataserviceConfig]`, so their names need no
  prefix and do not clash with the database configuration, which already declares `port` in
  the same module.
- **Defaults:** every field has a default, so the service runs without any `Config.toml` entry,
  unlike the database settings. A field left out of the table keeps its default.
- **Misspelled names:** the record is closed, so an unknown field, such as `pagesize`, stops the
  program at startup.
- **Per protocol:** every protocol uses these field names. The values shown are the HTTP
  defaults; a protocol library's type can give its own, because a good page size differs by
  protocol: an agent reading MCP results needs smaller pages than an HTTP client. It adds its
  own fields, such as listener and auth settings.
- **Library types:** a setting added to a library type, in a minor version, is available
  without regenerating, and a generated name cannot clash with the user's types.

✅ On Ballerina 2201.14.0, a field left out of `[dataserviceConfig]` kept its default, an
unknown field stopped the program with
`undefined field 'pagesize' provided for closed record`, and a record type that includes
`Config` and gives `pageSize` another default used that default.

The values are checked at startup by `dataservice:toPageConfig` in the service's `init`. The
service does not start, and the program stops with a message, when a value is out of range:

| Case | Message |
|---|---|
| `maxPageSize` below 1 | `The configurable value 'dataserviceConfig.maxPageSize' must be at least 1, found <value>.` |
| `pageSize` below 1 or above `maxPageSize` | `The configurable value 'dataserviceConfig.pageSize' must be between 1 and 'dataserviceConfig.maxPageSize' (<max>), found <value>.` |

Other listener settings, such as TLS, are left to the protocol proposals.

### Observability

The generated service is an ordinary Ballerina service, so Ballerina observability, with its
metrics, tracing and logs, applies to its listener. What the service itself logs is given in
[Errors](#errors). Health checks are out of scope.

### Datastore support

A data service is generated for the SQL datastores of `ballerinax/persist.sql`: MySQL, MSSQL,
PostgreSQL and H2. Query options and relations run in the database through the SQL client's
clause arguments, which the in-memory, Google Sheets and Redis clients do not have: they read
every record of an entity for each query. Any other `options.datastore` is an error.

Changing between the SQL datastores needs no change to the model or to callers. `bal build`
regenerates the client and the service for the new datastore, with the same behaviour except
where the databases differ, such as the collation of string comparisons and sorting; see
[Filter](#filter).

Whether each field type can be represented in each protocol is defined by the protocol
proposals. For example, persist's `time:*` record types and `byte[]` need a GraphQL mapping.

### Compatibility of the generated API

The generated API follows the model, so a change to the model can break callers:

| Breaks callers | Does not break callers |
|---|---|
| Renaming or removing an entity or a field | Adding an entity |
| Adding a required field without a default | Adding an action |
| Adding a field that is returned, for a client that rejects unknown fields | Adding a field that is returned, for a client that ignores unknown fields |
| Changing the type of a field or a key | Adding an optional field that is not returned, such as an `Internal` one |
| Removing an action | |

An entity's types are closed records, so the protocol's definition says that a record holds
no other field, and a client generated from it may reject one. ✅ On Ballerina 2201.14.0, an
`http:Client` reading a response into a closed record failed with
`Payload binding failed: undefined field 'extra'`. Adding a field to an entity is therefore a
breaking change for such clients.

The list envelopes, `<Entity>List`, `<Entity>PartialList` and `<Entity>RelatedPartialList`,
are open, so a field added to them later, such as a total count, does not break a client.
Clients must ignore unknown fields in them.

`DataserviceError` stays closed. As an open record, it would stop Ballerina from narrowing the
unions that the library functions return, such as `Query|DataserviceError|ConversionError`:
✅ on Ballerina 2201.14.0, `if query !is Query { return query; }` left `query` typed with
`Query` when `DataserviceError` was open, and compiled when it was closed. A new error code or
field, such as one for a failed precondition, is therefore added in a new major version of the
libraries, and the services are regenerated.

A breaking change can be published beside the old API by generating it with a new `basePath`,
such as `/api/v2`. Regenerating with a newer persist-tools keeps the wire contract unchanged
within a major version of the libraries, apart from additions to the list envelopes.

### Backward compatibility

- Without `options.dataservice`, nothing changes: the client, its files and all commands
  behave as today.
- `persist-options-schema.json` currently sets `additionalProperties: false`. It gains a
  `dataservice` object; existing entries still validate.
- Models that do not import `ballerina/dataservice` are unaffected. Without
  `options.dataservice`, `@dataservice:Expose` annotations in a model have no effect.

### Generated code

- **Location:** the data service is generated only into the package's default module. When
  `options.dataservice` is present, `targetModule` must be the package name, which is persist's
  default when `--module` is not passed. Any other `targetModule` is an error.
- **Why the default module:** a service in the default module is started without the user
  importing anything.
- **Files:** the service is generated next to the persist client, in `dataservice.bal`, which
  holds the client, the listener and the service, `dataservice_types.bal`, which holds the types
  the service uses, and `dataservice_config.bal`. From the `[[tool.persist]]` entry, they go
  into `generated/` and, like the client, are regenerated on every build and must not be edited.
  From `generate`, they go into the package root, where the client also goes, and are the
  user's.
- **Regeneration:** in `generated/`, the service files are rewritten whenever the client is.
  The tool's check that skips generation for an unchanged model also covers
  `options.dataservice`, so changing any of its keys regenerates the service. When
  `options.dataservice` is removed, the tool deletes the service files from `generated/`.
  Files that `generate` wrote into the package root are the user's and are never deleted.
- **Names:** generated module-level names share the default module's namespace with the user's
  own code, as the persist client's generated names already do. The service follows the same
  convention: type names are derived from entity names, as listed in [Types](#types), the
  functions that convert to and from a protocol's wire types are named `transform<Entity>ToPayload`,
  `transformPayloadTo<Entity>Insert` and `transformPayloadTo<Entity>Update`, and other
  module-level names start with `dataservice`.
- **Client construction:** the service creates the persist client with `new ()`, so
  `options.withInitParams = true` cannot be used together with `options.dataservice`.
- **One service per package:** a package has one persist model and at most one data service.
  Persist's `--model` option for several models is not supported together with
  `options.dataservice`.

### Implementation scope

| Implemented with this proposal and #1513 | Designed, not implemented |
|---|---|
| `ballerina/dataservice`: `Operation`, `ExposeConfig`, `Expose`, `ErrorCode`, `DataserviceError`, the persist error mapping, the date, time and `byte[]` conversions, the [query options](#query-options), relation reads, `Scopes`, the [field rules](#field-rules) `ReadOnly`, `Immutable` and `Internal`, and the compiler plugin | |
| `ballerina/dataservice.http`, as #1513 defines it | `EXECUTE`, which is not a member of `Operation` until custom operations are proposed |
| persist-tools: `options.dataservice` with `protocol = "http"` and `auth`, the CLI flags, validation, and generation of the HTTP service with its documentation | The `graphql`, `mcp`, `odata` and `soap` protocol values, which are errors |
| | Everything in the [Roadmap](#roadmap) |

End-to-end behaviour tests live in persist-tools, which generates the service. The libraries
test their own functions and the compiler plugin.

The releases go in this order: `ballerinax/persist.sql`, with the offset clause and the limit
fix of #1515, then `ballerina/dataservice`, then `ballerina/dataservice.http`, then
persist-tools. The generated package depends on those minimum versions.

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
exposed when the list is omitted. This splits what is exposed across two files, and a
misspelled entity name is caught only when the tool runs, while an annotation sits on the type
it exposes and is checked by the compiler plugin as it is written. Exposing every entity by
default also exposes an entity added to the model later without anyone choosing to.

Per-entity operations in `Ballerina.toml`, such as
`options.dataservice.entities.Department = ["read"]`, have the same split and cannot express
field-level rules such as a hidden field. `Ballerina.toml` is kept for how the service is
generated; the model holds what is exposed and what each entity allows.

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

### Per-field query restrictions

OData can mark a property as not filterable or not sortable, and Google AIP-160 lets a service
restrict its filter fields, usually to keep queries on indexed columns. A
`@dataservice:NotFilterable` style annotation is not included: the page size bounds every
result, and fields a caller must not see are excluded by field rules. It can be added if unindexed
scans become a problem in practice.

### Cursor paging

Data API builder pages by an opaque cursor that marks the last record of the previous page, so
pages do not shift when records are created or deleted before them. Offset paging is used
because a client can go to any page with it, as ZenStack, PostgREST and Spring Data REST allow,
and because a cursor ties every page to the sort it was issued for. A cursor can be added
later without changing the envelope.

### Field rules in `ballerina/persist`

The rules say what the service does with a field, not what the persist client does: an
`Internal` field is still read and written by the client. Under `persist`, a rule such as
`@persist:ReadOnly` would read as a rule for the client, and next to Ballerina's `readonly`, which
marks a key field, as another way to mark a key. They belong with `@dataservice:Expose`.

### Leaving a field out of the model

A field that the service must not show could be left out of the model. That works only when
nothing else needs it through persist. Otherwise the user's own code can no longer read or
write it, creates fail on a `NOT NULL` column without a database default, persist's script and
migrations lose the column, `pull` adds it back, and a relation that uses it cannot be declared.
`Internal` keeps the field in the model and out of the API.

### Persist's resource names as collection names

The collections could use the persist client's resource names, so that a path such as
`/projectassignments` matched the client's `dbClient->/projectassignments`. Persist lowercases
the whole entity name, a default kept from its first design's table names, while Ballerina names
fields in camelCase, as in the relation field `projectAssignments`. An API would then spell one
entity two ways: `/projectassignments/7` and
`/employees/4/projectAssignments`. Collections use camelCase instead, and
[ballerina-library#9434](https://github.com/ballerina-platform/ballerina-library/issues/9434) proposes the same rule for persist; adopting it would change no
path of the service.

### Field rules on the relation field

A rule on the relation field could govern both the relation and its foreign key, so that a
relation has its rule in one place whether its foreign key is inferred or declared. One
annotation then carries two meanings: `Internal` on the owning side would hide the foreign key
and both directions, with no way to hide only one direction and keep the key. Rules on the
foreign key fields, and `Internal` alone on relation fields, keep data and navigation apart.
The cost is that an inferred foreign key must be declared to take a rule.

### An annotation for relations

A separate annotation could control navigation: `@dataservice:ExposeRelation` to offer a
relation, or `@dataservice:NoRelation` to withhold one. Offering relations only on request
would match `@dataservice:Expose`, but `Expose` is opt-in because an entity can hold data that
must not be public, while a relation between two readable entities reveals nothing new. Turning
one off only shapes the API, which `Internal` on the relation field already says without a
second annotation.

### The relation field holding the foreign key

Directus and Strapi return a relation as its foreign key, `"department": 2`, and the same
field becomes the related record when the caller asks for it. The field's type then changes
with `fields`, which a typed client and an OpenAPI definition cannot describe as one type, and
every entity with a relation needs wire types in place of the persist types, which already hold
the foreign key fields.

### Reference objects for relations

JSON:API returns a relation as a reference, `{"type": "departments", "id": "2"}`, and keeps
foreign keys out of the attributes; Spring Data REST returns a link. Both hide the table's
structure, but need new types for every entity with a relation, make payloads larger, need a
syntax of their own to filter by a related key, and make the client follow a reference that a
plain foreign key field gives directly.

### Several protocols from one entry

The listeners of `ballerina/graphql` and `ballerina/mcp` both accept an `http:Listener`, so
several services can share one port. This is deferred so that each protocol's rendering can be
specified and settled on its own first. `protocol` is a string that can later also accept an
array.

### Separate configurable values

For example, `dataservicePort`, `dataservicePageSize` and `dataserviceMaxPageSize`, each a
configurable value of a simple type. One value, such as the port, can then be overridden with
`-CdataservicePort=8080` or an environment variable. It is not adopted because the settings
are scattered as top-level keys, each needing the `dataservice` prefix to avoid the database
configuration's names, and a protocol's listener and auth settings add more such keys. A
record groups them under one table and catches a misspelled field.

### An open error body

`DataserviceError` could be an open record with a string `code`, so that a code or a field
added later would not break a client. It is not adopted because an open record in a union
stops Ballerina's type narrowing, as shown in
[Compatibility of the generated API](#compatibility-of-the-generated-api), so the library
functions would need another way to return their errors. The cost is that a new code or field
needs a new major version.

### A generated configuration type

The tool could generate the record type into `dataservice_config.bal`. It is not adopted
because the generated name would share the user's namespace, a new setting would need
regeneration, and every protocol would generate the same paging fields.

## Testing

- **Options schema:** `options.dataservice` with valid and invalid values; required
  `protocol`; reserved protocol values.
- **CLI:** `add`, `pull` and `generate` with and without `--dataservice`; `pull` with and without
  `--expose-tables`, including unknown tables; `pull` into a project with and without an
  existing `[[tool.persist]]` entry; `pull` without `--dataservice` into an entry with and
  without `options.dataservice`.
- **Annotation validation:** each compiler-plugin rule; the bare annotation and its default
  operations; a model with no annotated entity; each field rule check.
- **Field rules:** per rule, the field returned or not, accepted or rejected on create and
  update, `value` set on create, an `Internal` field absent from `fields`, filters, sorting,
  get related and error messages; each rule on a declared foreign key, single and composite,
  and on a one-to-one foreign key;
  `Internal` on each relation field, and on the foreign key hiding both directions.
- **Code generation:** expected-output tests for each protocol, with single and composite keys,
  one-word, multi-word and irregularly pluralized entity names,
  every action combination, `auth` on and off, and the default and custom base path.
- **Auth warnings:** `scopes` with `auth = false`.
- **Relation auth:** with `auth = true`, a relation whose related entity shares a `read` scope
  with the entity, and one whose does not, each checked when the request runs.
- **Patch and delete auth:** with `auth = true`, a caller with and without a `read` scope gets
  the record and no record; an empty patch by a caller without one reads nothing.
- **Query building:** per datastore, quoted identifiers, null ordering, and escaping in
  `contains` and `startsWith`; an empty `anyOf`; `ne` on a nullable field; a field named twice
  in `sort`; the `fields` edge cases; an `offset` too large for the `size`.
- **Startup:** each out-of-range page size stops the program with its message; a field left out
  of `[dataserviceConfig]` keeps its default.
- **Compilation:** the generated package compiles on MySQL, MSSQL, PostgreSQL and H2, and any
  other datastore is rejected.
- **Behaviour:** an end-to-end CRUD round trip per protocol against H2, and against MySQL,
  PostgreSQL and MSSQL where a database is available, including each error category; a create
  many with a duplicate key among its records, which creates none of them; a create many above
  `dataserviceConfig.maxPageSize`; patch and delete on an entity with and without `read`; a
  to-one relation in `fields` that is empty or points at a missing record; a to-many relation
  in `fields` with more records than `dataserviceConfig.pageSize`.
- **Backward compatibility:** existing persist tests pass unchanged without
  `options.dataservice`.

## Risks and assumptions

- **Offset pages can shift.** A record created or deleted before a page between two requests
  moves the records after it, so a client paging through changing data can see a record twice
  or miss one.
- **Unindexed filters and sorts.** Every readable field can be filtered and sorted, so a
  caller can make the database scan a large table. The page size limits the result, not the
  scan.
- **To-many relations in `fields`.** Each costs one query per record of the page, until a single
  query with a limit per record replaces it. That change needs no change to the API.
- **Exposure without auth.** With `auth = false`, every caller can perform every enabled
  action. A bare `@dataservice:Expose` enables all four, including delete, and
  `pull --dataservice` annotates every pulled entity this way. Users must set `operations` in
  the annotations, or set `auth = true` and configure [Auth](#auth).
- **Dangling foreign keys.** A create or patch that sets a foreign key to a missing record is
  rejected with `CONSTRAINT_VIOLATION` only when the database has the foreign key constraint.
  Otherwise the reference dangles, and the relation reads as `null`.
- **Lost updates.** There is no optimistic concurrency control, such as `ETag` and `If-Match`,
  so concurrent patches of one record can overwrite each other.
- **Logged database detail.** The persist error detail that the service logs comes from the
  database and can contain values, such as a duplicate key value.
- **Name clashes in the default module.** Generated names share the user's namespace, as the
  persist client's already do. A user type with any name in [Types](#types), such as
  `EmployeeList`, fails to compile alongside the generated one.
- **No single-value overrides.** `-C` command-line arguments and `BAL_CONFIG_VAR_`
  environment variables take only simple types, so they cannot set one field of
  `dataserviceConfig`, such as the port. ✅ On Ballerina 2201.14.0,
  `-CdataserviceConfig.port=8080` was rejected as an unused command line argument. A deployment
  sets the table in `Config.toml`, in a file named by `BAL_CONFIG_FILES`, or in
  `BAL_CONFIG_DATA`.
- **Assumption:** the persist client's resource names, keys and generated types are stable
  enough for the service to build on them.

## Dependencies

- `persist-tools`: options schema, CLI flags, model validation, code generation.
- `ballerina/sql`, for the queries that `ballerina/dataservice` builds.
- `ballerina/persist` and `ballerinax/persist.sql`. Paging needs the SQL client's
  `offsetClause`
  ([#1515](https://github.com/ballerina-platform/ballerina-spec/issues/1515)), which also binds
  the `limitClause` value
  ([ballerina-library#9386](https://github.com/ballerina-platform/ballerina-library/issues/9386)). Atomic creates
  need the SQL client to take part in a Ballerina `transaction`, as `ballerinax/persist.sql`
  1.7.4 does.
  Constraint checks need the persist tool to keep every constraint in
  the generated types
  ([ballerina-library#9376](https://github.com/ballerina-platform/ballerina-library/issues/9376)).
  The persist changes that later work needs, such as a runtime projection
  for `fields` and a count, are tracked separately.
- The persist tool keeping the model's doc comments in the generated types, for the
  [documentation](#documentation) of entities without wire types
  ([ballerina-library#9390](https://github.com/ballerina-platform/ballerina-library/issues/9390)).
- `ballerina/dataservice` and `ballerina/dataservice.<protocol>`: new libraries.
- `ballerina/http`, `ballerina/graphql` and `ballerina/mcp`, through the protocol proposals.

## Future work

### Follow-up proposals

Each protocol proposal defines how the CRUD shape in this proposal is rendered. Each covers the
same points: the listener and service type, how each operation maps to a resource, query,
mutation or tool, how keys and types map, how the error categories map, the base path, and the
listener configuration.

| Proposal | Scope |
|---|---|
| 2. HTTP, [#1513](https://github.com/ballerina-platform/ballerina-spec/issues/1513) | `http:Service`: collection and key paths, methods, status codes, request and response bodies |
| 3. GraphQL, later | `graphql:Service`: queries and mutations, input and output types, type mappings for persist's time types and `byte[]`, error mapping |
| 4. MCP, later | `mcp:StreamableHttpService`: tool names, input and output schemas, descriptions from doc comments, tool annotations such as read-only hints, error results |

### Roadmap

| Area | Adds | Fits into v1 through |
|---|---|---|
| More query options | `or` and nested filter groups, a total count, reading only the selected fields from the database | The filter tree; the `<Entity>List` envelope; the names each protocol reserves |
| More auth | Row-level rules and fields visible only to some scopes | Scopes per action; annotations that only narrow |
| More datastores | The in-memory datastore, with query options applied in the service and its text comparison rules documented | The same query options and results |
| More relations | Nested writes, filtering and sorting on related fields, relations more than one hop away, many to many through a join entity that holds only the two keys, read as one hop | Get related and relations in `fields`; the `read` action |
| More write operations | Upsert, full replace, update or delete by filter, once the persist client supports them | The `create`, `update` and `delete` actions |
| Concurrency control | Optimistic concurrency through `ETag` and `If-Match` | Patch and delete by key |
| Custom operations | Named queries exposed as operations | The reserved `EXECUTE` action |
| Several protocols | Several services from one entry, on a shared listener | `protocol` also accepting an array |
| More protocols | OData, SOAP | The reserved `odata` and `soap` values |
| Pulling again | A later `pull` keeps the entities the replaced model exposed, and exposes a new table only through `--expose-tables` | `--expose-tables` |
