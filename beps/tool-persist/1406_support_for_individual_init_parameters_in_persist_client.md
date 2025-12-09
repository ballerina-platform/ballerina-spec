# Support for Individual Init Parameters in Persist Clients

- Authors - @TharmiganK
- Reviewed by - @daneshk
- Created date - 2025-12-05
- Updated date - 2025-12-05
- Issue - [#1406](https://github.com/ballerina-platform/ballerina-spec/issues/1406)
- State - Submitted

## Summary

This proposal introduces support for individual initialization parameters in Ballerina persist clients as an alternative to the existing module-level configurable-based approach. This enables a more low-code friendly and programmatic way to initialize database connections.

## Motivation

Currently, Ballerina persist clients are initialized using configurables bound to module-level variables and exposed through a parameter-less `init()` function:

```ballerina
// Generated configurables (module-level)
configurable string host = ?;
configurable int port = ?;
configurable string user = ?;
configurable string password = ?;
configurable string database = ?;

// Generated init function
public function init() returns Client|error {
    final Client dbClient = check new (); // Uses configurables internally
    return new (dbClient);
}
```

This approach presents significant challenges:

1. **Client reusability**: The parameter-less `init()` function makes it impossible to initialize the same client module with different configurations. Applications requiring multiple database connections (e.g., read replicas, multi-tenant scenarios) cannot reuse the generated client code and must resort to workarounds.

2. **Low-code developer experience**: In low-code environments, the generated configurables appear as separate, unrelated variables. The association between these variables and the database client is hidden within the generated code, making it unclear to developers which parameters are required for client initialization. This disconnect significantly degrades the developer experience and makes the client initialization opaque.

This proposal introduces support for individual initialization parameters, enabling explicit, self-documenting client initialization while maintaining backward compatibility with the existing configurable-based approach.

## Goals

- Enable persist clients to be initialized with individual parameters directly in code
- Support both configurable-based and parameter-based initialization approaches
- Maintain backward compatibility with existing persist applications
- Apply this feature to all SQL-based datastores (MySQL, PostgreSQL, MSSQL, H2)
- Provide tooling support through CLI flags for code generation

## Non-Goals

- Replacing or deprecating the existing configurable-based approach
- Supporting this feature for non-SQL datastores (in-memory, Redis, Google Sheets)
- Automatic migration of existing projects to the new approach
- Runtime configuration switching between approaches

## Design

### CLI Changes

A new hidden flag `--with-init-params` is introduced to both `bal persist generate` and `bal persist add` commands:

```bash
bal persist generate --datastore mysql --module entities --with-init-params
bal persist add --datastore mysql --module entities --with-init-params
```

When this flag is used:

1. The generated `init()` function accepts individual parameters instead of relying on configurables
2. No `Config.toml` file is generated
3. No `persist_db_config.bal` file is generated
4. The `Ballerina.toml` is updated with `options.withInitParams = true` for build integration

### Generated Code Structure

**Without `--with-init-params` (Current approach):**

```ballerina
public function init() returns Client|error {
    final Client dbClient = check new ();
    return new (dbClient);
}
```

**With `--with-init-params` (New approach):**

For MySQL:

```ballerina
public function init(
    string host,
    int port,
    string user,
    string password,
    string database,
    mysql:ConnectionOptions connectionOptions = {}
) returns Client|error {
    final mysql:Client dbClient = check new (host, port, user, password, database, connectionOptions);
    return new (dbClient);
}
```

For MSSQL/PostgreSQL (includes additional schema parameter):

```ballerina
public function init(
    string host,
    int port,
    string username,
    string password,
    string database,
    string defaultSchema = (),
    postgresql:ConnectionOptions connectionOptions = {}
) returns Client|error {
    final postgresql:Client dbClient = check new (host, port, username, password, database, connectionOptions);
    // Schema metadata initialization logic
    return new (dbClient);
}
```

For H2:

```ballerina
public function init(
    string url,
    string user = (),
    string password = (),
    h2:ConnectionOptions connectionOptions = {}
) returns Client|error {
    final h2:Client dbClient = check new (url, user, password, connectionOptions);
    return new (dbClient);
}
```

> **Note:** For non-SQL data stores, the init function will not change based on this option. It will remain as the default where we use module-level configurable variables.

### Build Integration

When using `bal persist add --with-init-params`, the tool configuration in `Ballerina.toml` includes:

```toml
[[tool.persist]]
id = "generate-db-client"
targetModule = "myapp.entities"
options.datastore = "mysql"
options.withInitParams = true
filePath = "persist/model.bal"
```

This ensures that subsequent `bal build` operations regenerate the client with the correct initialization approach.

### Usage Example

Developers can now initialize persist clients programmatically:

```ballerina
import myapp/entities;

public function main() returns error? {
    entities:Client db = check entities:init(
        host = "localhost",
        port = 3306,
        user = "admin",
        password = getPasswordFromVault(),
        database = "production_db"
    );
    
    // Use the client
    stream<entities:User, error?> users = db->/users();
    check users.forEach(user => io:println(user));
}
```

### Impact of Not Implementing

Without this feature, developers would continue facing the following limitations:

1. **No client reusability**: Applications requiring multiple database connections with different configurations would be forced to duplicate generated client code or create complex workarounds, leading to code duplication and maintenance burden.

2. **Poor low-code experience**: The disconnect between configurables and client initialization would persist, making it difficult for low-code developers to understand which parameters are required and how they relate to the database client.

## Future Work

1. **Additional datastores**: Consider extending this feature to other datastores (Redis, Google Sheets) based on user demand and technical feasibility.

2. **Connection pooling configuration**: Enhance the `ConnectionOptions` parameter handling to support more advanced connection pool configurations specific to each datastore.
