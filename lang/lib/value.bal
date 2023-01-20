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

# The type of value to which `clone` and `cloneReadOnly` can be applied.
public type Cloneable readonly|xml|Cloneable[]|map<Cloneable>|table<map<Cloneable>>;

# A type parameter that is a subtype of `Cloneable`.
# Has the special semantic that when used in a declaration
# all uses in the declaration must refer to same type.
@typeParam
type CloneableType Cloneable;

# Returns a clone of `v`.
# A clone is a deep copy that does not copy immutable subtrees.
# A clone can therefore safely be used concurrently with the original.
# It corresponds to the Clone(v) abstract operation,
# defined in the Ballerina Language Specification.
#
# + v - source value
# + return - clone of `v`
public isolated function clone(CloneableType v) returns CloneableType = external;

# Returns a clone of `v` that is read-only, i.e. immutable.
# It corresponds to the ImmutableClone(v) abstract operation,
# defined in the Ballerina Language Specification.
#
# + v - source value
# + return - immutable clone of `v`
public isolated function cloneReadOnly(CloneableType v) returns CloneableType & readonly = external;

# Constructs a value with a specified type by cloning another value.
# + v - the value to be cloned
# + t - the type for the cloned to be constructed
# + return - a new value that belongs to type `t`, or an error if this cannot be done
# 
# When `v` is a structural value, the inherent type of the value to be constructed
# comes from `t`. When `t` is a union that includes more than one type descriptor
# that can be used as the inherent type of values with `v`'s basic type, then
# the inherent type used will be the first (leftmost) such type descriptor such that a value
# belonging to that type can be constructed from `v`.
# The `cloneWithType` operation is recursively applied to each member of `v` using
# the type descriptor that the inherent type requires for that member.
# 
# Like the Clone abstract operation, this does a deep copy, but differs in
# the following respects:
# - the inherent type of any structural values constructed comes from the specified
#   type descriptor rather than the value being constructed
# - the read-only bit of values and fields comes from the specified type descriptor
# - the graph structure of `v` is not preserved; the result will always be a tree;
#   an error will be returned if `v` has cycles
# - immutable structural values are copied rather than being returned as is
# - numeric values can be converted using the NumericConvert abstract operation
# - if a record type descriptor specifies default values, these will be used
#   to supply any missing members
public isolated function cloneWithType(anydata v, typedesc<anydata> t = <>) returns t|error = external;

# Safely casts a value to a type.
# This casts a value to a type in the same way as a type cast expression,
# but returns an error if the cast cannot be done, rather than panicking.
# + v - the value to be cast
# + t - a typedesc for the type to which to cast it
# return - `v` cast to the type described by `t`, or an error, if the cast cannot be done
public isolated function ensureType(any|error v, typedesc<any> t = <>) returns t|error = external;

# Performs a direct conversion of a value to a string.
# The conversion is direct in the sense that when applied to a value that is already
# a string it leaves the value unchanged.
#
# + v - the value to be converted to a string
# + return - a string resulting from the conversion
#
# The details of the conversion are specified by the ToString abstract operation
# defined in the Ballerina Language Specification, using the direct style.
public isolated function toString(any v) returns string = external;

# Converts a value to a string that describes the value in Ballerina syntax.
# + v - the value to be converted to a string
# + return - a string resulting from the conversion
#
# If `v` is anydata and does not have cycles, then the result will
# conform to the grammar for a Ballerina expression and when evaluated
# will result in a value that is == to v.
#
# The details of the conversion are specified by the ToString abstract operation
# defined in the Ballerina Language Specification, using the expression style.
public isolated function toBalString(any v) returns string = external;

# Parses and evaluates a subset of Ballerina expression syntax.
# + s - the string to be parsed and evaluated
# return - the result of evaluating the parsed expression, or
# an error if the string cannot be parsed
# The subset of Ballerina expression syntax supported is that produced
# by toBalString when applied to an anydata value.
public isolated function fromBalString(string s) returns anydata|error = external;

