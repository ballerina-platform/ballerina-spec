# Tables and query

Please add comments to the associated issue [#286](https://github.com/ballerina-platform/ballerina-spec/issues/286).

## Tables

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

### Types and values

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


#### Discussion

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


##### Type parameter

We need to be able to write a type for e.g. table:iterator or table:forEach. If we do this in a similar way to other collections (list, mapping), then table needs to be able to have type parameter that gives the type that we will expose each row as.


```
@typeParam
type RowType map<anydata|error>;
public function forEach(table<RowType> tbl,
    function(RowType row) returns () func) returns () = external;
```


If we don't want to do this, then we need to come up with an alternative solution, which I do not currently see.


##### Column ordering

The type parameter for the table type descriptor could be a tuple or a record. A record will clearly be more convenient. That implies that order is not part of the type, which implies it is not part of the shape, which implies that == will ignore column order.

Nonetheless, given that



*   column order is significant in SQL
*   column order is significant in spreadsheets
*   the natural literal syntax is ordered

I think table _values_ should preserve the order of columns.


##### Row ordering

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


##### Open record types

When a table type descriptor is being used as an abstract type, open record types make perfect sense. We can use table with an open record type to describe a record that has at least a certain set of columns.


##### Auto-increment

Not provided. Preserving ordering makes it redundant.


##### Table member types

The restriction on the types of members comes from mutability. We have to require a type that allows immutable clone.

See below for this.


### Mutability

Key points



*   The members of rows are immutable.
*   The list of column names and inherent type is immutable
*   Tables are mutable: mutation is performed at  the level of a row - by adding, removing or replacing a row
*   When a row is inserted, an ImmutableClone operation is performed on each member (same as happens with error).
*   When a row is retrieved, no clone is performed on the members.
*   The inherent type of the table constrains mutation, as with other structural types


#### Discussion

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


### Direct table type descriptor

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


### Table constructor

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

#### Discussion

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


### Primary keys

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


### Operations


#### Indexed access

E[x] expression and lvalue uses primary key


#### toString

Need to define how toString works. Given that we are using spaces to separate lists, we should use newlines to separate rows. So representation should be something like:


```
    firstName lastName country
    James Clark TH
    Sanjiva Weerawarana SL
```


We could use tabs instead of spaces to separate fields.


### Lang library

See [lang.table module](table.bal).

A lot of this is very similar to lang.map and lang.array.

### SQL interop

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


### Issues

#### Rows vs parameter lists

Is there a parallel between table rows and parameter lists. Both are simultaneously named and ordered. Fundamentally ordered, but offer access by name for convenience.

#### Singleton types

typeof on immutable value has to return singleton type, so we have to have (at least conceptually) singleton types

Can we explain inherent type for immutable values differently, i.e. causing type check to look at current value rather than inherent type. How would this work with typeof?


#### Uniqueness constraints

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


#### Open tables

Does it make sense and would it be useful to allow a table whose inherent type was open i.e. columns can be added dynamically? Particularly in the context of noSQL databases.


#### Find function

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

### Changes

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

### Background

Some other programming languages with a table data type are:

*   [Power Query M](https://docs.microsoft.com/en-us/powerquery-m/power-query-m-language-specification) A functional language from Microsoft (included in Excel) 
*   [Pyret](https://www.pyret.org/) A language intended particularly for CS education, done by some of the people behind Racket


## Query

Basic idea is to take C# LINQ as the starting point.


### Table query basics


```
query-expr := (foreach-clause [where-clause])+ select-clause
foreach-clause := "foreach" typed-binding-pattern "in" expression	
where-clause := "where" expression
select-clause := "select" expression
```


This would work as follows:


*   the foreach-clause works like the existing `foreach` statement
    *   the expression would evaluate to a table value
    *   the typed-binding-pattern gets bound successively to the record representing each row
    *   the typed-binding-pattern would often include a mapping-binding-pattern
    *   any variables bound by the typed-binding-pattern are in scope in the where-clause and the select-clause
    *   multiple foreach clauses are similar to a join 
*   the where-clause would use a boolean expression
*   the expression in the select-clause would typically be a mapping constructor expression

The static typing of mapping constructor expr will need to be refined to work as expected in the select-clause, since the spec currently makes the contextually expected type of a mapping constructor expr be map<T> if there is no contextually expected type.


#### Discussion

##### Comprehensions

An SQL query is in essence a table comprehension. It consists of


*   iterating over rows
*   for each row binding variables to columns of the row
*   filtering out some rows using a condition that uses a bound variables
*   creating a new row using bound variables for each remaining row 
*   creating a table from all these rows

We already have constructs in the language to do much of this


*   foreach iterates over the row
*   record binding pattern binds variable
*   if with boolean condition expresses condition (in if statement and match clause)
*   a record constructor can create a new row
*   a table constructor creates a table from a number of rows


##### C# LINQ syntax

The syntax proposed above (including the exact choice of keywords is inspired from the C# LINQ syntax, but is adapted to use constructs that already exists in the language. C# also provides more clauses, which we can incorporate:



*   join
*   group
*   orderby


##### Examples

Assuming


```
type Person record {|
   string firstName;
   string lastName;
   string country;
|};
table<Person> peopleTable;
```


We could write


```
var x =
   foreach var person in peopleTable
   where person.country == "UK"
   select {
       firstName: person.firstName,
       lastName: person.lastName
   };
```


or


```
var x =
   foreach var { firstName: nm1, lastName: nm2, country: c } in peopleTable
   where c == "UK"
   select { firstName: nm1, lastName: nm2 };
```


This can be shortened to:


```
var x =
   foreach var { firstName, lastName, country } in peopleTable
   where country == "UK"
   select { firstName: firstName, lastName: lastName };
```


but we should also have a shortcut mapping constructor syntax to parallel the shortcut mapping binding pattern syntax, so you can write:


```
var x =
   foreach var { firstName, lastName, country } in peopleTable
   where country == "UK"
   select { firstName, lastName };
```


The inferred type of x would be:


```
table<record {| string firstName; string lastName; |}>
```


We also should make spread operator work in mapping constructors:


```
var x =
   foreach var { country, ...rest } in peopleTable
      where country == "UK"
      select { country, ...rest }
```



##### Keywords

C# uses `from` instead of `foreach` presumably following SQL. However I don't think `from` reads well when it is before the `select`, as it must be to ensure that declarations always lexically precede their usage.


```
var x =
   from var { firstName, lastName, country } in peopleTable
     where country == "UK"
     select { firstName, lastName };
```


More importantly, foreach in a query is conceptually doing exactly the same thing as foreach in the existing foreach statement, i.e. binding a variable to successive members of an iteration.

For uniformity, we could also allow our existing `foreach` statement to have a where clause.

The reason to stick with `select` rather a keyword that suggests addition (e.g. `add` or `insert`) is to avoid making it seem that this mutates an existing table, particularly if we have keywords `update` and `delete` that do mutate (see below).


### Query for other structured types

The expression in the from-clause can be anything iterable (as with foreach).

A query-expr can construct not only tables but values of other structured types, specifically lists and xml. The type of thing constructed depends on the contextually expected type and the type of the expression in the from clause



*   if the contextually expected type allows only one of list, xml and table, then that is what is constructed
*   otherwise, the type of the from clause determines what is constructed.


#### Discussion

In C# the query syntax is sugar that maps onto a variety of complex method calls making sophisticated use of parameterized types. The result will be an IEnumerable<T> for some T. In our case, we want the query syntax to simply produce a table. However, the comprehension concept (and indeed syntax) works just as well for lists (and other iterable collections) as it does for tables. [List comprehensions](https://en.wikipedia.org/wiki/List_comprehension) are a well-established feature of [many programming languages](https://en.wikipedia.org/wiki/Comparison_of_programming_languages_(list_comprehension)). The key XQuery feature (the FLWOR statement) is essentially just a comprehension over XML sequences.

With a comprehension, you have a source collection type and a result collection type. These do not have to be the same. It is straightforward to allow the expression in the from clause to be anything iterable, just as with foreach. The problem is how to decide what the type of the result collection should be.

The second part of the rule given above is motivated by consistency with the map/filter functions, which always construct a result of the same basic type as their first argument.

An alternative would be to use the type of the select clause:



*   if the type is record, construct a table
*   if the type is xml, construct and xml sequence
*   otherwise, construct a list

Another alternative would be use a keyword other than select when constructing xml or list values.

Note that the type of <T>E is the intersection of T and the static type of E. So you can use <table>query-expr to construct a table from a list, without having to specify the precise type of the table.


##### Constructor syntax

An alternative approach is to use a comprehension syntax based on the constructor syntax. This is the usual syntactic approach for list comprehensions e.g. [Python](https://docs.python.org/3/tutorial/datastructures.html#list-comprehensions). Applying this approach to lists for Ballerina, would give something like


```
list-comprehension-expr :=
  "[" (foreach-clause [where-clause])+ select-clause "]"
foreach-clause := "foreach" typed-binding-pattern "in" expression
where-clause := "where" expression
select-clause := "select" expression
```


For example:


```
var list = [foreach var i in 1 ..< 10 where i % 2 = 0 select i]
```


We could use add instead of select


```
var list = [foreach var i in 1 ..< 10 where i % 2 = 0 add i]
```


Applying this to tables would give us something like this:


```
var x =
   table [
      foreach var { firstName, lastName, country } in peopleTable
      where country == "UK"
      add { firstName, lastName }
    ]
```


I'm not sure if I like this better.  It feels a little better to me with curly braces:


```
var x =
   table {
      foreach var { firstName, lastName, country } in peopleTable
      where country == "UK"
      select { firstName, lastName }
    }
```


Problems with this:



*   does not extend to update/delete
*   does not extend (at least not obviously) to XML
*   does not extend to aggregations


### [Incomplete] Query sorting

We want something like this to work:


```
foreach var { firstName, lastName, country } in peopleTable
   where country == "UK"
   orderby firstName, lastName
   select { firstName, lastName };

foreach var person in peopleTable
  orderby person.firstName, person.lastName
  select person;
```


The orderby clause conceptually specifies a function from a row to a sequence of values, which is used to sort the rows.

We want to allow this to do the right i18n thing without building this into the core language (different locales need different sort orders). Probably the orderby clause needs to be able to reference a collation object that can be provided by a standard library module.

This should work for lists and xml as well.

The static type of the expressions in the orderby clause must be _ordered_, where the following rules determine whether a type is ordered:



*   a subtype of a simple basic type is ordered
    *   strings are ordered as with codePointCompare
    *   numbers are ordered by <
        *   -0.0f is before +0.0f
        *   need to say how NaN is handled (IEEE has a totalOrder function)
*   if T is ordered, T? is ordered; nil comes first
*   if T is ordered, T[] is ordered; ordering is lexicographic


### Joins

C# LINQ does this quite nicely:


```
join-clause :=
  "join" typed-binding-pattern "in" iterable-expr
  "on" left-expr "equals" right-expr
```


This does an inner equi-join (which is the most useful kind of join).

There's some SQL-funkiness as regards handling NULL.


### Grouping

```
group-clause :=
   "group" construct-expr "by" group-expr "into" typed-binding-pattern
```

`construct-expr` and `group-expr` are evaluated once for each iteration yielding values c and g.
For each distinct (using `==`) value of g

*  a list is constructed of all corresponding values of c,
*  the list is bound to typed-binding-pattern
*  the following clauses of the query are executed with the variables bound by typed-binding-pattern in scope

TBD: also variant without `into`.

XXX: How to determine the result? Typically with `into` the result will be a list.

### Aggregation

TBD 


*   sum, average, count etc
*   make sense for lists and xml too
*   not in C# LINQ syntax
*   not a comprehension

For things that are using the value of a field, this feels natural to me:


```
    foreach var employee in employeeTable
    sum employee.salary
```


i.e. use an aggregating keyword instead of select (we don't want to reserve these as keywords in expressions generally).

But for count this would mean:


```
    foreach var employee in employeeTable count
```


which feels a bit weird. You could just do:


```
    foreach var employee in employeeTable sum 1
```


Or maybe


```
    count foreach var employee in employeeTable
```


Or do nothing in which case

```
     (foreach var employee in employeeTable select employee).length()
```


would work.


### Update

SQL has update statement (which mutates a table). I think we can make something similar work, e.g:


```
    foreach var employee in employeeTable
    where employee.rating >= 5
    update { salary: employee.salary + 1000 }
```


Semantics are that the row is replaced by a row with the specified fields changed. For this to work the expression after `in` has to evaluate to a table.


### Delete

SQL has a delete statement. I think we can make something similar work, e.g.


```
    foreach var employee in employeeTable
    where employee.rating >= 5
    delete
```


or


```
    delete foreach var employee in employeeTable
    where employee.rating >= 5
```


This is different from the filter function in that it mutates the table. Syntactically, this has some similarities with `count`.


## Related changes



*   pure functions (which can only access data through parameters, module-level consts and other pure functions)
*   be able to construct data immutably at runtime without relying on immutable clone
*   refine static typing for list and mapping constructors to allow the contextually expected type to be a record or tuple type descriptor rather than just mapping or list type
*   allow `foreach` statements to have a `where` clause
*   abbreviated form of mapping constructor (where field is just an identifier), analogous to abbreviated form of mapping binding pattern
*   function on typedesc to test whether a value belongs to the type (or would it be better to do this with is-expr?)


