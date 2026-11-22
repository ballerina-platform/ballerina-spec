# Data service generation for bal persist: GraphQL

- Author: @niveathika
- Reviewers: 
- Created: 2026-11-10
- Updated: 2026-11-17
- Issue: [#1520](https://github.com/ballerina-platform/ballerina-spec/issues/1520)
- Status: Draft

## Summary

This proposal defines how the protocol-neutral CRUD shape in
[Data service generation for bal persist](https://github.com/ballerina-platform/ballerina-spec/issues/1503)
is rendered as a `graphql:Service` when `options.dataservice.protocol = "graphql"`.

Each exposed entity gets two root query fields, a list and a get one by key, and up to four
mutation fields: create one, create many, update and delete. A relation is a field of the
entity's object type, with the query options of get many on a to-many relation. Results are
GraphQL object types, the query options are typed arguments, and each error category of #1503
is an entry of the response's `errors` array with #1503's message. The service
publishes its schema through introspection and serves GraphiQL as its Try-It.

The rendering follows the HTTP proposal,
[#1513](https://github.com/ballerina-platform/ballerina-spec/issues/1513), wherever GraphQL
allows it: the same type names, value formats, messages, configuration layout and auth
providers.

Please add any comments to issue [#1520](https://github.com/ballerina-platform/ballerina-spec/issues/1520).

## Goals

- Define the schema of a generated service: its root fields, arguments, types and nullability.
- Map every operation, query option, field rule and error category of #1503 to GraphQL.
- Read relations as nested fields with a bounded number of database queries per request.
- Keep what a user configures, and the formats a client sees, the same as in #1513.

## Non-goals

- Subscriptions.
- Relay connections, cursors and global object identification.
- Relations more than one hop away, and nested writes. They follow the roadmap in #1503.
- GraphQL federation, persisted queries and custom scalars.
- MCP, which is the next protocol proposal.

## Design

The examples use the model of the demo project, where `Department` allows `read` and `create`,
`Employee` hides its `department` direction, and `Assignment` has a composite key:

```ballerina
@dataservice:Expose {operations: [dataservice:READ, dataservice:CREATE]}
type Department record {|
    @sql:Generated
    readonly int id;
    string name;
    Employee[] employees;
|};

@dataservice:Expose
type Employee record {|
    readonly int id;
    string name;
    string? email;
    time:Date hiredOn;
    @dataservice:Internal
    Department department;
    Assignment[] assignments;
|};

@dataservice:Expose
type Assignment record {|
    readonly string projectCode;
    readonly int seq;
    decimal hours;
    Employee employee;
|};
```

Persist infers the foreign keys `Employee.departmentId` and `Assignment.employeeId`. The enum
examples use `Status` from #1503.

### The generated schema

For the model above, the service has this schema, shown without its descriptions:

```graphql
type Query {
  departments(filter: DepartmentFilter, sort: [DepartmentSort!], size: Int, offset: Int): DepartmentList
  department(id: Int!): DepartmentObject
  employees(filter: EmployeeFilter, sort: [EmployeeSort!], size: Int, offset: Int): EmployeeList
  employee(id: Int!): EmployeeObject
  assignments(filter: AssignmentFilter, sort: [AssignmentSort!], size: Int, offset: Int): AssignmentList
  assignment(projectCode: String!, seq: Int!): AssignmentObject
}

type Mutation {
  createDepartment(input: DepartmentInsertInput!): DepartmentObject
  createDepartments(input: [DepartmentInsertInput!]!): DepartmentList
  createEmployee(input: EmployeeInsertInput!): EmployeeObject
  createEmployees(input: [EmployeeInsertInput!]!): EmployeeList
  updateEmployee(id: Int!, input: EmployeeUpdateInput!): EmployeeObject
  deleteEmployee(id: Int!): EmployeeObject
  createAssignment(input: AssignmentInsertInput!): AssignmentObject
  createAssignments(input: [AssignmentInsertInput!]!): AssignmentList
  updateAssignment(projectCode: String!, seq: Int!, input: AssignmentUpdateInput!): AssignmentObject
  deleteAssignment(projectCode: String!, seq: Int!): AssignmentObject
}

type DepartmentObject {
  id: Int!
  name: String!
  employees(filter: EmployeeFilter, sort: [EmployeeSort!], size: Int, offset: Int): EmployeeRelatedList
}

type EmployeeObject {
  id: Int!
  name: String!
  email: String
  hiredOn: String!
  departmentId: Int!
  assignments(filter: AssignmentFilter, sort: [AssignmentSort!], size: Int, offset: Int): AssignmentRelatedList
}

type AssignmentObject {
  projectCode: String!
  seq: Int!
  hours: Decimal!
  employeeId: Int!
  employee: EmployeeRelatedObject
}

type EmployeeRelatedObject {
  id: Int!
  name: String!
  email: String
  hiredOn: String!
  departmentId: Int!
}

type AssignmentRelatedObject {
  projectCode: String!
  seq: Int!
  hours: Decimal!
  employeeId: Int!
}

type DepartmentList { items: [DepartmentObject!]!  hasMore: Boolean! }
type EmployeeList { items: [EmployeeObject!]!  hasMore: Boolean! }
type AssignmentList { items: [AssignmentObject!]!  hasMore: Boolean! }
type EmployeeRelatedList { items: [EmployeeRelatedObject!]!  hasMore: Boolean! }
type AssignmentRelatedList { items: [AssignmentRelatedObject!]!  hasMore: Boolean! }

input EmployeeFilter {
  id: IntFilter
  name: StringFilter
  email: StringNullableFilter
  hiredOn: DateFilter
  departmentId: IntFilter
}

input EmployeeSort {
  id: SortDirection
  name: SortDirection
  email: SortDirection
  hiredOn: SortDirection
  departmentId: SortDirection
}

input DepartmentInsertInput { name: String! }
input EmployeeInsertInput { id: Int!  name: String!  email: String  hiredOn: String!  departmentId: Int! }
input EmployeeUpdateInput { name: String  email: String  hiredOn: String  departmentId: Int }
input AssignmentInsertInput { projectCode: String!  seq: Int!  hours: Decimal!  employeeId: Int! }
input AssignmentUpdateInput { hours: Decimal  employeeId: Int }

# DepartmentFilter, DepartmentSort, AssignmentFilter and AssignmentSort follow the same form.
# IntFilter, StringFilter, StringNullableFilter, DateFilter and SortDirection come from
# ballerina/dataservice.graphql; see Filter and Sort.
```

`EmployeeObject` has no `department` field because the relation field is `Internal`, and
`Department` has no `updateDepartment` or `deleteDepartment` because it allows neither action.
`departmentId` is still returned, as #1503 defines for an `Internal` relation field.

### Listener and service

`dataservice.bal` declares one listener and one service in the default module:

```ballerina
final Client dataserviceClient = check new ();

listener graphql:Listener dataserviceListener =
        new (dataserviceConfig.port, dataserviceConfig.listenerConfig);

@graphql:ServiceConfig {
    graphiql: {enabled: true},
    cors: dataserviceConfig.serviceConfig.cors,
    maxQueryDepth: dataserviceConfig.serviceConfig.maxQueryDepth,
    queryComplexityConfig: {maxComplexity: dataserviceConfig.serviceConfig.maxQueryComplexity},
    contextInit: dataserviceInitContext,
    validation: false
}
service graphql:Service /graphql on dataserviceListener {

    function init() returns error? {
        check dsGraphql:checkLimits(dataserviceConfig.serviceConfig);
    }

    // the root fields of each exposed entity
}

isolated function dataserviceInitContext(http:RequestContext requestContext, http:Request request)
        returns graphql:Context|error {
    graphql:Context ctx = new;
    ctx.registerDataLoader("Assignment.employee",
            new dataloader:DefaultDataLoader(dataserviceLoadAssignmentEmployee));
    return ctx;
}
```

- **Base path:** the service's base path is `options.dataservice.basePath`, `/graphql` by
  default, as #1503 gives.
- **Requests:** a document is sent with `POST` and `Content-Type: application/json`, or with
  `GET` and the `query`, `operationName` and `variables` query parameters, as `ballerina/graphql`
  accepts them.
- **Configurable annotation values:** `cors`, `maxQueryDepth` and `queryComplexityConfig` take
  their values from `dataserviceConfig`.
- **Startup checks:** the service's `init` checks the limits, so a value out of range stops the
  program with its message; see [Limits](#limits).
- **Context:** `dataserviceInitContext` creates the `graphql:Context` of each request. It
  registers one dataloader per to-one relation that the service offers, see
  [Relations](#relations), and with `auth = true` authenticates the request, see [Auth](#auth).
  A service whose model offers no to-one relation and has no auth uses `ballerina/graphql`'s
  default context.
- **Validation:** `validation: false` turns off `ballerina/graphql`'s constraint validation,
  because the service checks the model's constraints itself; see [Constraints](#constraints).
- **One query field at least:** a GraphQL schema needs a query type, so a service in which no
  entity allows `read` cannot be generated. The persist tool reports it as an error, with the
  other GraphQL checks of #1503.

#### GraphiQL

With `options.dataservice.introspection` left `true`, the service enables GraphiQL as its
Try-It, as #1513 serves Swagger UI.

| Request | Response |
|---|---|
| `GET /graphiql` | GraphiQL, set up to send its documents to the service |

- **Path:** GraphiQL is served at `/graphiql` from the root of the listener, not under the base
  path, which is where `ballerina/graphql` serves it by default. The path is fixed, as Swagger UI's
  is in #1513.
- **Without introspection:** with `introspection = false`, GraphiQL is not enabled, and
  `GET /graphiql` is answered with `404`. GraphiQL needs introspection to load the schema.
- **Scripts:** GraphiQL loads `graphiql@2.4.0`, React and its explorer plugin from `unpkg.com`, so
  it needs internet access in the browser, as Swagger UI does.
- **Auth:** with `auth = true`, the page itself is served without a credential, and the
  documents it sends, including its introspection query, need one; see
  [Introspection and GraphiQL under auth](#introspection-and-graphiql-under-auth).

### Operations

For an entity `Employee` whose collection name is `employees`, with key `id`:

| Operation | Action | Root field | Result |
|---|---|---|---|
| Get many | `read` | `employees(filter: EmployeeFilter, sort: [EmployeeSort!], size: Int, offset: Int): EmployeeList` | One page of records |
| Get one | `read` | `employee(id: Int!): EmployeeObject` | The record, or `null` and `NOT_FOUND` when no record has the key |
| Get related | `read` | A field of the object type, such as `EmployeeObject.assignments` or `AssignmentObject.employee`; see [Relations](#relations) | The related records |
| Create one | `create` | `createEmployee(input: EmployeeInsertInput!): EmployeeObject` | The created record |
| Create many | `create` | `createEmployees(input: [EmployeeInsertInput!]!): EmployeeList` | The created records, with `hasMore: false` |
| Patch one | `update` | `updateEmployee(id: Int!, input: EmployeeUpdateInput!): EmployeeObject` | The updated record, or `null`; `Boolean` when the entity does not allow `read` |
| Delete one | `delete` | `deleteEmployee(id: Int!): EmployeeObject` | The deleted record, or `null`; `Boolean` when the entity does not allow `read` |

#### Names

- **Get many:** the collection name of #1503, such as `employees`, `projectAssignments`,
  `people` and `httpLogs`.
- **Get one:** the entity name with its first word in lowercase, as the collection name is
  formed but without the plural, such as `employee`, `projectAssignment`, `person` and `httpLog`.
- **Mutations:** `create`, `update` or `delete` followed by the entity name for one record, such
  as `createEmployee`, and `create` followed by the collection name with its first letter in
  uppercase for create many, such as `createEmployees` and `createPeople`.
- **Same singular and plural:** for an entity whose collection name is its singular name, such
  as `Equipment`, `Staff` or `Series`, which persist does not pluralize, get many and create
  many add `List`: `equipmentList` and `createEquipmentList`, while get one and create one are
  `equipment` and `createEquipment`.
- **Unique names:** two root fields with the same name, from two entities, are an error of the
  persist tool, as #1503 gives.
- **Order:** root fields are in model order, and within an entity, get many and get one in the
  query type, then create one, create many, update and delete in the mutation type.

#### Results

- **Nullable root fields:** every root field is nullable, so an error in one root field leaves
  the data of the others. A root field that fails is `null` and has an entry in `errors`,
  while a non-null field that fails makes the whole `data` `null`.
- **Get one of a missing record** is `null` with `NOT_FOUND`; see [Not found](#not-found).
- **Creates are atomic.** Create one and create many run the insert and the read-back in one
  transaction, as #1503 and #1513 define, so a batch with one failing record creates none.
- **Create many takes at most `dataserviceConfig.maxPageSize` records.** A larger list is
  answered with `INVALID_INPUT`. An empty list is answered with `{items: [], hasMore: false}`
  without calling the persist client.
- **Create without `read`:** create one and create many return the created records whether or
  not the entity allows `read`, as #1503 defines, so the object type is generated for an entity
  that allows `create`. With `read` allowed, they return `null`, with no entry in `errors`, to a
  caller who may not read the entity; see [Auth](#auth).
- **Patch is partial.** A field left out of `input` is not changed. A field set to `null` is
  set to `null` when the entity's field is nullable, and is answered with `INVALID_INPUT`
  otherwise.
- **Patch and delete with `read`** return the record, as #1503 defines. They return `null`,
  with no entry in `errors`, when the caller may not read the entity, see [Auth](#auth), or when
  the update is saved but cannot be read back, which is logged.
- **Patch and delete without `read`** return `Boolean`, `true` when the record was changed or
  deleted. GraphQL has no empty result, and #1503 returns no record in this case; see
  [Alternatives](#alternatives).
- **A missing record** in patch or delete is answered with `null` and `NOT_FOUND`.
- **An empty patch,** `input: {}`, changes nothing, as #1503 defines. It reads the record as get
  one does when the record would be returned, and returns `true` without reading otherwise.
  Neither calls the persist client's update. A missing record is `NOT_FOUND`, as for any patch.
- **Several mutations in one document** run one after the other, in document order, as GraphQL
  requires. Each runs in its own transaction, and one that fails does not undo the others.
- **Get many without `sort`** returns records ordered by key, as #1503 defines.

#### Disabled operations

An operation whose action is not enabled is not generated, so its root field is not in the
schema, and `ballerina/graphql` answers a document that selects it with a request error, as
#1503 says for GraphQL:

```json
{"errors": [{"message": "Cannot query field \"deleteDepartment\" on type \"Mutation\".", "locations": [{"line": 1, "column": 12}]}]}
```

A schema whose entities allow no `create`, `update` or `delete` has no mutation type.

### Keys

- **Arguments:** get one, patch and delete take one non-null argument per key field, named as
  the field, in declaration order: `employee(id: Int!)` and
  `assignment(projectCode: String!, seq: Int!)`.
- **Key types:** persist allows `int`, `string`, `float`, `decimal` and `boolean` key fields,
  which are `Int`, `String`, `Float`, `Decimal` and `Boolean` arguments. A value of another type
  is a request error of `ballerina/graphql`, such as `Int cannot represent non Int value: abc`.
- **Float keys:** `ballerina/graphql` accepts a `Float` literal beyond the largest `float`, such
  as `1e400`, as `Infinity`. A key that is not finite is answered with `INVALID_INPUT` and the
  message #1503 gives.
- **Key text:** in error messages, a key value is written with Ballerina's `toString`, and a
  composite key as its values joined by `/`, as in #1503.
- **Key names:** a key field is a parameter of the resolvers that take a key, so it cannot be
  named `input`, which is the argument of patch, or as a parameter or variable of the generated
  resolvers. The implementation lists the names, as #1513 does, and the persist tool reports
  such a key as an error, as #1503 gives. `pull` leaves such an entity unannotated, with
  #1503's warning.

### Types

#### Type names

`ballerina/graphql` names each schema type after its Ballerina type, and has no annotation to
rename one. The default module already holds persist's `Employee`, `EmployeeInsert` and
`EmployeeUpdate`, so the GraphQL types have names of their own, with GraphQL's `Input` suffix on
input types. #1503 leaves type names to each protocol proposal.

| GraphQL type | Kind | Ballerina type | Holds | Generated when the entity |
|---|---|---|---|---|
| `EmployeeObject` | object | service class | The returned fields of `Employee`, and a field per offered relation | allows `read` or `create` |
| `EmployeeRelatedObject` | object | service class | The returned fields of `Employee`, without relation fields, as a related record; see [Relations](#relations) | allows `read` and is the target of a readable relation |
| `EmployeeList` | object | open record | A page of `EmployeeObject`, with `hasMore` | allows `read` or `create` |
| `EmployeeRelatedList` | object | open record | A page of `EmployeeRelatedObject`, with `hasMore` | allows `read` and is the target of a readable to-many relation |
| `EmployeeInsertInput` | input | closed record | The fields that create one and create many accept | allows `create` |
| `EmployeeUpdateInput` | input | closed record | The fields that patch accepts, all optional | allows `update` |
| `EmployeeFilter` | input | closed record | One optional field per filterable field | allows `read` |
| `EmployeeSort` | input | closed record | One optional field per sortable field | allows `read` |

- **Always generated:** unlike #1513's wire types, these types are generated for every exposed
  entity, each when an operation uses it. GraphQL needs input types separate from output types,
  and `ballerina/graphql` rejects a type used as both: ``the GraphQL field 'Query.echoDay' uses
  output type 'Date' as an input type``. Persist makes `EmployeeInsert` an alias of `Employee`
  when the key is not generated, so persist's types cannot be the input types.
- **Not generated:** `<Entity>Partial`, `<Entity>PartialList`, `<Entity>Created` and
  `<Entity>ListCreated`. A GraphQL client chooses its fields with its selection set, and a
  create returns the record itself.
- **Object as a service class:** `EmployeeObject` holds the persist record, and each field is
  a resolver that returns the field in its GraphQL form. Its relation fields take arguments,
  which a record field cannot. A record would not work in any case: `ballerina/graphql` compares
  records by structure, so an output record with the same fields as an input record is one
  type, used as both. On Ballerina 2201.14.0, an output record with the fields of
  `EmployeeInsertPayload` failed with ``the GraphQL field 'Mutation.createEmployee' uses output
  type 'EmployeeInsertPayload' as an input type``. A service class is a type of its own. The same
  holds for `<Entity>RelatedObject`, whose fields can match `<Entity>InsertInput` too.
- **Open envelopes:** the list envelopes are open records, as #1503 defines. A field added to
  them later, such as a total, does not break a client, since a client selects the fields it
  reads.

#### Field types

| Ballerina type | GraphQL type | In a request and a response |
|---|---|---|
| `int` | `Int` | A number. `ballerina/graphql` accepts and returns values beyond GraphQL's 32-bit `Int`, such as `9007199254740993`, unchanged |
| `float` | `Float` | A number. A value that is not finite is answered with an error; see below |
| `decimal` | `Decimal` | A number, the custom scalar that `ballerina/graphql` defines. A response holds the value at its column's scale, as the database returns it: persist's `DECIMAL(65,30)` gives `1.500000000000000000000000000000` for `1.50` |
| `string`, `boolean` | `String`, `Boolean` | |
| an enum | the enum, with the member names as its values | The member name, such as `ACTIVE` |
| `byte[]` | `String` | A base64 string (RFC 4648, standard alphabet, padded) |
| `time:Date` | `String` | An ISO 8601 date, `2024-01-02` |
| `time:TimeOfDay` | `String` | An ISO 8601 time, `10:15:30` or `10:15:30.5` |
| `time:Civil` | `String` | An ISO 8601 date-time without an offset, `2024-01-02T10:15:30` |
| `time:Utc` | `String` | An ISO 8601 date-time in UTC, `2024-01-02T10:15:30Z`. In a request, any offset is accepted and converted to UTC |
| `T?` | the nullable type | The value or `null` |

The formats are #1513's and use the same conversion functions of `ballerina/dataservice`, such
as `dataservice:dateToString` and `dataservice:dateFromString`, so a value has one form in every
protocol. A request value that does not parse is answered with `INVALID_INPUT` and #1513's
message, ``The field '<field>' of the entity '<Entity>' is not <format>.``

- **Why strings for dates, times and `byte[]`:** `ballerina/graphql` cannot represent them. A
  `time:*` field fails to compile with ``failed to generate schema for type 'Seconds'. Type alias
  for type 'decimal' is not supported``, and a `byte[]` field with ``invalid GraphQL field Type
  'byte'``. It defines no custom scalars other than `Decimal` and `Upload`, so a `Date` or
  `Base64` scalar cannot be added. The description of each such field names its format, such as
  `The hiredOn field of Employee, as an ISO 8601 date`.
- **Large integers:** GraphQL's `Int` is 32-bit, while a Ballerina `int` is 64-bit. The service
  keeps `Int` for every `int` and returns values beyond 32 bits as they are, as
  `ballerina/graphql` does. A client that holds numbers as JavaScript numbers loses precision
  beyond 2^53, so a value such as `9007199254740993` is read as `9007199254740992` there. See
  [Risks and assumptions](#risks-and-assumptions).
- **Decimals in a document:** a `Decimal` value written as a literal in the document is parsed
  as a `float` by `ballerina/graphql`, so `1.50` arrives as `1.5`, and
  `12345678901234567890.123456789` as `1.2345678901234567E+19`. The same values sent as
  variables arrive unchanged, so clients send decimals as variables. A string such as `"1.50"`
  is rejected with `Decimal cannot represent non Decimal value`.
- **Values that are not finite:** `ballerina/graphql` writes a `float` `NaN` or `Infinity` in a
  response as the bare words `NaN` and `Infinity`, which are not JSON, and accepts `1e400` in a
  request as `Infinity`. A `float` input value that is not finite is answered with
  `INVALID_INPUT`, `The field '<field>' of the entity '<Entity>' is not a finite number.` A stored
  value that is not finite, which H2 and PostgreSQL can hold, is answered as an error of the
  field that holds it, with `INTERNAL` and
  `The field '<field>' of the entity '<Entity>' holds a value that is not a finite number.`
- **Enums:** the model's enum types are the GraphQL enum types, under the same names. Their
  doc comments describe the enum and its values.

#### Nullability

| Field | GraphQL type |
|---|---|
| A field of type `T` | `T!` in `<Entity>Object`, `<Entity>RelatedObject` and `<Entity>InsertInput`; `T` in `<Entity>UpdateInput` |
| A field of type `T?` | `T` everywhere |
| A to-one relation field | nullable: `null` when there is no related record |
| A to-many relation field | nullable: `null` only with an entry in `errors` |
| `items` and `hasMore` of a list envelope | `[T!]!` and `Boolean!` |
| Root fields | nullable |

- **Insert fields:** a nullable field is optional in GraphQL, so a create that leaves out
  `email` creates the record with `email` set to `null`. `ballerina/graphql` binds a field left
  out of the input as `()` when the record field is nullable.
- **Nullable input fields:** GraphQL has no input field that a client can leave out but cannot set
  to `null`, so every input field that is not required is nullable, and the Ballerina field is
  nullable too. Filter operators, filter fields and sort fields are `T? field;`, where a field
  left out and a field set to `null` both bind as `()` and mean no condition. Fields of
  `<Entity>UpdateInput` are `T? field?;`, where a field left out is absent and one set to `null`
  is `()`, so a patch can tell "not changed" from "set to null"; a `null` on a field that cannot
  hold one is answered with `INVALID_INPUT`, `The field '<field>' of the entity '<Entity>' cannot
  be null.`
- **Not `T field?`:** `ballerina/graphql` publishes an optional non-nullable field as the
  nullable `T` too, and cannot bind the `null` a client may then send.

#### Field rules

The field rules of #1503 shape the types:

| Rule | `<Entity>Object` and `<Entity>RelatedObject` | `<Entity>InsertInput` | `<Entity>UpdateInput` | `<Entity>Filter` and `<Entity>Sort` |
|---|---|---|---|---|
| `ReadOnly` | Holds the field | Does not hold the field | Does not hold the field | Hold the field |
| `Immutable` | Holds the field | Holds the field | Does not hold the field | Hold the field |
| `Internal` | Does not hold the field | Does not hold the field | Does not hold the field | Do not hold the field |

- **Rejected fields:** a document that sets a field that its input type does not hold, a
  `ReadOnly` or `Internal` field, or an `Immutable` field on patch, is a request error of
  `ballerina/graphql`, before any resolver runs:

  ```json
  {"errors": [{"message": "Field \"notes\" is not defined by type \"input\".", "locations": [{"line": 1, "column": 42}]}]}
  ```

  The message names the argument, `input`, rather than the input type. See
  [Errors](#errors) for its code.
- **`ReadOnly` is rejected, not ignored.** #1503 ignores a `ReadOnly` field sent on create or
  update, so that a client can send back a record it has read. A GraphQL client cannot send back
  an object it has read: the output and input types are separate, and the input type lists what
  the caller can write. Leaving the field out of the input types keeps the schema exact, as #1503
  allows where a protocol's input types are separate from its output types.
- **Values on create:** `transformInputTo<Entity>Insert` sets a `ReadOnly` or `Internal`
  field to the `value` of its annotation, or to `()`, as in #1513.
- **Relation fields:** a direction that is not offered, because its relation field or the
  foreign key is `Internal`, has no field in `<Entity>Object`.

### Query arguments

The query options of #1503 are arguments of get many and of a to-many relation field. Get one
and a to-one relation field take none, since the selection set chooses the fields:

| Argument | Type | Example |
|---|---|---|
| `filter` | `<Entity>Filter` | `filter: {hiredOn: {gte: "2024-01-01"}, email: {isNull: false}}` |
| `sort` | `[<Entity>Sort!]` | `sort: [{hiredOn: DESC}, {name: ASC}]` |
| `size` | `Int` | `size: 20` |
| `offset` | `Int` | `offset: 40` |

`fields` is not an argument: the selection set names the fields to return, including relations.
As with `fields` in #1503, the record is read in full and then narrowed.

#### Filter

`<Entity>Filter` has one optional field per filterable entity field. Each is an input type of
`ballerina/dataservice.graphql` that holds the operators of #1503 that the field's type allows,
with values in the field's GraphQL form:

| Input type | Field type | Operators |
|---|---|---|
| `IntFilter`, `FloatFilter`, `DecimalFilter` | `int`, `float`, `decimal` | `eq`, `ne`, `lt`, `lte`, `gt`, `gte`, `anyOf` |
| `StringFilter` | `string` | `eq`, `ne`, `lt`, `lte`, `gt`, `gte`, `anyOf`, `contains`, `startsWith` |
| `BooleanFilter` | `boolean` | `eq`, `ne`, `anyOf` |
| `DateFilter`, `TimeOfDayFilter`, `CivilFilter`, `UtcFilter` | `time:Date`, `time:TimeOfDay`, `time:Civil`, `time:Utc` | `eq`, `ne`, `lt`, `lte`, `gt`, `gte`, `anyOf`, with ISO 8601 strings |
| `<Enum>Filter`, generated per model enum | an enum | `eq`, `ne`, `anyOf` |

Each has a `Nullable` variant for a nullable field, such as `StringNullableFilter`, which adds
`isNull`. The names follow Prisma's filter types.

```ballerina
# The conditions on a nullable `string` field.
public type StringNullableFilter record {|
    # Equal to the value
    string? eq;
    # Not equal to the value; a null field does not match
    string? ne;
    ...
    # Equal to any of the values
    string[]? anyOf;
    # Contains the value, following the database's collation
    string? contains;
    # Starts with the value, following the database's collation
    string? startsWith;
    # `true` for null, `false` for not null
    boolean? isNull;
|};
```

- **Several operators on one field** all apply, so `{id: {gte: 2, lt: 10}}` is a range.
- **Library types:** the operator types are shared by every entity, so the schema holds one
  `IntFilter`, not one per field. A type from another module keeps its own name in the schema.
- **Null operators:** an operator left out or set to `null`, and an empty operator object such as
  `{id: {}}`, set no condition. A null field is matched with `isNull`.
- **Strict input:** an unknown field or operator, a value of the wrong type and an unknown enum
  value are request errors of `ballerina/graphql`.
- **Dates and times** are strings, as in the types, and are parsed by `ballerina/dataservice`; a
  value that does not parse is answered with `INVALID_INPUT`.
- **Reserved fields:** `_and`, `_or` and `_not` are reserved in every `<Entity>Filter` for
  joining conditions in a later proposal; see [Reserved names](#reserved-names).

#### Sort

`sort` is a list of `<Entity>Sort` entries, each naming one field with a direction from the
library's `SortDirection` enum:

```graphql
enum SortDirection {
  "Ascending, nulls last"
  ASC
  "Descending, nulls first"
  DESC
}
```

- **One field per entry:** an entry that sets no field or more than one is answered with
  `INVALID_INPUT`, `Each entry of 'sort' must name exactly one field.` The order of fields in an
  input object is not part of its value, so the list carries the order.
- **Rules of #1503:** the key fields are added at the end, a field named in two entries is
  answered with #1503's message, and nulls sort last ascending and first descending.

#### Size and offset

As #1503 defines: without `size`, `dataserviceConfig.pageSize` applies; a `size` above
`dataserviceConfig.maxPageSize` is reduced to it; a `size` below 1, an `offset` below 0, and an
`offset` too large for the `size`, are `INVALID_INPUT` with #1503's messages.

```graphql
{ employees(sort: [{hiredOn: DESC}], size: 2) { items { id name } hasMore } }
# {"data": {"employees": {"items": [{"id": 7, "name": "Ann"}, {"id": 3, "name": "Bob"}], "hasMore": true}}}
```

### Relations

Each relation that #1503 offers, because both entities allow `read` and neither the relation
field nor the foreign key is `Internal`, is a field of the entity's `<Entity>Object`, named as
the relation field in the model:

| Relation | Field | Type |
|---|---|---|
| To-one, such as `Assignment.employee` | `employee` | `EmployeeRelatedObject`, `null` when there is no related record |
| To-many, such as `Employee.assignments` | `assignments(filter, sort, size, offset)` | `AssignmentRelatedList` |

```graphql
{
  department(id: 2) {
    name
    employees(sort: [{name: ASC}], size: 2) { items { id name } hasMore }
  }
  assignments(filter: {hours: {gt: 10}}) {
    items { projectCode seq employee { name } }
    hasMore
  }
}
```

- **Replaces get related and `fields`:** a nested field reads the same records as #1503's get
  related, with its query options on a to-many relation, and as a relation in `fields`. There is
  no separate root field for get related, since the related records are read from the record
  that holds them.
- **One hop:** a related record is a `<Target>RelatedObject`, which has the related entity's
  own fields and no relation fields, as #1503 defines. A document therefore cannot nest a
  relation inside a relation, and the schema says so rather than a runtime check:
  ``Cannot query field "assignments" on type "EmployeeRelatedObject".`` See
  [Alternatives](#alternatives).
- **Hidden directions:** a direction that is not offered has no field, so selecting it is a
  request error: ``Cannot query field "department" on type "EmployeeObject".``
- **Under a mutation:** the object a mutation returns has the relation fields too, read the same
  way.
- **Empty to-one:** a to-one relation with no related record is `null`, with no entry in
  `errors`. This happens on the side of a one-to-one relation that does not hold the foreign
  key, and when a foreign key points at a missing record, as #1503 defines.
- **To-many:** a to-many relation is a list envelope with the query options of get many. Its
  default size is `dataserviceConfig.pageSize`, and `hasMore` tells the caller to read the next
  page with `offset`.
- **Nullable relation fields:** an error while reading a relation, such as `FORBIDDEN` or an
  invalid argument, makes only that field `null`, not the record that holds it.

#### Queries per request

A to-one relation is read through a `ballerina/graphql` dataloader, and a to-many relation with
one query per record that holds it:

| Read | Queries |
|---|---|
| Get many or get one | One |
| A to-one relation field | One per request for each such field: the related records whose key is any of the foreign key values of every record that selects it |
| A to-many relation field | One per record that selects it: the related records whose foreign key is the record's key, limited to `size + 1` rows |

These are the costs that #1503 gives for a relation in `fields`.

- **Dataloader:** `dataserviceInitContext` registers a `dataloader:DefaultDataLoader` per
  to-one relation for each request. The relation field's prefetch method adds the record's
  link to it: a record of the fields that link the relation, such as `{employeeId: 1}`. The
  field reads the related record from it once the links of every record are collected. The
  batch function reads every related record with one query, `dataservice:toIncludeQuery`, which
  matches the related entity's linked fields, and returns them in the order of the links, with
  `null` for a link that has no record. A link, rather than the related record's key, also
  serves the side of a one-to-one relation that does not hold the foreign key, and a composite
  foreign key.
- **No dataloader for to-many:** each record reads its own page of related records, ordered and
  limited, which one query for every record cannot do without a limit per group. The number of
  such queries is bounded by the page size and by the query complexity; see [Limits](#limits).
  #1503 leaves a single query with a limit per record to later work, and it needs no change to
  the schema.

```ballerina
public isolated service class AssignmentObject {
    private final readonly & Assignment row;

    isolated function init(Assignment row) {
        self.row = row.cloneReadOnly();
    }

    # The `hours` field of `Assignment`
    isolated resource function get hours() returns decimal => self.row.hours;

    isolated function prefetchEmployee(graphql:Context ctx) {
        ctx.getDataLoader("Assignment.employee").add({employeeId: self.row.employeeId});
    }

    # Gets the employee of the assignment.
    @graphql:ResourceConfig {prefetchMethodName: "prefetchEmployee"}
    isolated resource function get employee(graphql:Context ctx) returns EmployeeRelatedObject?|error {
        Employee? row = check ctx.getDataLoader("Assignment.employee").get({employeeId: self.row.employeeId});
        return row is Employee ? new (row) : ();
    }

    // the other fields
}

isolated function dataserviceLoadAssignmentEmployee(readonly & anydata[] keys) returns anydata[]|error {
    map<anydata>[] links = from anydata key in keys
        select check key.ensureType();
    dataservice:Query query = dataservice:toIncludeQuery(dataserviceAssignmentEntity, "employee", links,
            dataservicePageConfig);
    stream<Employee, persist:Error?> rows = dataserviceClient->/employees(Employee,
        whereClause = query.whereClause, orderByClause = query.orderByClause
    );
    Employee[]|persist:Error found = from Employee row in rows
        select row;
    if found is persist:Error {
        return dsGraphql:toListError(found, "Assignment", "get related");
    }
    return dsGraphql:toKeyOrder(found, dataserviceAssignmentEntity, "employee", links);
}
```

The batch function returns persist records, because a dataloader holds `anydata` and a service
object is not, as `anydata[]`, the type of `dataloader:BatchLoadFunction`. The field reads its
record back as the persist type, which the dataloader's `get` converts to, and wraps it in its
object type.

### Errors

Each error category of #1503 is an entry of the response's `errors` array, with #1503's message
in `message`, the category's code in `extensions.code`, and `locations` and `path` from
`ballerina/graphql`:

```json
{
  "errors": [{
    "message": "A record with the key '99' does not exist for the entity 'Employee'.",
    "locations": [{"line": 1, "column": 12}],
    "path": ["updateEmployee"],
    "extensions": {"code": "NOT_FOUND"}
  }],
  "data": {"updateEmployee": null}
}
```

| Category | `extensions.code` | Where | Raised from | Message |
|---|---|---|---|---|
| Not found | `NOT_FOUND` | The field of get one, patch or delete | `persist:NotFoundError` | #1503's |
| Conflict | `CONFLICT` | The field of create or patch | `persist:AlreadyExistsError` | #1503's |
| Constraint violation | `CONSTRAINT_VIOLATION` | The field of create, patch or delete | `persist:ConstraintViolationError` | #1503's |
| Invalid input | `INVALID_INPUT` | The field whose argument holds the value | A date, time or `byte[]` value that does not parse; a `float` that is not finite; `null` for an update field that needs a value; a constraint broken; an unusable `sort` entry, a field named twice in `sort`, `size` below 1, `offset` below 0 or too large for the `size`; a create above `dataserviceConfig.maxPageSize` records; a `float` key that is not finite | #1503's, and #1513's for a value that does not parse |
| Invalid input | none | The response, with no `data` | A document that `ballerina/graphql` rejects before it runs: a syntax error, an unknown field or argument, a value of the wrong type, a missing required argument, the depth or complexity limit | `ballerina/graphql`'s, such as `Field "input.name" of required type "String!" was not provided.` |
| Unauthenticated | `UNAUTHENTICATED` | The response, with no `data` | `dataserviceInitContext`, before the document is validated; see [Auth](#auth) | #1503's |
| Forbidden | `FORBIDDEN` | The root field | The caller holds no scope of the field's action, or no `read` scope of a related entity that the field's selection reads | #1503's |
| Internal | `INTERNAL` | The field | Any other error, including a stored `float` that is not finite | #1503's |

- **Field errors and request errors:** these are GraphQL's two kinds. A field error leaves the
  response's `data` with the field set to `null`, and is answered with `200`. A request error has
  no `data`, and `ballerina/graphql` answers it with `400`.
- **Request errors of `ballerina/graphql`** carry no `extensions`, since the service does not
  write them. An entry without `extensions.code` in a response without `data` is invalid input.
- **Errors in the service:** each error the service returns is a `graphql:ServiceError`, whose
  `graphql:ErrorDetail` holds `extensions: {code}`. `ballerina/graphql` copies the extensions
  into the error's entry. A missing credential is a `graphql:AuthnError` with the same detail,
  so it carries `UNAUTHENTICATED` and is still answered with `400`.
- **Logging:** the service logs what #1503 says it logs. `ballerina/graphql` logs an error
  sent with extensions at debug level, without a stack trace.

#### Not found

| Case | Result |
|---|---|
| Get one of a key that no record has | `null` and the not found message |
| Patch or delete of a key that no record has | `null` and the not found message |
| A to-one relation with no related record | `null`, no entry in `errors` |

A key that no record has is #1503's `NOT_FOUND`, in a lookup as in a mutation, as Data API
builder's `<entity>_by_pk` answers it with `Could not find item with the given key.` The field is
`null`, and the other root fields keep their data:

```json
{
  "errors": [{"message": "A record with the key '99' does not exist for the entity 'Employee'.", "locations": [{"line": 1, "column": 37}], "path": ["missing"]}],
  "data": {"employee": {"id": 1, "name": "Ann"}, "missing": null}
}
```

A to-one relation with no related record is not an error, because the record that holds it
exists, as #1503 defines for a relation in `fields`.

#### Partial results

A response holds every root field's data, or `null` with an entry in `errors` for each field
that failed. For example, with auth, a caller with `hr:read` alone asking for departments and
assignments:

```json
{
  "errors": [{
    "message": "The caller holds no scope that the operation needs.",
    "locations": [{"line": 1, "column": 34}],
    "path": ["assignments"]
  }],
  "data": {"departments": {"items": [{"name": "Research"}, {"name": "Sales"}]}, "assignments": null}
}
```

### Auth

With `options.dataservice.auth = false`, the default, the service has no auth and
`dataserviceConfig` is a `dsGraphql:Config`, whose `serviceConfig` has no `auth` field.

With `auth = true`, `dataserviceInitContext` authenticates each request with
`dsGraphql:Authenticator` before `ballerina/graphql` parses and validates the document, and each
root field checks the scopes of its action:

```ballerina
final dsGraphql:Authenticator dataserviceAuthenticator =
        check new (dataserviceConfig.serviceConfig.auth);

isolated function dataserviceInitContext(http:RequestContext requestContext, http:Request request)
        returns graphql:Context|error {
    graphql:Context ctx = new;
    check dataserviceAuthenticator.authenticate(ctx, request);
    // the dataloaders
    return ctx;
}

service graphql:Service /graphql on dataserviceListener {

    # Gets a page of employees.
    # ...
    resource function get employees(graphql:Context ctx, graphql:Field 'field,
            EmployeeFilter? filter = (), EmployeeSort[]? sort = (), int? size = (), int? offset = ())
            returns EmployeeList?|error {
        check dsGraphql:checkScopes(ctx, ["hr:read"]);
        check dsGraphql:checkRelationScopes(ctx, 'field, "Employee",
                {"assignments": {target: "Assignment", scopes: ["assignments:read"]}});
        // the read
    }
}
```

- **Why not declarative auth:** `@graphql:ServiceConfig {auth}` authenticates before
  validation, but it answers a missing credential with
  `Required authentication information is either missing or not valid for the resource.` and a
  missing scope with `Access is denied to the requested resource. The user might not have enough
  permission.`, both with `400`, checks one list of scopes for the whole service, and does not
  pass the caller to the resolvers, so no root field can check its own action's scopes.
- **Before validation:** `contextInit` runs before `ballerina/graphql` parses the document, so a
  request without a valid credential is answered with `UNAUTHENTICATED` whatever its document,
  including one that does not parse or validate and an introspection query, as #1503 requires.
- **Checking:** `authenticate` tries each provider that takes the `Authorization` header's
  scheme, in the order of the list, and the first that authenticates the credential decides, as
  `dsHttp:Authenticator` does in #1513. It keeps the caller in the `graphql:Context`.
- **Scopes:** each root field calls `dsGraphql:checkScopes` with the scopes of its action, as
  #1503 defines them, before anything else, and answers a caller without one with `FORBIDDEN`.
  An empty list takes the deciding provider's `scopes`, as in #1513. The scopes are written into
  each root field, since `ballerina/graphql` has already routed the document by then; there is
  no scope map as in #1513.
- **After validation:** an authenticated caller without a scope of the action gets the
  request errors of an invalid document before the scope check, since validation runs first.
  Such a caller can read the schema through introspection anyway, so a request error tells it
  nothing new.
- **Relations:** a root field whose selection reads a relation calls
  `dsGraphql:checkRelationScopes` with the `graphql:Field` of the root field, before it reads,
  as #1513 checks before existence. It walks the selection set, through fragments, and
  answers `FORBIDDEN` for the first selected relation whose related entity's `read` scopes the
  caller holds none of, with #1503's message. One check covers every record of the page, so the
  response has one error, not one per record. A mutation that returns a record checks the
  entity's own `read` scopes for a selected relation too, since a caller with `create` alone
  reads no relation.
- **Create, patch and delete results:** with `read` allowed, create, patch and delete call
  `dsGraphql:hasScope` with the entity's `read` scopes, and return `null`, with no entry in
  `errors`, to a caller without one, as #1503 gives. Create still creates the records, and an
  empty patch by such a caller does not read.
- **Required providers:** `dataserviceConfig` is a `dsGraphql:AuthConfig`, whose
  `serviceConfig.auth` is required, so the program does not start without it, and an empty list
  stops it with #1513's message,
  `The configurable value 'dataserviceConfig.serviceConfig.auth' must hold at least one
  authentication provider.`
- **Responses:** a missing or invalid credential is answered with `400`, the status that
  `ballerina/graphql` gives a `graphql:AuthnError` from `contextInit`, and
  `{"errors": [{"message": "The request needs a valid credential.", "extensions": {"code":
  "UNAUTHENTICATED"}}]}`. The response carries no
  `WWW-Authenticate` header, so a browser does not prompt for basic auth credentials.
- **Only `POST` with auth:** `authenticate` answers a `GET` request with `graphql:AuthzError`,
  `A request to a data service with auth must use POST.` `ballerina/graphql` runs mutations sent
  with `GET`, and a browser sends saved basic auth credentials with a cross-site `GET`, so a
  page on another site could otherwise run a mutation as the user. A `POST` must have
  `Content-Type: application/json`, which a cross-site page cannot send without a CORS
  preflight. Without auth, `GET` is accepted, since any caller can run the document anyway.

For example, to validate JWTs, set in `Config.toml` the same keys as #1513:

```toml
[[dataserviceConfig.serviceConfig.auth]]
[dataserviceConfig.serviceConfig.auth.jwtValidatorConfig]
issuer = "https://idp.example.com"
audience = "hr-api"
[dataserviceConfig.serviceConfig.auth.jwtValidatorConfig.signatureConfig.jwksConfig]
url = "https://idp.example.com/jwks"
```

`graphql:ListenerAuthConfig` has the fields of `http:ListenerAuthConfig`, so a provider is
configured as in #1513.

#### Introspection and GraphiQL under auth

- **Introspection** goes through `dataserviceInitContext`, so it needs a valid credential,
  and is published behind the service's auth, as #1503 requires. It checks no scope: no
  resolver of the service runs for `__schema` and `__type`, so the provider's `scopes` are not
  checked for it, unlike #1513's OpenAPI definition.
- **GraphiQL's page** is served without a credential. It is a static page, and holds nothing
  but the service's URL.
- **GraphiQL's requests** send the headers set in GraphiQL's Headers tab, so a user sets the
  credential there and re-fetches the schema.

### Limits

| Limit | Setting | Default | On a breach |
|---|---|---|---|
| Query depth | `maxQueryDepth` of `[dataserviceConfig.serviceConfig]` | `15` | Request error, `Query "<name>" has depth of <n>, which exceeds max depth of <max>` |
| Query complexity | `maxQueryComplexity` of `[dataserviceConfig.serviceConfig]` | `100` | Request error, `The operation <name> exceeds the maximum query complexity threshold. Maximum allowed complexity: <max>, actual complexity: <n>` |
| Page size | `pageSize` and `maxPageSize` of `[dataserviceConfig]` | `100`, `1000` | `size` above the maximum is reduced to it, as #1503 defines |
| Create many | `maxPageSize` | `1000` | `INVALID_INPUT`, `A create can hold at most <max> records.` |

- **Depth:** the generated schema nests data at most five fields deep, as in
  `departments { items { employees { items { name } } } }`, because related records have no
  relation fields. Introspection is the only part that nests further, and GraphiQL's
  introspection query has depth 13, which a lower limit would refuse. The default leaves room
  for it and stops deeper introspection documents.
- **Complexity:** `ballerina/graphql` adds up the complexity of each selected field, and does
  not multiply it by the size of a list. Each field counts `1`, and a to-many relation field
  counts `20`, through `@graphql:ResourceConfig {complexity: 20}`, because it runs one query per
  record that selects it. With the default, a document can select four to-many relation fields
  with their own fields. GraphiQL's introspection query counts `25`.
- **Queries per request:** with the limits, a document runs at most one query per root field, one
  per to-one relation field, and `size` queries per to-many relation field, of which there are at
  most `maxQueryComplexity / 20`.
- **Startup:** `dsGraphql:checkLimits` stops the program when a limit is below 1, with
  `The configurable value 'dataserviceConfig.serviceConfig.<limit>' must be at least 1, found
  <value>.` `ballerina/graphql` treats a complexity of `0` as no limit, which the check does not
  allow.

### Constraints

The service checks the model's constraints, kept in the generated persist types, with
`dataservice:checkConstraints` on each record that it converts from the input, as #1513 does for
its wire types, and answers a value that breaks one with `INVALID_INPUT` and #1503's message,
`The field '<field>' of the entity '<Entity>' breaks its '<constraint>' constraint.`
`ballerina/graphql`'s own validation is turned off, so the input types carry no constraint
annotations. With it on, `ballerina/graphql` answered a broken `maxLength` with
`Input validation failed in the field "createEmployee": Validation failed for '$.name:maxLength'
constraint(s).`

### Documentation

The schema's descriptions come from the generated doc comments, which carry the model's doc
comments, as #1503 defines:

| Schema element | Doc comment |
|---|---|
| A root field and its arguments | The resolver's summary and `+ param` lines |
| An object type and its fields | The service class's or record's summary, and each resolver's summary or each `+ field` line |
| An input type and its fields | The record's summary and each field's own doc comment |
| An enum and its values | The enum's summary and each member's doc comment |

- **Input fields:** `ballerina/graphql` reads the description of an input field from the field's
  own doc comment, not from the record's `+ field` lines, which it leaves out. The generated
  input types therefore document each field in place.
- **Summaries:** each root field's summary comes from its operation, and the entity's doc
  comment from the model follows it:

  | Operation | Summary |
  |---|---|
  | Get many | `Gets a page of employees.` |
  | Get one | `Gets an employee by its key.` |
  | A to-one relation | `Gets the employee of an assignment.` |
  | A to-many relation | `Gets the assignments of an employee.` |
  | Create one | `Creates an employee.` |
  | Create many | `Creates employees.` |
  | Patch | `Updates an employee by its key.` |
  | Delete | `Deletes an employee by its key.` |

- **Fields:** a field's description is its doc comment in the model, and otherwise names the
  field and its format, such as ``The `hiredOn` field of `Employee`, as an ISO 8601 date``. A
  foreign key without a doc comment gets #1503's `The key of the related 'Department'.`

With `options.dataservice.introspection = false`, the service carries
`@graphql:ServiceConfig {introspection: false}`, and `ballerina/graphql` answers `__schema` and
`__type` with `GraphQL introspection is not allowed by the GraphQL Service, but the query
contained __schema.`, while `__typename` still works. GraphiQL is not enabled.

### Configuration

| Setting | Where | Default |
|---|---|---|
| Base path | `options.dataservice.basePath` | `/graphql` |
| Auth | `options.dataservice.auth` | `false` |
| Introspection and GraphiQL | `options.dataservice.introspection` | `true` |
| Port | `port` of `[dataserviceConfig]` in `Config.toml` | `9090` |
| Page size when `size` is not given | `pageSize` of `[dataserviceConfig]` | `100` |
| Largest page size | `maxPageSize` of `[dataserviceConfig]` | `1000` |
| Other listener settings, such as TLS and timeouts | `listenerConfig` of `[dataserviceConfig]` | `ballerina/graphql`'s defaults |
| CORS | `cors` of `[dataserviceConfig.serviceConfig]` | no cross-origin requests |
| Query depth and complexity | `maxQueryDepth` and `maxQueryComplexity` of `[dataserviceConfig.serviceConfig]` | `15` and `100` |
| Authentication providers | `auth` of `[dataserviceConfig.serviceConfig]` | none: required when `auth` is `true`, and not declared otherwise |

`ballerina/dataservice.graphql` defines the configuration types, with #1513's layout. Each
includes `dataservice:Config` and adds GraphQL's fields:

```ballerina
public type ServiceConfig record {|
    graphql:CorsConfig cors = {};
    int maxQueryDepth = 15;
    int maxQueryComplexity = 100;
|};

public type AuthServiceConfig record {|
    *ServiceConfig;
    graphql:ListenerAuthConfig[] auth;
|};

public type Config record {|
    *dataservice:Config;
    graphql:ListenerConfiguration listenerConfig = {};
    ServiceConfig serviceConfig = {};
|};

public type AuthConfig record {|
    *dataservice:Config;
    graphql:ListenerConfiguration listenerConfig = {};
    AuthServiceConfig serviceConfig;
|};
```

```ballerina
// dataservice_config.bal
configurable dsGraphql:Config dataserviceConfig = {};
// With options.dataservice.auth = true:
// configurable dsGraphql:AuthConfig dataserviceConfig = ?;
```

- **Same keys as HTTP:** `graphql:ListenerConfiguration` and `graphql:CorsConfig` include
  `http:ListenerConfiguration` and `http:CorsConfig`, and `graphql:ListenerAuthConfig` has the
  fields of `http:ListenerAuthConfig`, so a `[dataserviceConfig]` table written for #1513 means
  the same here, apart from the two limits.
- **Limits are configurable** because they bound the cost of a request, as the page sizes do,
  and a deployment tunes them. Settings that change what the API accepts, such as `validation`,
  are not.
- **Two types for auth,** for the reason #1513 gives.

For example:

```toml
[dataserviceConfig]
port = 9092

[dataserviceConfig.serviceConfig]
maxQueryComplexity = 200

[dataserviceConfig.serviceConfig.cors]
allowOrigins = ["https://app.example.com"]
```

### Reserved names

GraphQL names allow only letters, digits and `_`, so #1503's `$` reservation becomes a leading
`_`:

- **Generated names:** no generated root field, argument, or field of a generated type starts
  with `_`. Names that start with one `_` are reserved for later query and metadata operations,
  such as `_and`, `_or` and `_not` in `<Entity>Filter`. GraphQL itself reserves names that start
  with `__`.
- **Model names:** a model field whose name starts with `_` cannot be exposed, and the persist
  tool reports it.
- **Names GraphQL cannot hold:** a Ballerina field name with characters other than ASCII letters,
  digits and `_`, written as a quoted identifier with escapes, cannot be a GraphQL name, and the
  persist tool reports it. A quoted identifier of a keyword, such as `'type`, is the name `type`.
- **Generated type names:** the types in [Type names](#type-names) are the names #1503's
  generated-type rule reserves for GraphQL, each only when it is generated. `OrderObject` is
  reserved next to an `Order` that allows `read` or `create`, and free next to an `Order` that
  only allows `update`. `OrderRelatedObject` is generated for `Order` as a relation target and is
  also the `<Entity>Object` of an entity `OrderRelated`, so the two entities cannot both be
  exposed. `pull` compares every name in the table.
- **Library type names:** the input types and enums of `ballerina/dataservice.graphql`, such as
  `IntFilter` and `SortDirection`, are schema types of every service, so a model entity or enum
  with one of their names is reported by the persist tool, as is a model enum whose generated
  `<Enum>Filter` would clash with another type.

### Generated code

#### Files

As in #1503: `dataservice.bal` holds the client, the listener, the service, the context
function, the payload classes and the dataloader batch functions; `dataservice_types.bal`
holds, per entity in model order, the related, list, input, filter and sort types, the entity
description of #1513, and the conversion functions; `dataservice_config.bal` holds
`dataserviceConfig`, the page configuration and, with `auth = true`, the authenticator.

The samples below read through streams. With `options.eagerLoading = true`, the client's
collection resources return arrays, and each read takes the array in place of the stream, as
#1503 gives.

Each generated public type, class and resolver has a short doc comment: a one-line summary and
one-line `+ param` and `+ return` lines, with the descriptions in [Documentation](#documentation).
Input types document each field in place.

#### Root fields

```ballerina
service graphql:Service /graphql on dataserviceListener {

    # Gets a page of employees.
    #
    # + filter - The conditions that the employees match
    # + sort - The order of the employees; each entry names one field
    # + size - The number of employees in the page
    # + offset - The number of employees to skip
    # + return - A page of employees, or the error
    resource function get employees(EmployeeFilter? filter = (), EmployeeSort[]? sort = (),
            int? size = (), int? offset = ()) returns EmployeeList?|error {
        dataservice:Query query = check dsGraphql:toQuery(dataserviceEmployeeEntity,
                dataservicePageConfig, filter, sort, size, offset);
        stream<Employee, persist:Error?> rows = dataserviceClient->/employees(Employee,
            whereClause = query.whereClause, orderByClause = query.orderByClause,
            limitClause = query.limitClause, offsetClause = query.offsetClause
        );
        Employee[]|persist:Error items = from Employee item in rows
            select item;
        if items is persist:Error {
            return dsGraphql:toListError(items, "Employee");
        }
        boolean hasMore = dataservice:trimToPage(items, query);
        return {items: from Employee item in items select new EmployeeObject(item), hasMore};
    }

    # Gets an employee by its key.
    #
    # + id - The id of the employee
    # + return - The employee, or the error
    resource function get employee(int id) returns EmployeeObject?|error {
        Employee|persist:Error item = dataserviceClient->/employees/[id];
        if item is persist:Error {
            return dsGraphql:toGetError(item, "Employee", [id]);
        }
        return new (item);
    }

    # Creates employees.
    #
    # + input - The employees to create
    # + return - The created employees, or the error
    remote function createEmployees(EmployeeInsertInput[] input) returns EmployeeList?|error {
        // Checks the count, converts each input, checks its constraints, and in one transaction
        // posts the records and reads them back with one query on their keys.
    }

    # Updates an employee by its key.
    #
    # + id - The id of the employee
    # + input - The fields to change
    # + return - The updated employee, `()` when it cannot be returned, or the error
    remote function updateEmployee(int id, EmployeeUpdateInput input) returns EmployeeObject?|error {
        EmployeeUpdate value = check transformInputToEmployeeUpdate(input);
        // An empty patch reads as get one. Otherwise:
        Employee|persist:Error updated = dataserviceClient->/employees/[id].put(value);
        if updated is persist:Error {
            return dsGraphql:toUpdateError(updated, "Employee", [id]);
        }
        return new (updated);
    }
}
```

- **Return types:** every root field returns `T?|error`, which `ballerina/graphql` makes a
  nullable field, and `T|error` would make non-null. GraphQL has no per-field error list, as
  HTTP has status codes, so the error categories are documented in this proposal and the module's
  specification rather than in each signature.
- **`toUpdateError`** returns `()` for `persist:ReadBackError`, after
  logging it, as #1513's does.
- **Context and field parameters:** with `auth = true`, root fields take the `graphql:Context`,
  and those whose result has relation fields take the `graphql:Field`. Neither is an argument
  in the schema.
- **Conversions:** `transformInputTo<Entity>Insert` and `transformInputTo<Entity>Update`
  convert the input types to persist's types with `ballerina/dataservice`'s conversions, and
  answer a value that does not parse, a `null` that the field cannot hold, or a broken
  constraint with an `Error`. The resolvers of `<Entity>Object` and `<Entity>RelatedObject` convert
  each field as they return it.

#### `ballerina/dataservice.graphql`

The generated service imports `ballerina/dataservice.graphql` as `dsGraphql`. Its public API,
named by what each function returns:

| Symbol | Kind | Use |
|---|---|---|
| `Config`, `AuthConfig`, `ServiceConfig`, `AuthServiceConfig` | types | The type of `dataserviceConfig` |
| `IntFilter`, `FloatFilter`, `DecimalFilter`, `StringFilter`, `BooleanFilter`, `DateFilter`, `TimeOfDayFilter`, `CivilFilter`, `UtcFilter`, and their `Nullable` variants | input types | The operators of `<Entity>Filter` |
| `SortDirection` | enum | The direction of a `<Entity>Sort` entry |
| `Error` | error type | `graphql:ServiceError`, with the category's code in `extensions.code`: every error that the service returns |
| `checkLimits(ServiceConfig config) returns error?` | function | Checks the limits at startup |
| `toQuery(dataservice:Entity entity, dataservice:PageConfig config, record {}? filter, record {}[]? sort, int? size, int? offset) returns dataservice:Query\|Error` | function | Checks the filter and sort arguments and builds the query of get many and of a to-many relation, through `dataservice:toQuery` |
| `toRelatedQuery(...) returns dataservice:Query\|Error` | function | The same, for a to-many relation of one record, through `dataservice:toRelatedQuery` |
| `toKeyOrder(map<anydata>[] rows, dataservice:Entity entity, string relation, map<anydata>[] links) returns (map<anydata>?)[]` | function | The related rows of a dataloader batch in the order of its links, `()` for a link without a record |
| `toListError`, `toGetError`, `toCreateError`, `toUpdateError`, `toDeleteError` | functions | The `Error` for a persist error of each operation, or `()` from `toUpdateError` for an update that cannot be read back |
| `toInvalidInput(dataservice:ConversionError err, string entity, string field) returns Error` | function | The `Error` for a value that does not parse |
| `toNullError(string entity, string field) returns Error` | function | The `Error` for `null` on a field that cannot hold it |
| `checkFinite(float value, string entity, string field) returns Error?` | function | Rejects an input `float` that is not finite |
| `toFinite(float value, string entity, string field) returns float\|Error` | function | Returns a stored `float`, or the error for one that is not finite |
| `Authenticator` | class | `init(graphql:ListenerAuthConfig[] providers)` and `authenticate(graphql:Context ctx, http:Request request) returns graphql:AuthnError\|graphql:AuthzError?` |
| `checkScopes(graphql:Context ctx, string[] scopes) returns Error?` | function | The scope check of a root field's action |
| `hasScope(graphql:Context ctx, string[] scopes) returns boolean` | function | Whether create, patch and delete return the record |
| `checkRelationScopes(graphql:Context ctx, graphql:Field field, string entity, map<RelationScopes> relations, string[]? entityScopes = ()) returns Error?` | function | The relation check of a root field's selection; `RelationScopes` holds the related entity's name and `read` scopes |

The exact signatures are settled in the implementation and listed in the module's
specification, which fixes them for generated code as #1503 requires.

What it shares and what it duplicates:

| From | Used as it is | Duplicated in `dsGraphql` |
|---|---|---|
| `ballerina/dataservice` | The annotations, the entity description, `Query` and the query functions, the page configuration, `checkCreateSize`, `checkFiniteKey`, `checkConstraints`, the date, time and `byte[]` conversions, `DataserviceError`, `ErrorCode` and the messages | — |
| `ballerina/dataservice.http` | — | The provider handling of `Authenticator` and the caller's scope check, the per-operation error functions, and the configuration layout. `dsGraphql` does not import `dsHttp`, as #1503 keeps protocol packages apart, and `ballerina/dataservice` stays free of `ballerina/http` |

The duplicated provider handling uses the same `ballerina/http` listener auth handlers, with
`graphql:ListenerAuthConfig` in place of `http:ListenerAuthConfig`.

### Several protocols on one listener

#1503 defers several protocols on one listener. Nothing in this proposal blocks it:

- **Listener:** a `graphql:Listener` can be created on an `http:Listener`, so an `http:Service`
  and a `graphql:Service` can answer on one port.
- **Paths:** the default base paths, `/api` and `/graphql`, and GraphiQL's `/graphiql` and
  Swagger UI's paths under `/api`, do not overlap.
- **Configuration:** `listenerConfig` has the same fields in `dsHttp:Config` and
  `dsGraphql:Config`, so a shared listener can take one.
- **Interceptors:** #1513's interceptors belong to the `http:Service`, and do not see GraphQL
  requests.

## Alternatives

- **Relay connections** (`edges`, `node`, `pageInfo`, cursors) are GraphQL's common paging
  convention. #1503 chose offset paging and the `items` and `hasMore` envelope, and rejected
  cursors because they tie every page to the sort it was issued for. A connection type could be
  added later as a separate field without changing the envelope.
- **One object type per entity, with relations at any depth.** A related record would then be
  an `<Entity>Object` with its own relation fields, so a document could nest relations
  without end. A to-many relation runs one query per record, and `ballerina/graphql`'s
  complexity does not multiply by list sizes, so nested to-many relations would cost `size`
  to the power of the depth in queries with no limit able to see it. `<Target>RelatedObject`
  keeps #1503's one hop in the schema. Allowing more hops later adds relation fields to it,
  which does not break a client.
- **Sort as a list of enum values,** such as PostGraphile's `[EMPLOYEES_NAME_DESC]`. Enum members
  are module-level constants in Ballerina, so the values of two entities, such as `ID_ASC`,
  would clash with each other and with the model's enums.
- **Errors as data,** a union of the record and error types for each result. `ballerina/graphql`
  allows only distinct service classes in a union, ``invalid GraphQL union type member '0'
  found. Only distinct service types are allowed``, clients must select each error type, and
  auth and validation errors would still be `errors` entries.
- **`null` alone for get one,** as Hasura's `<table>_by_pk` and PostGraphile answer a lookup that
  finds nothing. A client that treats any entry in `errors` as failure, such as Apollo Client's
  default error policy, would not throw for it. It is not adopted: it would make a missing key
  look the same as a record the caller may not see, and differ from patch and delete, from HTTP's
  `404` and from Data API builder.
- **A key object or `null` for patch and delete without `read`.** A key object repeats the
  arguments, and a nullable record type would put the entity's fields in the schema although
  the caller can never read them. `Boolean` says the action happened.
- **Declarative auth** on `@graphql:ServiceConfig`; see [Auth](#auth).
- **A field interceptor for scopes.** A `graphql:Interceptor` could check the scopes of every
  root field from one map, as #1513's request interceptor does. It runs after validation like
  the root field itself, adds a call to every field, and is generated in the service's package
  anyway; a call at the top of each root field is as short and shows the scopes beside the
  operation.
- **`ballerina/graphql`'s constraint validation.** Its message differs from #1503's, and it would
  need the constraints copied onto the input types, whose date fields are strings.
- **The `ID` scalar for keys.** `@graphql:ID` serializes a key as a string, which loses the type
  of `int`, `decimal` and composite keys, and GraphQL's `ID` is meant for opaque global
  identifiers, which this proposal does not have.
- **Custom scalars** such as `Long`, `Date` and `Base64`. `ballerina/graphql` does not support
  custom scalars.

## Testing

- **Code generation:** expected-output tests for single and composite keys, every action
  combination, `auth` on and off, `introspection` on and off, a custom base path, one-word,
  multi-word, irregular and uncountable entity names, enums, every field rule, and every field
  type.
- **Schema:** the introspected schema of the generated service for each of those, including
  nullability, descriptions from the model's doc comments, and the absence of `Internal` fields,
  disabled operations and hidden directions.
- **Persist tool checks:** each GraphQL check of #1503.
- **Behaviour,** against H2 and every other SQL datastore available to the test run: every
  operation and argument; patch with fields left out, set to `null` on a nullable field and on
  one that is not; an empty patch with and without `read`; patch and delete without `read`
  returning `true`; create many above the maximum, empty, and with a duplicate key; several
  mutations in one document with one failing.
- **Types:** a round trip of every `time:*` type, `byte[]`, `decimal` as a variable, an `int`
  beyond 32 bits, and an enum; `INVALID_INPUT` for a value in the wrong format and for a `float`
  that is not finite; `INTERNAL` for a stored `NaN` on H2.
- **Query arguments:** every operator on every type it allows, a `null` operator, `isNull`,
  `sort` entries with none or two fields, a field named twice, paging through every page, and the
  `size` and `offset` limits.
- **Relations:** to-one and to-many fields with single and composite keys, a dangling foreign
  key, an empty to-one side, a to-many field longer than the page, and the number of queries
  per request: one per to-one relation field and one per record for a to-many field.
- **Errors:** each category with its message, partial results across root fields, a
  request error without `data`, and the log lines.
- **Auth:** no credential and a bad one, for a valid document, an invalid one and introspection;
  a credential without a scope, with a default scope, with a scope from `scopes`, and with an
  empty list; relation scopes under a query and under a mutation; create, patch and delete for a
  caller without a `read` scope; `GET` refused; a missing and an empty `auth` list stopping the program;
  CORS headers on an auth error.
- **Limits:** the depth and complexity limits, GraphiQL's introspection query within the
  defaults, and each limit below 1 stopping the program.
- **GraphiQL:** served at `/graphiql` with introspection and not without it.

## Risks and assumptions

- **Large integers.** `Int` values beyond 32 bits break GraphQL's specification of `Int`, and
  lose precision beyond 2^53 in JavaScript clients.
- **Decimal literals** in a document lose their scale and precision; clients must send decimals
  as variables.
- **Authentication answers `400`,** not `401`, without `WWW-Authenticate`, as `ballerina/graphql`
  answers a `contextInit` auth error.
- **To-many relations cost one query per record,** as in #1503, bounded by the page size and the
  query complexity.
- **Lost updates.** As in #1503, there is no optimistic concurrency control.

## Dependencies

- [Data service generation for bal persist](https://github.com/ballerina-platform/ballerina-spec/issues/1503).
- [Data service generation for bal persist: HTTP](https://github.com/ballerina-platform/ballerina-spec/issues/1513),
  for the formats, messages and configuration layout this proposal reuses.
- `ballerina/graphql` 1.19.2, for `graphql:ServiceError`.
- `ballerina/dataservice`.
- `ballerina/dataservice.graphql`: a new library, released separately from
  `ballerina/dataservice`, as `ballerina/dataservice.http` is.

## Future work

- **Subscriptions** for created, updated and deleted records. They need change events from
  persist or the database, which persist does not provide.
- **Relay connections** as additional fields, if clients ask for them.
- **Reading only the selected columns,** from the selection set, once persist has a runtime
  projection, as #1503's roadmap gives for `fields`.
- **MCP,** the next protocol proposal of #1503.
- **More hops,** by adding relation fields to the `<Target>RelatedObject` types, with the
  complexity of nested to-many fields multiplied.
- **One query for a to-many relation across a page,** with a limit per record, as #1503's
  roadmap gives.
- **`_and`, `_or` and `_not`** in the filter, and a total on the list envelopes, as #1503's
  roadmap gives.
- **Several protocols on one listener,** as [above](#several-protocols-on-one-listener).
- **Federation,** through `ballerina/graphql.subgraph`, with each entity's key as its `@key`.
