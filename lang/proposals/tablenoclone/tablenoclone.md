# Non-cloning tables

lease add comments to the associated issue [#47](https://github.com/ballerina-platform/ballerina-spec/issues/47).

## Goals

A table is a collection of records where each record is uniquely identified in the collection by one or more fields. It can be thought of as a general-purpose hash table, where the keys are "inline" i.e. the keys are part of the values being stored in the hash table. A key design principal of Ballerina is to make extensive use of a few, built-in general-purpose collection data types, rather than use a large number of special purpose, library-defined collection types. Table is designed to be an addition to this set of built-in collection types, which complements the existing list and mapping types.

The table type is useful whenever an application wants to represent a collection of entities, where each entity has a key that uniquely identifies it within the collection. One obvious example is data from a relational database table with a primary key. CSV files and spreadsheets are also often used to represent such collections. It is a situation that occurs in many applications: it is table as in "hash table" or "symbol table", not just table as in "relational database table".

The existing structural data types (list and mapping) don't work well in this case:

*   map doesn't work well when the key isn't just a string
*   map work well with query because the key and the value are separate
*   list doesn't work well because you don't have efficient access using the key
*   list and map aren't enough to make query join work with reasonable performance

Query joins are important, because one of the key scenarios for doing query in Ballerina rather than in the database is when you want to combine data from multiple data sources.

The main difference in this proposal for tables, as compared to the [previous proposal](https://github.com/ballerina-platform/ballerina-spec/blob/master/lang/proposals/table/table.md), is to make tables behave in a more uniform way to lists and mappings. Specifically:


*   a table value has members, where each member is a mapping value representing a row of the table
*   adding a row to a table and getting a row from a table does not require the mapping to be cloned

To make this work, the inherent type of a mapping that is a member of a table must prevent both storing a new value in a key field and mutating the value of a key field. The [proposal](https://github.com/ballerina-platform/ballerina-spec/blob/master/lang/proposals/immutable/immutable.md) for improved immutability provides the building blocks to enable this.

In this proposal, it is _not_ a goal to allow a table to be a transparent proxy for a persistent table in an SQL database. This was found not to combine well with Ballerina's explicit approach to error handling: errors in SQL database access caused by network unreliability or transaction failure need to be surfaced as error results. This makes SQL database access very different from access to members of a built-in collection.

Note that since members aren't cloned, a single record can be a member of multiple tables. This allows a database table with a foreign key column to be mapped into an in-memory table whose members are records with a field with record type that refers to a record that is a member of another table.

## Proposal overview

Suppose we have a simple record type:

```
type Customer record {
   # unique identifier of customer
   int id;
   string name;
};
```

To use this in a table, the first step is to make the id field readonly:


```
type Customer record {
   # unique identifier of customer
   readonly int id; 
   string name;
};
```

This means that not only is the the type of the value of the field readonly (i.e. the value cannot be mutated), but the field itself cannot be mutated (i.e. you cannot assign a value to the id field).

A table type can then be declared like this:


```
type CustomerTable table<Customer> key(id);
```

This means that

*   the CustomerTable type has members that are customers, and
*   within a CustomerTable each member is uniquely identified within the table by its id field.

It is a compile-error to use `key(f)` unless f is readonly.

Once you have a table, the key can be used to access the members like with mappings:

```
CustomerTable tab;

function changeName(int id, string name) returns Customer? {
   Customer? c = tab[id];
   if c != () {
     c.name = name;
  }
  return c;
}
```

As with mappings and xml, if you know the key exists, you can use a function, which will panic rather than returning nil if the key does not exist:

```
Customer c = tab.get(id);
```

A table constructor works like a list constructor:

```
CustomerTable tab = table [
  { id: 1, name: "John Smith" },
  { id: 2, name: "Joe Bloggs" }
];
```


The constructor for `table<T>` is like that for `T[]`, except that it has a `table` keyword in front.

The table preserves the order of its members. Iterating over the table gives the members of the table in order.

The table constructor can be used without a contextually expected type by specifying the key in the table constructor:

```
var tab = table key(id) [
  { id: 1, name: "John Smith" },
  { id: 2, name: "Joe Bloggs" }
];
```

Note that this will imply `readonly` for the `id` field of the mapping constructors of the table members.

A table can have a key that comes from multiple fields:

```
type Customer record {
   readonly string countryId;
   # unique identifier of customer within country
   readonly int id;
   string name;
};
type CustomerTable table<Customer> key(countryId, id);
```

In this case the key is represented by a tuple [string, int].

```
[string,int] id = ["GB", 1];
Customer? c = tab[id];
// or
c = tab[["GB", 1]]; // ugly
c = tab["GB", 1]; // allow this also
```

Since it's ugly to say `tab[["GB", 1]]`, we allow that to be written `tab["GB",1]`. But the get function needs the tuple, e.g.

```
c = tab.get(["GB", 1]);
```


We also allow `key<T>` in order to enable us to write the type of `get` in lang.table:

```
public function get(table<Type> key<KeyType> tab) returns KeyType;
```

In the above example `KeyType` would be `[string,int]`.

A type `table<T>` without any following key qualifier means a table with member type T, and provides no information about which fields are keys. Like map<T> and T[] it is covariant in T i.e. `table<S>` is a subtype of `table<T>` if S is a subtype of T.

A table can also have no keys. The type of such a table is `table<T> key()`. Both `table<T> key ()` and `table<T> key(f)` are subtypes of `table<T>`. The type table<T> is abstract in the sense that it cannot be the inherent type of a table:

the inherent type of a table also has a specific (possible empty) sequence of keys. Note that `table<T> key ()` is equivalent to `table<T> key<never>`, so t.get(x) will not compile (since there is no value x that belongs to type `never`).

The types of the built-in functions illustrate the differences between the above cases. Note that filter preserves the "keyness" of its argument.

```
function forEach(table<Type> table,
                function(Type val) returns () func)
   returns ();
function 'map(table<Type> tab,
              function(Type val) returns Type1 func)
   returns table<Type1> key<never> = external;
function filter(table<Type> key<KeyType> tab,
                function(Type val) returns boolean func)
   returns table<Type> key<KeyType> = external;
```

A query-expr can specify the key fields like a table constructor

```
var tab2 =
   table key(id)
      from var { id, name } in tab
         select { id, name };
```

This has the same effect as: 

```
var tab2 =
   <table<*> key(id)>
      from var { id, name } in tab
         select { id, name };
```

In the absence of a contextually expected type, a query-expr whose source type is table will create a table (as with other basic types).

A mapping constructor can use readonly to make a field readonly, e.g.

```
  { readonly id: 1, name: "John Smith" }
  { readonly id, name }
```

When the readonly fields in a select clause come from a table that has those fields as its keys, a query-expr can infer a key qualifier for the type of the constructed table (similar to filter). As a trivial example, in the following:

```
 var tab2 =
   from var { id, name } in tab
       select { readonly id, name };
```

if `tab` has type table<T> key(id), then the inferred type of tab2 will be table<T'> key(id).

When a table is used in a join whose join condition refers to the key fields, the query does not iterate over the table, but instead does a lookup.

Conversion of a table to json produces a list of mappings.

## Design points

*   table type descriptor has member type as type parameter
*   multipart keys are represented as tuples rather than records
*   which fields are key fields is determined by type descriptor of the table not of the member
*   key syntax similar to SQL primary key syntax
*   simple syntax that reuses syntactic constructs that already exist
*   key descriptor used uniformly in type descriptor, constructor and query
*   a single record can be a member of multiple tables with different keys in each; we can provide the functionality of a database table with both a primary key and a unique constraint by using two tables with the same members

### Readonly fields

Note that the following two types are equivalent:

```
    record {| readonly T1 x; readonly T2 y; |}
    readonly<record {| T1 x; T2 y; |}>
```

but this is different:

```
    record {| readonly<T1> x; readonly<T2> y; |}
```

I chose the syntax:

    ` readonly T x;`

rather than:

     `final readonly<T> x;`

because:

*   final is for variables not members, and members of values are different from variables
    *   with a variable you declare it and potentially initialize it later
    *   with a member, you construct a structure which has a member with a given value 
*   readonly for members is connected to readonly types in a way that final is not
*   the important and useful case is when both the member and its value are immutable, so this case should be simple

## Specification

[in progress]

### Table type

```
table-type-descriptor :=
  concrete-table-type-descriptor | abstract-table-type-descriptor

concrete-table-type-descriptor :=
  "table" type-parameter key-descriptor
key-descriptor := "key" "(" [ field-name ("," field-name)* ] ")"
abstract-table-type-descriptor :=
  "table" type-parameter ["key" type-parameter]
```

In `table<R>`, R must be a subtype of `map<any|error>`. Furthermore, in a concrete table type `table<R> key(f1, f2,...,fN)`, R must refer to a single record type descriptor with an individual field f<sub>i</sub> for each i and

*   f<sub>i</sub> must not be optional
*   type of f<sub>i</sub> is a subtype of anydata
*   f<sub>i</sub> is a readonly member

A table value has a "key sequence", which is  an ordered sequence of the names of the fields that together uniquely identify each member of the table. The key sequence is part of the shape, but is not part of the primary aspect of the shape and so does not affect `==`.

When a mapping is added to a table, if the value of any of the key fields has a cycle it should be a panic. If a value has been entirely constructed as readonly, then the implementation knows that it does not have cycles; only if cloneReadOnly has been used can cycles occur. The implementation will need to hash the keys. When it does so, it needs to check for cycles coming from cloneReadOnly and panic rather than blow up. 

### Table constructor

```
table-constructor-expr :=
  "table" [key-descriptor] "[" [expr-list] "]"
```

### Table query

```
table-query-expr := "table" [key-descriptor] query-expr
```

Issue:
*   How to deal with duplicate keys? Probably error result is best. In some cases, can statically determine that duplicate is impossible, in which case the static result type would not include error. Other possibilities
    *   panic
    *   last one wins
    *   first one wins


### Other changes

*   record type allows field descriptor to use readonly
*   mapping constructor allows field to be readonly
*   table join uses lookup rather than iteration for tables
*   in a query expression when source type is table and there is no contextually expected type, result type is table; result type will have key qualifier if statically known that there are readonly keys with no duplicates
*   member access t[k] works for table (not allowed when key type is never)
*   definition of anydata allows table<map<anydata>>> not arbitrary table


### Lang library

These all have analogues in lang.map:

*   length
*   iterator
*   get
*   map
*   forEach
*   filter
*   reduce
*   remove
*   removeIfHasKey
*   removeAll
*   hasKey
*   keys
*   toArray


```
# When the key is an int, find the next available key.
# This is maximum used key value + 1, or 0 if no key used
# XXX should it be 0, if the maximum used key value is < 0?
# Provides similar functionality to auto-increment
function nextKey(table<Type> key<IntType> tab) returns int;
```

## Ideas (not yet stable)

### Syntax to avoid field name repetition

It would be convenient to have a syntax, which should work for both list and table constructors, to avoid the need to repeat field key names when you a list/table of records with the same keys.

Semantically, the idea is that the first member of the list/table constructor is a special header row specifying the field names; this special header row causes the result of evaluating  each of the subsequent members of the list to be converted from a tuple to a record. To make this work, the header row must use syntax that is not a valid expression.

Ideas:

```
    [
      {id, name, country}: // header row
      [ 1, "John Smith", "GB" ], // list-constructor-expr
      [ 2, "Fred Bloggs", "GB" ]
    ]
```


This gives us typesafe conversion from arrays of tuples to arrays of records.


```
    [int,string,string][] tuples = [
      [ 1, "John Smith", "GB" ], 
      [ 2, "Fred Bloggs", "GB" ]
    ];
    record {
       int id;
       string name;
       string country;
    }[] records = [
      { id, name, country }:
       ...tuples
    ]
```

### Tuples with header row

It is very common (e.g. CSV and spreadsheets) to represent tabular data as an sequence of rows, where each row is a sequence of ordered fields, and the first row contains strings giving the name of the column.

It ought to be easy to convert between this representation and an array of mappings.

Given a record type such as


```
  type R record {
     int A;
     string B;
  };
```


a type `table<R>` or `R[]` has a natural representation in tuple form, with a tuple giving the headers and then a tuple for each rows. We can almost represent the type for this by the type:

```
 [["A", "B"], [int, string]...]
```

except that the columns can be in any order. This is leveraging both singleton types and tuple rest types.

We have a keys method on maps which gives us the keys: we could also have a values method that gives us the values in the same order. But there is no guarantee currently that if you have a list of mappings of a closed type, that the keys will also be in a consistent order.

For a single tuple/record conversion we can just use destructuring and construction.


### Generalize key to key path

We could allow `key(x.y)` to mean that the key comes from the field y of the value of field x.

(Web DB API IndexedDB has this.)


### Tuples as table members

We could extend this proposal to allow tables of tuples as well as tables of mappings


*   needs key(N) as well as key(field)
*   needs readonly tuple members
*   underlying reality of spreadsheets/SQL tables are that rows are tuples

### Objects as table members

If we allow final fields for objects, we could have tables that have objects of members with the final fields giving the key.

Might be useful for ORM.

### Ordered keys

Another model would be that keys are ordered. There is a "natural" order for:


*   int
*   float (except NaN)
*   decimal
*   boolean
*   string
*   arrays

Allows additional operations e.g. next entry with key greater than some specified value.

Problems:

*   existing map does not expose key order
*   code point string order is arbitrary
*   ordering different basic types is arbitrary
*   if we allow user to control order with a function, then
    *   not really anydata
    *   hard to do at compile time

### Indexing of other fields

We could have a built-in function that suggests that a table maintain an index for the values of a readonly field that is not a key field. This would affect only performance, by making queries that test for equality on that field go faster.

```
customers.maintainIndex("country"); // "country" must be readonly
var ukCustomers =
   from customer in customers
      where customer.country = "UK" // runs fast
      select customer;
```

### Persistence

There is potentially a restricted kind of persistence that we could support transparently on top of table:

*   `table<T>` where T is subtype of anydata and readonly
*   T does not have storage identity
*   persistence on top of embedded key-value store library (LevelDB, RocksDB)
*   DB error conditions would be panics (probably OK since caused by things like out of disk space, which are not dissimilar to things that already cause panics)
*   need to think further about transactions aspect

