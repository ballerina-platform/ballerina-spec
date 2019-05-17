@typeParam
private type Type = any|error;
@typeParam
private type Type1 = any|error;
@typeParam
private type PureType = anydata|error;

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

# Removes the member of `arr` and index `i` and returns it.
# Panics if `i` is out of range.
public function remove(Type[] arr, int i) returns Type = external;
// no return value to avoid need to ignore it
# Increase or decrease length.
public function setLength(Type[] arr, int i);

# Returns index of first member of `arr` that is equal to `val` if there is one.
# Returns `()` if not found
# Equality is tested using `==`
public function indexOf(PureType[] arr, PureType val, int startIndex = 0) returns int? = external;
# Reverse the order of the members of `arr`.
# Returns `arr`.
public function reverse(Type[] arr) returns Type[] = external;
# Sort `arr` using `func` to order members.
# Returns `arr`.
public function sort(Type[] arr, function(Type val1, Type val2) returns int func) returns Type[] = external;
// Stack-like methods (JavaScript, Perl)
// panic on fixed-length array
// compile-time error if known to be fixed-length
public function pop(Type[] arr) returns Type = external;
public function push(Type[] arr, Type... vals) returns () = external;
// Queue-like methods (JavaScript, Perl, shell)
// panic on fixed-length array
// compile-time error if known to be fixed-length
public function shift(Type[] arr) returns Type = external;
public function unshift(Type[] arr, Type... vals) returns () = external;



