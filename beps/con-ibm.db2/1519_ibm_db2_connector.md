# 1519: IBM Db2 connector (`ballerinax/ibm.db2`)

- Authors - Dilan Perera
- Reviewed by - Danesh Kuruppu
- Created date - 2026-11-10
- Updated date - 2026-11-10
- Issue - [#1519](https://github.com/ballerina-platform/ballerina-spec/issues/1519)
- State - Submitted

## Summary

This proposal adds a Ballerina connector for IBM Db2, published as `ballerinax/ibm.db2`. It is built on `ballerina/sql` in the same way as the `mysql`, `mssql`, `postgresql` and `oracledb` connectors, so a `db2:Client` offers `query`, `queryRow`, `execute`, `batchExecute` and `call` with the standard `sql` types. On top of that it defines the Db2 connection options, the mapping between Db2 and Ballerina types, and four Db2 specific OUT parameter classes. The IBM JDBC driver is not bundled with the package; an application adds it as a platform dependency.

## Motivation

IBM Db2 is widely used in banking, insurance, retail and government systems, on Linux, UNIX and Windows, on IBM Z and on IBM i. Ballerina has dedicated connectors for MySQL, Microsoft SQL Server, PostgreSQL and Oracle Database, but not for Db2. The only way to reach Db2 today is `ballerinax/java.jdbc` with the IBM driver, which has these problems:

- `batchExecute` fails against Db2. The generic client asks for generated keys on a batch and reads a result set that the IBM driver has already closed (driver error `-4470`).
- A nil parameter is bound as the JDBC `NULL` type, which the IBM driver rejects (`-4228`).
- `DECFLOAT` columns are reported as the JDBC type `OTHER` and are returned as strings.
- `XML` values, binary OUT parameters and `time:Utc` values are not converted correctly.
- Errors carry only the SQLCODE, because the driver does not fetch the server message unless asked to.
- Connection options such as TLS, the current schema and the DRDA security mechanism have to be written as raw driver properties.

A dedicated connector removes these problems and gives Db2 users the same programming model and documentation as the other databases.

## Goals

- A `db2:Client` with the remote methods of the other SQL connectors: `query`, `queryRow`, `execute`, `batchExecute`, `call` and `close`.
- A typed `db2:Options` record for TLS, the current schema, DRDA security mechanisms, timeouts, the client program name and XA transactions, with a pass-through for any other driver property.
- A correct mapping for every Db2 data type in both directions, including `DECFLOAT`, `GRAPHIC`/`VARGRAPHIC`/`DBCLOB`, `XML`, `BOOLEAN`, `BINARY`/`VARBINARY`, `FOR BIT DATA` columns and `TIMESTAMP(12)`.
- Stored procedures with IN, OUT and INOUT parameters of every type and multiple result sets.
- Server error messages in the error text, with the SQLCODE and SQLSTATE in the error detail.
- Compile-time validation of the connection pool and timeout values, as in the other SQL connectors.
- GraalVM native image support.

## Non-Goals

- A change data capture listener for Db2. It can follow as a `ballerinax/ibm.db2.cdc.driver` package once the connector is released.
- Bundling or redistributing the IBM JDBC driver (see [Driver distribution](#driver-distribution)).
- Db2 specific APIs beyond SQL, such as the administrative API or `LOAD`.
- Verified support for Db2 for z/OS and Db2 for i. The driver supports them and nothing in the design excludes them, but the first release is tested against Db2 for Linux, UNIX and Windows only.

## Design

### Package and module layout

| Item | Value |
|---|---|
| Package | `ballerinax/ibm.db2` |
| Default prefix | `db2` |
| Repository | `ballerina-platform/module-ballerinax-ibm.db2` |
| Native code | `io.ballerina.lib.ibm.db2` (`ibm.db2-native`) |
| Compiler plugin | `ibm.db2-compiler-plugin` |
| Driver | IBM Data Server Driver for JDBC and SQLJ (JCC), type 4, `com.ibm.db2:jcc` |

The name follows `ballerinax/ibm.ibmmq` and `ballerinax/ibm.ctg`: the vendor first, then the product.

### Client

```ballerina
public isolated client class Client {
    *sql:Client;

    public isolated function init(string host = "localhost", string? user = (), string? password = (),
            string? database = (), int port = 50000, Options? options = (),
            sql:ConnectionPool? connectionPool = ()) returns sql:Error?;

    remote isolated function query(sql:ParameterizedQuery sqlQuery, typedesc<record {}> rowType = <>)
            returns stream<rowType, sql:Error?>;
    remote isolated function queryRow(sql:ParameterizedQuery sqlQuery, typedesc<anydata> returnType = <>)
            returns returnType|sql:Error;
    remote isolated function execute(sql:ParameterizedQuery sqlQuery) returns sql:ExecutionResult|sql:Error;
    remote isolated function batchExecute(sql:ParameterizedQuery[] sqlQueries) returns sql:ExecutionResult[]|sql:Error;
    remote isolated function call(sql:ParameterizedCallQuery sqlQuery, typedesc<record {}>[] rowTypes = [])
            returns sql:ProcedureCallResult|sql:Error;
    public isolated function close() returns sql:Error?;
}
```

The parameter order of `init` matches the other SQL connectors. The `database` is required, because a Db2 connection is always made to a database (the location name for Db2 for z/OS); a missing or blank value is reported as an `sql:ApplicationError` before any connection is attempted.

### Connection options

```ballerina
public type Options record {|
    SecureSocket secureSocket?;
    string currentSchema?;
    SecurityMechanism securityMechanism?;
    decimal loginTimeout?;
    decimal socketTimeout?;
    decimal queryTimeout?;
    string clientProgramName?;
    boolean useXADatasource = false;
    map<string|int|boolean> properties?;
|};

public type SecureSocket record {|
    crypto:TrustStore cert?;
    string certFile?;
    crypto:KeyStore key?;
    string tlsVersion?;
    boolean verifyHostName = true;
|};

public enum SecurityMechanism {
    CLEAR_TEXT_PASSWORD,
    ENCRYPTED_PASSWORD,
    ENCRYPTED_USER_AND_PASSWORD,
    ENCRYPTED_USER_PASSWORD_AND_DATA,
    KERBEROS,
    TLS_CLIENT_CERTIFICATE
}
```

- `secureSocket` turns TLS on. The host name of the server certificate is verified by default.
- `currentSchema` sets the `CURRENT SCHEMA` special register.
- The timeouts are in seconds and are rounded up to whole seconds, which is the resolution of the driver.
- `clientProgramName` is the application name the server shows in its monitoring views.
- `properties` passes any other driver property through, for example client reroute or IBM Cloud IAM settings. These override the values derived from the typed fields.

### Type mapping

| Db2 type | Ballerina type |
|---|---|
| `SMALLINT`, `INTEGER`, `BIGINT` | `int` |
| `DECIMAL`, `NUMERIC` | `decimal` |
| `DECFLOAT(16)`, `DECFLOAT(34)` | `decimal` (`float` or `string` for `Infinity` and `NaN`) |
| `REAL`, `DOUBLE` | `float` |
| `CHAR`, `VARCHAR`, `CLOB`, `GRAPHIC`, `VARGRAPHIC`, `DBCLOB` | `string` |
| `BINARY`, `VARBINARY`, `BLOB`, `CHAR`/`VARCHAR FOR BIT DATA` | `byte[]` |
| `DATE` | `time:Date` or `string` |
| `TIME` | `time:TimeOfDay` or `string` |
| `TIMESTAMP(p)` | `time:Civil`, `time:Utc`, `string` or `int` |
| `BOOLEAN` | `boolean` |
| `XML` | `xml` |

Rules that differ from the `sql` defaults, each forced by Db2 or its driver:

- **Nulls.** A nil parameter is sent as a typed null, because the driver rejects the JDBC `NULL` type.
- **Instants.** Db2 has no time zone types. A `time:Utc` value and a `time:Civil` value with a `utcOffset` are stored as the UTC wall clock time, and a `TIMESTAMP` read as `time:Utc` is interpreted as UTC, so instants round-trip. A `time:TimeOfDay` with a `utcOffset` is rejected.
- **`NaN` and `Infinity`.** A non-finite `float` parameter is rejected with an `sql:DataError`, because `DOUBLE` and `REAL` have no such values and the driver cannot bind them for `DECFLOAT`. The SQL literal `DECFLOAT('NaN')` stores such a value.
- **Arrays.** The driver cannot bind arrays, so array parameters and the `sql:*ArrayValue` types are rejected with an `sql:DataError`.
- **National character types.** `sql:NClobValue` is sent as a `CLOB`, because the driver has no `createNClob`.

### OUT parameters

The `sql` module converts the values of its own OUT parameter classes with its default conversion, which cannot read the binary and XML values the Db2 driver returns. The module therefore defines four classes that include `sql:OutParameter` and convert with the Db2 rules, the pattern `oracledb` and `postgresql` already use:

```ballerina
public isolated distinct class BinaryOutParameter { *sql:OutParameter; }
public isolated distinct class VarBinaryOutParameter { *sql:OutParameter; }
public isolated distinct class BlobOutParameter { *sql:OutParameter; }
public isolated distinct class XmlOutParameter { *sql:OutParameter; }
```

Passing the `sql` class for one of these types returns an `sql:DataError` that names the `db2` class to use. Every other `sql:*OutParameter` and `sql:InOutParameter` works unchanged.

### Batches

Db2 keeps executing a batch after a failed command. The `sql:BatchExecuteError` holds one result for every command, with an `affectedRowCount` of `-3` for a failed one. The driver does not report the generated keys of a batch, so `lastInsertId` is nil for batched inserts.

### Errors

The client always asks the server for the message text, so an error reads `"DB2INST1.ORDERS" is an undefined name` and not only `SQLCODE=-204`. The `errorCode` of the error detail is the SQLCODE and `sqlState` is the SQLSTATE.

### Driver distribution

The IBM driver is licensed under the IBM International Program License Agreement. Its License Information allows `db2jcc4.jar` to be redistributed only as part of a value-added application. A Ballerina package on Ballerina Central is a library, so the driver cannot be bundled in the connector and cannot be published as a separate `ibm.db2.driver` package the way `mysql.driver` or `mssql.driver` are.

The connector therefore declares the driver with the `provided` scope, as `ballerinax/ibm.ibmmq` and `ballerinax/ibm.ctg` do for their IBM libraries, and an application adds the driver itself:

```toml
[[platform.java21.dependency]]
groupId = "com.ibm.db2"
artifactId = "jcc"
version = "12.1.5.0"
```

Ballerina downloads the driver from Maven Central, where IBM publishes it. The published connector package contains no IBM code.

### Usage

```ballerina
import ballerina/io;
import ballerina/sql;
import ballerinax/ibm.db2;

configurable string host = ?;
configurable string user = ?;
configurable string password = ?;
configurable string database = ?;

final db2:Client dbClient = check new (host, user, password, database);

type Employee record {|
    int id;
    string name;
    decimal salary;
|};

public function main() returns error? {
    sql:ExecutionResult result = check dbClient->execute(
        `INSERT INTO EMPLOYEE (NAME, SALARY) VALUES (${"Ann"}, ${9500.00d})`);
    io:println("Inserted employee ", result.lastInsertId);

    stream<Employee, sql:Error?> employees = dbClient->query(`SELECT ID, NAME, SALARY FROM EMPLOYEE`);
    check from Employee e in employees
        do {
            io:println(e);
        };
}
```

## Alternatives

- **Keep using `ballerinax/java.jdbc`.** Rejected for the defects listed under Motivation. Several of them cannot be fixed in the generic client without Db2 specific code.
- **Name the package `ballerinax/db2`.** Rejected in favour of `ibm.db2`, which matches the existing IBM connectors and leaves room for other IBM data products.
- **Publish a `ballerinax/ibm.db2.driver` package that bundles the driver.** Rejected because the driver licence does not allow it.
- **Use the IBM CLI/ODBC driver or the Db2 REST service.** Rejected because both would need a new client layer, while the JDBC driver plugs into `ballerina/sql` and its connection pool, transactions and stream handling.

## Testing

- 108 integration tests run against Db2 12.1 Community Edition in a container: connection options and TLS, queries and streams, every data type in both directions with plain values, typed values and nulls, stored procedures with IN, OUT and INOUT parameters of every type and multiple result sets, batches including partial failures and a batch larger than the driver chunk size, local and XA transactions, and special characters in values, identifiers and XML.
- The same tests run as a GraalVM native image.
- Compiler plugin tests cover the connection pool and timeout validations.
- JMeter load tests with Java Flight Recorder recordings cover a query and an update service on 1 CPU and 512 MiB.

## Risks and Assumptions

- **Driver licence.** Users accept IBM's licence when they add the driver. The connector documentation states this.
- **Virtual thread pinning.** The IBM driver does its network I/O in `synchronized` methods. On Java 21 this pins the carrier thread of a virtual thread for the duration of a database call, which limits the number of concurrent Db2 calls to the number of carrier threads. The load tests measured this, and raising `jdk.virtualThreadScheduler.parallelism` removes the limit. A general fix belongs in `ballerina/sql`.
- **Test platform.** The Db2 Community Edition image is available for x86-64 only, so the tests cannot run on ARM hosts.
- **Platforms.** Db2 for z/OS and Db2 for i are assumed to work through the same driver but are not tested.

## Dependencies

- `ballerina/sql` 1.19.0 or later.
- IBM Data Server Driver for JDBC and SQLJ, `com.ibm.db2:jcc`, supplied by the application.

## Future Work

- A Db2 change data capture listener.
- Verification against Db2 for z/OS, Db2 for i and Db2 on Cloud with IAM authentication.
- Fixes in `ballerina/sql` for the defects found while building the connector: XML OUT values, the conversion of OUT parameters by the vendor processor, chained batch exceptions and a nil boolean OUT value.
- A page for the connector in the WSO2 Integrator documentation.

## References

- Implementation: [ballerina-platform/module-ballerinax-ibm.db2#1](https://github.com/ballerina-platform/module-ballerinax-ibm.db2/pull/1)
- [IBM Data Server Driver for JDBC and SQLJ](https://www.ibm.com/docs/en/db2/12.1.x?topic=apis-data-server-driver-jdbc-sqlj)
- [Driver License Information L-HJHH-A2W6TH](https://www.ibm.com/support/customer/csol/terms/?id=L-HJHH-A2W6TH)
- [`ballerinax/ibm.ibmmq`](https://central.ballerina.io/ballerinax/ibm.ibmmq/latest), the precedent for the `provided` driver dependency

[]: # (end)
[]: # Please add any comments to [#1519](https://github.com/ballerina-platform/ballerina-spec/issues/1519)