// JSON conversion

# Converts a value of type `anydata` to `json`.
# This does a deep copy of `v` converting values that do
# not belong to json into values that do.
# A value of type `xml` is converted into a string as if
# by the `toString` function.
# A value of type `table` is converted into a list of
# mappings one for each row.
# The inherent type of arrays in the return value will be
# `json[]` and of mappings will be `map<json>`.
# A new copy is made of all structural values, including
# immutable values.
#
# + v - anydata value
# + return - representation of `v` as value of type json
# This panics if `v` has cycles.
public isolated function toJson(anydata v) returns json = external;

# Returns the string that represents `v` in JSON format.
# `v` is first converted to `json` as if by the `toJson` function.
#
# + v - anydata value
# + return - string representation of `v` converted to `json`
public isolated function toJsonString(anydata v) returns string = external;

# Parses a string in JSON format and returns the value that it represents.
# Numbers in the JSON string are converted into Ballerina values of type
# decimal except in the following two cases:
# if the JSON number starts with `-` and is numerically equal to zero, then it is
# converted into float value of `-0.0`;
# otherwise, if the JSON number is syntactically an integer and is in the range representable
# by a Ballerina int, then it is converted into a Ballerina int.
# A JSON number is considered syntactically an integer if it contains neither
# a decimal point nor an exponent.
# 
# Returns an error if the string cannot be parsed.
#
# + str - string in JSON format
# + return - `str` parsed to json or error
public isolated function fromJsonString(string str) returns json|error = external;

# Subtype of `json` that allows only float numbers.
public type JsonFloat ()|boolean|string|float|JsonFloat[]|map<JsonFloat>;

# Parses a string in JSON format, using float to represent numbers.
# Returns an error if the string cannot be parsed.
#
# + str - string in JSON format
# + return - `str` parsed to json or error
public isolated function fromJsonFloatString(string str) returns JsonFloat|error = external;

# Subtype of `json` that allows only decimal numbers.
public type JsonDecimal ()|boolean|string|decimal|JsonDecimal[]|map<JsonDecimal>;

# Parses a string in JSON format, using decimal to represent numbers.
# Returns an error if the string cannot be parsed.
#
# + str - string in JSON format
# + return - `str` parsed to json or error
public isolated function fromJsonDecimalString(string str) returns JsonDecimal|error = external;

# Converts a value of type json to a user-specified type.
# This works the same as `cloneWithType`,
# except that it also does the inverse of the conversions done by `toJson`.
#
# + v - json value
# + t - type to convert to
# + return - value belonging to type `t` or error if this cannot be done
public isolated function fromJsonWithType(json v, typedesc<anydata> t = <>)
    returns t|error = external;

# Converts a string in JSON format to a user-specified type.
# This is a combination of `fromJsonString` followed by
# `fromJsonWithType`.
# + str - string in JSON format
# + t - type to convert to
# + return - value belonging to type `t` or error if this cannot be done
public isolated function fromJsonStringWithType(string str, typedesc<anydata> t = <>)
    returns t|error = external;
    
# Merges two json values.
#
# + j1 - json value
# + j2 - json value
# + return - the merge of `j1` with `j2` or an error if the merge fails
#
# The merge of `j1` with `j2` is defined as follows:
# - if `j1` is `()`, then the result is `j2`
# - if `j2` is `()`, then the result is `j1`
# - if `j1` is a mapping and `j2` is a mapping, then for each entry [k, j] in j2,
#   set `j1[k]` to the merge of `j1[k]` with `j`
#     - if `j1[k]` is undefined, then set `j1[k]` to `j`
#     - if any merge fails, then the merge of `j1` with `j2` fails
#     - otherwise, the result is `j1`.
# - otherwise, the merge fails
# If the merge fails, then `j1` is unchanged.
public isolated function mergeJson(json j1, json j2) returns json|error = external;
