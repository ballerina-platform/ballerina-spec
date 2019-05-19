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
# Return absolute value of `n`
public function abs(int n) returns int = external;

# Sum of all the arguments
# 0 if no args
public function sum(int... ns) returns int = external;

# Maximum of all the arguments
# XXX should we allow no args?
public function max(int n, int... ns) returns int = external;

# Minimum of all the arguments
# XXX should we allow no args?
public function min(int n, int... ns) returns int = external;