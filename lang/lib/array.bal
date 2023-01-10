// Copyright (c) 2019, 2020 WSO2 Inc. (http://www.wso2.org) All Rights Reserved.
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

# A type parameter that is a subtype of `any|error`.
# Has the special semantic that when used in a declaration
# all uses in the declaration must refer to same type.
@typeParam
type Type any|error;

# A type parameter that is a subtype of `any|error`.
# Has the special semantic that when used in a declaration
# all uses in the declaration must refer to same type.
@typeParam
type Type1 any|error;

# A type parameter that is a subtype of `anydata|error`.
# Has the special semantic that when used in a declaration
# all uses in the declaration must refer to same type.
@typeParam
type AnydataType anydata;

# Returns the number of members of an array.
#
# ```
# ["a", "b", "c", "d"].length() ⇒ 4
# ```
#
# + arr - the array
# + return - number of members in `arr`
public isolated function length((any|error)[] arr) returns int = external;

# Returns an iterator over an array.
#
# ```
# object {
#     public isolated function next() returns record {|int value;|}?;
# } iterator = [2, 4, 6, 8].iterator();
# iterator.next() ⇒ {"value":2}
# ```
#
# + arr - the array
# + return - a new iterator object that will iterate over the members of `arr`.
public isolated function iterator(Type[] arr) returns object {
    public isolated function next() returns record {|
        Type value;
    |}?;
} = external;

# Returns a new array consisting of index and member pairs.
#
# ```
# [1, 2, 3, 4].enumerate() ⇒ [[0,1],[1,2],[2,3],[3,4]]
# ```
#
# + arr - the array
# + return - array of index, member pairs
public isolated function enumerate(Type[] arr) returns [int, Type][] = external;

// Functional iteration

# Applies a function to each member of an array and returns an array of the results.
#
# ```
# int[] numbers = [0, 1, 2];
# numbers.map(n => n * 2) ⇒ [0,2,4]
# ```
#
# + arr - the array
# + func - a function to apply to each member
# + return - new array containing result of applying `func` to each member of `arr` in order
public isolated function 'map(Type[] arr, @isolatedParam function(Type val) returns Type1 func) returns Type1[] = external;

# Applies a function to each member of an array.
# The function `func` is applied to each member of array `arr` in order.
#
# ```
# int total = 0;
# [1, 2, 3].forEach(function (int i) {
#     total += i;
# });
# total ⇒ 6
# ```
#
# + arr - the array
# + func - a function to apply to each member
public isolated function forEach(Type[] arr, @isolatedParam function(Type val) returns () func) returns () = external;

# Selects the members from an array for which a function returns true.
#
# ```
# int[] numbers = [12, 43, 60, 75, 10];
# numbers.filter(n => n > 50) ⇒ [60,75]
# ```
#
# + arr - the array
# + func - a predicate to apply to each member to test whether it should be selected
# + return - new array only containing members of `arr` for which `func` evaluates to true
public isolated function filter(Type[] arr, @isolatedParam function(Type val) returns boolean func) returns Type[] = external;

# Combines the members of an array using a combining function.
# The combining function takes the combined value so far and a member of the array,
# and returns a new combined value.
#
# ```
# [1, 2, 3].reduce(isolated function (int total, int next) returns int => total + next, 0) ⇒ 6
# ```
#
# + arr - the array
# + func - combining function
# + initial - initial value for the first argument of combining function `func`
# + return - result of combining the members of `arr` using `func`
#
# For example
# ```
# reduce([1, 2, 3], function (int total, int n) returns int { return total + n; }, 0)
# ```
# is the same as `sum(1, 2, 3)`.
public isolated function reduce(Type[] arr, @isolatedParam function(Type1 accum, Type val) returns Type1 func, Type1 initial) returns Type1 = external;

# Tests whether a function returns true for some member of an array.
# `func` is called for each member of `arr` in order unless and until a call returns true.
# When the array is empty, returns false.
#
# ```
# int[] numbers = [1, 2, 3, 5];
# numbers.some(n => n % 2 == 0) ⇒ true
# ```
#
# + arr - the array
# + func - function to apply to each member
# + return - true if func returns true for some member of `arr`; otherwise, false
public isolated function some(Type[] arr, @isolatedParam function(Type val) returns boolean func) returns boolean = external;

# Tests whether a function returns true for every member of an array.
# `func` is called for each member of `arr` in order unless and until a call returns false.
# When the array is empty, returns true.
#
# ```
# int[] numbers = [1, 2, 3, 5];
# numbers.every(n => n % 2 == 0) ⇒ false
# ```
#
# + arr - the array
# + func - function to apply to each member
# + return - true if func returns true for every member of `arr`; otherwise, false
public isolated function every(Type[] arr, @isolatedParam function(Type val) returns boolean func) returns boolean = external;

