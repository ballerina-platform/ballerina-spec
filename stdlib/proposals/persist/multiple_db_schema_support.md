# Multiple DB schema support for bal persist

- Author: @daneshk
- Reviewers: 
- Created: 2025-01-24
- Updated: 2025-01-24
- Issue: [#1327](https://github.com/ballerina-platform/ballerina-spec/issues/1327)
- Status: Submitted

## Summary

Many database providers allow you to organize database tables into named groups. You can use this to make the logical structure of the data model easier to understand, or to avoid naming collisions between tables. In PostgreSQL, CockroachDB, and SQL Server, these groups are known as schemas.

This proposal introduces support for connecting to tables in multiple database schemas in `bal persist`. Right now, `bal persist` only supports connecting to tables in the default schema of the database. But in real-world scenarios, tables are often distributed across multiple schemas in the database. When we are working with such existing databases, it is essential to provide a way to represent the schema of the table explicitly in the model file.

Please add any comments to issue [#1327](https://github.com/ballerina-platform/ballerina-spec/issues/1327).

## Goals

- Allow users to connect to tables in multiple schemas in the database.
- Provide a way to represent the schema of the table explicitly in the model file.
- Maintain backward compatibility with the current `bal persist` API.
- Support multiple schemas in PostgreSQL, CockroachDB, and SQL Server.

## Motivation

In real-world scenarios, tables are often distributed across multiple schemas in the database. When we are working with such existing databases, it is essential to provide a way to represent the schema of the table explicitly in the model file. This will make the logical structure of the data model easier to understand and avoid naming collisions between tables.

The initial `bal persist` framework only supports connecting to tables in the default schema of the database. We can't connect to tables in multiple schemas in the database. If the tables are in a different schema other than the default schema, there is one workaround to connect to those tables. We can set the search_path in the database to the schema where the tables are located. But this is not a good practice because it affects all the queries in the database.

This is a common requirement in real-world applications. So this is a road blocker for many users who are using `bal persist` in their applications. This proposal aims to provide a solution to this problem.

## Design

Backward compatibility is the key. The following usages should work regardless of any improvements proposed in this document.

The current `bal persist` model supports the following annotations to map the model to a different table name in the database. For example, the following model will be mapped to the `patients` table in the database.

```ballerina
import ballerinax/persist.sql;

@sql:Name {
    value: "patients"
}
type Patient record {|
    readonly int id;
    string name;
    int age;
    string address;
    string phoneNumber;
    Gender gender;
    Appointment[] appointment;
|};
```

This proposal introduces a new annotation to map the model to a different schema in the database. For example, the following model will be mapped to the `patients` table in the `healthcare` schema in the database.

```ballerina
import ballerinax/persist.sql;

@sql:Schema {
    value: "healthcare"
}
@sql:Name {
    value: "patients"
}
type Patient record {|
    readonly int id;
    string name;
    int age;
    string address;
    string phoneNumber;
|};
```

The `@sql:Schema` annotation is used to specify the schema of the table in the database. The value of the annotation should be the name of the schema. The `@sql:Schema` annotation is optional. If the schema is not specified, the table will be created in the default schema of the database.

### Example

The following are examples of how to use the `@sql:Schema` annotation in a model.

#### Multiple database schemas in your Prisma schema

```ballerina
import ballerinax/persist.sql;

@sql:Schema {
    value: "healthcare"
}
@sql:Name {
    value: "patients"
}
type Patient record {|
    readonly int id;
    string name;
    int age;
    string address;
    string phoneNumber;
|};

@sql:Schema {
    value: "hr"
}
@sql:Name {
    value: "employees"
}
type Employee record {|
    readonly int id;
    string name;
    int age;
    string address;
    string phoneNumber;
|};
```

### Tables with the same name in different database schemas

If there are tables with the same name in different schemas, the `@sql:Schema` annotation should be used to specify the schema of the table in the model. For example, the following model will be mapped to the `users` table in the `healthcare` schema and the `hr` schema in the database.

```ballerina
import ballerinax/persist.sql;

@sql:Schema {
    value: "healthcare"
}
@sql:Name {
    value: "users"
}
type PatientUser record {|
    readonly int id;
    string name;
    int age;
    string address;
    string phoneNumber;
|};

@sql:Schema {
    value: "hr"
}
@sql:Name {
    value: "users"
}
type EmployeeUser record {|
    readonly int id;
    string name;
    int age;
    string address;
    string phoneNumber;
|};
```

### Why not use the `@sql:Name` annotation to specify the schema?

The `@sql:Name` annotation is used to specify the name of both the table and the column in the database. The schema is a part of the table name in the database and it is a grouping of tables in the database. So it is not a good idea to use the `@sql:Name` annotation to specify the schema. The `@sql:Name` annotation should be used to specify the name of the table and the column in the database.

### Limitations

- The `@sql:Schema` annotation is only supported for PostgreSQL, CockroachDB, and SQL Server databases which support multiple schemas.
- The `@sql:Schema` annotation is not supported for other databases which do not support multiple schemas.

## Future Work

- Support introspection of the specific database schema. 
When introspecting the existing database, the user should be able to specify the schema in which the tables are located. This will generate the model file with the schema information.
