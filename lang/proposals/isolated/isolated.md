# Isolated functions and objects

This is issue #[145](https://github.com/ballerina-platform/ballerina-spec/issues/145): please add comments there.


## Motivation

The main point of the current readonly feature is to help with concurrency safety: if a value is readonly, then it is safe for it to be used simultaneously by two functions running in different threads. The way to think about Ballerina's readonly is that it is saying something about the data, i.e. that the data is safe for concurrent access.  This is very different from something like C's concept of const, which is more like a permission: you do not have permission to mutate data through a pointer to const.

There are three operations on storage in the Ballerina runtime environment: read, write, execute.  The readonly feature relates to the read and write operations:

*   readonly means that any attempted write operation will not succeed
*   readonly is deep, which means a write applied to the result of any number of reads will not succeed

However, readonly by itself doesn't get very far in enabling reasoning about concurrency safety properties of the program because it does not say anything about execution. In particular, it does not ever by itself allow the programmer to know that two function calls (with specific arguments) can be called simultaneously on two threads. Readonly by itself is thus much less helpful for objects than for anydata, since objects often encapsulate data using functions.

At a high-level, the goal of the isolated functions feature is to go the last mile with readonly, to allow users to get the maximum value out of the existing language support readonly.

The problem is to design the semantics of the property of a function:

1. we need to design the semantics of the property along along with a set of restrictions on functions so that we can prove that a function f that calls only functions that have this property can be proved itself to have this property provided that f satisfies the restrictions
2. if we make the property too restrictive, then it won't be useful because functions that people want to write won't have the property
3. if we make the property too loose, then a function having the property won't give us useful information

Balancing 2 and 3 is key to getting something useful.

In previous discussions, we have talked about this as being pure functions.  We should not be  overinfluenced by the word "pure": we need to design the semantics and then choose a word that is appropriate to the semantics. As well as concurrency safety, there are many other concepts that are relevant to "purity":



*   no side-effects
*   result depends only on arguments
*   can be called at compile-time
*   mathematical function
*   memoizable (i.e. cache the results and reuse)
*   does not modify program state

Doing 1, 2 and 3 is already hard, so we need to focus on designing the property so that it works well for concurrency safety, not try to accommodate preconceptions about the term "pure".