# Returns a slice of an array.
#
# ```
# int[] numbers = [2, 4, 6, 8, 10, 12];
#
# numbers.slice(3) ⇒ [8,10,12]
#
# numbers.slice(0, 4) ⇒ [2,4,6,8]
#
# numbers.slice(0, 10) ⇒ panic
# ```
#
# + arr - the array
# + startIndex - index of first member to include in the slice
# + endIndex - index of first member not to include in the slice
# + return - new array containing members of `arr` with index >= `startIndex` and < `endIndex` 
public isolated function slice(Type[] arr, int startIndex, int endIndex = arr.length()) returns Type[] = external;

# Removes a member of an array.
#
# ```
# int[] numbers = [2, 4, 6, 8];
#
# numbers.remove(1) ⇒ 4
#
# numbers.remove(7) ⇒ panic
# ```
#
# + arr - the array
# + index - index of member to be removed from `arr`
# + return - the member of `arr` that was at `index`
# This removes the member of `arr` with index `index` and returns it.
# It panics if there is no such member.
public isolated function remove(Type[] arr, int index) returns Type = external;

# Removes all members of an array.
#
# ```
# int[] numbers = [2, 4, 6, 8];
# numbers.removeAll();
# numbers ⇒ []
#
# int[2] values = [1, 2];
# values.removeAll() ⇒ panic
# ```
#
# + arr - the array
# Panics if any member cannot be removed.
public isolated function removeAll((any|error)[] arr) returns () = external;

# Changes the length of an array.
#
# ```
# int[] numbers = [2, 4, 6, 8];
#
# numbers.setLength(2);
# numbers ⇒ [2,4]
#
# numbers.setLength(0);
# numbers ⇒ []
# ```
# 
# + arr - the array of which to change the length
# + length - new length
# `setLength(arr, 0)` is equivalent to `removeAll(arr)`.
public isolated function setLength((any|error)[] arr, int length) returns () = external;

# Returns the index of first member of `arr` that is equal to `val` if there is one.
# Returns `()` if not found.
# Equality is tested using `==`.
#
# ```
# string[] strings = ["a", "b", "d", "b", "d"];
#
# strings.indexOf("e") is () ⇒ true
#
# strings.indexOf("b") ⇒ 1
#
# strings.indexOf("b", 2) ⇒ 3
# ```
#
# + arr - the array
# + val - member to search for
# + startIndex - index to start the search from
# + return - index of the member if found, else `()`
public isolated function indexOf(AnydataType[] arr, AnydataType val, int startIndex = 0) returns int? = external;

# Returns the index of last member of `arr` that is equal to `val` if there is one.
# Returns `()` if not found.
# Equality is tested using `==`.
#
# ```
# string[] strings = ["a", "b", "d", "b", "d", "b"];
#
# strings.lastIndexOf("e") is () ⇒ true
#
# strings.lastIndexOf("b") ⇒ 5
#
# strings.lastIndexOf("b", strings.length() - 2) ⇒ 3
# ```
#
# + arr - the array
# + val - member to search for
# + startIndex - index to start searching backwards from
# + return - index of the member if found, else `()`
public isolated function lastIndexOf(AnydataType[] arr, AnydataType val, int startIndex = arr.length() - 1) returns int? = external;

# Reverses the order of the members of an array.
#
# ```
# [2, 4, 12, 8, 10].reverse() ⇒ [10,8,12,4,2]
# ```
#
# + arr - the array to be reversed
# + return - new array with the members of `arr` in reverse order
public isolated function reverse(Type[] arr) returns Type[] = external;

# Direction for `sort` function.
public enum SortDirection {
   ASCENDING = "ascending",
   DESCENDING = "descending"
}

# A type of which any ordered type must be a subtype.
# Whether a type is an ordered type cannot be defined in
# terms of being a subtype of a type, so being a subtype
# of `OrderedType` is a necessary but not sufficient condition
# for a type to be an ordered type.
public type OrderedType ()|boolean|int|float|decimal|string|OrderedType[];

# Sorts an array.
# If the member type of the array is not sorted, then the `key` function
# must be specified.
# Sorting works the same as with the `sort` clause of query expressions.
#
# ```
# string[] strings = ["c", "a", "B"];
#
# strings.sort() ⇒ ["B","a","c"]
#
# strings.sort("descending") ⇒ ["c","a","B"]
#
# strings.sort(key = string:toLowerAscii) ⇒ ["a","B","c"]
#
# strings.sort("descending", string:toLowerAscii) ⇒ ["c","B","a"]
# ```
#
# + arr - the array to be sorted; 
# + direction - direction in which to sort
# + key - function that returns a key to use to sort the members
# + return - new array consisting of the members of `arr` in sorted order
public isolated function sort(Type[] arr, SortDirection direction = ASCENDING,
        (isolated function(Type val) returns OrderedType)? key = ()) returns Type[] = external;

