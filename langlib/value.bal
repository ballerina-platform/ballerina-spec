// Copyright (c) 2019 WSO2 Inc. (http://www.wso2.org) All Rights Reserved.
//
// WSO2 Inc. licenses this file to you under the Apache License,
// Version 2.0 (the "License"); you may not use this file except
// in compliance with the License.
// You may obtain a copy of the License at
//
// http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing,
// software distributed under the License is distributed on an
// "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
// KIND, either express or implied.  See the License for the
// specific language governing permissions and limitations
// under the License.

// Module lang.value
private type PureStructure = (anydata|error)[]|map<anydata|error>;

# A type parameter that is a subtype of `PureStructure`.
# Has the special semantic that when used in a declaration
# all uses in the declaration must refer to same type. 
@typeParam
private type PureStructureType = PureStructure;

@typeParam
private type AnydataType anydata;

// Functions that were previously built-in methods

# Freezes `struct` and returns it
public function clone(PureStructureType struct) returns PureStructureType = external;
# Returns clone of `struct` that is not frozee
public function freeze(PureStructureType struct) returns PureStructureType = external;
public function unfrozenClone(PureStructureType struct) returns PureStructureType = external;
# Tests whether `struct` is frozen
public function isFrozen(PureStructure struct) returns boolean = external;

# Modify the inherent type of a value
# + v - the value whose type is to be changed
# + t - the type to change to
# + return the value with its type changed, or an error if this cannot be done
# 
# The function first checks that `v` is a tree. If `v` is a reference value, and the graph
# structure of `v` is not a tree, then it returns an error.
# 
# If the shape of `v` is not a member of the set of shapes denoted by `t` (i.e. `v`
# does not look like `t`), then `setType` will attempt to modify it so that it is, by
# using numeric conversions (as defined by the NumericConvert operation) on
# members of containers and by adding fields for which a default value is defined.
# If this fails or can be done in more than one way, then `setType` will return an
# error. Frozen structures will not be modified, nor will new structures be created.
# 
# If at this point, the function has not yet returned an error, the shape of `v`
# will be in the set of shapes denoted by `t`. Now `setType` narrows the inherent type of `v`, and
# recursively of any members of `v`, so that the `v` belongs to `t`, and then returns `v`.
# Any frozen values in `v` are left unchanged by this.
public function setType(anydata v, typedesc<AnydataType> t) returns AnydataType|error = external;

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
public function convertTo(anydata v, typedesc<AnydataType> t) returns AnydataType|error = external;

// JSON conversion
# Return the string that represents `v` JSON format.
public function toJsonString(json v) returns string = external;
# Parse a string in JSON format and return the the value that it represents.
# All numbers in the JSON will be represented as float values.
# Returns an error if the string cannot be parsed.
public function fromJsonString(string str) returns json|error = external;
