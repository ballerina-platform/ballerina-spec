# Data service generation for bal persist: HTTP

- Author: @niveathika
- Reviewers: 
- Created: 2026-10-07
- Updated: 2026-10-22
- Issue: [#1513](https://github.com/ballerina-platform/ballerina-spec/issues/1513)
- Status: Draft

## Summary

Defines how the protocol-neutral CRUD shape in
[Data service generation for bal persist](https://github.com/ballerina-platform/ballerina-spec/issues/1503) is rendered as an
`http:Service` when `options.dataservice.protocol = "http"`.

Each exposed entity becomes a collection resource and a key resource under the base path. The
six operations map to `GET`, `POST`, `PATCH` and `DELETE`, results are JSON, and the error
categories map to status codes.

Everything marked ✅ was compiled and run on Ballerina 2201.13.3 with `ballerina/http` 2.17.3
and a generated persist in-memory client.

## Goals

- Define the URL, method, request body, response body and status code of every operation.
- Use the persist-generated types as the request and response bodies, except where a field's
  JSON form must differ: date and time values and `byte[]`.
- Use plain REST conventions: the key in the path, `201` with `Location` on create, `PATCH`
  for a partial update.

## Non-goals

- Query options, relations and auth. They follow the roadmap in #1503.
- `PUT` as a full replace. The persist client has no replace operation.
- OpenAPI generation. It is listed under future work.
- Compatibility with the wire format of WSO2 MI data services.

## Design

### Listener and service

The generated file declares one listener and one service in the default module:

```ballerina
final Client dataserviceClient = check new ();
listener http:Listener dataserviceListener = new (dataservicePort, dataserviceListenerConfig);

service /api on dataserviceListener {
    // one group of resources per exposed entity
}
```

- **Base path:** the service's base path is `options.dataservice.basePath`, `/api` by default.
- **Shared listener:** `dataserviceListener` is a module-level listener, so user code in the
  same module can attach its own `http:Service` to it, with a different base path, and be
  served on the same port. This is the escape hatch for custom endpoints. ✅ (A GraphQL and an
  MCP service were attached to the same `http:Listener` and served alongside it.)

### Operations

For an entity `Employee` whose persist resource name is `employees`, with key `id`:

| Operation | Action | Request | Success response |
|---|---|---|---|
| Get many | `read` | `GET /api/employees` | `200`, `{"items": [Employee, ...]}` |
| Get one | `read` | `GET /api/employees/{id}` | `200`, `Employee` |
| Create one | `create` | `POST /api/employees` with an `EmployeeInsert` object | `201`, `Location: /api/employees/{id}`, the created `Employee` |
| Create many | `create` | `POST /api/employees` with an array of `EmployeeInsert` | `201`, `{"items": [Employee, ...]}` |
| Patch one | `update` | `PATCH /api/employees/{id}` with an `EmployeeUpdate` object | `200`, the updated `Employee` |
| Delete one | `delete` | `DELETE /api/employees/{id}` | `200`, the deleted `Employee` |

- **Create one and create many share one route.** The payload parameter is typed
  `EmployeeInsert|EmployeeInsert[]`; `ballerina/http` binds a JSON object to the first and an
  array to the second. ✅
- **Create many has no `Location` header**, because it creates several resources.
- **Patch is partial.** Fields left out of the body are not changed. A field set to `null`
  is set to `null` when the field is nullable.
- **Delete returns the deleted record**, as the persist client does. A client that does not
  need it can ignore the body.

#### Generated resources

```ballerina
service /api on dataserviceListener {

    resource function get employees() returns EmployeeList|dsHttp:InternalError {
        Employee[]|persist:Error items = from Employee item in dataserviceClient->/employees(Employee)
            select item;
        if items is persist:Error {
            return dsHttp:internalError(items);
        }
        return {items};
    }

    resource function get employees/[int id]() returns Employee|dsHttp:ErrorResponse {
        Employee|persist:Error item = dataserviceClient->/employees/[id];
        if item is persist:Error {
            return dsHttp:errorResponse(item, "Employee", [id]);
        }
        return item;
    }

    resource function post employees(EmployeeInsert|EmployeeInsert[] payload)
            returns EmployeeCreated|EmployeeListCreated|dsHttp:ErrorResponse {
        // Posts the records as an array, then reads back each created record by its returned key.
    }

    resource function patch employees/[int id](EmployeeUpdate payload)
            returns Employee|dsHttp:ErrorResponse { ... }

    resource function delete employees/[int id]() returns Employee|dsHttp:ErrorResponse { ... }
}
```

- **Return types:** get many returns only `dsHttp:InternalError` on failure. Every other operation
  returns `dsHttp:ErrorResponse`, the union of the error records in [Errors](#errors),
  because a write can fail with any of them.
- **Library calls:** the generated service imports `ballerina/dataservice.http` as `dsHttp`
  and passes the entity name and key values to its functions, which build the error response,
  log the detail and build `Location`.
- **Location:** each key value is percent-encoded as a path segment, so a key such as `P 1/a`
  gives `/api/assignments/P%201%2Fa/1`. ✅

The status code types are records that include the `ballerina/http` status code records:

```ballerina
public type EmployeeCreated record {|
    *http:Created;
    Employee body;
|};

public type EmployeeListCreated record {|
    *http:Created;
    EmployeeList body;
|};
```

#### Disabled operations

An operation whose action is not enabled is not generated. `ballerina/http` then answers on its
own:

| Situation | Response |
|---|---|
| A method that exists on no resource of the path, for example `PATCH` on a read-only entity | `405 Method Not Allowed` ✅ |
| A path that matches no resource, for example an entity that is not exposed | `404 Not Found` |

### Keys

- **Single key:** one path segment, `/employees/{id}`, typed as the key field's type.
- **Composite key:** one segment per key field, in declaration order, for example
  `/assignments/{employeeId}/{projectCode}`. ✅ There is no common convention for composite keys
  (see [Alternatives](#alternatives)); positional segments are the conventional REST form for a
  single key, extend it without new syntax, and match the persist client's resource paths.
- **Key types:** `int`, `string`, `float`, `decimal` and `boolean` keys bind as path
  parameters. A segment that does not convert to the key's type is answered with `400` by
  `ballerina/http`. ✅

### Types and JSON

The resources use the persist-generated types directly: `Employee` in responses,
`EmployeeInsert` and `EmployeeUpdate` in requests.

| Ballerina type | JSON |
|---|---|
| `int`, `float`, `decimal` | number |
| `string`, `boolean` | string, boolean |
| `T?` | the value or `null` |
| enum | string |
| `byte[]` | a base64 string (RFC 4648, standard alphabet, padded) |
| `time:Date` | an ISO 8601 date, `2024-01-02` |
| `time:TimeOfDay` | an ISO 8601 time, `10:15:30` or `10:15:30.5` |
| `time:Civil` | an ISO 8601 date-time without an offset, `2024-01-02T10:15:30` |
| `time:Utc` | an ISO 8601 date-time in UTC, `2024-01-02T10:15:30Z` |

Ballerina's own JSON form of these types does not suit a client: `time:Utc` is a tuple and
becomes an array such as `[1704189330, 0.5]`, the other `time:*` types become records, and
`byte[]` becomes an array of numbers.

#### Wire types

An entity with a `time:*` or `byte[]` field gets generated wire types that hold those fields as
`string`. The other entities use the persist types as they are.

| Persist type | Wire type |
|---|---|
| `Employee` | `EmployeeRecord` |
| `EmployeeInsert` | `EmployeeInsertRecord` |
| `EmployeeUpdate` | `EmployeeUpdateRecord` |

```ballerina
public type EmployeeRecord record {|
    readonly int id;
    string name;
    string hiredOn;
|};
```

The `<Entity>List` envelope and the status code records of such an entity hold the wire type.
The generated service converts between the two with functions from `ballerina/dataservice`,
so a fix to a format is released without regeneration:

| Type | To JSON | From JSON |
|---|---|---|
| `byte[]` | `dataservice:bytesToString` | `dataservice:bytesFromString` |
| `time:Date` | `dataservice:dateToString` | `dataservice:dateFromString` |
| `time:TimeOfDay` | `dataservice:timeOfDayToString` | `dataservice:timeOfDayFromString` |
| `time:Civil` | `dataservice:civilToString` | `dataservice:civilFromString` |
| `time:Utc` | `dataservice:utcToString` | `dataservice:utcFromString` |

A request value that does not parse is answered with `400` and `INVALID_INPUT`; see
[Errors](#errors).

### Errors

Each error category in #1503 maps to a status code. The body is the `DataserviceError` record
from `ballerina/dataservice`, with the code and message #1503 defines for the category.

| Category | Status | `code` | Raised from |
|---|---|---|---|
| Not found | `404` | `NOT_FOUND` | `persist:NotFoundError` ✅ |
| Conflict | `409` | `CONFLICT` | `persist:AlreadyExistsError` ✅ |
| Constraint violation | `409` | `CONSTRAINT_VIOLATION` | `persist:ConstraintViolationError`, raised only by an update today; see [Risks](#risks-and-assumptions) ✅ |
| Invalid input | `400` | `INVALID_INPUT` | a date, time or `byte[]` value that does not parse |
| Invalid input | `400` | — | `ballerina/http` payload or path binding ✅ |
| Internal | `500` | `INTERNAL` | any other error |

The status code records are not specific to an entity, so they are defined in
`ballerina/dataservice.http`, which keeps `ballerina/dataservice` free of `ballerina/http`:

```ballerina
public type NotFound record {|
    *http:NotFound;
    dataservice:DataserviceError body;
|};
```

`InvalidInput`, `Conflict`, `ConstraintViolation` and `InternalError` follow the same form,
and `ErrorResponse` is the union of the five.

The message for a value that does not parse is
`The field '<field>' of the entity '<Entity>' is not <format>.`, where `<format>` is
`an ISO 8601 date`, `an ISO 8601 time`, `an ISO 8601 date-time` or `a base64 string`.

Other invalid input is answered by `ballerina/http` before the resource runs, so its body is
the module's default error body, not `DataserviceError`. It names every missing or mistyped field.
✅

Example responses: ✅

```
POST /api/employees  {"id":1, ...}            → 201  Location: /api/employees/1
POST /api/employees  {"id":1, ...} (again)    → 409  {"code":"CONFLICT", "message":"A record that conflicts with an existing record of the entity 'Employee' already exists."}
GET  /api/employees/99                        → 404  {"code":"NOT_FOUND", "message":"A record with the key '99' does not exist for the entity 'Employee'."}
GET  /api/employees/abc                       → 400  (ballerina/http default body)
PUT  /api/employees/2                         → 405
```

### Configuration

| Setting | Where | Default |
|---|---|---|
| Base path | `options.dataservice.basePath` | `/api` |
| Port | `dataservicePort` in `Config.toml` | `9090` |
| Other listener settings, such as TLS and timeouts | `dataserviceListenerConfig` in `Config.toml` | `ballerina/http`'s defaults |

`persist_dataservice_config.bal` declares both configurable values:

```ballerina
configurable int dataservicePort = 9090;
configurable http:ListenerConfiguration dataserviceListenerConfig = {};
```

For example, to serve over TLS:

```toml
[dataserviceListenerConfig.secureSocket.key]
certFile = "/path/to/public.crt"
keyFile = "/path/to/private.key"
```

## Alternatives

- **A separate route for create many**, such as `POST /employees/$batch`. Not needed: the
  union payload type lets one route take both, and `$` names stay reserved for query and
  metadata operations.
- **`PUT` for update.** `PUT` means full replace in HTTP, and the persist client's update is
  partial, so the method is `PATCH`.
- **`204 No Content` for delete.** Returning the deleted record matches the persist client and
  the other protocols, and costs nothing.
- **A bare array for get many.** Rejected in #1503: paging and count need room in the
  envelope.
- **Other composite key forms.** Named pairs, as Data API builder uses
  (`/assignments/employeeId/4/projectCode/P1`), say which value is which key but make single
  keys unusual (`/employees/id/4`). OData's `/assignments(employeeId=4,projectCode='P1')` has no
  form in a Ballerina resource path. A delimiter in one segment (`/assignments/4,P1`) needs
  escaping and cannot be typed. Query parameters (`/assignments?employeeId=4&projectCode=P1`)
  address the collection, where filters belong.

## Testing

- Code generation: expected-output tests for single and composite keys, every action
  combination, and a custom base path.
- Behaviour, against the in-memory and H2 datastores: every row of the operations and errors
  tables, including `405` for a disabled method and `400` for a mistyped key.
- A round trip of every `time:*` type and `byte[]` through create and get one, and `400` with
  `INVALID_INPUT` for a value in the wrong format.
- A user-written service attached to `dataserviceListener` is served on the same port.

## Risks and Assumptions

- **Two error body shapes.** Invalid input that `ballerina/http` rejects uses its default
  body, the others use `DataserviceError`. Aligning them needs an error interceptor on the generated
  service.
- **Foreign key violations on create and delete are internal errors.** The persist SQL client
  raises `persist:ConstraintViolationError` only from an update. A create or delete that violates a
  foreign key raises a plain `persist:Error`, so the service answers `500` until the persist SQL
  client classifies those errors too. An update that violates a foreign key is answered with `409`
  and `CONSTRAINT_VIOLATION`. ✅
- **Create reads back after insert.** As in #1503, a create is not atomic with the read that
  builds its response.

## Dependencies

- [Data service generation for bal persist](https://github.com/ballerina-platform/ballerina-spec/issues/1503)
- `ballerina/http`
- `ballerina/dataservice`
- `ballerina/dataservice.http`: a new library, released separately from `ballerina/dataservice`

## Future work

- OpenAPI generation for the generated service.
- An error interceptor so invalid-input errors use `DataserviceError`.
- Query parameters for filter, sort, page and count, under the `read` action.
- Relations, under the `read` action, as follows.

### Relations

| Form | Example | Returns |
|---|---|---|
| Relation route, to-many | `GET /api/employees/4/assignments` | `AssignmentList`, with the query parameters of get many |
| Relation route, to-one | `GET /api/employees/4/department` | `Department`, or `404` |
| `expand` | `GET /api/employees/4?expand=department,assignments` | The record with the related records embedded |

- **Segment:** the relation field's name in the model, unchanged, after the entity's full key:
  `/assignments/4/P1/employee` for a composite key. Every entity has a fixed number of key
  segments, so a relation route never matches the same path as get one.
- **`expand`:** works on to-one and to-many relations, as OData `$expand`, PostgREST embedding
  and Data API builder's nested GraphQL fields do. An expanded to-many list holds at most one
  page and has no cursor; the relation route pages through all of it.
- **Exposure:** a relation is offered only when both entities allow `read`. It needs no
  annotation of its own: a caller who can read both entities can already reach the related
  records through the foreign key, so a separate switch would protect nothing. Without the
  related entity's `read`, the foreign key field is still returned as a field of the record.
- **Writes:** a relation is set by writing its foreign key fields under the owning entity's
  `create` or `update`. Nested writes are later work.
- **Persist prerequisites:** the persist SQL client loads to-many relations with one query per
  parent record and without a limit. Expanding a to-many relation on get many needs batched,
  limited loading in the client first.
