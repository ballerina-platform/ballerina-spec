# Introducing Additional Connection Pool Configurations to the Ballerina SQL

- Authors
  - Thisaru Guurge
- Reviewed by
  - Sameera Jayasoma
- Created date
  - 2025-09-11
- Issue
  - [1383](https://github.com/ballerina-platform/ballerina-spec/issues/1383)
- State
  - Submitted

## Summary

This proposal introduces an enhancement to the Ballerina `sql` library that enables the developer to configure the
connection pool configurations. The ballerina SQL package uses HikariCP as the connection pool implementation under the
hood, but the existing configuration options are limited from the Ballerina side, and the developers do not have a
control over the additional, advanced configurations that are available in HikariCP. This proposal aims to introduce the
missing configurations to the Ballerina SQL library.

## Goals

- Provide the developer more control over the connection pool configurations for the Database connectors.

## Motivation

The Ballerina SQL package is the basis of the SQL-based database connectors in Ballerina. These database connectors use
HikariCP as the connection pool implementation under the hood. Even thought HikariCP is a powerful connection pool
implementation, the existing configuration options are limited from the Ballerina side, and the developers do not have a
control over the additional, advanced configurations that are available in HikariCP. This limitation prevents the
developers from properly tuning the connection pool configurations, recover from pool exhaustion, which results in
service restarts and impact the production stability. This proposal aims to introduce the missing configurations to the
Ballerina SQL library, so that the developers can properly tune, recover from pool exhaustion, and improve the
production stability.

## Description

### Current state

The Ballerina SQL package currently exposes the following configurations for the connection pool, through the
`sql:ConnectionPool` record type. All the configurations are configurable through the Ballerina configurable variables,
with default values as follows.

```ballerina
configurable int maxOpenConnections = 15;
configurable decimal maxConnectionLifeTime = 1800.0;
configurable int minIdleConnections = 15;

public type ConnectionPool record {|
    int maxOpenConnections = maxOpenConnections;
    decimal maxConnectionLifeTime = maxConnectionLifeTime;
    int minIdleConnections = minIdleConnections;
|};
```

### Similar implementations

This section describes the similar connection pool implementations in other programming languages and/or frameworks.

#### Go

Go lang has the `database/sql` package which provides the basic functionality to interact with a database. The
connection pool configurations are available through the [`sql.DB`](https://pkg.go.dev/database/sql#DB.SetConnMaxIdleTime) type. It exposes the following configurations.

- `DB.SetMaxIdleConns` - The maximum number of idle connections to the database.
- `DB.SetConnMaxIdleTime` - The maximum amount of time an idle connection can stay in the pool.
- `DB.SetConnMaxLifetime` - The maximum amount of time a connection can stay in the pool.
- `DB.SetMaxOpenConns` - The maximum number of open connections to the database.

#### Node (Node-postgres)

Node postgres has the following connection pool configurations through the [`PoolConfig`](https://node-postgres.com/apis/pool) object.

- `connectionTimeoutMillis` - The maximum time to wait for a connection from the pool before failing.
- `idleTimeoutMillis` - The maximum amount of time an idle connection can stay in the pool.
- `max` - The maximum number of open connections to the database.
- `min` - The minimum number of idle connections to the database.
- `allowExitOnIdle` - Whether to allow the pool to exit on idle.
- `maxLifetimeSeconds` - The maximum amount of time a connection can stay in the pool.

#### Java (HikariCP)

HikariCP has the following connection pool configurations.

- `maximumPoolSize` - Maximum total connections in the pool.
- `minimumIdle` - Target minimum idle connections kept in the pool.
- `connectionTimeout` - Max time to wait for a connection from the pool before failing.
- `idleTimeout` - Max time a connection may remain idle before retirement.
- `keepaliveTime` - Interval to ping idle connections to prevent external timeouts.
- `maxLifetime` - Max lifetime of a connection before it is retired.
- `validationTimeout` - Max time to validate a connection’s aliveness.
- `connectionTestQuery` - Custom validation query (use only if JDBC4 `isValid()` is unreliable).
- `connectionInitSql` - SQL executed after creating each new connection.
- `initializationFailTimeout` - Fail-fast vs lazy pool initialization behavior.
- `isolateInternalQueries` - Run pool’s internal queries in their own transaction (when `autoCommit=false`).
- `allowPoolSuspension` - Allow pool suspension/resume via JMX.
- `autoCommit` - Default auto-commit for connections returned from the pool.
- `readOnly` - Default read-only mode for connections.
- `transactionIsolation` - Default transaction isolation level.
- `leakDetectionThreshold` - Time a connection can be out of the pool before logging a potential leak.
- `poolName` - Name shown in logs/JMX to identify the pool.
- `registerMbeans` - Register JMX MBeans for management/monitoring.
- `catalog` - Default catalog (driver supports).
- `schema` - Default schema (driver supports).

### Proposed state

Although the HikariCP exposes a lot of configurations, practically, Ballerina does not need to expose all of them. This
section describes the configurations that are most commonly used and are most likely to be configured by the developers,
which this proposal aims to introduce to the Ballerina SQL package.

#### Configurable variables

The proposed state introduces the following configurable variables to the Ballerina SQL package.

```ballerina
# Maximum time (in seconds) to wait for a connection from the pool before failing.
configurable decimal connectionTimeout = 30.0;

# Maximum time (in seconds) an idle connection is kept before retirement.
configurable decimal idleTimeout = 600.0;

# Maximum time (in seconds) allowed for a connection validation.
configurable decimal validationTimeout = 5.0;

# Threshold (in seconds) to flag a potential connection leak (use `0` to disable leak detection).
configurable decimal leakDetectionThreshold = 0.0;

# Interval (in seconds) to periodically keep idle connections alive (use `0` to disable keep alive).
configurable decimal keepAliveTime = 0.0;

# Pool name for logs/metrics. If unset, an internal name is used.
configurable string? poolName = ();

# Controls pool boot behavior: fail fast vs. lazy init. Use negative value to disable failure timeout.
configurable decimal initializationFailTimeout = 1.0;

# Default transaction isolation for connections. If unset, driver default is used.
# Allowed values typically: `NONE`, `READ_UNCOMMITTED`, `READ_COMMITTED`, `REPEATABLE_READ`, `SERIALIZABLE`.
configurable TransactionIsolation transactionIsolation = NONE;

# SQL query to validate a connection.
# Leave unset to use driver-native validation.
configurable string? connectionTestQuery = ();

# SQL executed when a new connection is created. Useful for session-level settings.
configurable string|string[]? connectionInitSql = ();

# Marks connections as read-only by default. Use with care when apps issue writes.
configurable boolean readOnly = false;

# Allows suspending the pool for maintenance. Rarely needed; keep disabled.
configurable boolean allowPoolSuspension = false;

# Isolates pool’s internal queries from application transactions.
configurable boolean isolateInternalQueries = false;

# Represents the transaction isolation level.
public enum TransactionIsolation {
    # No isolation level
    NONE,
    # Read committed isolation level
    READ_COMMITTED,
    # Read uncommitted isolation level
    READ_UNCOMMITTED,
    # Repeatable read isolation level
    REPEATABLE_READ,
    # Serializable isolation level
    SERIALIZABLE
}
```

### The `sql:ConnectionPool` record type

The proposed state introduces the following configurations to the `sql:ConnectionPool` record type.

```ballerina
public type ConnectionPool record {|
    // Existing fields
    int     maxOpenConnections = maxOpenConnections;
    decimal maxConnectionLifeTime = maxConnectionLifeTime;
    int     minIdleConnections = minIdleConnections;

    // New fields
    # Maximum time (in seconds) to wait for a connection from the pool before failing
    decimal connectionTimeout = connectionTimeout;

    # Maximum time (in seconds) an idle connection is kept before retirement
    decimal idleTimeout = idleTimeout;

    # Maximum time (in seconds) allowed for a connection validation
    decimal validationTimeout = validationTimeout;

    # Threshold (in seconds) to flag a potential connection leak (use `0` to disable leak detection)
    decimal leakDetectionThreshold = leakDetectionThreshold;

    # Interval (in seconds) to periodically keep idle connections alive (use `0` to disable keep alive)
    decimal keepAliveTime = keepAliveTime;

    # Pool name for logs/metrics. If unset, an internal name is used
    string? poolName = poolName;

    # Controls pool boot behavior: fail fast vs. lazy init. Use negative value to disable failure timeout
    decimal initializationFailTimeout = initializationFailTimeout;

    # Default transaction isolation for connections. If unset, driver default is used
    TransactionIsolation transactionIsolation = transactionIsolation;

    # SQL query to validate a connection. Use nil to use driver-native validation
    string? connectionTestQuery = connectionTestQuery;

    # SQL executed when a new connection is created. Useful for session-level settings
    string|string[]? connectionInitSql = connectionInitSql;

    # Marks connections as read-only by default. Use with care when apps issue writes
    boolean readOnly = readOnly;

    # Allows suspending the pool for maintenance. Rarely needed; keep disabled
    boolean allowPoolSuspension = allowPoolSuspension;

    # Isolates pool’s internal queries from application transactions
    boolean isolateInternalQueries = isolateInternalQueries;
|};
```

## Risks and Assumptions

- Introducing these new fields and configurable variables might have an impact on the dependent sql-based connectors.
  Proper testing should be done to ensure that the existing connectors are not affected by this change.

## Dependencies

- The following Ballerina packages can be affected by this change.
  - `ballerinax/mysql`
  - `ballerinax/mssql`
  - `ballerinax/postgresql`
  - `ballerinax/oracledb`
  - `ballerinax/java.jdbc`
  - `ballerinax/persist.sql`

## Testing

- Unit tests will be added to verify the correct behavior of the new configurations.
- Manual testing will be done to verify the correct behavior of the new configurations with the dependent connectors.
