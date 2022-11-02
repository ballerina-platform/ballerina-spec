// Copyright (c) 2022 WSO2 Inc. (http://www.wso2.org) All Rights Reserved.
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

# The type RegExp refers to the tagged data basic type with tag `re`.
@builtinSubtype
public type RegExp any;

# A span of a string.
# A span is a substring of another string.
public type Span readonly & object {
   # The index within the string where the span starts.
   public int startIndex;
   # The index within the string following the end of the span.
   # The length of the span is `endIndex - startIndex`.
   public int endIndex;
   # Returns a string with the content of the span.
   isolated function substring() returns string;
};

# A list providing detailed information about the match of a regular expression within string.
# Each member of the list identifies the `Span` within the string matched
# by each of the regular expression's capturing groups. 
# The member with index 0 corresponds to the entire regular expression.
# The group with index i, where i > 1,is the i-th capturing group;
# this will be nil if the match of the regular expression did not use
# a match of the capturing group.
# The capturing groups within a regular expression are ordered by the position
# of their opening parenthesis.
public type Groups readonly & [Span, Span?...];

# Returns the first match of a regular expression within a string.
# 
# + re - the regular expression  
# + str - the string in which to look for a match of `re` 
# + startIndex - the index within `str` at which to start looking for a match
# + return - a `Span` describing the match, or nil if no match was found
public isolated function find(RegExp re, string str, int startIndex = 0) returns Span? = external;

# Returns the `Groups` for the first match of a regular expression within a string.
#
# + re - the regular expression  
# + str - the string in which to look for a match of `re` 
# + startIndex - the index within `str` at which to start looking for a match
# + return - a `Groups` list describing the match, or nil if no match was found
public isolated function findGroups(RegExp re, string str, int startIndex = 0) returns Groups? = external;

# Returns a list of all the matches of a regular expression within a string.
# After one match is found, it looks for the next match starting where the previous
# match ended, so the list of matches will be non-overlapping.
# 
# + re - the regular expression  
# + str - the string in which to look for matches of `re` 
# + startIndex - the index within `str` at which to start looking for matches
# + return - a list containing a `Span` for each match found
public isolated function findAll(RegExp re, string str, int startIndex = 0) returns Span[] = external;

# Returns the `Groups` of all the matches of a regular expression within a string.
# After one match is found, it looks for the next match starting where the previous
# match ended, so the list of matches will be non-overlapping.
# 
# + re - the regular expression  
# + str - the string in which to look for matches of `re` 
# + startIndex - the index within `str` at which to start looking for matches
# + return - a list containing a `Group` for each match found
public isolated function findAllGroups(RegExp re, string str, int startIndex = 0) returns Groups[] = external;

# Tests whether there is a match of a regular expression at a specific index in the string.
# 
# + re - the regular expression  
# + str - the string in which to look for a match of `re` 
# + startIndex - the index within `str` at which to look for a match; defaults to zero
# + return - a `Span` describing the match, or nil if `re` did not match at that index; the startIndex of the
#   `Span` will always be equal to `startIndex`
public isolated function matchAt(RegExp re, string str, int startIndex = 0) returns Span? = external;

# Returns the `Groups` of the match of a regular expression at a specific index in the string.
# 
# + re - the regular expression  
# + str - the string in which to look for a match of `re` 
# + startIndex - the index within `str` at which to look for a match; defaults to zero
# + return - a `Groups` list describing the match, or nil if `re` did not match at that index; the startIndex of the
#   first `Span` in the list will always be equal to the `startIndex` of the first member of the list
public isolated function matchGroupsAt(RegExp re, string str, int startIndex = 0) returns Groups? = external;

# Tests whether there is full match of regular expression with a string.
# A match of a regular expression in a string is a full match if it
# starts at index 0 and ends at index `n`, where `n` is the length of the string.
#
# + re - the regular expression  
# + str - the string
# + return - true if there is full match of `re` with `str`, and false otherwise
public isolated function isFullMatch(RegExp re, string str) returns boolean = external;

# Returns the `Groups` of the match of a regular expression that is a full match of a string.
# A match of the regular expression in a string is a full match if it
# starts at index 0 and ends at index `n`, where `n` is the length of the string.
# 
# + re - the regular expression  
# + str - the string in which to look for a match of `re` 
# + return - a `Groups` list describing the match, or nil if there is not a full match; the 
#   first `Span` in the list will be all of `str`
public isolated function fullMatchGroups(RegExp re, string str) returns Groups? = external;

# A function that constructs the replacement for the match of a regular expression.
# The `groups` parameter describes the match for which the replacement is to be constructed.
public type ReplacerFunction function(Groups groups) returns string;

# The replacement for the match of a regular expression found within a string.
# A string value specifies that the replacement is a fixed string.
# A function that specifies that the replacement is constructed by calling a function for each match.
public type Replacement ReplacerFunction|string;

# Replaces the first match of a regular expression.
#
# + re - the regular expression  
# + str - the string in which to perform the replacements  
# + replacement - a `Replacement` that gives the replacement for the match  
# + startIndex - the index within `str` at which to start looking for a match; defaults to zero
# + return - `str` with the first match, if any, replaced by the string specified by `replacement`
public isolated function replace(RegExp re, string str, @isolatedParam Replacement replacement, int startIndex = 0) returns string = external;

# Replaces all matches of a regular expression.
# After one match is found, it looks for the next match starting where the previous
# match ended, so the matches will be non-overlapping.
#
# + re - the regular expression  
# + str - the string in which to perform the replacements  
# + replacement - a `Replacement` that gives the replacement for each match  
# + startIndex - the index within `str` at which to start looking for matches; defaults to zero
# + return - `str` with every match replaced by the string specified by `replacement`
public isolated function replaceAll(RegExp re, string str, @isolatedParam Replacement replacement, int startIndex = 0) returns string = external;

# Splits a string into substrings separated by matches of a regular expression.
# This finds the the non-overlapping matches of a regular expression and
# returns a list of substrings of `str` that occur before the first match,
# between matches, or after the last match.  If there are no matches, then
# `[str]` will be returned.
# 
# + re - the regular expression that specifies the separator
# + str - the string to be split
# + return - a list of substrings of `str` separated by matches of `re` 
public isolated function split(RegExp re, string str) returns string[] = external;

# Constructs a regular expression from a string.
# The syntax of the regular expression is the same as accepted by the `re` tagged data template expression.
#
# + str - the string representation of a regular expression
# + return - the regular expression, or an error value if `str` is not a valid regular expression
public isolated function fromString(string str) returns RegExp|error = external;
