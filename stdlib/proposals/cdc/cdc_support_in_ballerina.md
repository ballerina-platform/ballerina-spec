# CDC Support in Ballerina

- Author: @niveathika
- Reviewers: 
- Created: 2025-03-16
- Updated: 2025-03-16
- Issue: [#1341](https://github.com/ballerina-platform/ballerina-spec/issues/1341)
- Status: Submitted

## Summary

This proposal aims to integrate Change Data Capture (CDC) support into Ballerina, enabling real-time tracking and processing of database changes (INSERT, UPDATE, DELETE). The solution will provide a seamless and scalable way for Ballerina applications to consume CDC events.

Please add any comments to issue [#1341](https://github.com/ballerina-platform/ballerina-spec/issues/1341)

## Goals

- Enable real-time CDC support for various databases in Ballerina.
- Provide a Ballerina connector API to consume CDC events seamlessly.
- Ensure lightweight, scalable, and efficient CDC integration.

## Motivation

CDC is a critical component in real-time data integration, benefiting industries like finance, healthcare, retail, and telecommunications. Since Ballerina is designed for seamless integration, native CDC support enhances its ability to:

- Connect different systems efficiently.
- Process real-time database events.
- Streamline data workflows with minimal overhead.

## Design

### Possible Approaches

1. **JDBC Polling**

   ✅ Simple, works with standard JDBC drivers.  
   ✅ Compatible with MSSQL native CDC support.  
   ❌ Polling introduces delays in detecting changes.  
   ❌ Adds additional load on the database.  

2. **Debezium-Based CDC (Preferred)**

   ✅ Provides real-time changes.  
   ✅ Uses log-based CDC, avoiding additional database load.  
   ✅ Designed for high-frequency updates.  
   ✅ Supports event filtering, transformation, and error handling.  
   ❌ Requires a Kafka cluster.  

Ballerina's CDC component will use **Debezium** as the underlying engine to capture database events. The module will use **Debezium in Embedded mode**, which does not make a Kafka cluster mandatory.

### Module Organization

The implementation will consist of a **core module** containing Debezium dependencies and logic:

```
module-ballerinax-cdc
```

Additionally, there will be **database-specific modules** for different connectors:

```
module-ballerinax-cdc.mysql.driver
module-ballerinax-cdc.mssql.driver
```
These modules will only pack the dependencies and can be used as ignored imports.

```ballerina
import ballerinax/cdc.mssql.driver as _;
```

## Components

### 1. Listeners

Each supported database will have a dedicated `Listener`.

> **Note**: A single listener for all databases was **scrapped** due to usability issues. Since different databases share the same configuration structure with varying default values, Ballerina’s type system resulted in "Ambiguous type" errors, requiring manual type casting.

Each listener follows the same structure but uses database-specific configurations.

#### Example: MySQL Listener

```ballerina
# Ballerina CDC Listener
public isolated class MySqlListener {

    public isolated function init(*MySqlConnectorConfiguration config) returns Error? {
        return externInit(self, config);
    }

    public isolated function attach(Service s, string[]|string? name = ()) returns Error? =
        @java:Method { 'class: "io.ballerina.lib.cdc.Listener" } external;

    public isolated function 'start() returns Error? =
        @java:Method { 'class: "io.ballerina.lib.cdc.Listener" } external;

    public isolated function detach(Service s) returns Error? =
        @java:Method { 'class: "io.ballerina.lib.cdc.Listener" } external;

    public isolated function gracefulStop() returns Error? =
        @java:Method { 'class: "io.ballerina.lib.cdc.Listener" } external;

    public isolated function immediateStop() returns Error? =
        @java:Method { 'class: "io.ballerina.lib.cdc.Listener" } external;
}
```

---

#### Listener Configuration

Each listener requires a set of **mandatory and optional** configuration properties.

#### General CDC Configuration

```ballerina
public type CdcConfiguration record {
    string engineName = "ballerina-cdc-connector";
    string connectorClass;
    FileSchemaHistoryInternal|KafkaSchemaHistoryInternal schemaHistoryInternal = <FileSchemaHistoryInternal>{};
    FileOffsetStorage|KafkaOffsetStorage offsetStorage = <FileOffsetStorage>{};
    int tasksMax = 1;
    int maxQueueSize = 8192;
    int maxBatchSize = 2048;
    string eventProcessingFailureHandlingMode = FAIL;
    string snapshotMode = INITIAL;
    string skippedOperations = TRUNCATE;
    boolean skipMessagesWithoutChange = false;
};

public type MySqlConnectorConfiguration record {| *CdcConfiguration;
    string connectorClass = "io.debezium.connector.mysql.MySqlConnector";
    MySQLConnection database;
|};

public type MSSQLConnectorConfiguration record {| *CdcConfiguration;
    string connectorClass = "io.debezium.connector.sqlserver.SqlServerConnector";
    MSSQLConnection database;
|};
```

#### Database Connection Configuration

```ballerina
public type DatabaseConnection record {
    string hostname;
    int port;
    string username;
    string password;
    SecureDatabaseConnection secure?;
    int connectTimeoutMs?;
    string[] tableInclude?;
    string[] tableExclude?;
    string[] columnInclude?;
    string[] columnExclude?;
};

public type MySQLConnection record {|
    *DatabaseConnection;
    string hostname = "localhost";
    int port = 3306;
    string databaseServerId = "cdc-ballernia";
    string[] databaseInclude?;
    string[] databaseExclude?;
|};
```

---

### 2. Services

Multiple **services** can be attached to a **single listener**. Services allow event grouping based on business logic.

#### Example Service

```ballerina
public type Service distinct service object {
    remote function onRead(record{} after, string tableName = "") returns Error?;
    remote function onCreate(record{} after, string tableName = "") returns Error?;
    remote function onUpdate(record{} before, record{} after, string tableName = "") returns Error?;
    remote function onDelete(record{} before, string tableName = "") returns Error?;
    remote function onError(Error 'error) returns Error?;
};
```

Function will support data binding. The `tableName` parameter is optional. 

The structure of the service will be validated with compiler plugin.

---

### 3. Annotations

Annotations define event routing per service.

#### Annotation Definition

```ballerina
public type EventsFromConfig record {| string|string[] tables; |};

# Configure event sources for a CDC service.
public annotation EventsFromConfig EventsFrom on service;
```

#### Usage Example

```ballerina
@cdc:EventsFrom {
    tables: "inventory.products"
}
service cdc:Service on new cdc:MySqlListener({
    database: {username: "root", password: "root"}
}) {
}
```

> **Note**: If **multiple services** are attached to a listener, **annotations are mandatory** to avoid event ambiguity.

> **Important**: Multiple services **cannot** receive events from the same table. This ensures there is no event duplication at the Ballerina layer.

---

## Future Work

1. **Schema Change Capture** – Track database schema modifications.
2. **Support for Additional Databases** – PostgreSQL, Oracle, etc.

