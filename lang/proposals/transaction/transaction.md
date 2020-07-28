<h1>Transactions proposal</h1>

<h2 id="introduction">Introduction</h2>

This document proposes Ballerina language features that are designed to make it easier and more convenient to write robust applications that use transactions, including distributed transactions. It is not a design for a complete distributed transaction processing system. Please add any comments to issue #[267](https://github.com/ballerina-platform/ballerina-spec/issues/267).

Ballerina does not provide transactional memory. If in-memory data structures need to be updated depending on how a transaction completes, then it is the responsibility of the user to do so explicitly. A [commit/rollback handler feature](#commit-rollback-handlers) is provided to make this easier.

<h2 id="transaction-manager">Transaction manager</h2>

A running instance of a Ballerina program includes a transaction manager. This may run in the same process as the Ballerina program or in a separate process. It should not be connected over an unreliable network.

The transaction manager maintains a mapping from each strand to a stack of transactions (or, in a distributed context, transaction branches - see below). When a strand's transaction stack is non-empty, we say it is in _transaction mode_; the topmost transaction on a strand's transaction stack is the current transaction for that strand.

Ballerina also has the concept that a transaction may be part of a sequence of retries, where the last transaction can complete with either a rollback or commit, and the preceding transactions all completed with a rollback.

The transaction manager supports the following abstract operations. We will explain the semantics of the transactional language features in terms of these abstract operations. These operations are modelled after the X/Open [TX Specification](https://pubs.opengroup.org/onlinepubs/009649599/toc.pdf) and Java's [UserTransaction](https://docs.oracle.com/javaee/7/api/javax/transaction/UserTransaction.html) interface. These cover only the interface between the application and the transaction manager, not the interface between the resource manager and the application. These operations are all performed by a Ballerina program in the context of a strand (this is a Ballerina term which means roughly thread or coroutine).


*   Begin(t)
    *   this marks the beginning of a transaction (in a distributed setting, this marks the beginning of a global transaction)
    *   t is an optional parameter providing information about the preceding transaction in the sequence of retries
    *   this either panics or succeeds
    *   if it succeeds, then a new transaction is pushed on the strand's transaction stack, so the strand will be in transaction mode
*   Commit() 
    *   precondition is that the strand is in transaction mode
    *   this directs the transaction manager to try to commit the current transaction
    *   this can return as soon as the transaction manager has made a decision as to whether commit or rollback
    *   this fails with an error, panics or succeeds
    *   after return, the strand is not in transaction mode
*   Rollback(e)
    *   precondition is that the strand is in transaction mode
    *   this directs the transaction manager to try to rollback the transaction
    *   this either panics or succeeds
    *   e is the cause or the rollback, which is error or nil; this can be included in the error value in the event of a panic
    *   after return, the transaction stack is popped, removing the transaction that was the current transaction
*   Info()
    *   precondition is that the strand is in transaction mode
    *   returns information about the current transaction such as its identifier and state
    *   after return, the strand's transaction stack is unchanged
*   SetRollbackOnly(e) 
    *   precondition is that the strand is in transaction mode
    *   causes any subsequent Commit() not to succeed
    *   after return, the strand's transaction stack is unchanged
    *   e, which is error or nil, is the error that resulted in the application deciding to do this
*   SetTimeout(duration)
    *   precondition is that the strand is in transaction mode
    *   Issue: when is this measured from?
    *   applies to current transaction branch
    *   after return, the strand's transaction stack is unchanged

Note that this does not support the X/Open chained mode of transaction execution: each transaction always starts with a Begin() and is completed by a Commit() or Rollback().

The above operations may result in the transaction manager getting into an error state from which it cannot recover automatically. We probably need to provide some way for the application to get called in this situation.

<h2 id="static-typing">Static typing</h2>

The central concept is that a lexical scope can be transactional. This means that within the region of the program source code corresponding to the scope, the compiler guarantees that the strand is in transaction mode.

A function or method can be declared with the qualifier `transactional`. This means that


*   the scope of its default worker is transactional
*   it can only be called from a lexical scope

This is similar to `MANDATORY` in JEE, except that it is checked at compile-time.

<h2 id="statement-evaluation-semantics">Statement evaluation semantics</h2>

Evaluation/execution semantics in Ballerina are currently as follows:


*   The evaluation of an expression either
    *   completes normally with a value, or
    *   completes abruptly with either
        *   a panic and associated error value, or
        *   a check-fail and associated error value
*   The execution of a statement either
    *   succeeds, in which case there is no associated value
    *   terminates abnormally with a panic and associated error value
*   The execution of a worker either:
    *   terminates normally
        *   success - returning a non-error value
        *   fail - returning an error value
    *   terminates abnormally - a panic with associated error

Recall that the semantics of an expression `check E` is to evaluate E resulting in a value v. If if v is an error, then the evaluation of check E completes abruptly; this causes the statement evaluating the expression to terminate the worker, like a return statement does. Otherwise, the expression evaluates normally with result v.

To handle transactions, we can make this more flexible, but in a way that is consistent with the fundamental Ballerina design principle that normal control flow should be explicit. We can say that there is an additional possible outcome for statement execution - failure. When a statement evaluates an expression that completes abruptly with a check-fail, instead of the worker always returning, we can say that the execution of the statement fails. It is then up to the containing statement to determine how to handle this, where the default behaviour is to pass the error up to the containing statement, eventually resulting in the worker terminating. This means that failure of a `check` expression is no longer always equivalent to returning the error. In particular a transaction will be able to treat check-failure as different from return. This flexibility will be useful not only for transactions, but also for making error handling more convenient (see issue #[337](https://github.com/ballerina-platform/ballerina-spec/issues/337)).

We will use the following notation to describe the three possible, mutually exclusive outcomes of the execution of a statement:

*   panic(e) - panic with error value e
*   fail(e) - fail with error value e (from a failed check expression)
*   success

<h2 id="transaction-statement">Transaction statement</h2>

A transaction is performed using a transaction statement. The semantics of the transaction statement guarantees that every Begin() operation will be paired with a corresponding Rollback() or Commit() operation.


```
transaction-stmt := "transaction" block-stmt
```

The block-stmt is a transactional scope. It is a compile-time error for it to occur in transactional scope. It is required at compile time that the block-stmt lexically contain at least one commit action:

```
commit-action := "commit"
```

A commit-action can only occur lexically in a transaction statement. The commit-action performs the transaction manager Commit() operation; if the result of the Commit() operation is an error, then the result of the commit-action is an error; otherwise, the result is nil.

Since the result of a commit action is not always nil, Ballerina's usual rules ensure that the result cannot be ignored. Note that the commit action does not change the flow of control.

The block-stmt can also contain rollback statements:

```
rollback-stmt := "rollback" [expression] ";"
```

The rollback-stmt performs the transaction manager Rollback() operation. The expression, if specified, must be a subtype of `error?`; if it's an error, it specifies the cause of the rollback and is passed as a parameter to the transaction manager's Rollback() operation. Note that like the commit action, the rollback statement does not change the flow of control. (If we add a fail expression, then it could be used to change the flow of control and thus cause a rollback.) 

It is a compile-time requirement that any exit out of the block-stmt that is neither a panic nor a failure must have executed a commit action or rollback statement.

The scope following a commit-action or rollback-stmt is not transactional. For example, if bar() is declared as transactional, then this is a compile error:


```
    transaction {
        foo();
        check commit;
        bar();
    }
```


Note that this also would be an error:


```
    transaction {
        transaction {
            foo();
            check commit;
            bar();
        }
        check commit;
    }
```

i.e. the scope in which bar() occurs ins non-transactional rather than in the outer transaction.

The semantics of a transaction statement are as follows:


*   Perform the transaction manager Begin() operation. If the outcome of this is panic(e), then the execution of the transaction statement terminates with outcome panic(e).
*   Execute the block statement. Let o be the outcome.
*   If the strand is not in transaction mode, then the outcome of the transaction statement is o.
*   If the strand is still in transaction mode, then o must be either fail(e) or panic(e) (success is not possible because of the compile-time requirement for explicit commit or rollback actions). In this case, perform the Rollback(e) operation. If the result of the Rollback is a panic(e'), then the outcome of the transaction statement is panic(e'). Otherwise, the outcome is fail(e).

Issue



*   The following case is tricky. I think we can say it should be a compile-time error if you try to flow into a transactional code path from a non-transactional code path.

```
        transaction {
          fooTx();
          if something() {
             rollback;
             // not in transaction mode
             bazNonTx();
             // not in transaction mode
          }
          barTx();
          check commit;
        }

```


<h2 id="retry-statement">Retry statement</h2>


The retry statement provides a general-purpose retry facility independent of transactions.


```
retry-stmt := "retry" retry-spec block-stmt
retry-spec :=  [type-parameter] [ "(" arg-list ")" ]
```


The type-parameter must refer to a non-abstract object type that must be a subtype of the following abstract object type, called a `RetryManager<E>`, where E is a subtype of error.


```
    abstract object {
       public function shouldRetry(E e) returns boolean;
    }
```


`RetryManager<E>` is contravariant in E i.e. `RetryManager<E>` is a subtype of `RetryManager<E'>` iff E' is a subtype of E. If the failure type of the block-stmt is F, then the retry manager must be a subtype of `RetryManager<F>`, which requires that F must be a subtype of the first parameter type. 

The arg-list specifies parameters to the object type's initializer. As with `new`, the arg-list can be omitted if the object type's initializer has no required arguments.

A retry-stmt is executed as follows:



1. Create a RetryManager object r using the type-param and arg-list
2. Execute the block. Let the outcome be o.
3. If o is fail(e), then call r.shouldRetry(e). If the result is true, go back to step 2.
4. Terminate the execution of the retry-stmt with outcome o.

A retry without a type-param is equivalent to `retry<DefaultRetryManager>`, where `DefaultRetryManager` is defined in langlib as follows:


```
public type RetriableError distinct error;

public type DefaultRetryManager object {
   private int count;
   public function init(int count = 3) {
     this.count = count;
   }
   public function shouldRetry(error e) returns boolean {
      if e is RetriableError && count >  0 {
          count -= 1;
          return true;
      }
      else {
        return false;
      }
   }
}
```


In its simplest form, a retry statement looks like:


```
retry {
  block
}
```


The more complex form looks like:


```
retry<MyRetryManager>(arg-list) {
   block
}
```


A RetryManager can implement arbitrarily complex logic. For example, it could have a time limit within which retry is attempted; it could implement retry with exponential backoff by sleeping before returning; It could even make use of machine learning to determine whether it was useful to retry.

<h2 id="retry-transaction-statement">Retry transaction statement</h2>


A retry transaction statement combines the retry statement and the transaction statement, but with the additional semantics that each transaction is part of a sequence of retries.

```
retry-transaction-stmt := "retry" retry-spec transaction-stmt
```

Semantics of a retry-transaction-stmt differ from wrapping a retry-stmt around a transaction-stmt in the following ways.

First, when the transaction is retried, information about the previous transaction is passed to the Begin() operation, so that it can be available through the Info() operation.

Second, if the outcome of the transaction attempt was error(e), but the transaction was committed successfully, the transaction will not be retried; in this case, the outcome of the transaction-stmt will be fail(e).  The exceptional case would happen, for example, in the following, if `bar()`, which is non-transaction, returned an error:

```
retry(3) transaction {
   check foo();
   check commit;
   check bar();
}
```

The various possibilities for the block statement outcome are described in the following table. The rows are whether a commit-action or rollback-stmt was executed and what the result was. The columns are what the outcome of executing the block was. The table cell says what the attempt does after the block has been executed and what the outcome of the attempt is.


<table>
  <tr>
   <td>action\block
   </td>
   <td>success
   </td>
   <td>fail(e)
   </td>
   <td>panic(e)
   </td>
  </tr>
  <tr>
   <td>commit success
   </td>
   <td>success
   </td>
   <td>fail(e) but no retry
   </td>
   <td>panic(e)
   </td>
  </tr>
  <tr>
   <td>commit fail
   </td>
   <td>[unusual] success
   </td>
   <td>fail(e)
   </td>
   <td>panic(e)
   </td>
  </tr>
  <tr>
   <td>rollback
   </td>
   <td>success
   </td>
   <td>fail(e)
   </td>
   <td>panic(e)
   </td>
  </tr>
  <tr>
   <td>panic from rollback or commit
   </td>
   <td>[unusual] success
   </td>
   <td>[unusual] fail(e)
   </td>
   <td>panic(e)
   </td>
  </tr>
  <tr>
   <td>no commit or rollback performed
   </td>
   <td>[disallowed at compile time]
   </td>
   <td>Rollback();
<p>
fail(e)
   </td>
   <td>Rollback();
<p>
panic(e)
   </td>
  </tr>
</table>

Third, the rollback handler (described below) will get a willRetry argument, indicating whether the function will be retried.

<h2 id="testing-for-transaction-mode">Testing for transaction mode</h2>

We also have a boolean expression that evaluates to true if the current strand is in transaction mode.

```
transactional-expr := "transactional"
```

We can then do something like what we do with an `is` expression and type narrowing with conditional statements, e.g.


```
if transactional {
  // We are in transaction mode
  // So this scope is transactional.
  // So I can now call a function foo declared as transactional
  foo();
}
else {
   // give an error
   // do something appropriate for non-transactional case
}
```

<h2 id="langlib-transaction-module">Langlib transaction module</h2>

Operations on the current transaction that do not affect the transaction mode are provided by functions in a langlib lang.transaction module. These are declared as transactional, so they are allowed only in a transactional scope. An important function is be one that provides information about the current transaction:


```
    // lang.transaction
    # Information about a transaction that does not change
    # after the transaction is started.
    type Info readonly & record {|
       // unique identifier
       byte[] xid;
       // non-zero means this transaction was a retry of 
       // a previous one
       int retryNumber;
       // probably useful for timeouts and logs
       timestamp startTime;
       // maybe useful
       Info? prevAttempt;
    |};
    # Returns information about the current transaction
    public transactional function info() returns Info = external;
    # Returns information about the transaction with
    # the specified xid.
    # XXX need better names for the info/getInfo pair
    public function getInfo(byte[] xid) returns Info? = external;
    public transactional function setRollbackOnly(error? e)
       = external;
    public transactional function getRollbackOnly()
       returns boolean = external;
    public transactional function setData(readonly data)
      = external;
    // returns () if no data has been set
    public transactional function getData() returns readonly
      = external;
```

Note that this langlib module only defines the interface between the application and the transaction manager. It doesn't provide the interface between the resource manager and the transaction manager (such as is defined by the XA spec).

In a future version, we can add functions to control isolation levels.

Issues

*   Decide on the exact set of functions.
*   Should we separate information about transaction that is fixed after the transaction is created and information that can change during the lifetime of a transaction?

<h2 id="distributed-transactions">Distributed transactions</h2>

With distributed transactions, a global transaction consists of multiple transaction branches, where a branch corresponds to work done by one strand of a Ballerina program that is part of the global transaction. Every transaction branch is uniquely identified by an XID, which consists of an identifier of the global transaction and an identifier of a branch with the global transaction. A strand's stack of transactions is actually a stack of transaction branches.

A global transaction involving two Ballerina programs, A and B, works like this:

*   program A uses the transaction statement to create a new global transaction
*   program A creates a client object that is transaction-aware
    *   remote methods on the client object may support transactions optionally or may require them
    *   a remote method that can only be used within a transaction would be declared as transactional
*   program B creates a Listener than is transaction-aware
    *   resource methods on the service may support transactions optionally or may require them
    *   a resource method that can only be used within a transaction would be declared as transactional
*   program A calls a remote method on the client object
*   the client object and transaction manager on program A coordinate with the Listener and transaction manager on program B as a result of which
    *   a new transaction branch with its own XID is created for the work to be done in program B by the resource method to be called by the Listener
    *   the transaction managers on both program A and program B know about this
*   the Listener chooses which resource method to call and creates a new strand to call it on
*   the Listener puts the strand into transaction mode and associates it with the new transaction branch
*   the Listener then calls the resource method
*   program B cannot commit or rollback the transaction started by program A
*   program B can use SetRollbackOnly() if it wants to force the global transaction not to commit
*   use of a transaction statement by program B will start a new global transaction independent of the transaction started by A

Requirements for making all of the above work include:

1. a network protocol for program A and B to communicate about the transaction, such as the Ballerina Micro Transaction Protocol
2. a library API that allows a Ballerina Listener or client object to communicate with the program's transaction manager

Neither of these are defined by the Ballerina _language_, but eventually both of them would be part of the Ballerina _platform_.

Note that:

*   it is not necessary for program A and program B to both be in Ballerina, provided program A and program B agree on the network protocol
*   the library API would initially be a Java API; eventually it should be possible to write a Listener completely in Ballerina, which would require a Ballerina API.

<h2 id="commit-rollback-handlers">Commit/rollback handlers</h2>

An application may want to take different actions depending on whether a transaction committed or was rolled back. In a non-distributed scenario, it can simply use the result of the commit action to decide what to do. However, this is rather inconvenient from a modularity perspective. In a distributed scenario, it becomes much more inconvenient, because, in the absence of some built-in support, it would require a separate application-level network interaction.

We therefore provide the ability to get a _handler_ called when the transaction completes. A handler is just a function, which may as usual be a closure. This works using two functions in lang.transaction that register a handler, which will get called when the transaction completes.


```
// lang.transaction
public type CommitHandler function(Info info);
public type RollbackHandler
    function(Info info, error? cause, boolean willRetry);
public transactional function onCommit(CommitHandler handler)
    = external;
public transactional function onRollback(RollbackHandler handler)
    = external;
```

These functions register handlers with the transaction manager, which are associated with a transaction branch. They can be used not just within the scope of a transaction statement, but anywhere in a transactional scope. Multiple handlers can be registered: they will all be called in reverse of the order in which they were registered.

The handlers are called by the transaction manager as part of the Commit() and Rollback() operations. The Commit() operation will call a handler registered with onCommit only if the result of the first phase is a decision to commit; if the decision is to rollback, then any handlers registered with onRollback will be called instead. The Rollback() operation will always call the handlers registered with onRollback. Handlers are always called on the strand on which they were registered. If the transaction branch was the root branch, i.e. it was created using the transaction statement, then the handlers will be called as part of the execution of the transaction statement, commit action or rollback statement.

In the case of a transaction branch created by a Listener for a resource method, it works like this. Handlers that have been registered for a transaction branch during the execution of a resource method will be executed after the resource method returns and a decision has been made whether to commit or rollback the global transaction to which the branch belongs. For any registered handlers h1 and h2, the strands used to execute h1 and h2 must be distinct if and only if the strands used to register h1 and h2 were distinct.

A RollbackHandler has a  `willRetry` parameter, which allows an application to perform some actions only if the transaction is not going to be retried. We need to adjust the semantics of transaction-stmt and of the Commit() and Rollback () operations as follows to allow the willRetry parameter to get the RollbackHandler:


*   A RetryManager can be provided to the Commit() and Rollback() abstract operations as an optional parameter.
*   When this parameter is provided, the operations outcome includes an indication of whether the transaction should be retried.
*   The retry-transaction-stmt provides its RetryManager to the Commit() and Rollback() operations that it performs; shouldRetry is called by these operations rather than directly by retry-transaction-stmt.
*   A Commit(r) operation works as follows:
    *   run the first phase of the commit in order to determine whether the transaction should commit
    *   if the decision is to commit, then
        *   initiate commit for the participants
        *   call the commit handlers
    *   if the decision is to rollback,
        *   initiate rollback for the participants
        *   call shouldRetry to get the willRetry value
        *   call the rollback handlers
    *   return the willRetry value
    *   if a commit or rollback handler panics, then the outcome of the Commit operation is a panic.

Issues

1. If shouldRetry sleeps in order to force a delay before retrying, then the transaction manager won't be able to use the sleep time to communicate with remote transaction managers, because they will want to know the willRetry value in order to call handlers registered with them. Could instead have shouldRetry return a number saying how long to sleep before retrying. 

<h2 id="new-strands">New strands</h2>


Ballerina provides two language constructs that result in the creation of a new strand; these are `start` and named workers. These interact with transactions as follows.

A named worker can be declared as `transactional`. This is only allowed within the body of function that is itself declared as `transactional`. The scope of a named worker is transactional if and only if it is declared as `transactional`. The effect at runtime is to create a new transaction branch that is joined to the current transaction (as in a distributed transaction) and to push this transaction branch onto the strand created for the named worker. Commit and rollback handlers are run by the transaction manager, after the worker returns and the outcome of the transaction is known, as with transaction branches created for distributed transactions.

So, for example, if `barTx` is a function declared as `transactional`, this would be an error


```
transactional function fooTx() {
   worker X {
     barTx();
   }
}
```


but  this  would be allowed:


```
transactional function fooTx() {
   transactional worker X {
     barTx();
   }
}
```


Similarly, within a transactional scope, using `start` to call a function declared as `transactional` would not be an error; instead, it would result in the creation of a new transaction branch which will be pushed on the transaction stack of the strand used to run the function.

So this would be an error:


```
function foo() {
   start barTx();
}
```


but this would be allowed:


```
transactional function foo() {
   start barTx();
}
```


<h2 id="leveraging-new-check-semantics">Leveraging new check semantics</h2>


The new semantics for check provides a foundation for solving #[337](https://github.com/ballerina-platform/ballerina-spec/issues/337). This is not needed in order to be able to implement the transactions feature.

<h3 id="fail-expression-action">Fail expression/action</h3>


Saying "check err" to cause failure of a statement when err is known to be an error is rather confusing, so we can add a new keyword `fail` for this. If err is a subtype of error, then the following are equivalent:


```
    check err;
    fail err;
```


<h3>On fail clause</h3>


Idea is:


```
do {
   check foo();
   check bar();
}
on fail var e {
   // this will be executed if the block-stmt following do fails
   // which will happen if and only if one of the two
   // check actions fails
   // type of e will be union of the error types that can be
   // returned by foo and bar
   io:println("whoops");
   return e;
}
```


Note that `on fail` catches failures (from `fail` statement or failure of a check expression) not panics.

We are already using `do` with query, but we can unify these two usages as follows. At the moment a block-stmt is a statement (as usual in C-family languages), so you can do e.g.


```
if x {
   {
      int i = 1;
      foo(i);
   }
   {
      int i = 2;
      foo(i);
   }
}
```


We could instead use `do` for this, i.e.


```
if x {
   do {
      int i = 1;
      foo(i);
   }
   do {
      int i = 2;
      foo(i);
   }
}
```


Then we say the `on fail` clause can optionally be applied to various kinds of block-stmt, including `do` and the new kinds of block statement proposed below.

Issue:

1. Should it be `onfail` (one word) or `on fail` (two words)? Have used two words to be consistent with `on conflict` in query expressions.

<h2 id="implementation-staging">Implementation staging</h2>


1. One resource manager (e.g. one database), one Ballerina program (no two phase commit or other substantial functionality needed from Ballerina transaction manager; ACID properties provided by database)
2. Multiple resource managers, one Ballerina program (transaction manager needs to run two phase commit; full ACID would require durability from the Ballerina transaction manager)
3. Multiple resource managers, multiple Ballerina programs (i.e. transactional services and micro-transaction protocol)
4. Multiple resource managers, multiple programs in multiple languages (i.e. transactional services and micro-transaction protocol standardized)