A good starting point is the D language, which like Ballerina has deep immutability. It has a [concept of pure functions](https://dlang.org/spec/function.html#pure-functions). D's concept of pure function is a function that only accesses mutable state through its parameters. Such a function is _conditionally_ safe: concurrent calls to the function are safe provided the caller ensures that the callee has exclusive access to any mutable storage accessible from the parameters for the duration of the call.

The term “pure” does not seem a good fit for this concept: it suggests something more like a mathematically pure function. The concept here is of a function that is well-behaved and "keeps to its lane".  Instead we use the term "isolated". Other names we considered were


*   confined
*   controlled
*   restrained
*   restricted
*   restrict (C99)
*   limited
*   local
*   readonly
*   safe
*   strand

An additional argument in favour of the term _isolated_ is that for Ballerina this feature serves the same purpose that isolates do in other languages/systems (e.g. Dart/V8).

For Ballerina, perhaps the most important case is that the Listener can ensure that a call to a service method/resource can safely be run on a separate thread by controlling the parameters that are passed to it.  This is a good fit for _function as a service_ concept: service function provides logic; state is separated out and passed as a parameter, so it can be managed externally,

There are some complications to be dealt with in specifying exactly how the concept works:


1. return values: a pure function needs to be able to not only call other pure functions but also use the values they return
2. the pure concept should interact usefully with the lock statement, since the lock mechanism is our current mechanism for concurrency control
3. we need to deal with input/output and other interactions between a Ballerina program and the environment within which it is running
4. there probably needs to be an escape hatch of some kind: the programmer needs to be able to tell the compiler that the programmer knows that something is OK even if the compiler cannot prove it


## Isolated functions

The basic idea of an isolated function is that it access mutable storage only through its parameters. A caller of an isolated function can ensure that a call is concurrency-safe by ensuring that it is safe to access the parameters for the duration of the call.  So, in particular, a call to an isolated function is guaranteed safe if all its arguments are read-only.

Define

*   the _mutable storage graph_ of a value v as the storage locations reachable from v but not readonly. Reachable here means the same as in the requirement that value reachable from readonly value is readonly, i.e. you can get to it by a sequence of read operations.
*   the _local mutable storage graph_ of a function invocation as the union
    *   the mutable storage graphs of its parameters
    *   storage locations allocated during the function invocation

In a method call, `self` is treated as a parameter, and the object's fields are thus part of the local mutable storage graph of the method call.

A function can be declared as isolated, by using the `isolated` keyword before the function keyword in the following syntactic constructs:

*   function-type-descriptor
*   function-defn
*   method-decl
*   method-defn
*   service-method-defn
*   anonymous-function-expr

A function can be declared as isolated if:

*   all functions that it calls are declared as isolated
*   it does not create new strands using either named workers or `start`
*   the compiler can verify that, in any invocation of the function, all mutable storage that is accessed in the function's body is part of its invocation's local mutable storage graph (this implies that the return value is also part of its local storage graph).

Whether a function is isolated is part of a function's type. A function declared as isolated is a subtype of an equivalent function that is not declared as isolated. Type-casting a function to a pure function type will work as casting usually does: it will succeed if the function was in fact declared as isolated.

External functions can be declared as isolated, and external makes no difference for how the function is called. The implementation of the external function is responsible for ensuring that it is isolated. What does isolated mean for external functions?

*   in terms of accessing Ballerina program state, it should have the same constraints as if it were implemented in Ballerina
*   D does not allow isolated functions to perform IO, but I think that is too restrictive for us (it would be too limiting to say that a service that cannot do IO) and would not really be practical (D has an escape hatch explicitly for debug printing)
*   isolated external functions must also be safe for concurrent access from multiple threads

When compiling a module, the compiler can infer that some or all of the functions in the module are isolated even though they were not explicitly declared as such, if the functions would meet the requirements for isolated if they had all been declared as such. In doing so, the compiler must not assume that a call to a function outside the module is isolated unless it was declared as such. Furthermore, if a function is explicitly declared as isolated, then all functions it calls must also be explicitly declared as isolated.

The langlib functions that meet the requirements for isolated will need to be declared as such. (I believe they all do.)

## Isolated objects

The purpose of an isolated object is to be an object that is guaranteed to be safe for concurrent access from multiple threads. A call to an isolated function whose arguments are all either isolated objects or readonly is thus guaranteed safe.

A important special case of an isolated object is a stateless object. An object without fields or an object all of whose fields are readonly is inherently isolated. This is particularly important for service objects, since the Listener will need to ensure that its used of threads does not cause problems for service objects that are not isolated.

Whereas writing an isolated _function_ is straightforward and many functions will be isolated without extra work, this is not the case with isolated _objects_. Writing an isolated stateful object requires that the programmer make appropriate use of the `lock` statement.

An object's _mutable storage graph_ are the non-readonly storage locations reachable from its fields. An isolated object guarantees thread safety by ensuring that its mutable storage graph is always accessed within a `lock` statement.
Specifically, the following requiements apply to an isolated object:

1. all mutable fields of the object are  private
2. all methods only access mutable fields of the object within a `lock` statement
3. it maintains an invariant that there are no references into the object's mutable storage graph from outside the object, except through other isolated objects

The third point is the difficult one. There are two parts:
 * `init` must establish the requirement
 * all other methods must maintain it

For module-level classes and service objects, we should infer when they are isolated. Note that point 3 means that an isolated object can have final fields (or resources) that reference  isolated objects.

### init method

Define an expression to be unique if it is known at compile-time that either the result is readonly or the result is the unique reference to the value.
We can define rules for when an expression is unique, e.g.
* a string literal is unique
* a list constructor expression is unique if all its subexpressions are unique
* a call to the clone or cloneReadOnly method is always unique
* a function-call-expression to an isolated function is unique if the expressions for all its arguments are unique
* a variable reference is unique if there is only one reference to the variable and the variable was assigned or initialized with a unique expression
* etc, etc

We can then require that every field whose type is neither readonly nor an isolated object is initialized with a unique expression.

### Other methods

We need to ensure that the invariant is maintained by every lock statement that contains accesses to the object's fields, i.e. if it applies at entry to the lock statement, it also applies at exit. We maintain the invariant by controlling how values are transferred in and out of the lock statement. Values are transferred in by reading from a variable or parameter defined outside the lock statement. Values are transferred out by writing to a variable defined outside the lock statement or by a return statement. A value can only be transferred in or out if it is readonly or the result of a calling the `clone` method or is an isolated object. In addition, within the lock statement only isolated functions can be called.

For example:

```
type Pair record {
    int x;
    int y;
};

isolated class X {
    private Pair[] x = []; // unique
    isolated function set(int i, Pair p) {
        lock {
            self.x[i] = p.clone(); // copy in
        }
    }
    isolated function get(int i) returns Pair {
        lock {
            return self.x[i].clone(); // copy out
        }
    }
}
```

### isolated objects vs isolated methods 

An isolated object allows simultaneously access by
* one thread that can all methods, both isolated and non-isolated, and
* multiple other threads calling only isolated methods

This is what you need to ensure automatic safe parallelization: you can safely schedule a strand that makes isolated methods calls on an isolated object on a separate thread.

It makes sense to have non-isolated methods of isolated objects: they are constrained only to behave "well" as regards the object's state.

### Bound methods

With the proposed fix to #[574](https://github.com/ballerina-platform/ballerina-spec/issues/574), you can get a method bound to a particular object by accessing the method name like a field name. Since isolated methods treats the self variable like a special parameter, the bound method will be isolated only if the method and the object are isolated.

## Standard library implications

For this to be useful, many of the functions in the standard library will need to be declared as isolated. It would be good if the compiler can help with this.

## Further work

### Access to module-level state

We can extend allow safe access to module-level state by using a similar approach to isolated objects:

* allow a module-level variable to be defined as `isolated`
* initialization requirements are the same as for the fields of an isolated object
* the requirements that apply to the methods of an isolated object as regards access to the object's fields apply to the functions defined in the module as regards access to each isolated variable
* each isolated variable has its own isolated graph 

 Within a module, we can potentially infer particular variables to be isolated.

### Escape hatch

There probably needs to be some way for the user to force the compiler to treat a call as isolated even though it does not meet the compiler's requirements for being isolated. Note that a type-cast does not do this.

