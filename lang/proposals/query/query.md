# Query

Please add comments to the associated issue [#355](https://github.com/ballerina-platform/ballerina-spec/issues/355).

There is an [experimental](https://ballerina.io/spec/lang/2019R3/experimental.html#section_3.1) implementation of a query facility for Ballerina, which builds on the table and stream features.

[List comprehensions](https://en.wikipedia.org/wiki/List_comprehension) are a well-established feature of [many programming languages](https://en.wikipedia.org/wiki/Comparison_of_programming_languages_(list_comprehension)). At a high level, queries can be viewed as a kind of comprehension. They consist of:

*  iterating over some kind of collection
*  for each member of the collection
      * binding variables
      * using those variables to perform a boolean test
      * if the test succeeds, using those variables to produce some new values
*  constructing a new collection using the values produced in the iteration

An SQL select statement is a kind of comprehension that iterates over the rows of a table.
The XQuery FLWOR statement is a kind of comprehension that iterates over XML sequences.

C# provides a sophisticated language-integrated query (LINQ) facility, with an SQL-like syntax, which is a generalized and sophisticated kind of list comprehension.

This document proposes a simple form of language-integrated query for Ballerina, with a syntax similar to C#.

## Query basics

In its simplest form, a query has the following syntax:

```
query-expr := (foreach-clause [where-clause])+ select-clause
foreach-clause := "foreach" typed-binding-pattern "in" expression	
where-clause := "where" expression
select-clause := "select" expression
```

A `query-expr` is a kind of comprehension that builds on existing Ballerina language elements:

*   the `foreach-clause` iterates and binds variables
    *   it works like the existing `foreach` statement
    *   the `in` expression must result in an iterable value, which is used to create an iterator object
    *   an iterator object is created from the iterable value
    *   the typed-binding-pattern can use destructuring to bind multiple variables
    *   any variables bound by the typed-binding-pattern are in scope in the where-clause and the select-clause
    *   multiple foreach clauses are similar to a join 
*   the `where` clause uses a boolean expression to filter
*   the `select` clause produces values, which become members of the constructed collection

A common case is to query some kind of collection of records, where the collection might be a list, a table or a stream. In this case:

*   the typed-binding-pattern would often include a mapping-binding-pattern
*   the expression in the select-clause would typically be a mapping constructor expression

A `query-expr` is not restricted to constructing lists. The type of value constructed is determined as follows:

1. If there is a contextually expected type that allows only one basic type of structure, then the contextually expected type determines what is constructed.
2. Otherwise, it constructs the same kind of thing it is iterating over. In other words the type of the `in` expression in the foreach-clause determines what is constructed. To make this work in an extensible way with objects representing collections, we will need a richer `Queryable` interface similar to `Iteratable` that allows for construction. This could also support queries that mutate collections (see below)

In the first case, the contextually expected type for the `query-expr` will determine the contextually expected type for the expression in the select clause. For the second case, the static typing of mapping constructor expr will need to be refined to work as expected in the select-clause, since the spec currently makes the contextually expected type of a mapping constructor expr be `map<T>` if there is no contextually expected type.

### Examples

Assuming


```
type Person record {|
   string firstName;
   string lastName;
   string country;
|};
Person[] personList;
```


We could write


```
var x =
   foreach var person in personList
   where person.country == "UK"
   select {
       firstName: person.firstName,
       lastName: person.lastName
   };
```


or


```
var x =
   foreach var { firstName: nm1, lastName: nm2, country: c } in personList
   where c == "UK"
   select { firstName: nm1, lastName: nm2 };
```


This can be shortened to:


```
var x =
   foreach var { firstName, lastName, country } in personList
   where country == "UK"
   select { firstName: firstName, lastName: lastName };
```


but we should also have a shortcut mapping constructor syntax to parallel the shortcut mapping binding pattern syntax, so you can write:


```
var x =
   foreach var { firstName, lastName, country } in personList
   where country == "UK"
   select { firstName, lastName };
```


The inferred type of x would be:


```
record {| string firstName; string lastName; |}[]
```


We also should make spread operator work in mapping constructors:


```
var x =
   foreach var { country, ...rest } in personList
      where country == "UK"
      select { country, ...rest }
```

### Discussion

#### Keyword syntax

The syntax proposed above is inspired by C# LINQ (which was in turn inspired by SQL). C# uses `from` instead of `foreach` presumably following SQL. However I don't think `from` reads well when it is before the `select`, as it must be to ensure that declarations always lexically precede their usage.


```
var x =
   from var { firstName, lastName, country } in personList
     where country == "UK"
     select { firstName, lastName };
```


More importantly, `foreach` in a query is conceptually doing exactly the same thing as foreach in the existing `foreach` statement, i.e. binding a variable to successive members of an iteration.

For uniformity, we could also allow our existing `foreach` statement to have a where clause.

The reason to stick with `select` rather a keyword that suggests addition (e.g. `add` or `insert`) is to avoid making it seem that this mutates an existing table, particularly if we have keywords `update` and `delete` that do mutate (see below).

A keyword-based syntax enables adding more clauses to provide richer query functionality. For example, C# provides `join`, `group` and `orderby` clauses.

#### What to construct?

The proposed SQL-like syntax creates an important design problem. What type of structure does the `query-expr` construct?

The proposed rule that a query-expr should by default create a collection of the same kind as it is iterating over is motivated by consistency with the map/filter functions, which always construct a result of the same basic type as their first argument.

In C# the query syntax is sugar that maps onto a variety of complex method calls making sophisticated use of parameterized types. The result will be an `IEnumerable<T>` for some T. In our case, we want the query syntax to simply produce a table. However, the comprehension concept (and indeed syntax) works just as well for lists (and other iterable collections) as it does for tables. 

With a comprehension, you have a source collection type and a result collection type. These do not have to be the same. It is straightforward to allow the expression in the from clause to be anything iterable, just as with foreach. The problem is how to decide what the type of the result collection should be.

An alternative would be use a keyword other than select when constructing xml or list values.

Note that the type of `<T>E` is the intersection of T and the static type of E. So you can use `<table>query-expr` to construct a table from a list, without having to specify the precise type of the table.

#### Constructor-based syntax

There is an alternative syntactic approach based on constructor syntax, which makes explicit the kind of thing that is explicit. This is the usual syntactic approach for list comprehensions e.g. [Python](https://docs.python.org/3/tutorial/datastructures.html#list-comprehensions). Applying this approach to lists for Ballerina, would give something like


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


Applying this to tables might give us something like this:


```
var x =
   table [
      foreach var { firstName, lastName, country } in personList
      where country == "UK"
      add { firstName, lastName }
    ]
```


I'm not sure if I like this better.  It feels a little better to me with curly braces:


```
var x =
   table {
      foreach var { firstName, lastName, country } in personList
      where country == "UK"
      select { firstName, lastName }
    }
```


Problems with this approach:


*   does not extend to update/delete
*   does not extend (at least not obviously) to XML
*   does not extend to aggregations


## [Incomplete] Query sorting

We want something like this to work:


```
foreach var { firstName, lastName, country } in personList
   where country == "UK"
   orderby firstName, lastName
   select { firstName, lastName }

foreach var person in personList
  orderby person.firstName, person.lastName
  select person
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


## Joins

C# LINQ does this quite nicely:


```
join-clause :=
  "join" typed-binding-pattern "in" iterable-expr
  "on" left-expr "equals" right-expr
```


This does an inner equi-join (which is the most useful kind of join).

There's some SQL-funkiness as regards handling NULL.


## Grouping

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

## Aggregation

TBD 


*   sum, average, count etc
*   make sense for lists and xml too
*   not in C# LINQ syntax
*   not a comprehension

Something like this would be possible:


```
    foreach var employee in employeeTable
    sum employee.salary
```


i.e. use an aggregating keyword instead of select, but it's not very extensible,
and it would be weird for `count`.


```
    foreach var employee in employeeTable count
```


An alternative would be too put the aggregation up front:


```
    count foreach var employee in employeeTable
```

Then `sum` might become

```
     sum foreach var employee in employeeTable select employee.salary
```

More thought is needed on this.

## Insert into

SQL has an INSERT INTO statement that allows rows to be added to a table.

We can provide similar functionality via a query statement that does not use the values produced to construct a new structure, but instead adds them to an existing structure. For example:


```
    foreach var employee in employeeTable
    where employee.rating >= 5
    insert employee into goodEmployeeTable;
```


## Mutation

SQL provides statements that mutate the table being iterated over. This cannot be supported by Ballerina's existing iterator interface; a richer interface would be needed.

### Update

SQL has update statement (which mutates a table). We could do something similar, e.g.:

```
    foreach var employee in employeeTable
    where employee.rating >= 5
    update { salary: salary + "1000" };
```

Semantics are that the row is replaced by a row with the specified fields changed. For this to work the expression after `in` has to evaluate to a table.

### Delete

SQL has a delete statement. We could do something similar, e.g.:


```
    foreach var employee in employeeTable
    where employee.rating < 2
    delete;
```

or

```
    delete foreach var employee in employeeTable
    where employee.rating < 2;
```

This is different from the filter function in that it mutates the table. Syntactically, this has some similarities with `count`.

## Streaming query

XXX

## Related language changes


*   refine static typing for list and mapping constructors to allow the contextually expected type to be a record or tuple type descriptor rather than just mapping or list type
*   allow `foreach` statements to have a `where` clause
*   abbreviated form of mapping constructor (where field is just an identifier), analogous to abbreviated form of mapping binding pattern
*   make spread operator work in mapping constructor
