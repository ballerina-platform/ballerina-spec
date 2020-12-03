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

# Information about a transaction that does not change
# after the transaction is started.
type Info readonly & record {|
   // unique identifier
   byte[] xid;
   // non-zero means this transaction was a retry of 
   // a previous one
   int retryNumber;
   // probably useful for timeouts and logs
   timestamp startTime;
   // maybe useful
   Info? prevAttempt;
|};

# Returns information about the current transaction
public transactional function info() returns Info = external;

# Returns information about the transaction with
# the specified xid.
public isolated function getInfo(byte[] xid) returns Info? = external;

public transactional isolated function setRollbackOnly(error? e) = external;

public transactional isolated function getRollbackOnly() returns boolean = external;

public transactional isolated function setData(readonly data) = external;

// returns () if no data has been set
public transactional isolated function getData() returns readonly = external;

public type CommitHandler function(Info info);

public type RollbackHandler function(Info info, error? cause, boolean willRetry);

public transactional isolated function onCommit(CommitHandler handler) = external;

public transactional isolated function onRollback(RollbackHandler handler) = external;
