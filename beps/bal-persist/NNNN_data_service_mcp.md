# Data service generation for bal persist: MCP

- Author: @niveathika
- Reviewers: 
- Created: 2026-10-07
- Updated: 2026-10-07
- Issue: TBD
- Status: Draft

> This file is renamed to its issue number once the issue is created.

## Summary

Defines how the protocol-neutral CRUD shape in
[Data service generation for bal persist](1503_data_service.md) is rendered as an MCP server
when `options.dataservice.protocol = "mcp"`.

Each enabled operation becomes one typed MCP tool per entity, such as `getEmployee` and
`createEmployee`. `ballerina/mcp` derives each tool's input schema from the remote function's
signature and its description from the doc comment, so the generator writes no JSON Schema of
its own.

Everything marked ✅ was compiled and run on Ballerina 2201.13.3 with `ballerina/mcp` 1.3.0
and a generated persist in-memory client.

## Goals

- Define the tool set: names, descriptions, arguments and results.
- Give an AI agent typed, per-entity tools with accurate input schemas.
- Map the error categories to MCP tool errors.

## Non-goals

- Query options, relations and auth. They follow the roadmap in #1503.
- Generic tools that take the entity name as an argument, as in Azure Data API builder's
  `read_records`. See Alternatives.
- MCP resources and prompts. Only tools are generated.
- The stdio transport. Only Streamable HTTP is generated.

## Design

### Listener and service

```ballerina
configurable int dataservicePort = 9090;

final Client dataserviceClient = check new ();
listener http:Listener dataserviceListener = new (dataservicePort);
listener mcp:StreamableHttpListener dataserviceMcpListener = new (dataserviceListener);

@mcp:StreamableHttpServiceConfig {
    info: {name: "<package name>", version: "<package version>"}
}
service mcp:StreamableHttpService /mcp on dataserviceMcpListener {
    // one remote function per tool
}
```

- **Base path:** `options.dataservice.basePath`, `/mcp` by default.
- **Server info:** the package name and version from `Ballerina.toml`.
- **Listener type:** `mcp:StreamableHttpListener`. The older `mcp:Listener` is deprecated in
  1.3.0. ✅
- **Shared listener:** the MCP listener is built on a module-level `http:Listener`, so a
  user-written HTTP service can attach to `dataserviceListener` and share the port. ✅

### Tools

For an entity `Employee` with key `id`:

| Operation | Action | Tool | Arguments | Result |
|---|---|---|---|---|
| Get many | `read` | `listEmployees` | none | `{"items": [Employee, ...]}` |
| Get one | `read` | `getEmployee` | `id` | `Employee` |
| Create one | `create` | `createEmployee` | `value: EmployeeInsert` | the created `Employee` |
| Create many | `create` | `createEmployees` | `values: EmployeeInsert[]` | `{"items": [Employee, ...]}` |
| Patch one | `update` | `updateEmployee` | `id`, `value: EmployeeUpdate` | the updated `Employee` |
| Delete one | `delete` | `deleteEmployee` | `id` | the deleted `Employee` |

- **Tool name:** the remote function name. ✅ Get many uses `list` plus the entity name in the
  plural (`listEmployees`); the rest use a verb plus the entity name.
- **Composite keys:** one argument per key field, in declaration order.
- **Disabled operations** are not generated, so the tool does not appear in `tools/list`.
- **Tool count:** up to six tools per entity. A model with many entities gives an agent a long
  tool list; annotating only the entities and actions an agent needs is the way to keep it
  short.

#### Generated service

```ballerina
service mcp:StreamableHttpService /mcp on dataserviceMcpListener {

    # Get an employee by its key.
    # + id - The employee's id
    # + return - The employee
    remote function getEmployee(int id) returns Employee|error {
        return dataserviceClient->/employees/[id];
    }

    # Create an employee.
    # + value - The employee to create
    # + return - The created employee
    remote function createEmployee(EmployeeInsert value) returns Employee|error {
        int[] ids = check dataserviceClient->/employees.post([value]);
        return dataserviceClient->/employees/[ids[0]];
    }

    // listEmployees, createEmployees, updateEmployee, deleteEmployee
}
```

### Descriptions and schemas

`ballerina/mcp` builds every tool definition from the remote function: ✅

| Tool definition field | Source |
|---|---|
| `name` | the function name |
| `description` | the first line of the function's doc comment |
| `inputSchema` | the parameters; record parameters become nested object schemas with `required` lists |
| each property's `description` | the parameter's `+ param` doc line |

