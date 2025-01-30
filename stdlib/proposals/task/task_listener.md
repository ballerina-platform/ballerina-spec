# Listener support for ballerina/task
- Authors
  - Tharmigan Krishnananthalingam
- Reviewed by
    - TBD
- Created date
    - 2025-01-30
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

- Make the job ID in the service optional. If not provided, the job implemented by that service cannot be managed.
- Implement a compiler plugin to validate job IDs in task services or provide code actions for onTrigger function implementation.
- Enable job-level schedule configuration via annotations.

## Motivation

Currently, scheduling a task in Ballerina requires blocking the main strand, typically using a `sleep` statement in the main function:

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
    remote function onTrigger() returns error?;
}
```

The `onTrigger` function executes when the scheduled trigger fires.

### Task listener

#### Configuration

The task listener requires a schedule (one-time or recurring) and supports worker pool configurations:

```ballerina
# Listener configuration.
#
# + schedule - The schedule configuration for the listener
# + workerPool - The worker pool configuration for the listener
public type ListenerConfiguration record {|
    OneTimeConfiguration|RecurringConfiguration schedule;
    WorkerPoolConfiguration workerPool = {};
|};

# Recurring schedule configuration.
#
# + interval - The duration of the trigger (in seconds), which is used to run the job frequently
# + maxCount - The maximum number of trigger counts
# + startTime - The trigger start time in Ballerina `time:Civil`. If it is not provided, a trigger will
#               start immediately
# + endTime - The trigger end time in Ballerina `time:Civil`
# + taskPolicy -  The policy, which is used to handle the error and will be waiting during the trigger time
public type RecurringConfiguration record {|
    decimal interval;
    int maxCount = -1;
    time:Civil startTime?;
    time:Civil endTime?;
    task:TaskPolicy taskPolicy = {};
|};

# One-time schedule configuration.
#
# + triggerTime - The specific time in Ballerina `time:Civil` to trigger only one time
public type OneTimeConfiguration record {|
    time:Civil triggerTime;
|};

# Worker pool configuration.
#
# + workerCount - Specifies the number of workers that are available for the concurrent execution of jobs.
#                 It should be a positive integer. The recommendation is to set a value less than 10. Default sets to 5.
# + waitingTime - The number of seconds as a decimal the scheduler will tolerate a trigger to pass its next-fire-time
#                 before being considered as `ignored the trigger`
public type WorkerPoolConfiguration record {|
    int workerCount = 5;
    time:Seconds waitingTime = 5;
|};
```

#### Listener APIs

The task listener provides the following APIs:

- Lifecycle Management
   - `start`: Starts the task listener.
   - `gracefulStop`: Stops the task listener gracefully.
   - `immediateStop`: Stops the task listener immediately.
   - `attach`/`schedule`: Attaches/Schedules a task service to the task listener.
   - `detach`/`unschedule`: Detaches/Unschedules a task service from the task listener.

- Job Management
   - `pauseAllJobs`: Pauses all the jobs.
   - `resumeAllJobs`: Resumes all the jobs.
   - `pauseJob`: Pauses a specific job.
   - `resumeJob`: Resumes a specific job.
   - `getRunningJobs`: Returns the list of running job ids.

### Service implementation

Each task service should have a unique task ID for job management.

### Example

The following example demonstrates using a task listener to execute a scheduled job:

```ballerina
import ballerina/io;
import ballerina/task;

listener task:Listener taskListener = new(schedule = {interval: 1});

service "job-1" on taskListener {
    private int i = 1;

    remote function onTrigger() {
        lock {
            self.i += 1;
            io:println("MyCounter: ", self.i);
        }
    }
}
```

This setup ensures jobs execute on schedule without blocking the main execution flow.
