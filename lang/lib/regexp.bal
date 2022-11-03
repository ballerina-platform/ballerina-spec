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

public type Span readonly & object {
   public int startIndex;
   public int endIndex;
   // This avoids constructtng a potentially long string unless and until it is needed
   isolated function substring() returns string;
};

public type Groups readonly & [Span, Span?...];

# Returns the span of the first match that starts at or after startIndex.
public isolated function find(RegExp re, string str, int startIndex = 0) returns Span? = external;

public isolated function findGroups(RegExp re, string str, int startIndex = 0) returns Groups? = external;

# Return all non-overlapping matches
public isolated function findAll(RegExp re, string str, int startIndex = 0) returns Span[] = external;
public isolated function findAllGroups(RegExp re, string str, int startIndex = 0) returns Groups[] = external;

public isolated function matchAt(RegExp re, string str, int startIndex = 0) returns Span? = external;
public isolated function matchGroupsAt(RegExp re, string str, int startIndex = 0) returns Groups? = external;

# Says whether there is a match of the RegExp that starts at the beginning of the string and ends at the end of the string.
public isolated function isFullMatch(RegExp re, string str) returns boolean = external;
public isolated function fullMatchGroups(RegExp re, string str) returns Groups? = external;

public type ReplacerFunction function(Groups groups) returns string;
public type Replacement ReplacerFunction|string;

# Replaces the first occurrence of a regular expression.
public isolated function replace(RegExp re, string str, @isolatedParam Replacement replacement, int startIndex = 0) returns string = external;
# Replaces all occurrences of a regular expression.
public isolated function replaceAll(RegExp re, string str, @isolatedParam Replacement replacement, int startIndex = 0) returns string = external;

public isolated function fromString(string str) returns RegExp|error = external;
