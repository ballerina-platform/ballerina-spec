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


# A type parameter that is a subtype of `any|error`.
# Has the special semantic that when used in a declaration
# all uses in the declaration must refer to same type.
@typeParam
type Type any|error;

# A type parameter that is a subtype of `error`.
# Has the special semantic that when used in a declaration
# all uses in the declaration must refer to same type.
@typeParam
type ErrorType error;

# A type parameter that is a subtype of `error?`.
# Has the special semantic that when used in a declaration
# all uses in the declaration must refer to same type.
# This represents the result type of an iterator.
@typeParam
type CompletionType error?;

# A type parameter that is a subtype of `any|error`.
# Has the special semantic that when used in a declaration
# all uses in the declaration must refer to same type.
@typeParam
type Type1 any|error;

# Returns an iterator over a stream.
#
# + stm - the stream
# + return - a new iterator object that will iterate over the members of `stm`.
public isolated function iterator(stream<Type,CompletionType> stm) returns object {
    public isolated function next() returns record {|
        Type value;
    |}|CompletionType;
} = external;

# Closes a stream.
# This releases any system resources being used by the stream.
# Closing a stream that has already been closed has no efffect and returns `()`.
#
# + stm - the stream to close
# + return - () if the close completed successfully, otherwise an error
public isolated function close(stream<Type,CompletionType> stm) returns CompletionType? = external;

// Functional iteration

# Applies a function to each member of a stream and returns a stream of the results.
#
# + stm - the stream
# + func - a function to apply to each member
# + return - new stream containing result of applying `func` to each member of `stm` in order
public isolated function 'map(stream<Type,CompletionType> stm, @isolatedParam function(Type val) returns Type1 func)
   returns stream<Type1,CompletionType> = external;

# Applies a function to each member of a stream.
# The function `func` is applied to each member of stream `stm` in order.
#
# + stm - the stream
# + func - a function to apply to each member
public isolated function forEach(stream<Type,CompletionType> stm, @isolatedParam function(Type val) returns () func) returns CompletionType = external;

# Selects the members from a stream for which a function returns true.
#
# + stm - the stream
# + func - a predicate to apply to each member to test whether it should be selected
# + return - new stream only containing members of `stm` for which `func` evaluates to true
public isolated function filter(stream<Type,CompletionType> stm, @isolatedParam function(Type val) returns boolean func)
   returns stream<Type,CompletionType> = external;

# Combines the members of a stream using a combining function.
# The combining function takes the combined value so far and a member of the stream,
# and returns a new combined value.
#
# + stm - the stream
# + func - combining function
# + initial - initial value for the first argument of combining function `func`
# + return - result of combining the members of `stm` using `func`
public isolated function reduce(stream<Type,ErrorType?> stm, @isolatedParam function(Type1 accum, Type val) returns Type1 func, Type1 initial)
   returns Type1|ErrorType = external;
