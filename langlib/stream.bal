// Copyright (c) 2018, 2019 WSO2 Inc. (http://www.wso2.org) All Rights Reserved.
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

# A type parameter that is a subtype of `anydata|error`.
# Has the special semantic that when used in a declaration
# all uses in the declaration must refer to same type. 
@typeParam
private type PureType = anydata|error;

# Publishes data to the stream.
#
# + data - Data to be published to the stream
public function stream<PureType>.publish(PureType data) = external;

# Subscribes to data from the stream.
#
# + func - The function pointer for the subscription, which will be invoked with data published to the stream
public function stream<PureType>.subscribe(function (PureType) func) = external;