// Copyright (c) 2020 WSO2 Inc. (http://www.wso2.org) All Rights Reserved.
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

# Converts a string to a boolean.
# Returns the boolean of which `s` is a string representation.
# The accepted representations are `true`, `false`
# (in any combination of lower- and upper-case),
# and also `1` for true and `0` for `false`.
# This is the inverse of `value:toString` applied to a `boolean`.
#
# + s - string representing a boolean value
# + return - boolean that `s` represents, or an error if there is no such boolean
public isolated function fromString(string s) returns boolean|error = external;

# Tests whether at least one of a number of boolean values is true.
# 
# + bs - boolean values to operate on
# + return - true if one or more of its arguments are true and false otherwise;
#    false if there are no arguments
public isolated function some(boolean... bs) returns boolean = external;

# Tests whether every one of a number of boolean values is true.
# 
# + bs - boolean values to operate on
# + return - true if all of its arguments are true and false otherwise;
#    true if there are no arguments
public isolated function every(boolean... bs) returns boolean = external;
