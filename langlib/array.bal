// XXX should this module be called list or array?
@typeParam
private type Type = any|error;
@typeParam
private type Type1 = any|error;
@typeParam
private type PureType = anydata|error;

// Previously built-in methods
# Freezes `arr` and returns it
public function clone(PureType[] arr) returns PureType[] = external;
# Returns clone of `arr` that is not frozen
public function freeze(PureType[] arr) returns PureType[] = external;
public function unfrozenClone(PureType[] arr) returns PureType[] = external;
# Tests whether `arr` is frozen
public function isFrozen((any|error)[] arr) returns boolean = external;
# Returns number of members in `arr`.
public function length((any|error)[] arr) returns int = external;
# Returns an iterator over the members of `arr`
public function iterator(Type[] arr) returns abstract object {
    public next() returns record {|
        Type value;
    |}?;
} = external;
public function enumerate(Type[] arr) returns [int, Type][] = external;

// Functional iteration

// use delimited identifer for function name to avoid conflict with reserved name
public function ^"map"(Type[] arr, function(Type val) returns Type1 func) returns Type1[] = external;
# Applies `func` to each member of `arr`.
public function forEach(Type[] arr, function(Type val) returns () func) returns () = external;
public function filter(Type[] arr, function(Type val) returns boolean func) returns Type[] = external;
public function reduce(Type[] arr, function(Type1 accum, Type val) returns Type1 func, Type1 initial) returns Type1 = external;


// subarray
public function slice(Type[] arr, int start, int end = arr.length()) returns Type[] = external;

# Returns index of first member of `arr` that is equal to `val`
# Equality is tested using `==`
# Returns nil if not found
public function indexOf(PureType[] arr, PureType val, int startIndex = 0) returns int? = external;
// XXX modifies arg?
public function reverse(Type[] arr) returns Type[] = external;
// XXX modifies arg?
public function sort(Type[] arr, function(Type val1, Type val2) returns int func) returns Type[] = external;
// Stack methods (JavaScript, Perl)
public function pop(Type[] arr) returns Type = external;
public function push(Type[] arr, Type... vals) returns () = external;
// Queue methods (JavaScript, Perl, shell)
public function shift(Type[] arr) returns Type = external;
public function unshift(Type[] arr, Type... vals) returns () = external;



