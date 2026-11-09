# Data service generation for bal persist: HTTP

- Author: @niveathika
- Reviewers: 
- Created: 2026-10-07
- Updated: 2026-11-01
- Issue: [#1513](https://github.com/ballerina-platform/ballerina-spec/issues/1513)
- Status: Draft

## Summary

This proposal defines how the protocol-neutral CRUD shape in
[Data service generation for bal persist](https://github.com/ballerina-platform/ballerina-spec/issues/1503)
is rendered as an `http:Service` when `options.dataservice.protocol = "http"`.

Each exposed entity becomes a collection resource and a key resource under the base path, with
a resource per relation under the key. The operations map to `GET`, `POST`, `PATCH` and
`DELETE`, the query options map to query parameters, results are JSON, and the error categories
map to status codes.

Each case marked ✅ has been compiled and run. Unless its text names another setup, it ran on
Ballerina 2201.13.3 with `ballerina/http` 2.17.3 and a generated persist in-memory client, and
the implementation's tests recheck it on H2 with Ballerina 2201.14.0. The implementation
targets Ballerina 2201.14.0 and the SQL datastores.

The examples use the `Employee` and `Department` entities of #1503.

## Goals

- Define the URL, method, request body, response body and status code of every operation.
- Use the persist-generated types as the request and response bodies, except where a field's
  JSON form must differ: date and time values and `byte[]`.
- Use plain REST conventions: the key in the path, `201` with `Location` on create, `PATCH`
  for a partial update.

## Non-goals

- Row-level auth and nested writes. They follow the roadmap in #1503.
- `PUT` as a full replace. The persist client has no replace operation.
- Compatibility with the wire format of WSO2 MI data services.

## Design

### Listener and service

`dataservice.bal` declares one listener and one service in the default module. The service
creates the persist client and checks the page sizes in its `init`, so a failure stops it from
starting:

```ballerina
listener http:Listener dataserviceListener =
        new (dataserviceConfig.port, dataserviceConfig.listenerConfig);

@http:ServiceConfig {cors: dataserviceConfig.serviceConfig.cors}
service http:InterceptableService /api on dataserviceListener {

    private final Client persistClient;
    private final dataservice:PageConfig pageConfig;

    function init() returns error? {
        self.persistClient = check new ();
        self.pageConfig = check dataservice:toPageConfig(dataserviceConfig.pageSize,
                dataserviceConfig.maxPageSize);
    }

    public function createInterceptors() returns DataserviceErrorInterceptor => new;

    // one group of resources per exposed entity
}

isolated service class DataserviceErrorInterceptor {
    *http:ResponseErrorInterceptor;

    isolated remote function interceptResponseError(error err, http:RequestContext ctx,
            http:Response response) returns http:NextService? {
        dsHttp:setErrorBody(response, err);
        http:NextService|error? next = ctx.next();
        return next is http:NextService ? next : ();
    }
}
```

- **Base path:** the service's base path is `options.dataservice.basePath`, `/api` by default.
- **Trailing slash:** a path with a trailing slash, such as `/api/employees/`, addresses the
  same resource as without it, as `ballerina/http` matches paths. ✅
- **CORS:** the service takes its CORS settings from `dataserviceConfig.serviceConfig.cors`,
  and allows no cross-origin request by default. ✅ On Ballerina 2201.14.0, a preflight request
  was answered with the origins and methods set in `Config.toml`.
- **Error interceptor:** `DataserviceErrorInterceptor` gives the errors that `ballerina/http`
  raises before a resource runs the `DataserviceError` body, through `dsHttp:setErrorBody`;
  see [Errors](#errors). It is generated in the service's package rather than defined in
  `ballerina/dataservice.http`, because the OpenAPI definition leaves out an interceptor class
  from another package
  ([ballerina-library#9633](https://github.com/ballerina-platform/ballerina-library/issues/9633)).
  ✅ On Ballerina 2201.14.0, with the class from a dependency, every `400` of the definition was
  `oneOf` the declared body and `ballerina/http`'s `ErrorPayload`; with the class in the
  service's package, it was the declared body alone.
- **Auth interceptor:** with `auth = true`, `DataserviceAuthInterceptor` checks the credential
  and scopes of each request before it is dispatched; see [Auth](#auth).

### Operations

For an entity `Employee` whose collection name is `employees`, with key `id`:

| Operation | Action | Request | Success response |
|---|---|---|---|
| Get many | `read` | `GET /api/employees` with the [query parameters](#query-parameters) | `200`, `{"items": [Employee, ...], "hasMore": false}` |
| Get one | `read` | `GET /api/employees/{id}`, optionally with `fields` | `200`, `Employee` |
| Get related, to-one | `read` | `GET /api/employees/{id}/department`, optionally with `fields` | `200`, `Department` |
| Get related, to-many | `read` | `GET /api/departments/{id}/employees` with the query parameters | `200`, `{"items": [Employee, ...], "hasMore": false}` |
| Create one | `create` | `POST /api/employees` with an `EmployeeInsert` object | `201`, `Location: /api/employees/{id}`, the created `Employee` |
| Create many | `create` | `POST /api/employees` with an array of `EmployeeInsert` | `201`, `{"items": [Employee, ...], "hasMore": false}` |
| Patch one | `update` | `PATCH /api/employees/{id}` with an `EmployeeUpdate` object | `200`, the updated `Employee`; `204` when the entity does not allow `read`, the caller may not read it, or the update cannot be read back |
| Delete one | `delete` | `DELETE /api/employees/{id}` | `200`, the deleted `Employee`; `204` when the entity does not allow `read` or the caller may not read it |

- **Create one and create many share one route.** The payload parameter is typed
  `EmployeeInsert|EmployeeInsert[]`; `ballerina/http` binds a JSON object to the first type and
  an array to the second. ✅
- **Creates are atomic.** Create one and create many run the insert and the read-back in one
  transaction, so a batch with one failing record creates none. ✅ On H2 with
  `ballerinax/persist.sql` 1.7.4, a batch with a duplicate key in the middle saved the other
  records without a transaction, and saved none inside a Ballerina `transaction`.
- **Create many has no `Location` header**, because it creates several resources.
- **Create many takes at most `dataserviceConfig.maxPageSize` records.** A larger array is
  answered with `400` and `INVALID_INPUT`.
- **Patch is partial.** Fields left out of the body are not changed. A field set to `null` is
  set to `null` when the field is nullable.
- **Delete returns the deleted record**, as the persist client does, when the entity allows
  `read`. A client that does not need it can ignore the body.
- **Without `read`,** patch and delete answer `204 No Content` with no body. So do they, with
  `auth = true`, for a caller who holds no `read` scope of the entity; see [Auth](#auth).
- **An update that cannot be read back** is answered with `204` and no body, because it is
  saved. `dsHttp:toUpdateError` maps `persist:ReadBackError` to `204` and logs it.
- **An empty array creates nothing.** `POST` with `[]` is answered with `201` and
  `{"items": [], "hasMore": false}`, without calling the persist client.
- **An empty patch changes nothing.** `PATCH` with `{}` is answered as get one when the record
  would be returned, and with `204` without reading otherwise. Neither calls the persist client's
  update, which would have no columns to set.
- **Key fields cannot be patched.** `EmployeeUpdate` is a closed record without the key fields,
  so a body that sets one is answered with `400` by `ballerina/http`.
- **Get many without `sort`** returns records ordered by key, as #1503 defines.

#### Disabled operations

An operation whose action is not enabled is not generated, and `ballerina/http` answers a
request for it on its own:

| Situation | Response |
|---|---|
| A method that exists on no resource of the path, for example `PATCH` on a read-only entity | `405 Method Not Allowed` ✅ |
| A path that matches no resource, for example an entity that is not exposed, or a relation whose direction is `Internal` | `404 Not Found` |

### Keys

- **Single key:** one path segment, `/employees/{id}`, typed as the key field's type.
- **Composite key:** one segment per key field, in declaration order, for example
  `/assignments/{employeeId}/{projectCode}`. ✅ There is no common convention for composite keys
  (see [Alternatives](#alternatives)). Positional segments are the conventional REST form for a
  single key, extend that form without new syntax, and match the persist client's resource
  paths.
- **Key types:** persist allows only `int`, `string`, `float`, `decimal` and `boolean` key
  fields, and each binds as a path parameter. A segment that does not convert to the key's type
  is answered with `400` by `ballerina/http`. ✅ A `float` key of `NaN` or `Infinity` is answered
  with `400` and `INVALID_INPUT`, with the message #1503 gives.
- **Key text:** in `Location` and in error messages, a key value is written with Ballerina's
  `toString`, so `1.5` stays `1.5` and a `decimal` keeps its scale. In `Location`, each value
  is then percent-encoded as a path segment.
- **Key names:** a key field is a path parameter of the resources that take a key, so it cannot
  be named as one of their parameters or variables: `broken`, `converted`, `created`, `ctx`,
  `entries`, `entry`, `err`, `fields`, `filter`, `forbidden`, `hasMore`, `i`, `include`,
  `included`, `includedMore`, `includedRows`, `invalidFields`, `invalidKey`, `item`, `itemKey`,
  `itemPayload`, `items`, `key`, `keyValues`, `keys`, `next`, `offset`, `partial`, `partials`,
  `payload`, `query`, `readable`, `related`, `row`, `rows`, `size`, `sort`, `sources`, `stored`,
  `tooMany`, `value` and `values`. The persist tool reports such a key as an error, as #1503
  gives. ✅
- **Reserved names:** path segments starting with `$`, such as `$count`, are reserved for later
  query and metadata operations, and are not used for anything else.

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
| `time:Utc` | an ISO 8601 date-time in UTC, `2024-01-02T10:15:30Z`. In a request, any offset is accepted and converted to UTC |

A `decimal` read from the database keeps the column's scale, so `1.5` in a `DECIMAL(10,2)`
column is returned as `1.50`. ✅

Ballerina's own JSON form of these types does not suit a client: `time:Utc` is a tuple and
becomes an array such as `[1704189330, 0.5]`, the other `time:*` types become records, and
`byte[]` becomes an array of numbers.

#### Wire types

An entity gets wire types when it has a `time:*` or `byte[]` field, which the wire types hold as
`string`, or a field with a [field rule](#field-rules). Each wire type is generated only when an
operation that uses it is generated. The other entities use the persist types as they are.

| Persist type | Wire type |
|---|---|
| `Employee` | `EmployeePayload` |
| `EmployeeInsert` | `EmployeeInsertPayload` |
| `EmployeeUpdate` | `EmployeeUpdatePayload` |

```ballerina
public type EmployeePayload record {|
    readonly int id;
    string name;
    string? email;
    string hiredOn;
    Status status;
    int departmentId;
|};
```

The `<Entity>List` envelope and the status code records of such an entity hold the wire type.
The generated functions `transform<Entity>ToPayload`, `transformPayloadTo<Entity>Insert` and
`transformPayloadTo<Entity>Update` convert between the persist types and the wire types with
functions from `ballerina/dataservice`, so a fix to a format is released without regenerating
the service:

| Type | To JSON | From JSON |
|---|---|---|
| `byte[]` | `dataservice:bytesToString` | `dataservice:bytesFromString` |
| `time:Date` | `dataservice:dateToString` | `dataservice:dateFromString` |
| `time:TimeOfDay` | `dataservice:timeOfDayToString` | `dataservice:timeOfDayFromString` |
| `time:Civil` | `dataservice:civilToString` | `dataservice:civilFromString` |
| `time:Utc` | `dataservice:utcToString` | `dataservice:utcFromString` |

A request value that does not parse is answered with `400` and `INVALID_INPUT`; see
[Errors](#errors).

#### Field rules

The field rules of #1503 shape the wire types:

| Rule | `<Entity>Payload` | `<Entity>InsertPayload` | `<Entity>UpdatePayload` |
|---|---|---|---|
| `ReadOnly` | Holds the field | Holds the field as optional, and the service ignores its value | Holds the field as optional, and the service ignores its value |
| `Immutable` | Holds the field | Holds the field | Does not hold the field |
| `Internal` | Does not hold the field | Does not hold the field | Does not hold the field |

- **Rejected fields:** the wire types are closed records, so a request that sets a field its
  wire type does not hold, an `Internal` field or an `Immutable` field on patch, is answered by
  `ballerina/http` with `400` and `INVALID_INPUT`.
- **Values on create:** `transformPayloadTo<Entity>Insert` sets a `ReadOnly` or `Internal`
  field to the `value` of its annotation, or to `()`.
- **Other types:** an `Internal` field is also left out of `<Entity>Filter`, `<Entity>Partial`
  and `<Entity>RelatedPartial`, so it cannot be filtered, sorted or selected.
- **Relation fields:** a direction that is not offered, because its relation field or the
  foreign key is `Internal`, has no get related resource and no field in `<Entity>Partial`.

### Query parameters

The query options of #1503 are query parameters of get many and of get related on a to-many
relation; get one and get related on a to-one relation take only `fields`:

| Parameter | Type | Example |
|---|---|---|
| `filter` | a JSON object, bound to the generated `<Entity>Filter` record | `filter={"hiredOn":{"gte":"2024-01-01"},"status":{"anyOf":["ACTIVE"]}}` |
| `sort` | field names, repeated or comma-separated; `-` before a name sorts it descending | `sort=name&sort=-hiredOn` or `sort=name,-hiredOn` |
| `size` | an integer | `size=20` |
| `offset` | an integer, the number of records to skip | `offset=40` |
| `fields` | field names, repeated or comma-separated | `fields=name,email` |

Repeated and comma-separated forms bind to the same `string[]`. ✅ Values in the URL are
percent-encoded as usual. A query parameter that the operation does not take, such as `limit`,
is ignored, and a repeated `filter`, `size` or `offset` uses its first value, as
`ballerina/http` binds query parameters. ✅

#### Filter

`<Entity>Filter` has one optional field per filterable entity field. Each is a record of the
operators that the field's type allows, and holds values of the field's wire type:

```ballerina
public type EmployeeFilter record {|
    record {| int eq?; int ne?; int lt?; int lte?; int gt?; int gte?; int[] anyOf?; |} id?;
    record {| string eq?; string ne?; string lt?; string lte?; string gt?; string gte?;
        string[] anyOf?; string contains?; string startsWith?; |} name?;
    record {| string eq?; string ne?; string lt?; string lte?; string gt?; string gte?;
        string[] anyOf?; string contains?; string startsWith?; boolean isNull?; |} email?;
    record {| string eq?; string ne?; string lt?; string lte?; string gt?; string gte?;
        string[] anyOf?; |} hiredOn?;
    record {| Status eq?; Status ne?; Status[] anyOf?; |} status?;
    record {| int eq?; int ne?; int lt?; int lte?; int gt?; int gte?; int[] anyOf?; |}
        departmentId?;
|};
```

- **Several operators on one field** all apply, so `{"id":{"gte":2,"lt":10}}` is a range.
- **Strict binding:** the records are closed, so `ballerina/http` answers an unknown field, an
  operator the type does not allow, a value of the wrong type or an unknown enum value with
  `400` before the resource runs. ✅
- **Dates and times** are strings in the filter, as in the body, and are parsed by
  `ballerina/dataservice`; a value that does not parse is answered with `INVALID_INPUT`.
- **Reserved keys:** keys starting with `$`, such as `$and`, `$or` and `$not`, are reserved for
  joining conditions in a later proposal, and `<Entity>Filter` holds no field with such a name.
  Adding them leaves every existing filter valid. ✅ `ballerina/http` binds a recursive filter
  record with `$or` keys from the query parameter.

#### Sort, page and fields

`sort` and `fields` are validated by `ballerina/dataservice` against the entity description, so
an unknown or unusable field is answered with `INVALID_INPUT` and the message #1503 gives.

```
GET /api/employees?sort=-hiredOn&size=2
→ 200 {"items": [{"id": 7, ...}, {"id": 3, ...}], "hasMore": true}

GET /api/employees?sort=-hiredOn&size=2&offset=2
→ 200 {"items": [{"id": 5, ...}], "hasMore": false}

GET /api/employees/7?fields=name
→ 200 {"id": 7, "name": "Ann"}
```

With `fields`, a record is returned as `<Entity>Partial` and a page as `<Entity>PartialList`.
`<Entity>Partial` has the fields of the entity's wire type and one field per relation. The key
fields are required and the others optional. A to-one relation is a nullable
`<Target>RelatedPartial`, and a to-many relation a `<Target>RelatedPartialList`:

```ballerina
public type EmployeePartial record {|
    int id;
    string name?;
    string? email?;
    string hiredOn?;
    Status status?;
    int departmentId?;
    DepartmentRelatedPartial? department?;
|};

public type DepartmentPartial record {|
    int id;
    string name?;
    EmployeeRelatedPartialList employees?;
|};

public type DepartmentRelatedPartial record {|
    int id;
    string name?;
|};

public type EmployeeRelatedPartialList record {
    EmployeeRelatedPartial[] items;
    boolean hasMore;
};
```

`fields=` with no value is answered with `400` and `INVALID_INPUT`. An empty entry in a list
is dropped, so `fields=name,` is `fields=name`, and `sort=` sorts by key. `sort=-` names an
empty field and is answered with `400` and `INVALID_INPUT`. ✅

### Relations

Each relation of an exposed entity gets a resource under the entity's key, and can be named in
`fields`, when both the entity and the related entity allow `read` and neither the relation
field nor the foreign key is `Internal`, as #1503 defines:

```
GET /api/employees/4/department
→ 200 {"id": 2, "name": "Research"}

GET /api/departments/2/employees?sort=name&size=2
→ 200 {"items": [{"id": 4, ...}, {"id": 9, ...}], "hasMore": true}

GET /api/employees?fields=name,department.name
→ 200 {"items": [{"id": 4, "name": "Ann", "department": {"id": 2, "name": "Research"}}, ...], "hasMore": false}

GET /api/departments/2?fields=name,employees.name
→ 200 {"id": 2, "name": "Research", "employees": {"items": [{"id": 4, "name": "Ann"}, ...], "hasMore": true}}
```

- **Segment:** the relation field's name in the model, unchanged, follows the entity's full key:
  `/assignments/4/P1/employee` for a composite key. Every entity has a fixed number of key
  segments, so a relation resource never matches the same path as get one.
- **Dotted fields:** in `fields`, a relation's own fields are written `<relation>.<field>`, as
  Directus does, on to-one and to-many relations. A relation named alone includes the whole
  related record.
- **To-many in `fields`:** an included to-many relation is a `{"items": [...], "hasMore": ...}`
  object. When `hasMore` is `true`, the caller pages through the rest with get related.
- **Empty to-one in `fields`:** a to-one relation with no related record is included as
  `"department": null`.
- **Not found:** a request is answered with `404` and `NOT_FOUND` when the record does not
  exist, or when a to-one relation has no related record, with the messages #1503 gives.
- **Scopes before existence:** with `auth = true`, a relation's scope check runs before the
  record is read, so a caller without a `read` scope of the related entity gets `403` whether
  or not the record exists, and does not learn which records exist. ✅

```ballerina
resource function get employees/[int id]/department(http:RequestContext ctx, string[]? fields = ())
        returns Department|DepartmentRelatedPartial|dsHttp:NotFound|dsHttp:InvalidInput
            |dsHttp:Forbidden|dsHttp:InternalError { ... }

resource function get departments/[int id]/employees(http:RequestContext ctx,
        EmployeeFilter? filter = (), string[]? sort = (), int? size = (), int? offset = (),
        string[]? fields = ())
        returns EmployeeList|EmployeeRelatedPartialList|dsHttp:NotFound|dsHttp:InvalidInput
            |dsHttp:Forbidden|dsHttp:InternalError { ... }
```

With `fields`, get related returns `<Target>RelatedPartial` or `<Target>RelatedPartialList`,
because `fields` on get related names only the related entity's own fields.

### Errors

Each error category in #1503 maps to a status code. The body is the `DataserviceError` record
from `ballerina/dataservice`, with the code and message #1503 defines for the category.

| Category | Status | `code` | Raised from |
|---|---|---|---|
| Not found | `404` | `NOT_FOUND` | `persist:NotFoundError` ✅ |
| Conflict | `409` | `CONFLICT` | `persist:AlreadyExistsError` ✅ |
| Constraint violation | `409` | `CONSTRAINT_VIOLATION` | `persist:ConstraintViolationError` |
| Invalid input | `400` | `INVALID_INPUT` | a date, time or `byte[]` value that does not parse; a constraint broken on a field of a wire type; an unusable `sort` or `fields` name, a field named twice in `sort`, an empty `fields`, `size` below 1, `offset` below 0 or too large for the `size`; a create above `dataserviceConfig.maxPageSize` records; a `float` key that is not finite |
| Invalid input | `400` | `INVALID_INPUT` | `ballerina/http` payload, path or query binding ✅, including a body whose `Content-Type` is XML, text, form or binary, which `ballerina/http` binds only to `xml`, `string`, `map<string>` or `byte[]` ✅; a constraint broken on an entity without wire types |
| Invalid input | `405`, or another `4xx` status of `ballerina/http` | `INVALID_INPUT` | a method that the path has no resource for ✅ |
| Not found | `404` | `NOT_FOUND` | a path that matches no resource ✅ |
| Internal | `500` | `INTERNAL` | any other error |
| Unauthenticated | `401` | `UNAUTHENTICATED` | `DataserviceAuthInterceptor`, before the request is dispatched ✅ |
| Forbidden | `403` | `FORBIDDEN` | `DataserviceAuthInterceptor`, when the caller holds no scope of the operation, before the request is dispatched ✅ |
| Forbidden | `403` | `FORBIDDEN` | get related or a relation in `fields`, when `auth` is `true` and the caller holds no `read` scope of the related entity |

The status code records are not specific to an entity, so they are defined in
`ballerina/dataservice.http`, which keeps `ballerina/dataservice` free of `ballerina/http`:

```ballerina
public type NotFound record {|
    *http:NotFound;
    dataservice:DataserviceError body;
|};
```

`InvalidInput`, `Conflict`, `ConstraintViolation`, `Unauthorized`, `Forbidden` and
`InternalError` follow the same form.

An error whose category is not among the error records of its resource is answered with `500`
and `INTERNAL`, and logged.

The message for a value that does not parse is
`The field '<field>' of the entity '<Entity>' is not <format>.`, where `<format>` is
`an ISO 8601 date`, `an ISO 8601 time`, `an ISO 8601 date-time` or `a base64 string`.

Other errors are raised by `ballerina/http` before the resource runs. The service is an
`http:InterceptableService` whose `DataserviceErrorInterceptor`, a `ResponseErrorInterceptor`,
answers each of them with the same status and a `DataserviceError` body: the code in the
table above and `ballerina/http`'s message. It sets the body on the response in place and
returns the next service, so its return type adds no response to the OpenAPI definition. For a
request body, the message names every missing or mistyped field. ✅ For `filter`, it does not;
see [Risks and assumptions](#risks-and-assumptions). ✅ On Ballerina 2201.14.0, the interceptor
received the `400` of payload, path and query binding and the `404` and `405` of dispatching,
each with its status code on the response, and the response was sent as `application/json`.

The OpenAPI definition lists what each resource declares, and what the interceptors' return
types declare; see [Generated resources](#generated-resources). ✅ On Ballerina 2201.14.0, an
`http:InterceptableService` with a `ResponseErrorInterceptor` from its own package exported a
resource's `400` with only its declared body, while a plain service also listed
`ballerina/http`'s default `ErrorPayload`. An interceptor that returned `http:Response` added a
`default` response to every operation, and one that returned `error` added a `500` with
`ErrorPayload`; one that returned `http:NextService?` added none.

Example responses: ✅

```
POST /api/employees  {"id":1, ...}            → 201  Location: /api/employees/1
POST /api/employees  {"id":1, ...} (again)    → 409  {"code":"CONFLICT", "message":"A record that conflicts with an existing record of the entity 'Employee' already exists."}
GET  /api/employees/99                        → 404  {"code":"NOT_FOUND", "message":"A record with the key '99' does not exist for the entity 'Employee'."}
GET  /api/employees/abc                       → 400  {"code":"INVALID_INPUT", "message":"error in casting path parameter : 'id'"}
PUT  /api/employees/2                         → 405  {"code":"INVALID_INPUT", "message":"Method not allowed"}
```

### Auth

With `options.dataservice.auth = false`, the default, the service has no auth and
`dataserviceConfig` is a `dsHttp:Config`, whose `serviceConfig` has no `auth` field.

With `auth = true`, a request interceptor checks the credential and the scopes of each request
with `dsHttp:Authenticator`, before `ballerina/http` dispatches the request and binds its
parameters:

```ballerina
final readonly & map<map<string[]>> dataserviceScopes = {
    "employees": {"GET": ["hr:read"], "POST": ["employees:create"], "PATCH": ["employees:update"]},
    "departments": {"GET": ["hr:read", "org:read"]}
};

service http:InterceptableService /api on dataserviceListener {

    private final dsHttp:Authenticator authenticator;
    ...

    function init() returns error? {
        ...
        self.authenticator = check new (dataserviceConfig.serviceConfig.auth, dataserviceScopes,
                dataserviceConfig.serviceConfig.cors);
    }

    public function createInterceptors()
            returns [DataserviceAuthInterceptor, DataserviceErrorInterceptor] =>
        [new (self.authenticator), new];
    ...
}

isolated service class DataserviceAuthInterceptor {
    *http:RequestInterceptor;

    private final dsHttp:Authenticator authenticator;

    isolated function init(dsHttp:Authenticator authenticator) {
        self.authenticator = authenticator;
    }

    isolated resource function 'default [string... path](http:RequestContext ctx,
            http:Request request)
            returns http:NextService|dsHttp:Unauthorized|dsHttp:Forbidden|error? =>
        self.authenticator.authorize(ctx, request, path);
}
```

- **Why not declarative auth:** `ballerina/http` enforces `@http:ServiceConfig {auth}` and
  `@http:ResourceConfig {auth}` with a call that the compiler inserts as the first statement of
  each resource, so a request is dispatched and its parameters are bound before auth runs
  ([ballerina-library#9632](https://github.com/ballerina-platform/ballerina-library/issues/9632)).
  ✅ On Ballerina 2201.14.0, with declarative auth, a request without credentials was answered
  with `400` for a mistyped query parameter or a body missing a field, naming the payload type
  and the field, `404` for an unknown path and `405` for an unknown method. A request
  interceptor runs before dispatching and binding, so each of them is answered with `401`. ✅
- **Scopes:** `dataserviceScopes` maps each collection to the scopes of each HTTP method: `GET`
  for get many, get one and get related, which use the `read` scopes, `POST` for create,
  `PATCH` for patch and `DELETE` for delete. An action with an empty scope list has no entry.
  An operation without scopes, and a path that is not a collection, such as the OpenAPI
  definition, take the `scopes` of the provider that authenticated the caller, as
  `ballerina/http` applies a service's scopes to a resource without scopes of its own. Without
  those, they need only a credential. ✅
- **Checking:** `authorize` tries the listener auth handler of each provider that takes the
  `Authorization` header's scheme, in the order of the list, as `ballerina/http` does:
  `http:ListenerFileUserStoreBasicAuthHandler` and `http:ListenerLdapUserStoreBasicAuthHandler`
  for `Basic`, and `http:ListenerJwtAuthHandler` and `http:ListenerOAuth2Handler` for `Bearer`,
  so a user's password is never sent to an OAuth2 introspection endpoint. ✅ The first that
  authenticates the credential decides, and its
  `authorize` checks the scopes, so a caller holds the same scopes as with declarative auth. For
  OAuth2, the scopes are the space-separated values of the introspection response's `scopeKey`
  claim, which is what `http:ListenerOAuth2Handler` checks. `authorize` keeps the caller in the
  request context for the checks below, and passes an `OPTIONS` request, such as a CORS
  preflight, without a credential. ✅
- **Required providers:** with `auth = true`, `dataserviceConfig` is a `dsHttp:AuthConfig`,
  whose `serviceConfig.auth` is required without a default, so the program does not start when
  `Config.toml` does not set it. ✅ On Ballerina 2201.14.0, it stopped with `value not provided
  for required configurable variable 'dataserviceConfig'`. An empty list also stops it at
  startup, through the module-level `check` on creating `dsHttp:Authenticator`, with the
  message `The configurable value 'dataserviceConfig.serviceConfig.auth' must hold at least one authentication provider.` ✅
- **Responses:** `authorize` answers a missing or invalid credential with `401` and
  `UNAUTHENTICATED`, and a caller without a scope of the operation with `403` and `FORBIDDEN`,
  with the messages #1503 gives. ✅
- **Headers:** the `401` carries one `WWW-Authenticate` challenge per kind of configured
  provider: `Basic realm="dataservice"` for a user store, and `Bearer realm="dataservice"` for
  JWT or OAuth2. `ballerina/http` adds CORS headers only to the responses of a resource, so
  `authorize` adds them to its `401` and `403` from `dataserviceConfig.serviceConfig.cors`, as
  `ballerina/http` does for a simple cross-origin request: `Access-Control-Allow-Origin` for an
  allowed origin, and `Access-Control-Allow-Credentials` and `Access-Control-Expose-Headers`
  when set. ✅ The `404` and `405` of dispatching carry no CORS headers, because no resource
  matches them.
- **Get related** and a relation in `fields` require the entity's `read` scopes, as `GET` on
  the entity's collection. With `auth = true`, a resource that reads a relation takes the
  `http:RequestContext` and calls `dsHttp:checkRelationScopes` before reading, as #1503
  defines. It checks the caller that `authorize` kept
  against the related entity's `read` scopes and returns `Forbidden`, with `FORBIDDEN`, when
  none matches. A caller is checked once per request, so no credential is checked twice:

  ```ballerina
  dsHttp:Forbidden? forbidden = dsHttp:checkRelationScopes(ctx, "Employee", "department",
          "Department", ["departments:read"]);
  if forbidden is dsHttp:Forbidden {
      return forbidden;
  }
  ```

- **Patch and delete results:** with `auth = true` and `read` allowed, patch and delete call
  `dsHttp:hasScope` with the entity's `read` scopes, as #1503 defines, which returns `true` when
  the caller holds one of them, or, for an empty list, the deciding provider's `scopes`. Without one,
  they answer `204` and, for an empty patch, do not read:

  ```ballerina
  if !dsHttp:hasScope(ctx, ["employees:read"]) {
      return http:NO_CONTENT;
  }
  ```

For example, to validate JWTs, set in `Config.toml`:

```toml
[[dataserviceConfig.serviceConfig.auth]]
[dataserviceConfig.serviceConfig.auth.jwtValidatorConfig]
issuer = "https://idp.example.com"
audience = "hr-api"
[dataserviceConfig.serviceConfig.auth.jwtValidatorConfig.signatureConfig.jwksConfig]
url = "https://idp.example.com/jwks"
```

### Constraints

The constraints of the model, kept in the generated types, are checked by `ballerina/http`'s
payload validation, which answers a value that breaks one with `400` and `INVALID_INPUT`.
Wire types copy the model's constraint annotations. A wire type holds dates, times and `byte[]`
values as strings, so the service checks the constraints on those fields on the converted
record, and answers a failure with `400`, `INVALID_INPUT` and the message #1503 gives,
`The field '<field>' of the entity '<Entity>' breaks its '<constraint>' constraint.`

### OpenAPI definition

Unless `options.dataservice.introspection` is `false`, the service carries
`@openapi:ServiceInfo {embed: true, title: "<package>"}`. The compiler then embeds an OpenAPI
definition built from the service and its doc comments, and `ballerina/http` serves it with
Swagger UI: ✅

| Request | Response |
|---|---|
| `OPTIONS /api` | A `Link` header, `</api/openapi-doc-dygixywsw>;rel="service-desc", </api/swagger-ui-dygixywsw>;rel="swagger-ui"` |
| `GET /api/openapi-doc-dygixywsw` | The OpenAPI definition, whose `info.title` is the package name in words, such as `Dataservice H2` for `dataservice_h2`. Operation summaries come from the resources' doc comments, and schema and property descriptions from the types' doc comments |
| `GET /api/swagger-ui-dygixywsw` | Swagger UI for the definition |

- **Paths:** the two paths are fixed by `ballerina/http` and cannot be changed. A client finds
  the definition through the `Link` header, whose `service-desc` relation is the standard one
  for a service description (RFC 8631).
- **Swagger UI** loads its scripts and styles from `unpkg.com`, so it needs internet access in
  the browser. The definition itself does not.
- **Auth:** with `auth = true`, the definition and Swagger UI are behind
  `DataserviceAuthInterceptor`, so a request without a valid credential is answered with `401`,
  and an authenticated caller can read them when it holds one of the deciding provider's
  `scopes`, or always when the provider sets none; see [Auth](#auth). The `OPTIONS` `Link`
  header stays public. ✅ The
  definition lists `401` and `403` on every operation, from the interceptor's return type. ✅
- **Open and closed schemas:** an entity's types and `DataserviceError` are closed, so their
  schemas carry `additionalProperties: false`. The list envelopes are open, as #1503 defines,
  so theirs do not. ✅ On Ballerina 2201.14.0, an open record in a resource's return type was
  exported without `additionalProperties: false`.
- **Swagger UI with a token:** a browser sends no bearer token when Swagger UI loads the
  definition, so with JWT or OAuth2 the page cannot load it unless the browser adds the token.
  The definition stays available to clients and tools that send one.

### Configuration

| Setting | Where | Default |
|---|---|---|
| Base path | `options.dataservice.basePath` | `/api` |
| Auth | `options.dataservice.auth` | `false` |
| Publishing the OpenAPI definition | `options.dataservice.introspection` | `true` |
| Port | `port` of `[dataserviceConfig]` in `Config.toml` | `9090` |
| Page size when `size` is not given | `pageSize` of `[dataserviceConfig]` | `100` |
| Largest page size | `maxPageSize` of `[dataserviceConfig]` | `1000` |
| Other listener settings, such as TLS and timeouts | `listenerConfig` of `[dataserviceConfig]` | `ballerina/http`'s defaults |
| CORS | `cors` of `[dataserviceConfig.serviceConfig]` | no cross-origin requests |
| Authentication providers | `auth` of `[dataserviceConfig.serviceConfig]` | none: required when `auth` is `true`, and not declared otherwise |

`ballerina/dataservice.http` defines the configuration types. Each includes
`dataservice:Config` from #1503 and adds HTTP's fields: the listener settings in
`listenerConfig`, and the settings of `@http:ServiceConfig` that vary by environment in
`serviceConfig`. The types with auth differ only in a required `auth`:

```ballerina
public type ServiceConfig record {|
    http:CorsConfig cors = {};
|};

public type AuthServiceConfig record {|
    *ServiceConfig;
    http:ListenerAuthConfig[] auth;
|};

public type Config record {|
    *dataservice:Config;
    http:ListenerConfiguration listenerConfig = {};
    ServiceConfig serviceConfig = {};
|};

public type AuthConfig record {|
    *dataservice:Config;
    http:ListenerConfiguration listenerConfig = {};
    AuthServiceConfig serviceConfig;
|};
```

`dataservice_config.bal` declares only the configurable value:

```ballerina
configurable dsHttp:Config dataserviceConfig = {};
// With options.dataservice.auth = true:
// configurable dsHttp:AuthConfig dataserviceConfig = ?;
```

The service checks the values in its `init`. With `auth = true`, `dataservice.bal` also declares
`dataserviceScopes`, and the service creates its authenticator; see [Auth](#auth).

- **Two types for auth:** `AuthConfig` does not include `Config`, because a closed
  `AuthServiceConfig` is not a subtype of `ServiceConfig`, so it cannot override that field.
  ✅ On Ballerina 2201.14.0, with `Config`, an `auth` entry in `Config.toml` stopped the program
  with `undefined field 'auth' provided for closed record`, and with `AuthConfig`, a missing
  one stopped it with the message above.
- **Field names:** `listenerConfig` and `serviceConfig`, not `listener` and `service`, because
  those are keywords.
- **Not configurable:** other settings of `@http:ServiceConfig`, such as `validation` and
  `laxDataBinding`, change what the API accepts, so they are not in `ServiceConfig`.
- **Startup:** the program stops, with the messages #1503 gives, when a page size is out of
  range or a field is unknown.

For example, to allow a browser application on another origin:

```toml
[dataserviceConfig.serviceConfig.cors]
allowOrigins = ["https://app.example.com"]
allowMethods = ["GET", "POST", "PATCH", "DELETE"]
```

For example, to serve over TLS:

```toml
[dataserviceConfig.listenerConfig.secureSocket.key]
certFile = "/path/to/public.crt"
keyFile = "/path/to/private.key"
```

### Generated code

#### Generated resources

```ballerina
service http:InterceptableService /api on dataserviceListener {

    resource function get employees(http:RequestContext ctx, EmployeeFilter? filter = (),
            string[]? sort = (), int? size = (), int? offset = (), string[]? fields = ())
            returns EmployeeList|EmployeePartialList|dsHttp:InvalidInput|dsHttp:Forbidden
                |dsHttp:InternalError {
        // Validates the options and builds the query with ballerina/dataservice, reads one page
        // through the persist client, and returns it with hasMore.
    }

    resource function get employees/[int id](http:RequestContext ctx, string[]? fields = ())
            returns Employee|EmployeePartial|dsHttp:NotFound|dsHttp:InvalidInput
                |dsHttp:Forbidden|dsHttp:InternalError { ... }

    resource function post employees(EmployeeInsert|EmployeeInsert[] payload)
            returns EmployeeCreated|EmployeeListCreated|dsHttp:InvalidInput|dsHttp:Conflict
                |dsHttp:ConstraintViolation|dsHttp:InternalError {
        // In one transaction, posts the records as an array and reads back the created records
        // with one query on their keys.
    }

    resource function patch employees/[int id](http:RequestContext ctx, EmployeeUpdate payload)
            returns Employee|http:NoContent|dsHttp:NotFound|dsHttp:InvalidInput
                |dsHttp:Conflict|dsHttp:ConstraintViolation|dsHttp:InternalError { ... }

    resource function delete employees/[int id](http:RequestContext ctx)
            returns Employee|http:NoContent|dsHttp:NotFound|dsHttp:InvalidInput
                |dsHttp:ConstraintViolation|dsHttp:InternalError { ... }
}
```

- **Wire types:** the signatures show the persist types. An entity with a date, time or
  `byte[]` field, such as `Employee` with `hiredOn`, uses its wire types in their place, such
  as `EmployeePayload`; see [Wire types](#wire-types).
- **Without `read`:** patch and delete return `http:NoContent` in place of the record.
- **Patch and delete with `read`:** with `auth = true`, patch and delete take the
  `http:RequestContext` and return `Employee|http:NoContent`. Without auth they take no
  request context, delete returns `Employee` alone,
  and patch returns `Employee|http:NoContent` for an update that cannot be read back.
- **Return types:** each resource lists the error records it can return, so an OpenAPI
  definition generated from the service shows exactly its status codes:

  | Operation | Error records |
  |---|---|
  | Get many | `InvalidInput`, `InternalError` |
  | Get one, get related | `NotFound`, `InvalidInput`, `InternalError` |
  | Create | `InvalidInput`, `Conflict`, `ConstraintViolation`, `InternalError` |
  | Patch | `NotFound`, `InvalidInput`, `Conflict`, `ConstraintViolation`, `InternalError` |
  | Delete | `NotFound`, `InvalidInput`, `ConstraintViolation`, `InternalError` |

- **Auth errors:** with `auth = true`, a resource that checks a relation also declares
  `Forbidden`, which it returns. The `401` and `403` of the operation's scopes come from
  `DataserviceAuthInterceptor`, whose return type the OpenAPI definition lists on every
  operation, so the resources do not declare them.
- **Request context:** with `auth = true`, a resource that reads a relation, and patch and
  delete, take the `http:RequestContext`, which is not a parameter of the OpenAPI definition.
  The signatures above are those of a service with `auth = true`.
- **Not listed:** a path that matches no resource (`404`) and a method that the path has no
  resource for (`405`) belong to no resource, so the definition does not list them. They are
  still answered with the `DataserviceError` body.
- **Library calls:** the generated service imports `ballerina/dataservice.http` as `dsHttp`
  and passes the entity name and key values to its functions, which build the error response,
  log the error detail, build the `Location` header and check a relation's scopes.
- **Location:** each key value is percent-encoded as a path segment, so a key such as `P 1/a`
  gives `/api/assignments/4/P%201%2Fa`. ✅ With the base path `/`, `Location` starts at the
  entity, as in `/employees/1`.

The status code records of an entity include the `ballerina/http` status code records:

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

#### Generated source

- **Header:** each generated file starts with the header of persist's generated files, stating
  that the file is generated and must not be edited. A service written by
  `bal persist generate` has the same header without the instruction not to edit it.
- **Order:** `dataservice.bal` holds the client and the listener, then one service with the
  resources of each exposed entity in model order. Within an entity, the order is get many, get
  one, get related (in model order of the relation fields), create, patch and delete.
  `dataservice_types.bal` holds, per entity in model order, the wire types, the `<Entity>List`
  envelope, the filter and partial types, the entity description that
  `ballerina/dataservice` builds queries from, the status code records and then the functions
  that convert to and from the wire types.
- **Doc comments:** every resource and every generated public type has a short doc comment: a
  one-line summary and one-line `+ param`, `+ return` and `+ field` lines. The summary of a
  resource comes from its operation, and the entity's doc comment from the model follows it:

  | Operation | Summary |
  |---|---|
  | Get many | `Gets a page of employees.` |
  | Get one | `Gets an employee by its key.` |
  | Get related | `Gets the department of an employee.` |
  | Create | `Creates one or more employees.` |
  | Patch | `Updates an employee by its key.` |
  | Delete | `Deletes an employee by its key.` |

  A field's `+ field` line is its doc comment in the model.

## Alternatives

- **A separate route for create many**, such as `POST /employees/$batch`. Not needed: the
  union payload type lets one route take both, and `$` names stay reserved for query and
  metadata operations.
- **`PUT` for update.** `PUT` means full replace in HTTP, and the persist client's update is
  partial, so the method is `PATCH`.
- **`204 No Content` for every delete.** When the entity allows `read`, returning the deleted
  record matches the persist client and the other protocols, and costs nothing.
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
  combination, and a custom base path; the paths of a multi-word entity, `/api/projectAssignments`,
  and of an irregular plural, `/api/people`.
- Behaviour, against H2 and every other SQL datastore available to the test run: every row of
  the operations and errors tables, including `405` for a disabled method and `400` for a
  mistyped key; `204` for patch, delete and `PATCH {}` on an entity without `read`, and with
  `auth = true` for a caller without a `read` scope; `201` with `{"items": [], "hasMore": false}`
  for `POST []`; a create many with a duplicate key among its records, which creates none; a
  create above `dataserviceConfig.maxPageSize` records.
- Keys: a `Location` round trip for a `float` key, and `400` for a `NaN` or `Infinity` key.
- Startup: an out-of-range page size, an unknown field of `[dataserviceConfig]`, and with
  `auth = true`, a missing or empty `dataserviceConfig.serviceConfig.auth`, each stopping the
  program with its message.
- CORS: a preflight and a cross-origin request with and without `cors` set.
- The OpenAPI definition: the `Link` header, the definition with the generated summaries and
  the model's descriptions, Swagger UI, and none of them with `introspection = false`; every
  error response with the `DataserviceError` schema and no `ErrorPayload`, and with
  `auth = true` the `401` and `403` of each operation.
- Field rules: per rule, the wire types generated, a `ReadOnly` field ignored on create and
  patch, an `Immutable` field rejected on patch, an `Internal` field rejected and never returned,
  and `value` set on create; a direction hidden by `Internal` answering `404` and absent from
  `<Entity>Partial` and the OpenAPI definition.
- A round trip of every `time:*` type and `byte[]` through create and get one, and `400` with
  `INVALID_INPUT` for a value in the wrong format.
- Query parameters, against H2 and every other SQL datastore available to the test run: every
  operator on every type it allows, `ne` on a nullable field, an empty `anyOf`, `contains` and
  `startsWith` with `%`, `_` and `[`, multi-field sort with nulls, a field named twice in
  `sort`, paging through every page by `offset` until `hasMore` is `false`, `size` above the
  maximum, `offset` below 0 and too large for the `size`, and `fields`, including a repeated
  field, an empty `fields=`, and a relation named with one of its fields.
- Relations, against H2 and every other SQL datastore available to the test run: get related on
  to-one and to-many relations, single and composite keys, a missing record and an empty to-one
  relation; one and several relations in `fields`, to-one and to-many, with dotted fields and a
  to-many list longer than the page size; an empty to-one relation and one pointing at a
  missing record, as `null`; a relation of a related entity in `fields`, rejected; the number
  of queries per request, as #1503 gives it.
- Auth: `auth = false`, with no auth code generated; a credential without a scope (`403`), with
  a default scope, with a scope from `scopes`, and with an empty scope list; no credential
  (`401`); get related and a relation in `fields` allowed for a caller holding a `read` scope of
  the related entity and answered with `403` and `FORBIDDEN` otherwise, and with an empty
  `read` list, checked against the provider's `scopes`, with JWT and with basic auth from a file user store; the OpenAPI
  definition published by default, answered with `401` without credentials when `auth` is
  `true`, and not published with `introspection = false`.
- Constraints: a create and a patch that break a constraint, on an entity with and without wire
  types.
- Error bodies: a `DataserviceError` body with its code for each error that `ballerina/http`
  raises: payload, path and query binding, `401`, `403`, a path with no resource, and `405`.

## Risks and assumptions

- **Binding messages come from `ballerina/http`.** The message of an error raised before the
  resource runs is `ballerina/http`'s. For `filter`, it says only
  `error in casting query param : 'filter'`, without naming the field or operator. ✅
- **Binding messages show Ballerina names.** The message of a binding error names the
  Ballerina type and holds the conversion error's text, such as
  `{ballerina}ConversionError` and module-qualified type names. It reaches only authenticated
  callers when `auth` is `true`. ✅
- **Auth outside `ballerina/http`.** The service checks auth in its own request interceptor
  until `ballerina/http` checks declarative auth before dispatching and binding
  ([ballerina-library#9632](https://github.com/ballerina-platform/ballerina-library/issues/9632)).
  `dsHttp:Authenticator` uses `ballerina/http`'s listener auth handlers, so a provider is
  configured and a credential is checked as with declarative auth.
- **Interceptors in the service's package.** The interceptor classes are generated rather than
  shared until the OpenAPI definition maps an interceptor class from another package
  ([ballerina-library#9633](https://github.com/ballerina-platform/ballerina-library/issues/9633)).
- **Lost updates.** As in #1503, there is no `ETag` or `If-Match`, so concurrent `PATCH`
  requests on one record can overwrite each other.

## Dependencies

- [Data service generation for bal persist](https://github.com/ballerina-platform/ballerina-spec/issues/1503)
- `ballerina/http`
- `ballerina/openapi`, for `@openapi:ServiceInfo`
- `ballerina/dataservice`
- `ballerina/dataservice.http`: a new library, released separately from `ballerina/dataservice`
