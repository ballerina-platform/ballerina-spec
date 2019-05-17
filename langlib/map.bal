@typeParam
private type Type = any|error;
@typeParam
private type Type1 = any|error;
@typeParam
private type PureType = anydata|error;

# Returns number of members in `m`.
public function length(map<any|error> m) returns int = external;
# Returns an iterator over the members of `m`
public function iterator(map<Type> m) returns abstract object {
    public next() returns record {|
        Type value;
    |}?;
} = external;
public function entries(map<Type> m) returns map<[string, Type]> = external;

// Functional iteration

// use delimited identifer for function name to avoid conflict with reserved name
public function ^"map"(map<Type> m, function(Type val) returns Type1 func) returns map<Type1> = external;
# Applies `func` to each member of `m`.
public function forEach(map<Type> m, function(Type val) returns () func) returns () = external;
public function filter(map<Type> m, function(Type val) returns boolean func) returns map<Type> = external;
public function reduce(map<Type> m, function(Type1 accum, Type val) returns Type1 func, Type1 initial) returns Type1 = external;

// subarray
public function slice(map<Type> m, int start, int end = m.length()) returns map<Type> = external;

# Removes the member of `m` with key `k` and returns it.
# Panics if there is no such member
public function remove(map<Type> m, string k) returns Type = external;
# Tells whether m has a member with key `k`.
public function hasKey(map<Type> m, string k) returns boolean = external;
# Returns a list of all the keys of map `m`.
public function keys(map<any|error> m) returns string[] = external;