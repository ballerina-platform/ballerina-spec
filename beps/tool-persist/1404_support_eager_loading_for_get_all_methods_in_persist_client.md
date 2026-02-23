# Support Eager Loading for Get All Methods in Persist Client

- Authors - @TharmiganK
- Reviewed by - @daneshk
- Created date - 2025/11/25
- Updated date - 2025/11/26
- Issue - [#1404](https://github.com/ballerina-platform/ballerina-spec/issues/1404)
- State - Submitted

## Summary

Introduce a command-line option `--eager-loading` to generate persist clients with get-all methods that return arrays instead of streams, enabling simpler client APIs for use cases where eager data loading is preferred.

## Motivation

The current persist client implementation returns streams for get-all operations, which is memory-efficient for large datasets. However, for simple use cases with smaller datasets, developers must manually convert streams to arrays using Ballerina query expressions:

```ballerina
stream<PurchaseTargetType, error?> purchasesStream = check persistClient->/purchases;
PurchaseTargetType[] purchases = check from PurchaseTargetType purchase in purchasesStream select purchase;
```

This additional conversion step adds boilerplate code for common scenarios where users need data as arrays for immediate processing. Providing an option to generate clients that directly return arrays simplifies the developer experience for such use cases.

## Goals

- Add `--eager-loading` flag to `bal persist generate` command
- Add `--eager-loading` flag to `bal persist add` command to integrate with build-time generation
- Generate get-all methods with return type `targetType[]|persist:Error` when eager loading is enabled
- Validate that eager loading is only used with SQL-based datastores
- Maintain backward compatibility with existing stream-based clients (default behavior)

## Non-Goals

- Changing the default behavior of get-all methods (streams remain the default)
- Supporting eager loading for NoSQL datastores (Redis, Google Sheets, in-memory)
- Performance optimization for large dataset scenarios

## Design

### Command-Line Interface

#### Generate Command

```bash
bal persist generate --datastore mysql --module db --eager-loading
```

#### Add Command

```bash
bal persist add --datastore mysql --module db --eager-loading
```

### Configuration Storage

When using `bal persist add`, the option is persisted in `Ballerina.toml`:

```toml
[[tool.persist]]
id = "generate-db-client"
targetModule = "db"
options.datastore = "mysql"
options.eagerLoading = true
filePath = "persist/model.bal"
```

### Generated Code Changes

**Without eager loading (default):**

```ballerina
isolated resource function get purchases(PurchaseTargetType targetType = <>, 
    sql:ParameterizedQuery whereClause = ``, 
    sql:ParameterizedQuery orderByClause = ``, 
    sql:ParameterizedQuery limitClause = ``, 
    sql:ParameterizedQuery groupByClause = ``) 
    returns stream<targetType, persist:Error?> = @java:Method {
        'class: "io.ballerina.stdlib.persist.sql.datastore.MySQLProcessor",
        name: "query"
    } external;
```

**With eager loading:**

```ballerina
isolated resource function get purchases(PurchaseTargetType targetType = <>, 
    sql:ParameterizedQuery whereClause = ``, 
    sql:ParameterizedQuery orderByClause = ``, 
    sql:ParameterizedQuery limitClause = ``, 
    sql:ParameterizedQuery groupByClause = ``) 
    returns targetType[]|persist:Error = @java:Method {
        'class: "io.ballerina.stdlib.persist.sql.datastore.MySQLProcessor",
        name: "queryAsList"
    } external;
```

### Supported Datastores

- MySQL
- Microsoft SQL Server
- PostgreSQL
- H2 (test-only datastore)

## Alternatives

### Alternative 1: Helper Method in Generated Client

Generate a helper method that converts streams to arrays, keeping the resource function unchanged.

**Rejected**: Adds unnecessary complexity and doesn't simplify the user experience significantly.

### Alternative 2: Separate Client Class

Generate two separate client classes (streaming and eager) for each entity.

**Rejected**: Increases code generation complexity and maintenance burden without clear benefits.

### Alternative 3: Runtime Parameter

Add a runtime parameter to switch between stream and array returns.

**Rejected**: Breaks type safety and complicates method signatures. This is also a breaking change.

### Impact of Not Implementing

Developers continue to write boilerplate stream-to-array conversion code for simple use cases, reducing productivity and code readability.

## Risks and Assumptions

### Risks

1. **Memory Usage**: Eager loading loads entire result sets into memory, potentially causing OutOfMemory errors for large datasets
2. **Performance**: Array construction has overhead compared to streaming

### Assumptions

1. Developers understand memory implications of eager loading
2. Use cases requiring eager loading typically involve smaller datasets
3. Native `queryAsList` method implementation is available in `ballerina/persist.sql` package
4. Lazy loading (streams) remains the recommended default approach

### Mitigation

- Flag is hidden by default as lazy loading is the recommended approach for most use cases
- Documentation clearly states SQL-only limitation
- Warning messages guide users away from unsupported datastores

## Dependencies

### Internal Dependencies

- **`ballerina/persist.sql` package**: Requires `queryAsList` native method implementation

## Future Work

1. **NoSQL Support**: Evaluate feasibility of eager loading for Redis and Google Sheets datastores
2. **Performance Optimization**: Investigate batch loading strategies for large datasets with eager loading
3. **Configuration Validation**: Enhanced validation to warn about potential memory issues with large tables
4. **Documentation**: Comprehensive usage guidelines comparing streaming vs eager loading trade-offs
