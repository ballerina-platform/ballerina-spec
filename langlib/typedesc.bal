
@typeParam
private type AnydataType anydata;

# Modify the inherent type of a value
# + t - the type to change to
# + v - the value whose type is to be changed
# + return the value with its type changed, or an error if this cannot be done
# 
# The function first checks that `v` is a tree. If `v` is a reference value, and the graph
# structure of `v` is not a tree, then it returns an error.
# 
# If the shape of `v` is not a member of the set of shapes denoted by `t` (i.e. `v`
# does not look like `t`), then stamp will attempt to modify it so that it is, by
# using numeric conversions (as defined by the NumericConvert operation) on
# members of containers and by adding fields for which a default value is defined.
# If this fails or can be done in more than one way, then stamp will return an
# error. Frozen structures will not be modified, nor will new structures be created.
# 
# If at this point, the function has not yet returned an error, the shape of `v`
# will be in the set of shapes denoted by `t`. Now stamp narrows the inherent type of `v`, and
# recursively of any members of `v`, so that the `v` belongs to `t`, and then returns `v`.
# Any frozen values in `v` are left unchanged by this.
public function stamp(typedesc<AnydataType> t, anydata v) returns AnydataType|error = external;

# Create a copy of a value with a specified inherent type.
# + t - the type for the copy to be created
# + v - the value to be copied
# + return a new value of type `t`, or an error if this cannot be done
# 
# The function first checks that `v` is a tree. If v `is` a reference value, and the graph
# structure of `v` is not a tree, then it returns an error.
# 
# The function now creates a new value that has the same shape as `v`, except
# possibly for differences in numeric types and for the addition of fields for
# which a default value is defined, but belongs to type `t`.
public function convert(typedesc<AnydataType> t, anydata v) returns AnydataType|error = external;
