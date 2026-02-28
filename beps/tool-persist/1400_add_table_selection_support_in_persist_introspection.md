# Table Selection for Database Introspection

- Authors - @TharmiganK
- Reviewed by - @daneshk
- Created date - 2025-11-21
- Updated date - 2025-11-21
- Issue - [#1400](https://github.com/ballerina-platform/ballerina-spec/issues/1400)
- State - Submitted

## Summary

This proposal introduces a table selection feature for the `bal persist pull` command, allowing users to selectively introspect specific tables from a database instead of always introspecting all tables.

The feature provides three modes of operation: default behavior (all tables), explicit table selection via command-line arguments, and an interactive mode with a user-friendly interface. Additionally, the implementation includes automatic foreign key dependency resolution to ensure valid model generation when tables have relational dependencies.

## Motivation

The `bal persist pull` command is designed to work with existing databases by introspecting the database schema and generating a `model.bal` file with entities and relations. As documented in the [Persist Introspection guide](https://ballerina.io/learn/persist-introspection), this feature supports MySQL, MSSQL, and PostgreSQL databases and uses advanced SQL annotations for name mapping, type conversions, and relationship definitions.

Currently, the `bal persist pull` command introspects all tables in a database without any option to select specific tables. This creates several challenges:

1. **Large Database Overhead**: When working with large databases containing hundreds of tables, introspecting all tables is time-consuming and generates unnecessarily complex models.
2. **Focused Development**: Developers often need to integrate with only a subset of database tables but are forced to deal with the entire database schema.
3. **Gradual Migration**: Teams migrating existing applications to Ballerina Persist need the ability to incrementally adopt persistence by starting with a few critical tables.
4. **Multi-tenant Databases**: In shared database environments, different services may only need access to specific tables relevant to their domain.
5. **Development Efficiency**: Reducing the scope of introspection speeds up the development cycle and reduces cognitive load.

## Goals

- Provide a command-line option (`--tables`) to select specific tables for introspection
- Offer an interactive mode for table selection with a user-friendly interface
- Maintain backward compatibility - default behavior introspects all tables when no selection is made
- Automatically resolve and include tables referenced by foreign keys to ensure valid model generation

## Non-Goals

- Pattern-based table selection (e.g., wildcards like `user_*`, `order_*`) - may be considered for future work
- Exclusion-based selection (e.g., `--exclude-tables`) - may be considered for future work
- Automatic inclusion of tables that reference selected tables (reverse dependencies) - only forward FK dependencies are included
- Schema-level filtering or multi-database introspection
- Performance optimization for extremely large databases (>1000 tables)

## Design

### Command-Line Interface

The `--tables` option is added to the existing `bal persist pull` command with optional arity (`arity = "0..1"`). The existing command structure is:

```bash
bal persist pull --datastore <mysql|mssql|postgresql> --host <host> --port <port> 
                 --user <user> --database <database> [--tables[=<table1,table2,...>]]
```

**Existing Command Options:**

| Command option |                         Description                          | Mandatory | Default Value |
|:--------------:|:------------------------------------------------------------:|:---------:|:-------------:|
|  --datastore   | Data store type: `mysql`, `mssql`, or `postgresql`           |    No     |     mysql     |
|     --host     | Database host address                                        |    Yes    |     None      |
|     --port     | Database port number                                         |    No     |     3306      |
|     --user     | Database user                                                |    Yes    |     None      |
|   --database   | Database name                                                |    Yes    |     None      |

**New Command Option:**

| Command option |                         Description                          | Mandatory | Default Value |
|:--------------:|:------------------------------------------------------------:|:---------:|:-------------:|
|    --tables    | Enable table selection (comma-separated or interactive)      |    No     |  All tables   |

**Three Modes of Operation:**

#### 1. Default Behavior (No Breaking Changes)

When `--tables` is not provided, all tables are introspected:

```bash
bal persist pull --datastore mysql --host localhost --port 3306 --user root --database mydb
```

#### 2. Explicit Table Selection

Users specify a comma-separated list of table names:

```bash
bal persist pull --datastore mysql --host localhost --port 3306 --user root --database mydb --tables=users,orders,products
```

#### 3. Interactive Mode

When `--tables` is provided without a value, an interactive prompt displays available tables:

```bash
bal persist pull --datastore mysql --host localhost --port 3306 --user root --database mydb --tables
```

Interactive mode features:

- Displays up to 50 tables (with indication if more exist)
- Supports multiple input formats:
  - Table names: `users,orders,products`
  - Table numbers: `1,3,5`
  - All tables: `all` or just press Enter
  - Abort: `q` or `quit`
- Color-coded output (cyan for headers, yellow for warnings)
- Clear, user-friendly prompts

> **Note**: When users select tables with foreign key relationships to other non-selected tables, those referenced tables will be automatically included in the introspection to ensure valid model generation.

### Examples

**Example 1: Explicit Selection with Auto-Inclusion**

```bash
$ bal persist pull --datastore mysql --host localhost --port 3306 \
    --user root --database mydb --tables=album_ratings

Database Password: ****
INFO: Automatically including table 'albums' due to foreign key relationship from 'album_ratings'
Introspection complete! The model.bal file created successfully.
```

**Example 2: Interactive Mode**

```bash
$ bal persist pull --datastore mysql --host localhost --port 3306 \
    --user root --database mydb --tables

Database Password: ****

Available tables in the database:
──────────────────────────────────
  1. users
  2. orders
  3. products
  4. categories
  5. reviews
──────────────────────────────────
Total: 5 tables

Select tables to introspect:
  • Enter table names separated by commas (e.g., users,orders,products)
  • Enter table numbers separated by commas (e.g., 1,3,5)
  • Enter 'all' to introspect all tables
  • Press Enter without input to introspect all tables
  • Enter 'q' or 'quit' to abort

Your selection: 2,3
INFO: Automatically including table 'users' due to foreign key relationship from 'orders'
Introspection complete! The model.bal file created successfully.
```

## Risks and Assumptions

### Risks

1. **Database Connectivity**
   - **Risk**: Table discovery query performance on large databases
   - **Mitigation**: Query is simple and fast; only table names are retrieved using standard metadata queries

2. **Foreign Key Detection**
   - **Risk**: Complex FK relationships might not be detected correctly
   - **Mitigation**: Use standard INFORMATION_SCHEMA queries specific to each database provider, consistent with existing introspection logic

3. **Circular Dependencies**
   - **Risk**: Infinite loops in dependency resolution
   - **Mitigation**: Track processed tables in a HashSet to prevent re-processing

4. **User Experience**
   - **Risk**: Interactive mode might be confusing for users
   - **Mitigation**: Clear prompts, examples, and comprehensive help text

5. **Backward Compatibility**
   - **Risk**: Existing scripts might break
   - **Mitigation**: Default behavior is unchanged; feature is opt-in

6. **Existing Limitations**
   - **Risk**: Inherits existing introspection limitations
   - **Known Limitations** (as documented in [Persist Introspection](https://ballerina.io/learn/persist-introspection/#limitations)):
     - Cross-referring relations (foreign keys on both sides) not supported
     - Foreign keys from unique keys not supported
     - Some data types unsupported (JSON, GEOMETRY, SET)
     - Only auto-increment generation strategy supported
     - Composite index column order not preserved

### Assumptions

1. Database users have SELECT permissions on system tables (INFORMATION_SCHEMA) to query metadata
2. Table names do not contain commas (standard SQL assumption)
3. Users understand their database schema well enough to select relevant tables
4. Foreign key constraints are properly defined in the database
5. Database connection is stable during introspection
6. Selected tables conform to [existing introspection limitations](https://ballerina.io/learn/persist-introspection/#limitations)
7. Users have already created a Ballerina project (required by `bal persist pull`)

## Future Work

1. **Pattern-Based Selection**

   ```bash
   --tables=user_*,order_*,product_*
   ```

   - Support glob patterns for table names
   - Support regular expressions for advanced filtering

2. **Exclusion-Based Selection**

   ```bash
   --exclude-tables=audit_*,log_*
   ```

   - Introspect all except specified tables
   - Useful for large databases with known tables to skip

3. **Performance Optimizations**
   - Caching of table lists for repeated operations
   - Parallel FK queries for multiple tables
   - Progress indicators for large-scale introspection
