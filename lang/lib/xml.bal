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

const string XML_NAMESPACE_URI = "http://www.w3.org/XML/1998/namespace";
const string XMLNS_NAMESPACE_URI = "http://www.w3.org/2000/xmlns/";

# Returns number of XML items in `x`.
public function length(xml x) returns int = external;

# Returns an iterator over the XML items in x.
# A character item is represented by a string of length 1.
# Other items are represented by xml singletons.
public function iterator(xml x) returns abstract object {
    public next() returns record {| (xml|string) value; |}?;
} = external;

# Concatenate all the `xs`. Empty xml sequence if empty.
public function concat((xml|string)... xs) returns xml = external;

# Returns true if `x` is a singleton xml sequence consisting of an element item.
public function isElement(xml x) returns boolean = external;

# Returns true if `x` is a singleton xml sequence consisting of a processing instruction item.
public function isProcessingInstruction(xml x) returns boolean = external;

# Returns true if `x` is a singleton xml sequence consisting of a comment item.
public function isComment(xml x) returns boolean = external;

# Returns true if `x` is an xml sequence consisting of one or more character items.
public function isText(xml x) returns boolean = external;

# Represents a parameter for which isElement must be true.
type Element xml;
# Represents a parameter for which isProcessingInstruction must be true.
type ProcessingInstruction xml;
# Represents a parameter for which isComment must be true.
type Comment xml;
# Represents a parameter for which isText must be true.
type Text xml;

# Returns a string giving the expanded name of `elem`.
public function getName(Element elem) returns string = external;
public function setName(Element elem, string xName) = external;

# Returns the children of `elem`.
# Panics if `isElement(elem)` is not true.
public function getChildren(Element elem) returns xml = external;

# Sets the children of `elem` to `children`.
# Panics if `isElement(elem)` is not true.
public function setChildren(Element elem, xml|string children) = external;

# Returns the map representing the attributes of `elem`.
# This includes namespace attributes.
# The keys in the map are the expanded name of the attribute.
# Panics if `isElement(elem)` is not true.
# There is no setAttributes function.
public function getAttributes(Element x) returns map<string> = external;

# Returns the target part of the processing instruction.
public function getTarget(ProcessingInstruction x) returns string = external;

# Returns the content of a text or processing instruction or comment item.
public function getContent(Text|ProcessingInstruction|Comment x) returns string = external;

# Creates an element with the specified children
# The attributes are empty initially
public function createElement(string name, xml children = concat()) returns Element = external;

# Creates a processing instruction with the specified target and content.
public function createProcessingInstruction(string target, string content) returns ProcessingInstruction
 = external;

# Creates a comment with the specified content.
public function createComment(string content) returns Comment = external;

# Returns a subsequence of x.
public function slice(xml x, int startIndex, int endIndex = x.length()) returns xml = external;

# Removes comments, processing instructions and text chunks that are all white space.
# After removal of comments and processing instructions, the text is grouped into
# the biggest possible chunks (i.e. only elements cause division into multiple chunks)
# and a chunk is removed only if the entire chunk is whitespace.
public function strip(xml x) returns xml = external;

# Returns a new xml sequence that contains just the element items of `x`
public function elements(xml x) returns xml = external;

// Functional programming methods
public function map(xml x, function(xml|string item) returns xml|string func) returns xml = external;
public function forEach(xml x, function(xml|string item) returns () func) = external;
public function filter(xml x, function(xml|string item) returns boolean func) returns xml = external;

# This is the inverse of `value:toString` applied to an `xml`.
public function fromString(string s) returns xml|error = external;