// Stack-like methods (JavaScript, Perl)
// panic on fixed-length array
// compile-time error if known to be fixed-length

# Removes and returns the last member of an array.
# The array must not be empty.
#
# ```
# int[] numbers = [2, 4, 6, 8, 10];
# numbers.pop() ⇒ 10
#
# int[] values = [];
# values.pop() ⇒ panic
# ```
#
# + arr - the array
# + return - removed member
public isolated function pop(Type[] arr) returns Type = external;

# Adds values to the end of an array.
#
# ```
# int[] numbers = [2];
#
# numbers.push(4, 6);
# numbers ⇒ [2,4,6]
#
# int[] moreNumbers = [8, 10, 12, 14];
# numbers.push(...moreNumbers);
# numbers ⇒ [2,4,6,8,10,12,14]
# ```
#
# + arr - the array
# + vals - values to add to the end of the array
public isolated function push(Type[] arr, Type... vals) returns () = external;

// Queue-like methods (JavaScript, Perl, shell)
// panic on fixed-length array
// compile-time error if known to be fixed-length

# Removes and returns first member of an array.
# The array must not be empty.
#
# ```
# int[] numbers = [2, 4, 6, 8, 10];
# numbers.shift() ⇒ 2
#
# int[] values = [];
# values.shift() ⇒ panic
# ```
#
# + arr - the array
# + return - the value that was the first member of the array
public isolated function shift(Type[] arr) returns Type = external;

# Adds values to the start of an array.
# The values newly added to the array will be in the same order
# as they are in `vals`.
#
# ```
# int[] numbers = [14];
#
# numbers.unshift(10, 12);
# numbers ⇒ [10,12,14]
#
# int[] moreNumbers = [2, 4, 6, 8];
# numbers.unshift(...moreNumbers);
# numbers ⇒ [2,4,6,8,10,12,14]
# ```
#  
# + arr - the array
# + vals - values to add to the start of the array
public isolated function unshift(Type[] arr, Type... vals) returns () = external;

// Conversion

# Returns the string that is the Base64 representation of an array of bytes.
# The representation is the same as used by a Ballerina Base64Literal.
# The result will contain only characters  `A..Z`, `a..z`, `0..9`, `+`, `/` and `=`.
# There will be no whitespace in the returned string.
#
# ```
# byte[] byteArray = [104, 101, 108, 108, 111, 32, 98, 97];
# byteArray.toBase64() ⇒ aGVsbG8gYmE=
# ```
#
# + arr - the array
# + return - Base64 string representation
public isolated function toBase64(byte[] arr) returns string = external;

# Returns the byte array that a string represents in Base64.
# `str` must consist of the characters `A..Z`, `a..z`, `0..9`, `+`, `/`, `=`
# and whitespace as allowed by a Ballerina Base64Literal.
#
# ```
# array:fromBase64("aGVsbG8gYmE=") ⇒ [104,101,108,108,111,32,98,97]
#
# array:fromBase64("aGVsbG8gYmE--") ⇒ error
# ```
#
# + str - Base64 string representation
# + return - the byte array or error
public isolated function fromBase64(string str) returns byte[]|error = external;

# Returns the string that is the Base16 representation of an array of bytes.
# The representation is the same as used by a Ballerina Base16Literal.
# The result will contain only characters  `0..9`, `a..f`.
# There will be no whitespace in the returned string.
#
# ```
# byte[] byteArray = [170, 171, 207, 204, 173, 175, 205];
# byteArray.toBase16() ⇒ aaabcfccadafcd
# ```
#
# + arr - the array
# + return - Base16 string representation
public isolated function toBase16(byte[] arr) returns string = external;

# Returns the byte array that a string represents in Base16.
# `str` must consist of the characters `0..9`, `A..F`, `a..f`
# and whitespace as allowed by a Ballerina Base16Literal.
#
# ```
# array:fromBase16("aaabcfccadafcd") ⇒ [170,171,207,204,173,175,205]
#
# array:fromBase16("aaabcfccadafcd==") ⇒ error
# ```
#
# + str - Base16 string representation
# + return - the byte array or error
public isolated function fromBase16(string str) returns byte[]|error = external;

# Returns a stream of the members of an array.
#
# ```
# stream<string> strm = ["a", "b", "c", "d"].toStream();
# strm.next() ⇒ {"value":"a"}
# ```
#
# + arr - the array
# + returns - stream of members of the array
# The returned stream will use an iterator over `arr` and
# will therefore handle mutation of `arr` in the same way
# as an iterator does.
# Theutation of the `arr`
public isolated function toStream(T[] arr) returns stream<T,()> = external;
