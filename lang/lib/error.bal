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


# Type for value that can be cloned.
# This is the same as in lang.value, but is copied here to avoid a dependency.

type Cloneable readonly|xml|Cloneable[]|map<Cloneable>|table<map<Cloneable>>;

# The type to which error detail records must belong.
public type Detail record {|
   ...Cloneable;
|};

# A type parameter that is a subtype of error `Detail` record type.
# Has the special semantic that when used in a declaration
# all uses in the declaration must refer to same type.
@typeParam
type DetailType Detail;

# Returns the error's message.
#
# + e - the error value
# + return - error message
public isolated function message(error e) returns string = external;

# Returns the error's cause.
#
# + e - the error value
# + return - error cause
public isolated function cause(error e) returns error? = external;

# Returns the error's detail record.
# The returned value will be immutable.
# + e - the error value
# + return - error detail value
public isolated function detail(error<DetailType> e) returns readonly & DetailType = external;

# Type representing a stack frame.
# A call stack is represented as an array of stack frames.
# This type is also present in lang.runtime to avoid a dependency.
public type StackFrame readonly & object {
   # Returns a string representing this StackFrame.
   # This must not contain any newline characters.
   # + return - a string
   public function toString() returns string;
};

# Returns an array representing an error's stack trace.
#
# + e - the error value
# + return - an array representing the stack trace of the error value
# The first member of the array represents the top of the call stack.
public isolated function stackTrace(error e) returns StackFrame[] = external;

# Converts an error to a string.
#
# + e - the error to be converted to a string
# + return - a string resulting from the conversion
#
# The details of the conversion are specified by the ToString abstract operation
# defined in the Ballerina Language Specification, using the direct style.
public isolated function toString(error e) returns string = external;

# Converts an error to a string that describes the value in Ballerina syntax.
# + e - the error to be converted to a string
# + return - a string resulting from the conversion
#
# The details of the conversion are specified by the ToString abstract operation
# defined in the Ballerina Language Specification, using the expression style.
public isolated function toBalString(error e) returns string = external;

# A type of error which can be retried.
public type Retriable distinct error;

# The RetryManager used by default.
public class DefaultRetryManager {
   private int count;
   public function init(int count = 3) {
     this.count = count;
   }
   public function shouldRetry(error e) returns boolean {
      if e is Retriable && count >  0 {
         count -= 1;
         return true;
      }
      else {
         return false;
      }
   }
}
