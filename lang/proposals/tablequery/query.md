# Query

Basic idea is to take C# LINQ as the starting point.


## Table query basics


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


### Discussion

#### Comprehensions

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


#### C# LINQ syntax

The syntax proposed above (including the exact choice of keywords is inspired from the C# LINQ syntax, but is adapted to use constructs that already exists in the language. C# also provides more clauses, which we can incorporate:



*   join
*   group
*   orderby


#### Examples

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



#### Keywords

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


## Query for other structured types

The expression in the from-clause can be anything iterable (as with foreach).

A query-expr can construct not only tables but values of other structured types, specifically lists and xml. The type of thing constructed depends on the contextually expected type and the type of the expression in the from clause



*   if the contextually expected type allows only one of list, xml and table, then that is what is constructed
*   otherwise, the type of the from clause determines what is constructed.


### Discussion

In C# the query syntax is sugar that maps onto a variety of complex method calls making sophisticated use of parameterized types. The result will be an IEnumerable<T> for some T. In our case, we want the query syntax to simply produce a table. However, the comprehension concept (and indeed syntax) works just as well for lists (and other iterable collections) as it does for tables. [List comprehensions](https://en.wikipedia.org/wiki/List_comprehension) are a well-established feature of [many programming languages](https://en.wikipedia.org/wiki/Comparison_of_programming_languages_(list_comprehension)). The key XQuery feature (the FLWOR statement) is essentially just a comprehension over XML sequences.

With a comprehension, you have a source collection type and a result collection type. These do not have to be the same. It is straightforward to allow the expression in the from clause to be anything iterable, just as with foreach. The problem is how to decide what the type of the result collection should be.

The second part of the rule given above is motivated by consistency with the map/filter functions, which always construct a result of the same basic type as their first argument.

An alternative would be to use the type of the select clause:



*   if the type is record, construct a table
*   if the type is xml, construct and xml sequence
*   otherwise, construct a list

Another alternative would be use a keyword other than select when constructing xml or list values.

Note that the type of <T>E is the intersection of T and the static type of E. So you can use <table>query-expr to construct a table from a list, without having to specify the precise type of the table.


#### Constructor syntax

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


## [Incomplete] Query sorting

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


## Update

SQL has update statement (which mutates a table). I think we can make something similar work, e.g:


```
    foreach var employee in employeeTable
    where employee.rating >= 5
    update { salary: employee.salary + 1000 }
```


Semantics are that the row is replaced by a row with the specified fields changed. For this to work the expression after `in` has to evaluate to a table.


## Delete

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


*   refine static typing for list and mapping constructors to allow the contextually expected type to be a record or tuple type descriptor rather than just mapping or list type
*   allow `foreach` statements to have a `where` clause
*   abbreviated form of mapping constructor (where field is just an identifier), analogous to abbreviated form of mapping binding pattern

