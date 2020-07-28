# Distinct types

This document describes a feature that provides the functionality of nominal typing just for the object and error basic types. For error values, this feature replaces the error reason string. This addresses issues #[413](https://github.com/ballerina-platform/ballerina-spec/issues/413), #[459](https://github.com/ballerina-platform/ballerina-spec/issues/459), #[75](https://github.com/ballerina-platform/ballerina-spec/issues/75). Please add any comments to issue #[413](https://github.com/ballerina-platform/ballerina-spec/issues/413).

This feature adds a new type-descriptor

```
distinct-type-descriptor := "distinct" type-descriptor
```

In a distinct-type-descriptor <code>distinct <em>T</em></code>, the type-descriptor <code><em>T</em></code> is constrained to be a subtype either of object or of error.

Informally, the effect is to create a type that is distinct from all other types including those that have the same structure. In more detail, the semantics are as follows.

The semantics rely on the concept of a type-id. Each occurrence of a distinct-type-descriptor in a source module has a distinct type-id that uniquely identifies it within a Ballerina program. A type-id has three parts:



*   an identifier for the module within which the distinct-type-descriptor occurs
*   an identifier that uniquely identifies the occurrence of the distinct-type-descriptor within the module
*   a flag saying whether the type-id is public

The second part takes one of two forms:

*   the named form is used when a distinct-type-descriptor is the only distinct-type-descriptor occurring on the RHS of a module-level type definition; in this case, the name of the defined type is used as the second part of the type-id
*   the anonymous form is used otherwise; it is generated automatically by the compiler 

The public flag is set if the distinct-type-descriptor occurs on the RHS of a public module-level type definition.

An object value or error value includes a set of type-ids. These type-ids are fixed at the time of construction and are immutable thereafter. A value's set of type-ids may be empty. The type-ids of a value are part of the value's shape and so affect static typing.

A type of a distinct-type-descriptor <code>distinct <em>T</em></code> contains a shape s if and only if

*   the type-id of the distinct-type-descriptor is one of the shape's type-ids, and
*   the type of _T_ contains s

A value's type-ids are divided into primary type-ids and secondary type-ids. The secondary type-ids could be derived from the primary type-ids using the program's source, but they are included explicitly to simplify the explanation of the semantics of distinct types.

An object or error value is always constructed using a type descriptor. When a type-descriptor T is used to construct an error value, the type-ids of the constructed value are computed from T as follows.

*   If T has the form `distinct T1`, then T has a single primary type-id, which is the type-id of that occurrence of `distinct T1`, and the secondary type-ids of T are the type-ids of T1
*   If T is an error-type-descriptor, then T has no type-ids
*   If T is an object-type-descriptor that includes types T1, T2,...,Tn (using the `*Ti;` syntax), then the primary type-ids of T are the union of the primary type-ids of the Ti and the secondary type-ids of T are the union of the secondary type-ids of the Ti; it is an error if this results in T including a non-public type-id from another module; if T does not include any types, then it has no type-ids;
*   If T is an intersection type `T1 & T2`, then the primary type-ids of T are the union of the primary type-ids of T1 and T2, and the secondary type-ids of T are union of the secondary type-ids of T1 and T2.
*   If T is a union T1 | T2, then it is a compile-time error if type-ids of T1 or T2 are non-empty (such a type descriptor T only results in a compile-time error if it is used to construct a value)
*   If T is a reference to a type descriptor T1, then primary and secondary type-ids of T are the same as those of T1; it is an error if this results in T including a non-public type-id from another module

The typeof operator applied to an error or object value returns a typedesc value representing the type descriptor used to construct the error or object value. The primary and secondary type-ids of a type-descriptor are available from this typedesc.

toString on an error or object value will include the primary type-ids; the version number of a module can be omitted, unless multiple versions of the module have been imported.

## Related changes to object type

### Double underscore method names on abstract object types

The double underscore convention for method names of language-defined operations on methods exists only because Ballerina has lacked the functionality of nominal typing. The reason for the double underscore conventions is to allow the user to freely choose the semantics of the methods that do not begin with double underscore. If the language needs to introduce a new method starting with double underscore and specific semantics, then it can do so without existing programs being invalidated. But the convention is ugly, and it's hard to explain when exactly double underscore is needed (e.g. `__iterator` vs `next`).

Distinct objects can replace the double underscore convention.

For example, in lang.object we would define a distinct object type:


```
type Iterable distinct abstract object {
   function iterator() returns abstract object {
      function next() returns record {| any|error value; |}|error?;
  }
}
```


Then an object that wants to make itself iterable would be explicit about it by including that object type:


```
type MyIterableObject object {
   *object:Iterable;
   function next() returns record {| string value; |}|() {
   }
```


}; 

An object is iterable if it is a subtype of object:Iterable.


### `__init`

If we replace double underscore method names on abstract object types by distinct object types, then the use of `__init` for objects and modules no longer makes much sense. The most straightforward solution is just to rename from `__init` to `init`. (I don't like this, but I don't see any better solution.)


### Type inclusion

 An object type descriptor consists of

*   tags
*   field declarations, which may include defaults
*   method declarations
*   method definitions

We need to be able to have a subtype relationship between two distinct non-abstract object types: this means we need to allow a non-abstract object class to include another non-abstract object class.

When an object type descriptor S includes an object type descriptor T (using *T;), it includes everything other than method definitions (i.e. the object implementation). S can override an included method or field declaration provided that the overriding declaration is a subtype of the overridden declaration. As now, a non-abstract object type descriptor must provide a definition for every included declaration.

### Intersection of object types

Intersection of two abstract types is straightforward and uses intersection of the sets of shapes. Note that the __init method is not part of an object's shape.

Note that intersection is not a substitute for type inclusion: it doesn't handle the case of where you want to have a distinct non-abstract object type be a subtype of another distinct non-abstract object type without forcing the introduction of additional types.

How should intersection of two object types work when at least one of them is not abstract? Possibilities:

1. When both are non-abstract, allow providing there are no conflicting methods, with the result being non-abstract. Need to decide what happens with init. Possible restrictions
    1. can have at most one init method
    2. can have at most one init method that has parameters; in this case the parameters for new would be used for the init method that has parameters
2. Say that at most one can be non-abstract and that the result is non-abstract, implying that the non-abstract object must implement all the methods of the abstract object types
3. Say that it is always allowed and the result is always an abstract object type: in other words it produces a type that is the intersection of the two types, and ignores the method definitions; this is consistent with *T
4. Say it is not allowed

Need to think about:

*   how this interacts with privacy
*   how this interacts with intersecting with readonly

## Related changes to error type

The error-type-descriptor changes to:


```
error-type-descriptor := "error" [type-param]
```


The type parameter of error specifies the type of the detail record. The first positional parameter of the error constructor specifies the message rather than the reason string.

Type intersection allows the detail record and the type-id of an error to be described together. For example:


```
type IoError distinct error;
type HttpError distinct IoError
  & error<record { int httpErrorCode; }>
```


An error error type `error<R>` means that the detail record must belong to the type


```
    readonly & record {| *R; (anydata|readonly)...; |}
```

In a match-statement, a error-match-pattern with a user-defined error type should match only if the shape of the value belongs to type.