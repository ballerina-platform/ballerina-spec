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

import ballerina/lang.regexp;

# Built-in subtype of string containing strings of length 1.
@builtinSubtype
type Char string;

# Returns the length of the string.
#
# + str - the string
# + return - the number of characters (code points) in `str`
public isolated function length(string str) returns int = external;

# Returns an iterator over the string.
# The iterator will yield the substrings of length 1 in order.
#
# + str - the string to be iterated over
# + return - a new iterator object
public isolated function iterator(string str) returns object {
    public isolated function next() returns record {| Char value; |}?;
} = external;

# Concatenates zero or more strings.
#
# + strs - strings to be concatenated
# + return - concatenation of all of the `strs`; empty string if `strs` is empty
public isolated function concat(string... strs) returns string = external;

# Returns the code point of a character in a string.
#
# + str - the string
# + index - an index in `str`
# + return - the Unicode code point of the character at `index` in `str`
public isolated function getCodePoint(string str, int index) returns int = external;

# Returns a substring of a string.
#
# + str - source string.
# + startIndex - the starting index, inclusive
# + endIndex - the ending index, exclusive
# + return - substring consisting of characters with index >= startIndex and < endIndex
public isolated function substring(string str, int startIndex, int endIndex = str.length()) returns string = external;

# Lexicographically compares strings using their Unicode code points.
# This orders strings in a consistent and well-defined way,
# but the ordering will often not be consistent with cultural expectations
# for sorted order.
#
# + str1 - the first string to be compared
# + str2 - the second string to be compared
# + return - an int that is less than, equal to or greater than zero,
#    according as `str1` is less than, equal to or greater than `str2`
public isolated function codePointCompare(string str1, string str2) returns int = external;

# Joins zero or more strings together with a separator.
#
# + separator - separator string
# + strs - strings to be joined
# + return - a string consisting of all of `strs` concatenated in order
#     with `separator` in between them
public isolated function 'join(string separator, string... strs) returns string = external;

# Finds the first occurrence of one string in another string.
#
# + str - the string in which to search
# + substr - the string to search for
# + startIndex - index to start searching from
# + return - index of the first occurrence of `substr` in `str` that is >= `startIndex`,
#    or `()` if there is no such occurrence
public isolated function indexOf(string str, string substr, int startIndex = 0) returns int? = external;

# Finds the last occurrence of one string in another string.
#
# + str - the string in which to search
# + substr - the string to search for
# + startIndex - index to start searching backwards from
# + return - index of the last occurrence of `substr` in `str` that is <= `startIndex`,
#    or `()` if there is no such occurrence
public isolated function lastIndexOf(string str, string substr, int startIndex = str.length() - substr.length()) returns int? = external;

# Tests whether a string includes another string.
#
# + str - the string in which to search
# + substr - the string to search for
# + startIndex - index to start searching from
# + return - `true` if there is an occurrence of `substr` in `str` at an index >= `startIndex`,
#    or `false` otherwise
public isolated function includes(string str, string substr, int startIndex = 0) returns boolean = external;

# Tests whether a string starts with another string.
#
# + str - the string to be tested
# + substr - the starting string
# + return - true if `str` starts with `substr`; false otherwise
public isolated function startsWith(string str, string substr) returns boolean = external;

# Tests whether a string ends with another string.
#
# + str - the string to be tested
# + substr - the ending string
# + return - true if `str` ends with `substr`; false otherwise
public isolated function endsWith(string str, string substr) returns boolean = external;

// Standard lib (not lang lib) should have a Unicode module (or set of modules)
// to deal with Unicode properly. These will need to be updated as each
// new Unicode version is released.

# Converts occurrences of A-Z to a-z.
# Other characters are left unchanged.
#
# + str - the string to be converted
# + return - `str` with any occurrences of A-Z converted to a-z
public isolated function toLowerAscii(string str) returns string = external;

# Converts occurrences of a-z to A-Z.
# Other characters are left unchanged.
#
# + str - the string to be converted
# + return - `str` with any occurrences of a-z converted to A-Z
public isolated function toUpperAscii(string str) returns string = external;


