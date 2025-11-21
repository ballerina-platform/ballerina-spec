# Evaluation for AI Agents in Ballerina

- Authors
  - @MohamedSabthar
- Reviewed by
    - @shafreenAnfar
- Created date
    - 2025-11-21
- Issue
    - [1402](https://github.com/ballerina-platform/ballerina-spec/issues/1402)
- State
    - Submitted

## Summary

This proposal introduces an observability-free, test-driven evaluation method for AI Agents in Ballerina. Unlike frameworks such as Arize Phoenix or Langfuse that rely heavily on observability traces, this approach focuses on input–output evaluation and behavioral assertions, allowing validation of agent behavior without requiring any observability infrastructure.

The result is a lightweight, reproducible, and environment-agnostic method suitable for CI/CD pipelines, multi-agent workflows, and integration scenarios.

## Goal

* Provide a test driven approach to evaluate AI agents
* Provide a lightweight, modular evaluation approach without coupling to any observability infrastructure. 

## Motivation

Most existing AI agent evaluation frameworks—such as **Arize Phoenix**, **LangSmith**, and **Langfuse**—depend heavily on observability traces to perform evaluations. While trace-based evaluation is powerful, it is not a requirement for assessing AI agent behavior. In many cases, evaluation can be approached just like testing traditional software: supplying inputs, simulating tool interactions, and asserting that the resulting outputs or actions meet expectations.

Traditional software testing relies on deterministic behavior—tests pass when the output matches an expected result. AI agents differ because they are driven by LLMs, which are inherently non-deterministic and may produce varying responses for the same input. This makes strict output matching ineffective. Instead, evaluation relies on **metrics** such as task success rate, relevance, coherence, or correctness. These metrics can be subjective or probabilistic, making them more suitable for **relative comparison** (e.g., comparing model or agent versions) than for exact correctness.

However, these evaluation metrics can still be expressed as **pass/fail conditions** by establishing baselines or thresholds—such as requiring an agent to reach at least an 85% task success rate. With such thresholds, evaluation becomes analogous to traditional testing, even if the underlying behavior is probabilistic. This means that the **Ballerina testing framework itself can handle agent evaluation**, without the need for an external observability-dependent evaluation system.

This proposal, therefore, introduces a simple, lightweight design that leverages Ballerina’s native testing framework to evaluate agent behavior in a deterministic, CI-friendly manner—while remaining entirely **independent of observability infrastructure**. This approach avoids several drawbacks commonly found in observability-based evaluation frameworks, such as:
* Mandatory dependency on observability infrastructure
* Higher overhead, making them slower or unsuitable for lightweight or CI-driven workflows
* Inability to publish traces in certain environments due to compliance or privacy restrictions

## Proposed Approach

Agent behavior can be evaluated by treating the agent as verifiable logic and applying familiar testing methodologies. The approach consists of the following key elements:

1. **Input–Output Driven Testing**
Deterministic evaluations are performed by supplying prompts, simulating tool responses, and asserting expected outcomes. Developers can use standard Ballerina unit tests to validate agent behavior through either code-based checks or LLM-as-a-judge evaluations.

2. **Behavioral Assertions**
Beyond final outputs, intermediate reasoning steps, tool invocations, and execution patterns can be validated to ensure the agent follows the intended workflow and logic.

3. **Trace-Free Execution**
The evaluation process does not rely on observability traces, making it fast, lightweight, and fully environment-agnostic—ideal for CI/CD pipelines and constrained environments.
See the design section for more details.

4. **Optional Observability Integration**
Observability can be layered on top if needed, but it is not required. Developers may still integrate systems like Arize or Langfuse by configuring an observability backend, without affecting the core evaluation mechanism.

## Desing

To enable evaluation without relying on any observability infrastructure, the `ballerina/ai` module will introduce a set of new APIs that expose intermediate steps and agent state transitions. These additions allow developers to inspect an agent’s reasoning process, tool interactions, and final outputs directly. Using this information, users can write evaluations through input–output–driven testing and behavioral assertions, all within the standard Ballerina testing framework.

### Trace and Iteration Records

```ballerina
# Represents the trace of an agent's execution.
public type Trace record {|
    # Unique identifier for the trace
    string id;
    # Input message provided by the user
    ChatUserMessage userMessage;
    # Sequence of iterations performed by the agent
    Iteration[] iterations;
    # Final output produced by the agent
    ChatAssistantMessage|Error output;
    # Schema of the tools used by the agent during execution
    ToolSchema[] tools;
    # Start time of the trace
    time:Utc startTime;
    # End time of the trace
    time:Utc endTime;
|};
```

```ballerina
# Represents the schema of a tool used by the agent.
public type ToolSchema record {|
    # Name of the tool
    string name;
    # Description of the tool
    string description;
    # Parameters schema of the tool
    map<json> parametersSchema?;
|};
```

```ballerina
# Represents a single iteration in the agent's execution trace.
public type Iteration record {|
    # History of chat messages up to this iteration
    ChatMessage[] history;
    # Output produced by the agent in this iteration
    ChatAssistantMessage|Error output;
    # Start time of the iteration
    time:Utc startTime;
    # End time of the iteration
    time:Utc endTime;
|};
```

### Type binding `Trace` as output of Agent `run` method

```ballerina
public isolated class Agent {
  // ... omitted for brevity

  public isolated function run(string query,
        string sessionId = DEFAULT_SESSION_ID,
        Context context = new, 
        typedesc<Trace|string> td = <>) returns td|Error = external;
}
```
The above change allows you to retrieve either the agent’s string response or the full execution trace.

> Note: Any types not explicitly listed here are imported from the `ballerina/ai` module.

### Trace utility functions

The following utility functions will be added to the `ballerina/ai` library as convenience functions for working with `Trace` records. These methods help users easily extract information and perform evaluations on agent executions.

```ballerina
# Retrieves all function calls made during the agent's execution.
# + trace - The trace object representing the agent's execution.
# + returns - An array of `FunctionCall` records for each function call made, or an empty array if none.
public isolated function getAllToolCalls(Trace trace) returns FunctionCall[] {
    return [];
}

# Verifies that a function call matches an expected function call in terms of name and parameters.
# + actual - The function call that was actually made.
# + expected - The expected function call to compare against.
# + returns - An `Error` if the calls do not match, otherwise returns nil.
public isolated function assertToolCall(FunctionCall actual, FunctionCall expected) returns Error? {
    return;
}

# Checks if any errors occurred during the agent's execution.
# + trace - The trace object representing the agent's execution.
# + returns - `true` if at least one error occurred, otherwise `false`.
public isolated function hasError(Trace trace) returns boolean {
    return false;
}

# Retrieves all errors encountered during the agent's execution.
# + trace - The trace object representing the agent's execution.
# + returns - An array of `Error` records encountered, or an empty array if none.
public isolated function getErrors(Trace trace) returns Error[] {
    return [];
}

# Retrieves the final answer produced by the agent after execution.
# + trace - The trace object representing the agent's execution.
# + returns - The final answer as a `string` if available, otherwise returns an `Error`.
public isolated function getFinalAnswer(Trace trace) returns string|Error {
    ChatAssistantMessage|Error output = trace.output;
    return output is ChatAssistantMessage
        ? output.content.toString()
        : output;
}

# Computes the total execution time of the agent's trace or a specific iteration.
# + trace - A `Trace` or `Iteration` object.
# + returns - The total execution time as `time:Seconds`.
public isolated function getTotalExecutionTime(Trace|Iteration trace) returns time:Seconds {
    return time:utcDiffSeconds(trace.endTime, trace.startTime);
}
```

#### Example of Writing an AI Evaluation

Using the elements proposed above, a user can write a typical test using the Ballerina test framework as follows:

```ballerina
@test:Config
isolated function evaluateToolCallOrder() returns error? {
    int numberOfPassedEntries = 0;
    ToolCallEvalDataProvider[] dataset = toolCallOrderDataSet();

    foreach ToolCallEvalDataProvider entry in dataset {
        ai:Trace trace = check agent.run(entry.input);
        ai:FunctionCall[] toolCalls = ai:getAllToolCalls(trace);
        string[] actualToolCallNames = toolCalls.'map(tool => tool.name);

        if actualToolCallNames == entry.expectedTools {
            numberOfPassedEntries += 1;
        }
    }

    float confidenceThreshold = 0.8;
    float passRate = <float>numberOfPassedEntries / <float>dataset.length();

    if passRate < confidenceThreshold {
        test:assertFail(string `Test failed with pass rate of: ${passRate}`);
    }
}
```

However, this approach does not provide a `first-class` experience for writing AI evaluations. To improve this, we can enhance the Ballerina test framework to natively support evaluation tests.

### Enhancement to Ballerina test framework

Currently, the test framework allows providing a dataset through the `dataProvider` field in the `@test:Config` annotation. But in the default behavior, the entire `bal test` command fails if **any single entry** fails. For AI evaluation, we usually want the test to fail **only if the overall performance falls below a specified threshold**, not because of one failed case.

To achieve this, the test framework could introduce a new field in `@test:Config` called `confidence` (or `threshold`). When this field is set, the framework would treat the entire dataset as a single evaluation test, calculate the average result, and pass or fail the test based on the configured threshold.

After this enhancement, users can write AI evaluation tests with a much cleaner and intuitive syntax:

#### Example of Writing an AI evaluation with test framework enhancement

```ballerina
import ballerina/ai;
import ballerina/test;

@test:Config {
    dataProvider: toolCallOrderDataSet,
    confidence: 0.8
}
isolated function evaluateToolCallOrder(ToolCallEvalDataProvider entry) returns error? {
    ai:Trace trace = check agent.run(entry.input);
    ai:FunctionCall[] toolCalls = ai:getAllToolCalls(trace);
    string[] actualToolCallNames = toolCalls.'map(tool => tool.name);
    test:assertEquals(actualToolCallNames, entry.expectedTools);
}

public type ToolCallEvalDataProvider record {|
    string input;
    string[] expectedTools;
|};

isolated function toolCallOrderDataSet() returns ToolCallEvalDataProvider[][] {
    return [
        // Simple greeting, no tools expected
        [{input: "Hi", expectedTools: []}],

        // Email-related tasks
        [{input: "Forward the last email from HR to my manager.", expectedTools: ["readEmail", "sendEmail"]}],
        [{input: "Delete all unread promotional emails.", expectedTools: ["readEmail", "deleteEmail"]}],

        // Calendar and scheduling tasks
        [{input: "Reschedule my call with Alice to next Monday.", expectedTools: ["readCalendar", "updateCalendar"]}],
        [{input: "List all my meetings for this week.", expectedTools: ["readCalendar"]}],

        // Mixed tasks
        [{input: "Summarize my unread emails and schedule a follow-up meeting.", expectedTools: ["readEmail", "summarizeEmail", "readCalendar", "bookCalendar"]}],
        [{input: "Send an email to Raj and add a calendar invite.", expectedTools: ["sendEmail", "bookCalendar"]}]
    ];
}
```

With this approach, writing AI evaluation tests feels natural, concise, and they integrate seamlessly with the Ballerina test framework.

**Note:** In addition to the above enhancement, the test report generated via `bal test --test-report` should also be improved to display the confidence score calculated for each evaluation test. This value can then serve as a baseline for future regression testing.

## Limitation

Evaluation platforms like Arize, Phoenix, Langfuse, and LangSmith maintain a persistent store of historical agent runs. This enables powerful capabilities such as:

* Monitoring performance trends over time
* Comparing current results against historical baselines
* Querying and analyzing metrics across versions, tasks, or datasets

While the Ballerina testing framework can replicate the **evaluation logic**, it does **not** provide built-in support for persistent storage, trend analysis, or historical comparisons. These capabilities could be added by exporting evaluation results to an external storage system—and in the future, they could be offered through **Devant** as a first-class feature.

For most integration and deployment scenarios, however, the proposed test-driven evaluation approach is more than sufficient to ensure agent reliability and prevent regressions.

Developers who prefer observability-based evaluation can still integrate existing tooling. As long as the agent is configured with a compatible observability provider, frameworks like Arize Phoenix can be used without friction. 

For example:
1. Configure Arize as the observability backend so that agent traces are exported directly to Arize.
2. Use Arize’s REST API to run evaluations and submit results back to the Arize platform.

This approach ensures that both **trace-free** and **observability-driven** evaluation workflows remain fully supported.

## Conclusion

This proposal demonstrates that AI agents in Ballerina can be evaluated using a lightweight, test-driven approach without relying on observability infrastructure. It allows developers to verify behavior, assert outcomes, and prevent regressions in a CI-friendly, reproducible way. While trace-based frameworks offer historical analysis, this method is sufficient for most integration and deployment scenarios. Observability integration remains optional for teams that need it.