# Listener support for ballerina/task

- Authors
  - Tharmigan Krishnananthalingam
- Reviewed by
  - TBD
- Created date
  - 2025-01-30
- Updated date
  - 2025-05-14
- Issue
  - [1329](https://github.com/ballerina-platform/ballerina-spec/issues/1329)
- State
  - Submitted

## Summary

The Ballerina Task package provides APIs to create, schedule, and manage jobs. This proposal introduces a task listener that allows jobs to be executed based on schedule configurations. Jobs are represented as Ballerina services that can be attached to the task listener.

## Goals

- Introduce a task listener to execute jobs based on a one-time or recurring schedule.
- Provide listener APIs to manage jobs.
- Define a task service type for implementing jobs.

## Non-Goals

- Implement a compiler plugin to validate job IDs in task services or provide code actions for onTrigger function implementation.
- Enable job-level schedule configuration via annotations.

## Motivation

Currently, scheduling a task in Ballerina requires blocking the main strand, typically using a `sleep` statement in the main function. In monolithic and microservice architectures, applications are typically deployed as long-running services rather than as main functions with explicit termination. The current approach doesn't align with this deployment model.
Introducing a task listener addresses these limitations by allowing developers to implement scheduled tasks as service.

```ballerina
import ballerina/io;
import ballerina/lang.runtime;
import ballerina/task;

class Job {

    *task:Job;
    int i = 1;

    public function execute() {
        self.i += 1;
        io:println("MyCounter: ", self.i);
    }

    isolated function init(int i) {
        self.i = i;
    }
}

public function main() returns error? {
    task:JobId id = check task:scheduleJobRecurByFrequency(new Job(0), 1);

    runtime:sleep(9);

    check task:unscheduleJob(id);
}
```

This approach is not user-friendly. Introducing a task listener will simplify job execution based on predefined schedules.

## Description

### Task service type

With the new listener-based approach, a job is implemented as a Ballerina service attached to the task listener. The task service type is defined as:

```ballerina
public type Service distinct service object {
    function execute() returns error?;
    function onError() returns error?;
}
```

The `execute` function executes when the scheduled trigger fires.

### Task listener

#### Configuration

The task listener requires a schedule configuration (one-time or recurring) and supports an optional worker pool:

```ballerina
# Listener configuration.
#
# + schedule - The schedule configuration for the listener
public type ListenerConfiguration record {|
    TriggerConfiguration trigger;
|};

# Recurring schedule configuration.
#
# + interval - The duration of the trigger (in seconds), which is used to run the job frequently
# + maxCount - The maximum number of trigger counts
# + startTime - The trigger start time in Ballerina `time:Civil`. If it is not provided, a trigger will
#               start immediately
# + endTime - The trigger end time in Ballerina `time:Civil`
# + taskPolicy -  The policy, which is used to handle the error and will be waiting during the trigger time
public type TriggerConfiguration record {|
    decimal interval;
    int maxCount = -1;
    time:Civil startTime?;
    time:Civil endTime?;
    task:TaskPolicy taskPolicy = {};
|};
```

#### Listener APIs

The task listener provides the following APIs:

- Lifecycle Management
  - `start()`: Starts the task listener.
  - `gracefulStop()`: Stops the task listener gracefully.
  - `immediateStop()`: Stops the task listener immediately.
  - `attach(service)`/`scheduleJob(service)`: Attaches/Schedules a task service to the task listener.
  - `detach(service)`/`unscheduleJob(service)`: Detaches/Unschedules a task service from the task listener.

### Service implementation

Each task service should have a unique task ID for job management, specified in the service declaration as an attachment point. The service must also implement the `execute` and `onError` functions, which define the job's execution logic and handle errors.

```ballerina
service "job-1" on taskListener {
    function execute() returns error? {
        // Job implementation
    }

    function onError() returns error? {
        // handle errors
    }
}
```

> **Note:** If a job is implemented without an ID, the listener generates a unique one. However, this prevents explicit job management, making it difficult to track individual jobs when multiple are running.

### Example

The following example demonstrates using a task listener to execute a scheduled job:

```ballerina
import ballerina/io;
import ballerina/task;

listener task:Listener taskListener = new(schedule = {interval: 1});

service "job-1" on taskListener {
    private int i = 1;

    function execute() returns error? {
        lock {
            self.i += 1;
            io:println("MyCounter: ", self.i);
        }
    }
}
```

This setup ensures jobs execute on schedule without blocking the main execution flow.