Example `tools/list` entry: ✅

```json
{"name": "getEmployee",
 "description": "Get an employee by its key.",
 "inputSchema": {"type": "object", "required": ["id"],
                 "properties": {"id": {"type": "integer", "format": "int64",
                                       "description": "The employee's id"}}}}
```

The descriptions are the agent's only guide to the tools, so the generator writes them from a
fixed template per operation and includes the entity's own doc comment from the model when it
has one.

#### Schema notes

- **Nullable fields** become `{"type": "string", "nullable": true}`. ✅
- **Time types** become verbose schemas. `time:Date` is an `allOf` that includes optional
  `hour`, `minute`, `second` and `utcOffset` properties, which a date does not use. ✅ See
  open question 1.

### Results

A successful call returns the result serialized as JSON in one text content block: ✅

```json
{"content": [{"type": "text",
              "text": "{\"id\":1,\"name\":\"Ann\",\"email\":\"a@x\",\"salary\":1000.5,...}"}]}
```

`ballerina/mcp` 1.3.0 does not set `structuredContent` or an `outputSchema` for a typed return
value. ✅ See open question 2.

### Errors

An error returned from a remote function becomes a tool result with `isError: true` and the
error message as text. ✅ This is the form MCP intends for errors an agent can act on.

| Category | Result |
|---|---|
| Not found | `isError: true`, the persist message ✅ |
| Conflict | `isError: true`, the persist message |
| Constraint violation | `isError: true`, the persist message |
| Invalid input | `isError: true`, a binding message from `ballerina/mcp`, for example `invalid value for argument 'id': 'string' value cannot be converted to 'int'` ✅ |
| Internal | `isError: true`, a generic message; the detail is logged |

Example: ✅

```json
{"content": [{"type": "text",
              "text": "A record with the key '99' does not exist for the entity 'Employee'."}],
 "isError": true}
```

### Configuration

| Setting | Where | Default |
|---|---|---|
| Base path | `options.dataservice.basePath` | `/mcp` |
| Port | `dataservicePort` in `Config.toml` | `9090` |

## Alternatives

### Generic tools

Azure Data API builder exposes a fixed set of tools that take the entity name as an argument:
`describe_entities`, `read_records`, `create_record` and so on. That keeps the tool list short
for large models, but each tool's input schema has to accept any entity, so the agent learns
an entity's fields only by calling `describe_entities` first.

Typed tools give the agent each entity's exact schema up front and need no generic schema code,
because `ballerina/mcp` derives the schemas. Generic tools can be added later as an option, using
`mcp:AdvancedService`, if large models need them.

### snake_case tool names

Many MCP servers use names such as `get_employee`. `ballerina/mcp` uses the function name as the
tool name, and Ballerina functions are camelCase, so the names are camelCase.

## Testing

- Code generation: expected output for every action combination, single and composite keys, and
  entities with and without doc comments.
- `tools/list`: exactly the expected tools, with the expected names, descriptions and input
  schemas.
- `tools/call`: every row of the tools and errors tables.
- An MCP client session through `initialize`, `tools/list` and `tools/call`.

## Risks and Assumptions

- **Read-only hints are missing.** MCP tool annotations such as `readOnlyHint` and
  `destructiveHint` tell a client which tools need confirmation. `@mcp:Tool` in 1.3.0 accepts
  only `description` and `schema`, so the generated tools carry no hints. A client may then
  treat `deleteEmployee` and `getEmployee` alike.
- **Tool list size.** Six tools per entity can crowd an agent's context for large models.

## Open questions

1. **Time types.** Should time values be ISO 8601 strings, as GraphQL requires, to give agents a
   simple schema? This needs the same generated types and conversions as GraphQL.
2. **Structured results.** Should `ballerina/mcp` set `structuredContent` and `outputSchema`
   from a remote function's return type? Agents and clients that validate results need them.
3. **Tool annotations.** Should `@mcp:Tool` accept MCP tool annotations, so that read tools are
   marked read-only and delete tools destructive?

## Dependencies

- [Data service generation for bal persist](1503_data_service.md)
- `ballerina/mcp`, with enhancements for open questions 2 and 3

## Future work

- Generic tools as an option for large models.
- Query options as tool arguments.
- MCP resources exposing the entity schemas.
