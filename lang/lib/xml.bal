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
#
# + x - xml item
# + return - number of XML items in `x`
public function length(xml x) returns int = external;

# Returns an iterator over the xml items of `x`
#
# + x - xml item to iterate
# + return - iterator object
# A character item is represented by a string of length 1.
# Other items are represented by xml singletons.
public function iterator(xml x) returns abstract object {
    public next() returns record {| (xml|string) value; |}?;
} = external;

# Concatenate all the `xs`. Empty xml sequence if empty.
#
# + xs - xml or string items to concat
# + return - xml sequence containing `xs`
public function concat((xml|string)... xs) returns xml = external;

# Returns true if `x` is a singleton xml sequence consisting of an element item.
#
# + x - xml value
# + return - true if `x` is an xml element item
public function isElement(xml x) returns boolean = external;

# Returns true if `x` is a singleton xml sequence consisting of a processing instruction item.
#
# + x - xml value
# + return - true if `x` is a xml processing instruction
public function isProcessingInstruction(xml x) returns boolean = external;

# Returns true if `x` is a singleton xml sequence consisting of a comment item.
#
# + x - xml value
# + return - true if `x` is a xml comment item
public function isComment(xml x) returns boolean = external;

# Returns true if `x` is an xml sequence consisting of one or more character items.
#
# + x - xml value
# + return - true if `x` is a sequence containing any charactor items
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
#
# + elem - xml element
# + return - element name
public function getName(Element elem) returns string = external;

# Change the name of element `elmem` to `xName`.
#
# + elem - xml element
# + xName - new name
public function setName(Element elem, string xName) = external;

# Returns the children of `elem`.
# Panics if `isElement(elem)` is not true.
#
# + elem - xml element
# + return - children of `elem`
public function getChildren(Element elem) returns xml = external;

# Sets the children of `elem` to `children`.
# Panics if `isElement(elem)` is not true.
#
# + elem - xml element
# + children - xml or string to set as children
public function setChildren(Element elem, xml|string children) = external;

# Returns the map representing the attributes of `elem`.
# This includes namespace attributes.
# The keys in the map are the expanded name of the attribute.
# Panics if `isElement(elem)` is not true.
# There is no setAttributes function.
#
# + x - xml element
# + return - attributes of `x`
public function getAttributes(Element x) returns map<string> = external;

# Returns the target part of the processing instruction.
#
# + x - xml processing instruction item
# + return - target potion of `x`
public function getTarget(ProcessingInstruction x) returns string = external;

# Returns the content of a text or processing instruction or comment item.
#
# + x - xml item
# + return - content of `x`
public function getContent(Text|ProcessingInstruction|Comment x) returns string = external;

# Creates an element with the specified children
# The attributes are empty initially
#
# + name - element name
# + children - children of element
# + return - new xml element
public function createElement(string name, xml children = concat()) returns Element = external;

# Creates a processing instruction with the specified `target` and `content`.
#
# + target - target potion of xml processing instruction
# + content - content potion of xml processing instruction
# + return - new xml processing instruction element
public function createProcessingInstruction(string target, string content) returns ProcessingInstruction
 = external;

# Creates a comment with the specified `content`.
#
# + content - comment content
# + return - xml comment element
public function createComment(string content) returns Comment = external;

# Returns a subsequence of x.
#
# + x - The xml source
# + startIndex - Start index, inclusive
# + endIndex - End index, exclusive
# + return - Sliced sequence
public function slice(xml x, int startIndex, int endIndex = x.length()) returns xml = external;

# Strips any text items from an XML sequence that are all whitespace.
# Removes comments, processing instructions and text chunks that are all white space.
# After removal of comments and processing instructions, the text is grouped into
# the biggest possible chunks (i.e. only elements cause division into multiple chunks)
# and a chunk is removed only if the entire chunk is whitespace.
#
# + x - The xml source
# + return - Striped sequence
public function strip(xml x) returns xml = external;

# Returns a new xml sequence that contains just the element items of `x`
# 
# + x - The xml source
# + return - All the elements-type items in the given XML sequence
public function elements(xml x) returns xml = external;

// Functional programming methods

# For xml sequence returns the result of applying function `func` to each member of sequence `item`.
# For xml element returns the result of applying function `funct` to `item`.
#
# + arr - the x
# + func - a function to apply to each child or `item`
# + return - new xml value containing result of applying function `func` to each child or `item`
public function map(xml x, function(xml|string item) returns xml|string func) returns xml = external;

# For xml sequence apply the `func` to children of `item`.
# For xml element apply the `func` to `item`.
#
# + x - the xml value
# + func - a function to apply to each child or `item`
public function forEach(xml x, function(xml|string item) returns () func) = external;

# For xml sequence returns a new xml sequence constructed from children of `x` for which `func` returns true.
# For xml element returns a new xml sequence constructed from `x` if `x` applied to `funct` returns true, else
# returns an empty sequence.
#
# + x - xml value
# + func - a predicate to apply to each child to determine if it should be included
# + return - new xml sequence containing filtered children
public function filter(xml x, function(xml|string item) returns boolean func) returns xml = external;

# This is the inverse of `value:toString` applied to an `xml`.
#
# + s - string representation of xml
# + return - parsed xml value or error
public function fromString(string s) returns xml|error = external;

