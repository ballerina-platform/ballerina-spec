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

# A type parameter that is a subtype of `anydata`.
# Has the special semantic that when used in a declaration
# all uses in the declaration must refer to same type. 
@typeParam
type AnydataType = anydata;

// Functions that were previously built-in methods

# Returns a clone of `v`.
# A clone is a deep copy that does not copy immutable subtrees.
# A clone can therefore safely be used concurrently with the original.
# It corresponds to the Clone(v) abstract operation,
# defined in the Ballerina Language Specification. 
public function clone(AnydataType v) returns AnydataType = external;

# Returns a clone of `v` that is read-only, i.e. immutable.
# It corresponds to the ImmutableClone(v) abstract operation,
# defined in the Ballerina Language Specification. 
public function cloneReadOnly(AnydataType v) returns AnydataType = external;

# Tests whether `v` is read-only, i.e. immutable
# Returns true if read-only, false otherwise.
public function isReadOnly(anydata v) returns boolean = external;

# Returns a simple, human-readable representation of `v` as a string.
# - if `v` is a string, then returns `v`
# - if `v` is `()`, then returns an empty string
# - if `v` is boolean, then the string `true` or `false`
# - if `v` is an int, then return `v` represented as a decimal string
# - if `v` is a float or decimal, then return `v` represented as a decimal string,
#   with a decimal point only if necessary, but without any suffix indicating the type of `v`;
#   return `NaN`, `Infinity` for positive infinity, and `-Infinity` for negative infinity
# - if `v` is a list, then returns the results toString on each member of the list
#   separated by a space character
# - if `v` is a map, then returns key=value for each member separated by a space character
# - if `v` is xml, then returns `v` in XML format (as if it occurred within an XML element)
# - if `v` is table, TBD
# - if `v` is an error, then a string consisting of the following in order
#     1. the string `error`
#     2. a space character
#     3. the reason string
#     4. if the detail record is non-empty
#         1. a space character
#         2. the result of calling toString on the detail record
# - if `v` is an object, then
#     - if `v` provides a toString method with a string return type and no required methods,
#       then the result of calling that method on `v`
#     - otherwise, `object` followed by some implementation-dependent string
# - if `v` is any other behavioral type, then the identifier for the behavioral type
#   (`function`, `future`, `service`, `typedesc` or `handle`)
#   followed by some implementation-dependent string
# 
# Note that `toString` may produce the same string for two Ballerina values
# that are not equal (in the sense of the `==` operator).
public function toString((any|error) v) returns string = external;

// JSON conversion

# Return the string that represents `v` in JSON format.
public function toJsonString(json v) returns string = external;

# Parse a string in JSON format and return the the value that it represents.
# All numbers in the JSON will be represented as float values.
# Returns an error if the string cannot be parsed.
public function fromJsonString(string str) returns json|error = external;

# Return the result of merging json value `j1` with `j2`.
# If the merge fails, the return an error.
# The merge of j1 with j2 is defined as follows:
# - if j1 is (), then the result is j2
# - if j2 is nil, then the result is j1
# - if j1 is a mapping and j2 is a mapping, then for each entry [k, j] in j2,
#   set j1[k] to the merge of j1[k] with j
#     - if j1[k] is undefined, then set j1[k] to j
#     - if any merge fails, then the merge of j1 with j2 fails
#     - otherwise, the result is j1.
# - otherwise, the merge fails
public function mergeJson(json j1, json j2) returns json|error = external;