# Tests whether two strings are the same, ignoring the case of ASCII characters.
# A character in the range a-z is treated the same as the corresponding character in the range A-Z.
#
# + str1 - the first string to be compared
# + str2 - the second string to be compared
# + return - true if `str1` is the same as `str2`, treating upper-case and lower-case
# ASCII letters as the same; false, otherwise
public isolated function equalsIgnoreCaseAscii(string str1, string str2) returns boolean = external;

# Removes ASCII white space characters from the start and end of a string.
# The ASCII white space characters are 0x9...0xD, 0x20.
#
# + str - the string
# + return - `str` with leading or trailing ASCII white space characters removed
public isolated function trim(string str) returns string = external;

# Represents `str` as an array of bytes using UTF-8.
#
# + str - the string
# + return - UTF-8 byte array
public isolated function toBytes(string str) returns byte[] = external;

# Constructs a string from its UTF-8 representation in `bytes`.
#
# + bytes - UTF-8 byte array
# + return - `bytes` converted to string or error
public isolated function fromBytes(byte[] bytes) returns string|error = external;

# Converts a string to an array of code points.
#
# + str - the string
# + return - an array with a code point for each character of `str`
public isolated function toCodePointInts(string str) returns int[] = external;

# Converts a single character string to a code point.
#
# + ch - a single character string
# + return - the code point of `ch`
public isolated function toCodePointInt(Char ch) returns int = external;

# Constructs a string from an array of code points.
# An int is a valid code point if it is in the range 0 to 0x10FFFF inclusive,
# but not in the range 0xD800 or 0xDFFF inclusive.
#
# + codePoints - an array of ints, each specifying a code point
# + return - a string with a character for each code point in `codePoints`; or an error
# if any member of `codePoints` is not a valid code point
public isolated function fromCodePointInts(int[] codePoints) returns string|error = external;

# Constructs a single character string from a code point.
# An int is a valid code point if it is in the range 0 to 0x10FFFF inclusive,
# but not in the range 0xD800 or 0xDFFF inclusive.
#
# + codePoint - an int specifying a code point
# + return - a single character string whose code point is `codePoint`; or an error
# if `codePoint` is not a valid code point
public isolated function fromCodePointInt(int codePoint) returns Char|error = external;

# Adds padding to the start of a string.
# Adds sufficient `padChar` characters at the start of `str` to make its length be `len`.
# If the length of `str` is >= `len`, returns `str`.
# 
# + str - the string to pad
# + len - the length of the string to be returned
# + padChar - the character to use for padding `str`; defaults to a space character
# + return - `str` padded with `padChar` 
public isolated function padStart(string str, int len, Char padChar = " ") returns string = external;

# Adds padding to the end of a string.
# Adds sufficient `padChar` characters to the end of `str` to make its length be `len`.
# If the length of `str` is >= `len`, returns `str`.
# 
# + str - the string to pad
# + len - the length of the string to be returned
# + padChar - the character to use for padding `str`; defaults to a space character
# + return - `str` padded with `padChar` 
public isolated function padEnd(string str, int len, Char padChar = " ") returns string = external;

# Pads a string with zeros.
# The zeros are added at the start of the string, after a `+` or `-` sign if there is one.
# Sufficient zero characters are added to `str` to make its length be `len`.
# If the length of `str` is >= `len`, returns `str`.
# 
# + str - the string to pad
# + len - the length of the string to be returned
# + zeroChar - the character to use for the zero; defaults to ASCII zero `0`
# + return - `str` padded with zeros 
public isolated function padZero(string str, int len, Char zeroChar = "0") returns string = external;

# Refers to the `RegExp` type defined by lang.regexp module.
public type RegExp regexp:RegExp;

# Tests whether there is a full match of a regular expression with a string.
# A match of a regular expression in a string is a full match if it
# starts at index 0 and ends at index `n`, where `n` is the length of the string.
# This is equivalent to `regex:isFullMatch(re, str)`.
#
# + str - the string
# + re - the regular expression
# + return - true if there is full match of `re` with `str`, and false otherwise
public function matches(string str, RegExp re) returns boolean = external;

# Tests whether there is a match of a regular expression somewhere within a string.
# This is equivalent to `regexp:find(re, str, startIndex) != ()`.
# 
# + str - the string to be matched
# + re - the regular expression
# + return - true if the is a match of `re` somewhere within `str`, otherwise false
public function includesMatch(string str, RegExp re, int startIndex = 0) returns boolean = external;
