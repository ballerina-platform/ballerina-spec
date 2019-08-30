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

// XXX this will panic for the most negative value (-2^63 is an int but +2^63 isn't)
// consistent with policy on integer overflow

# Returns absolute value of an int.
#
# + n - int value to be operated on
# + return - absolute value of `n`
public function abs(int n) returns int = external;

# Returns sum of zero or more int values.
#
# + ns - int values to sum
# + return - sum of all the `ns`; 0 is `ns` is empty
public function sum(int... ns) returns int = external;

# Maximum of one or more int values.
#
# + n - first int value
# + ns - other int values
# + return - maximum value of value of `x` and all the `xs`
public function max(int n, int... ns) returns int = external;

# Minimum of one or more int values
#
# + n - first int value
# + ns - other int values
# + return - minimum value of `n` and all the `ns`
public function min(int n, int... ns) returns int = external;

# Returns the integer that `s` represents in decimal.
# Returns error if `s` is not the decimal representation of an integer.
# The first character may be `+` or `-`.
# This is the inverse of `value:toString` applied to an `int`.
#
# + s - string representation of a integer value
# + return - int representation of the argument or error
public function fromString(string s) returns int|error = external;

# Returns representation of `n` as hexdecimal string.
# There is no `0x` prefix. Lowercase letters a-f are used.
# Negative numbers will have a `-` prefix. No sign for
# non-negative numbers.
#
# + n - int value
# + return - hexadecimal string representation of int value
public function toHexString(int n) returns string = external;

# Returns the integer that `s` represents in hexadecimal.
# Both uppercase A-F and lowercase a-f are allowed.
# It may start with an optional `+` or `-` sign.
# No `0x` or `0X` prefix is allowed.
# Returns an error if the `s` is not in an allowed format.
#
# + s - hexadecimal string representation of int value
# + return - int value or error
public function fromHexString(string s) returns int|error = external;
