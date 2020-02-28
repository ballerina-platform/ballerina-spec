# Improved support for immutability

This is issue #[338](https://github.com/ballerina-platform/ballerina-spec/issues/338).

## Problem


### Immutability

The overall goal here is to incorporate immutability into the type system somehow.

Immutability in Ballerina at the moment has limitations:


*   values cannot be directly constructed as immutable (with the exception of compile-time const) - instead values have to be constructed as mutable and then reconstructed as immutable by using an immutable clone
*   the user has to explicitly do the immutable clone on each value; there is no way for the type descriptor to make that happen automatically
*   there is no way to have a compile-time guarantee that a value constructed elsewhere at runtime is immutable, and thus safe for use from multiple threads; you have to explicitly do an immutable clone
*   attempts to write to immutable values are not detected at compile time
    *   this is to some degree inherent in making immutable a subtype of unqualified types
    *   but with immutability in types, the compiler/IDE could potentially help the user avoid simple errors

Making it easy and natural to use immutable values in a functional style is a good thing for multiple reasons:



*   subtyping works more simply and flexibly; there is no need to know about the inherent type; if a value looks like a type, it belongs to the type
*   good for concurrency safety
*   works well with declarative data transformation
*   works well with query
*   functional style helps reliability generally
*   immutable _types_ enable implementation optimizations


### Storage identity

When a value is always constructed as immutable, there is no point in its having a storage identity. It would be better for it to have pure "value" semantics, like the current string type. Such a value can be transparently persisted: serializing and deserializing v will result in a value that is indistinguishable from v. There is an important conceptual/modelling distinction between a mutable value with identity (i.e. an entity) and an immutable value without identity (i.e. attributes of entities); at the moment, Ballerina can only represent this properly in the case where attributes are simple values, which is not always the case.

The goal therefore to have structured types (lists, mappings) with "value" semantics. In the terminology of the Ballerina spec, this would mean values of the type



*   are not mutable
*   do not have storage identity
*   are === if and only if their members are ===

Typical examples would be:


*   `byte[]` representing binary data
*   `record {| int year; int month; int day; |}` representing calendar date

The objective is to add something to the type descriptor, so that the compiler can ensure at compile-time that values declared using that type descriptor have value semantics. A `byte[]` type with this addition would have value semantics in the same way that  the string type now does (difference is that the members of byte[] are a subtype of int).

Key use cases:



*    in working with SQL data, representing SQL data types that are used as the type of a column but are not built-in datatypes, in particular
    *   blob
    *   date-time types
    *   array
*   in an entity-relationship model, representing attributes of an entity, as distinct from references to another entity
*   `bytes` type in gRPC/protocol buffers
*   fields of a record that are primary keys (in the tables proposal)
*   persistence: a table whose columns types do not have storage identity can be persisted without change of semantics, e.g. by implementing on top of an embedded, persistent key-value store (like LevelDB, RocksDB) 


### Other languages

