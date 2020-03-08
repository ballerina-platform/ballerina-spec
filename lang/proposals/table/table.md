# Tables
**This proposal is inactive.**

Please add comments to the associated issue [#354](https://github.com/ballerina-platform/ballerina-spec/issues/354).

The design goals of the table feature are:


*   make it easier to deal with tabular data in general, not just from SQL databases, but from non-SQL databases, spreadsheets, CSV files and other existing sources of tabular data
*   fit into the language in a smooth and straightforward way, so that is easy to use and learn for somebody who is familiar with the rest of Ballerina
*   allow tables to be a structured type and so be a subtype of anydata

It is important to be clear about the relationship with SQL:



*   it is not a requirement that  the table data type be fully implementable on top of an SQL database;
*   it is not a goal to replace SQL; there will be sophisticated queries that can only be expressed, or can only be expressed efficiently, in SQL;
*   the basis for design choices is the experience that the Ballerina language as a whole, including the tables feature, will provide for all potential users, rather than the experience that the tables feature, by itself, will provide for those users already familiar with SQL.

See the SQL Interop section below for more about how this would work in practise with SQL.

This document does not address concurrency safety or transactional issues. For the most part, these issues are common to all mutable types.

## Types and values

There is a distinct `table` basic type that contains all table values. The table basic type is structured type and so table values can be cloned.

Table value of degree N consists of



1. column names - a list of N distinct strings
2. rows - list of rows, where each row is a tuple of length N (or equivalently a tuple of N lists, where all lists have the same length) where members of rows are pure (i.e. cloneable and belong to anydata|error)
3. an inherent type which is a table type descriptor

The order of columns does not affect the shape of the table. The shape of a table is a list of row shapes, one for each row, where a row shape is mapping from column names to the shapes of the members of the row.

A table type descriptor consists of



*   a row type descriptor, which is a record type, which constrains each row individually, and
*   zero or more additional constraints which affect the rows collectively

Constraints will be dealt with separately.

If `R` is a type descriptor for a subtype of `map<anydata|error>`, then `table<R>` is a table type descriptor, which describes a type that contains a table shape t if and only if for every row shape r in t, `R` contains r. Note that `R` is any type descriptor that describes a type that contains only mapping shapes, which could union type descriptor or an open record type. So if `S` is a subtype of `T`, then `table<S>` is a subtype of `table<T>`.

The row type descriptor of a table type descriptor that is the inherent type of a table value must be a closed record type, with the keys of the record type being the same as the column names.


### Discussion

Key issue is whether order significant



*   for columns and/or for rows
*   in the value and/or in the shape

Related to row ordering is auto-increment.

In SQL:



*   rows are tuples, not maps
*   table is rows plus array of column names
*   tables are multisets of rows i.e. rows are unordered
*   but queries return either
    *   tables, or
    *   cursors (which are ordered)
*   auto-increment columns allow insertion order to be preserved easily

In PyRet



*   row order is significant

In this proposal



*   order of rows is significant in the value and the shape
*   order of columns is significant in the value but not in the shape
*   there is no auto-increment feature


#### Type parameter

We need to be able to write a type for e.g. table:iterator or table:forEach. If we do this in a similar way to other collections (list, mapping), then table needs to be able to have type parameter that gives the type that we will expose each row as.


```
@typeParam
type RowType map<anydata|error>;
public function forEach(table<RowType> tbl,
    function(RowType row) returns () func) returns () = external;
```


If we don't want to do this, then we need to come up with an alternative solution, which I do not currently see.


#### Column ordering

The type parameter for the table type descriptor could be a tuple or a record. A record will clearly be more convenient. That implies that order is not part of the type, which implies it is not part of the shape, which implies that == will ignore column order.

Nonetheless, given that



*   column order is significant in SQL
*   column order is significant in spreadsheets
*   the natural literal syntax is ordered

I think table _values_ should preserve the order of columns.


#### Row ordering

Two requirements for ordering:



1. not gratuitously change the order of the rows of a table
2. be able to represent the result of a query expression with an order by clause as a table

SQL does 1 with auto increment and does 2 by having two distinct data types (table and cursor).

One challenge of auto-increment is typing. We don't want to have one record type for what you get from the table and another record type for what you put in the table. We can handle this by saying that the record type provides a fixed default for the auto increment field (e.g. 0 or -1), and when a record with that default is inserted, the table replaces the default by the next unused positive integer. With this approach, order would not be significant for == (which is consistent with columns).

However, for point 2, I think it will work better if we can use a table to represent the result of all queries including ones that do sorting.

As a pragmatic matter:



*   row order should affect == (otherwise == will be unexpectedly expensive)
*   do not support access to a row by position in row order (otherwise delete becomes problematic)
*   should be implementable in SQL by having an additional auto-increment column


#### Open record types

When a table type descriptor is being used as an abstract type, open record types make perfect sense. We can use table with an open record type to describe a record that has at least a certain set of columns.


#### Auto-increment

Not provided. Preserving ordering makes it redundant.


#### Table member types

The restriction on the types of members comes from mutability. We have to require a type that allows immutable clone.

See below for this.


## Mutability

Key points



*   The members of rows are immutable.
*   The list of column names and inherent type is immutable
*   Tables are mutable: mutation is performed at  the level of a row - by adding, removing or replacing a row
*   When a row is inserted, an ImmutableClone operation is performed on each member (same as happens with error).
*   When a row is retrieved, no clone is performed on the members.
*   The inherent type of the table constrains mutation, as with other structural types


### Discussion

Options to what happens to each row member:



1. value you put in is === to what you get out
2. clone when put in and clone when you get out
3. immutable clone when you put in, nothing when you get out

Note that all are equivalent when the value put in is immutable.

Things to consider:



*   option 1 is how mappings and lists work
*   option 3 is how error works (as regards detail record)
*   indexes won't work for option 1 when values are not simple
*   querying will need to use members in expressions; if these expressions modify the members, semantics will become very unclear
*   joins require implicit copying of members
*   for option 2, not clear when queries should perform copied, e.g. for intermediate results of queries
*   with option 3, retrieved rows can be made immutable
*   with option 3, can have primary keys and uniqueness constraints on non-simple types (including e.g. byte-arrays)

Overall I think option 3 will work best, perhaps in conjunction with an annotation that gives permission to implementations not to preserve ===-ness on get (which should allow implementation on top of an in-memory SQL database).

Background



*   PyRet tables are immutable


## Direct table type descriptor

As well as allowing a table type descriptor that describes the type of rows via a separate record type descriptor, it is convenient also for a table type descriptor to specify the columns directly.

A type descriptor


```
    table { Columns }
```


is just sugar for


```
    table<record {| Columns |}>
```


We restrict the record type to be something that can be used as the inherent type of the table, so no optional fields and no rest fields. This is not strictly necessary but will reduce confusion.

A direct table type descriptor will also provide a more convenient syntax for primary keys.


## Table constructor

In this document, to distinguish literal characters we use double quotes, rather than a different background color.

```
table-constructor-expr := "table" "[" [table-header [";" table-rows]] "]"
table-header := column-names | list-constructor-expr
column-names := column-name ("," column-name)*
column-name := identifier
table-rows := table-row ("," table-row)*
table-row := single-table-row | multiple-table-rows
single-table-row := expression
multiple-table-rows := "..." expression
```


single-table-row is an expression returning a tuple; the expression in multiple-table-rows should be an iterable over tuples.

The inherent type of the constructed table comes from the contextually expected type if there is one. Otherwise, it comes from the static types of the subexpressions (i.e. table-row), as with list and mapping constructors. Note that in this case, the single-table-row needs to get a contextually expected type whose type descriptor is a tuple type (if there was no contextually expected type, the static type of a single-table-row that was a list constructor would be an array type, which is not what is wanted).

We could also allow the expression in a table-row to return a record as an alternative to a tuple.

### Discussion

We need to be able to create a table where the list of columns is not known at compile time. We can either do that with a separate function in lang.table module or with the table constructor (as we do with computed map keys).

We also have to consider how that list of column names combines with the contextually expected type to determine



*   the column ordering of the table value
*   the inherent type of the value

One important decision is whether the explicit list of column names is required even for an empty table: this is convenient, but requires more complexity in combining two sources of information.  If the list of column names is optional, then we have to consider the fields of a record type descriptor (or at least the columns of a table descriptor) as being ordered, which is potentially confusing, since we are saying order is not significant in the type.

If contextually expected type is open, then we can the list of column names to narrow the open type to a closed one.

Other things that would add complexity here (if they were part of the value)



*   primary keys
*   other uniqueness constraints
*   auto-increment


## Primary keys

The database concept of a primary key is that is a set of columns that uniquely identify each row: i.e. there are no two rows that have the same value for all those columns.

We can support this as follows:



1. A table _value_ includes a flag for each column saying whether that column is part of the primary key
2. If the primary key flag is set for any column, then there is a constraint that no two rows have values that are == for all primary keys; this constraint will be enforced during construction and mutation.
3. There would be an implementation expectation that the table value would build some sort of index (hash table or binary tree) mapping the primary tree columns onto the row index.
4. Primary key columns are not allowed to be nil
5. Primary key columns are _not_ restricted to be of simple type
6. The shape of table value includes a set of column names that form the primary key
7. In a direct table type descriptor, a field descriptor can be preceded with `key` to indicate that the corresponding column is a part of the primary key (as in 2019R2); the meaning of this is that a table shape will only belong to the type, if its primary key column names are the same (if the type descriptor does not specify key for any columns, then the primary keys of the table shape are not constrained)
8. In a table constructor, a column-name can be preceded with key to indicate that it is part of the primary key
9. If a table constructor does not specify any primary key columns but the contextually expected type does, then the primary key columns of the value come from the contextually expected type; this also applies to typedesc:constructFrom
10. The representation of the primary key for a particular row as a value is a record with one field for each of the columns that are part of the primary key, even in the case where the primary key has a single column
11. An indirect table type descriptor can have an additional type parameter that specifies the primary key as a type e.g. `table<T,K>`
12. A member-access-expr E[x] can used with a table that has a primary key; E must be a table with a primary key, and x must belong to the record type for that
13. E[x] can also be used as an lvalue; the RHS would be a record representing the entire row;

TODO
* In a direct table type descriptor, there should be a way to reference a record type, then make one or more of the fields it declares be part of the primary key.

## Operations


### Indexed access

E[x] expression and lvalue uses primary key


### toString

Need to define how toString works. Given that we are using spaces to separate lists, we should use newlines to separate rows. So representation should be something like:


```
    firstName lastName country
    James Clark TH
    Sanjiva Weerawarana SL
```


We could use tabs instead of spaces to separate fields.


## Lang library

See [lang.table module](table.bal).

A lot of this is very similar to lang.map and lang.array.

## SQL interop

The most fundamental pattern of usage of the table data type is to rely entirely on the semantics defined by the Ballerina language specification:

*   table values are constructed using table constructor expressions
*   the inherent type of a table is specified by a Ballerina table type descriptor
*   the lifetime of table values does not extend beyond the execution of the program

With this pattern of usage, the implementation of the table data type will live in the same address space as the rest of the program, and will not typically make use of an SQL database. An SQL database is a network service that provides tabular data. The SQL query is sent as a string to the SQL server, and the result of this query (which is a cursor in SQL terms, and so ordered) is represented as a Ballerina table value. The receiving program can then use `typedesc:constructFrom` to construct a precisely typed table value to make it convenient to perform further operations on the table.

But there is another possible pattern of usage:

*   the Ballerina table value refers to a table that is stored outside the Ballerina program and can persist after the Ballerina program terminates, for example a table in a persistent SQL database;
*   a Ballerina program obtains the table value by calling a function with an external body, rather than by using a table descriptor;
*   the implementation of the table translates operations on the Ballerina table value into operations on the underlying persistent database;
*   the inherent type of the table, which represents the constraints on the values that the table can contain, is specified by the database schema, rather than by a Ballerina type descriptor.

With this pattern of usage, the implementation of the table value uses code that is part of the Ballerina program to act as a proxy for a table in the underlying persistent database. This code translates queries expressed in Ballerina into queries expressed in the database's query language and then sends those queries to the database for execution. We will call this kind of table a *persistent* table.

This pattern presents a number of challenges:


1. When cells contain a value of structured type, it will likely not be practical to implement the specified semantics for as regards identity `===`, which is to do an immutable clone on an insertion, and then return an identical value on each retrieval. It would be more practical to do a clone on each retrieval. The spec could explicitly license this, by saying that program behaviour as regards ===-ness of retrieved values is undefined for tables that were created by extra-linguistic mechanisms (i.e for any table not created by a table constructor). Related to this is dealing with identity vs equality for floating point types.
2. The inherent type specified by the database scheme may not correspond exactly to a Ballerina type descriptor.  In particular, in many cases the values allowed for a particular table column will be subset of a Ballerina basic type, for example strings up to length N. In general, column type will be mapped on to a Ballerina type together with some additional constraints; the proxy should understand the database schema types and enforce any additional constraints whenever the table is mutated. In addition, it should provide a typedesc for the column, which can be used to test whether a particular value is allowed for a column.
3. Ballerina queries can potentially contain expressions involving arbitrary function calls, and it will not always be possible to compile these into SQL queries. In order to identify these cases at compile time, the compiler will need information about the expected underlying implementation of a table value; this information could be provided by an annotation. It might sometimes be possible to decompose a query into a part that is translated into SQL and executed on the server and a part that further refines the result and is executed locally.

The Ballerina platform should define how the values that occur in SQL databases map onto Ballerina values.  In most cases, there is an obvious suitable language-defined data type; date and time is the one area where this is not the case. But there is a separate proposal to define a timestamp datatype which will help with this. Note that there quite a lot of variation in the data types provided by common SQL implementation.

The Ballerina platform can define a TableProvider abstract object type that has a method for each operation on a table, and then the standard library can provide a function that creates a table using an object that belongs to this type.


## Issues

### Rows vs parameter lists

Is there a parallel between table rows and parameter lists. Both are simultaneously named and ordered. Fundamentally ordered, but offer access by name for convenience.

### Singleton types

typeof on immutable value has to return singleton type, so we have to have (at least conceptually) singleton types

Can we explain inherent type for immutable values differently, i.e. causing type check to look at current value rather than inherent type. How would this work with typeof?


### Uniqueness constraints

A uniqueness constraint is a constraint on the shape of value. For a single column constraint, it just says you cannot have two rows where the values for this column both have the same shape and are not nil.

There several differences from primary keys:



*   you can have only one primary key, but you can have any number of uniqueness constraints;
*   uniqueness keys make no difference to the value, whereas which keys are primary is part of the value
*   the only way that uniqueness keys affect operations on the table is by constraining  the inherent type
*   primary keys cannot be nil, whereas uniqueness constraints ignore NULL keys

So it fits into our model of what a type is.


*   Enforcing a uniqueness constraint just becomes part of the normal process by which a container does not allow a mutation that is inconsistent with the container's inherent type.
*   When we stamp/convert a value with/to a type, it will cover the uniqueness constraints as well
*   A dynamic type check with `is` will look at constraints in the inherent type; if the table is immutable, then it  will look at the contents of the table rather than the inherent type.
*   For many queries, should be able to deduce uniqueness constraints of outputs from uniqueness properties of inputs.

     

Here's one way to write this:


```
constrained-type-descriptor := type-descriptor "where" constraints
constraints := constraint ("," constraint)*
constraint := unique-constraint
unique-constraint := "unique" "[" column-name ("," column-name)* "]"
column-name := identifier
```


This allows the underlying type descriptor to be a name.

When the uniqueness constraint applies to multiple columns, how is NULL handled? SQL says uniqueness constraint only considers rows where all the constrained columns have non-null values. This guarantees that if you search a table and specify non-null values for all columns that are part of the uniqueness constraint, then you are guaranteed to get at most one result.

We can problem manage with just primary key constraints to start with.


### Open tables

Does it make sense and would it be useful to allow a table whose inherent type was open i.e. columns can be added dynamically? Particularly in the context of noSQL databases.


### Find function

find supplies fragment of record type as with our match patterns (like in GraphQL)


```
// Module lang.table
public function find(table<RecordType> tbl> tbl,
                       record { *RecordType?; } q)
   returns RecordType[] = external;
```


This would require adding a new type reference syntax:

`record { *T; }` copies all fields of T

`record { *T?; }` copies all fields like *T, but adds ? to each field, making it optional

Is the `find` function sufficiently important to justify adding this? And would this *T? reference add optionality deeply or just for one level?

## Changes

The changes relative to 2019R2 can be divided up as follows:

1. Table rows are ordered
1. Storing a value in a table does an immutable clone; iteration yields immutable records
1. Remove restriction on primary key
1. Change table constructor syntax/semantics
   * Outer brackets are square rather than curly
   * Rows use expressions (typically list constructors), rather than special syntax
   * Different syntax for istinguishing header row from other rows
   * Allow column names in header row to be specified by expression
   * Get rid of auto-increment
   * Get rid of unique
   * Primary key can come from contextually expected type
1. Primary keys
   * Allow 2nd type parameter for primary key record type.
   * E[x] works for table specifying value of primary key as record, both as expression and lvalue
1. Define how toString works for table
1. More extensive lang.table module


## Related changes

*   be able to construct data immutably at runtime without relying on immutable clone
*   refine static typing for list and mapping constructors to allow the contextually expected type to be a record or tuple type descriptor rather than just mapping or list type

## Background

Some other programming languages with a table data type are:

*   [Power Query M](https://docs.microsoft.com/en-us/powerquery-m/power-query-m-language-specification) A functional language from Microsoft (included in Excel) 
*   [Pyret](https://www.pyret.org/) A language intended particularly for CS education, done by some of the people behind Racket