D has [immutable](https://dlang.org/spec/const3.html#immutable_type) types, which are quite similar.

Joe Duffy wrote an interesting [blog](http://joeduffyblog.com/2016/11/30/15-years-of-concurrency/) on Midori concurrency, in which he observed:


>    I should also note that, for convenience, you could mark a type as immutable to indicate “all instances of this type are immutable.” This was actually one of the most popular features of all of this. At the end of the day, I’d estimate that 1/4-1/3 of all types in the system were marked as immutable

C# has structs, which are records with value semantics. In Swift, the equivalent of maps and lists have value semantics. In C# and Swift, they are not immutable but rather assignment (including parameter passing) makes a copy (Swift does reference counting and COW IIRC).


## Proposal


### Immutability

The existing immutability flag on values becomes something that affects whether a value belongs to a type, i.e. part of the shape of value. We will distinguish multiple _aspects_ of a shape:



*   the primary aspect of a shape is what the spec currently calls shape; the == operator and match statement only consider the primary aspect of shape
*   the mutability aspect of shape comes from the existing immutability flag

The semantics of existing type descriptors is unchanged, i.e. they are not affected by a shape's immutability aspect.

The types that can have both mutable and immutable values are:



*   list
*   mapping
*   table
*   xml:Element|xml:ProcessingInstruction|xml:Comment

There is a new keyword `readonly.` Reasons for the choice of keyword are:



*   when we named value:cloneReadOnly we decided that our user-visible word for immutable was read-only	
*   with the foreach keyword and forEach method, we decided to stick strictly to camel-case for methods and all lower case for keywords, even when they were the same word

Issue:



*   Should we switch to immutable? The problem is that the most natural interpretation of a parameter being readonly is that you will only read a value through this parameter.

There is a new type descriptor `readonly<T>`, which is a type operator (transforming one set of shapes to another): 



*   allowed when T is a subtype of anydata|error
*   semantics is to transform the set of shapes denoted by T so that it does not allow mutable shapes at any depth
*   transformation happens after type references are resolved

So for example, given


```
    type IntList record {
       int value;
       IntList? next = ();
    };

    readonly<IntList> head;
```


The type of `head.next` is `readonly<IntList?>` *not* `IntList?`. This is because the readonly operator transforms IntList so that its members are also readonly.

When the contextually expected type is readonly, a list or mapping constructor will create an immutable value. Note that the members will not cloned, but rather the typing ensures it will be a compile-time type error if they are not immutable. For example:


```
type Foo record {int a; bar b;};
type Bar record {int z;};
Bar b1 = {z:11};
readonly<Foo> f = {a:10, b:b1}; // error: type of b1 is not readonly
```


The readonly type can be used without the following type parameter to match any immutable value. This is particularly useful in two cases:



*   a `<readonly>` cast can be used to assert that value is immutable and to establish a readonly contextually-expected type.
*   The `is` expression to use readonly to check whether a value is readonly like this:

        ```
        v is readonly

        ```


The signature of cloneReadOnly changes to:


```
    function cloneReadOnly(T value) returns readonly<T>
```


The type of a compile-time const is automatically readonly.

The typedesc:constructFrom function will construct immutable values when type uses readonly

In the table proposal, when a record has a field that has a primary key, the type of that field would be readonly (avoids the need for setting a field to do a clone, which would be weird).

It is important to be clear about what compile-time type-safety does and does not guarantee as regards readonly:



1. it _does_ guarantee that a value declared as readonly is immutable (and thus does guarantee that such a value can be safely accessed from multiple threads)
2. it _does not_ guarantee that a value not declared as readonly is mutable; thus writes to a structure may fail at runtime (as is now the case)

Despite point 2, the compiler can detect common cases where the user attempts to write to an immutable value.


#### Functions

Are functions inherently immutable?

Consider a module function that refers to a module-level variable. Calling the function might mutate that variable. Does that mean the function itself is mutable? I think not. A value being immutable means that what you read from the value will never change. In this sense, functions are immutable. Closures that refer to local variables outside the function are not fundamentally different in this respect from module level functions that refer to module level variables.

This relates to the issue of how we are going to use immutability to achieve concurrency safety.  Reading only immutable values is not sufficient to provide concurrency safety. We also need to have a safety aspect to the type of functions that provides guarantees about the effects of calling the function.


#### Type descriptors

Note that type descriptor for records refers to closure when there is a default value. So functions being inherently immutable is a prerequisite to type descriptors being immutable.


#### Final record fields

Final record fields can be seen as a kind of partial immutability. If the mapping value is immutable, then it's fields are automatically final.

When a mapping value is a member of a table, the primary key fields need to be final and the values of those fields need to be immutable.


#### Object

Can we have immutable objects? Prerequisite is immutable functions.

Previously impossible because


*   the only way to construct object was by cloning
*   thing that can be cloned is anydata
*   object is not anydata

Challenge is how to make methods (especially initializer) work. A non-abstract object type is not merely defining a type but a way to initialize a value of the type (including with methods).

This doesn't make sense:


```
    type O object { ... };
    var obj = new readonly<O>() ;
```


But this does:


```
    type O readonly object {...};
    var obj = new O();
```


I think this can be made to work with the semantics that:



*   fields are final meaning assignments to the fields are allowed only in the __init method 
*   field declared as  T is readonly<T>


### Error and anydata

The way the current language deals with error and anydata is currently complex:



*   error is half-in/half-out of anydata
*   not a subtype of anydata, so not allowed for a value of type anydata
*   allowed as a member of an anydata structure

The error doesn't really belong in structural types:



*   the only one that is always immutable
*   stack trace makes it not just a container for other values
*   does not have natural JSON serialization like other structural values
*   with xml becoming a sequence and table becoming a container, error is even more obviously the odd one out

The current design is forced by the following reasoning:



1. errors are passed between strands when using workers
2. therefore errors need to be immutable
3. therefore error detail record needs to be immutable
4. therefore error detail record needs to be cloneable
5. therefore error detail record needs to be anydata
6. but error detail needs to have fields that are errors (e.g. `cause` field)
7. so error needs to be allowed as member of anydata structure
8. but don't want error to be a subtype of anydata, so that it is explicit when errors are happening (eg as return value of function)

But step 4 of the reasoning no longer holds. We can instead say:



*   if a behavioural basic type is inherently immutable, then it is a subtype of readonly
*   error is an inherently immutable basic type
*   for a type error<S,R>, the members of R must be a subtype of `anydata|readonly` (the two arms of the union are not mutually exclusive, but that is perfectly OK in Ballerina's type system)
*   the error constructor only clones values that are anydata but not readonly
*   similarly we can state that inter-worker message send
    *   allows anydata|readonly and
    *   clones only if it is not readonly

Regardless of the above change to error, with readonly the error detail method returns readonly type.

```
  function detail(error<string,DetailType> e)
     returns readonly<DetailType>;
```


XXX Think about impact, if any, on lax static typing.

Alternative:



*   error constructor works more like a mapping constructor for a readonly record
    *   doesn't implicitly clone
    *   each field expects a readonly value


### Storage identity

High level concept is as follows.

Currently, when a list or mapping constructor constructs a value, it always creates a _new_ value, i.e. a value that has a storage identity distinct from any already constructed value. I will call this newing a value.

When constructing a value of readonly type there is an alternative way it could work: it can arrange for any two values of the same basic type constructed in this way have the same storage identity if their members are ===. One (inefficient) implementation to do this is to keep track of all values created and return one of the already created values if the value being constructed has the same members. A better implementation is to return a distinct implementation of the value that will implement === by comparing members. I will call this interning a value (as in String [interning](https://en.wikipedia.org/wiki/String_interning) construction).

The concept then is that there's syntax that controls whether a list/mapping constructor does newing or interning construction when constructing a value with a contextually expected type that is read-only.

This means that the new/interning distinction is not part of the shape and does not affect type.

Interning construction has a limitation like simple values as regard annotations: the type annotations on a value constructed by interning will not be available via typeof. However, we can have a method on typedesc that will indicate whether a value was constructed via an interning type descriptor; you can use this with typeof to determine whether a value was constructed by interning.

Note that cloneReadOnly cannot do interning construction, because it preserves the graph and allows cycles. Note also that whereas immutability has to be deep, interning does not.

How then should syntax distinguish interning from new construction?

For readonly types, interning construction should be the default. If you have declared a type to be always readonly, you typically do not want storage identity to be significant. So a mapping or list constructor should do interning construction when the contextually expected type is readonly.

```
type X record { int i; }

type Y record { X x; }

X rw = { i: 1 };

readonly<X> ro = rw.cloneReadOnly();

readonly<Y> y  = { x: ro }; // y interned, but ro not interned
```

In particular, typedef:constructFrom with a readonly type will do interning construction.

If the user wants for some reason to construct a value of a readonly type that is guaranteed to be new, then they can construct it as mutable and use cloneReadOnly. If that proves not to be enough, one idea would be to allow the new keyword before a list or mapping constructor to force the construction of a new value.

The net result is that if you declare a type as readonly


```
    type Blob readonly<byte[]>;
    type Date readonly<record {|
       int year;
       int month;
       int day;
    |}>;
```


values of the type that are constructed in the normal way will have value semantics.


## Commentary

The immutability part of this makes the current immutability feature of the language stronger.  I suspect this feature is not much used currently. This proposal will make it significantly easier to take advantage of it. This part does add any new concepts, but allows the type system to better describe the existing concept, which enables values to be constructed as immutable at runtime.

The storage identity design doesn't add anything beyond immutability to the type system. This is both an advantage and a disadvantage. Its advantage is that it keeps things simple and avoids having two slightly different, but related concepts in the type system. Its disadvantage is that having a storage identity is less first-class in the language, and in particular is not expressed in the type. The guarantee that storage identity is insignificant for readonly types is not water-tight.