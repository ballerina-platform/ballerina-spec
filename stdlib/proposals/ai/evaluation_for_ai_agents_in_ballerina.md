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

This proposal introduces a test-driven evaluation method for AI Agents in Ballerina that integrates directly into the existing Ballerina test framework. Unlike observability-dependent frameworks, this approach treats AI agent evaluation as an extension of integration testing—allowing developers to validate agent behavior using the same tools, patterns, and workflows they already use for testing Ballerina applications.

The result is a lightweight, reproducible, and CI-friendly evaluation method that requires no additional infrastructure, no new toolchains, and no learning curve for integration engineers.

## Goals

- Provide a test-driven approach to evaluate AI agents that integrates seamlessly with existing Ballerina test framework
- Enable evaluation that is not coupled to observability infrastructure
- Make AI evaluation accessible to integration engineers through familiar testing patterns

## Motivation

### The Problem with Observability-Dependent Evaluation

Most existing AI agent evaluation frameworks depend heavily on observability traces to perform evaluations (e.g., Arize Phoenix, LangSmith, and Langfuse). While trace-based evaluation is powerful for certain use cases, it introduces several challenges:

- **Infrastructure Overhead:** Requires dedicated observability backends, trace collectors, and storage systems
- **Environment Constraints:** Cannot be used in air-gapped environments, CI pipelines without network access, or compliance-restricted contexts where trace data cannot be externalized
- **Complexity:** Adds a separate toolchain that integration engineers must learn and maintain
- **Slower Feedback:** Trace collection, indexing, and query latency can slow down evaluation cycles
- **Deployment Friction:** Not suitable for lightweight or local deployment scenarios

### Why Integration Engineers Need Test-Driven Evaluation

Integration engineers building Ballerina applications already rely on the Ballerina test framework to validate service behavior, API contracts, and business logic. When AI agents are introduced into these integrations, engineers need to validate agent behavior in the same way—ensuring that agents make correct decisions, invoke the right tools, and produce expected outputs.

**Test-driven evaluation aligns perfectly with this reality:**

- **Familiar Workflow:** Integration engineers already use the Ballerina test framework daily. Adding AI evaluation there keeps their workflow consistent—no new tools, servers, or platforms to learn.
- **No New Toolchain:** Tests run with `bal test`, produce standard test reports, and integrate into existing CI/CD pipelines without modification.
- **Unified Validation:** The same pass/fail signal that works for integration logic now also works for AI behavior, giving instant clarity and confidence.
- **Fast Feedback Loops:** Tests run locally, in CI, and in isolated environments without extra setup. Engineers catch regressions early and ensure new features do not degrade expected behavior.
- **Lightweight and Portable:** No observability backends, no trace storage, no network dependencies—just code, tests, and assertions.

For integration engineers, **evaluation is just testing AI behavior the same way they test everything else**. This proposal makes that possible.

## Key Concepts

In this framework, it is important to distinguish between **dataset entries** and **evaluation tests**:

- **Dataset Entry:** A single input–output pair that the agent is evaluated against. Each entry produces a **binary pass/fail outcome** based on whether the agent meets the specified criterion for that input. Entries themselves are not considered full test cases; they are the atomic units of evaluation.

- **Evaluation Test /Test Case:** A function annotated with `@test:EvalConfig` that receives a dataset entries (via a data provider). The **entire dataset together forms one evaluation test**, and the overall pass/fail of the evaluation is determined by the **cumulative pass rate across all entries**, compared against the configured confidence threshold.

### Understanding Evaluation vs Testing

While traditional software testing relies on **deterministic behavior** (exact output matching), AI agent evaluation must account for the **non-deterministic nature** of LLMs. The same input can produce different outputs across runs, making strict assertions impractical.

| Aspect | Traditional Testing | AI Evaluation |
|--------|-------------------|---------------|
| **Behavior** | Deterministic | Non-deterministic |
| **Assertion Style** | Exact matching (`assertEquals`) | Probabilistic metrics (accuracy, relevance, task success) |
| **Pass Criteria** | Single execution must pass | Aggregate performance across dataset must meet threshold |
| **Measurement** | Binary (pass/fail) | Scored (0.0 to 1.0 or percentage) |

**However, evaluation can be expressed as testing when:**

1. Individual dataset entries produce binary outcomes: Each entry evaluates to pass or fail, even if the underlying decision uses scoring internally
2. Aggregate performance determines overall pass/fail: A confidence threshold (e.g., 80%) is set for the entire dataset—if 80% or more entries pass, the evaluation passes

This allows **evaluation to be expressed within the test framework** while respecting the probabilistic nature of AI systems.

### Why Binary Outcomes Per Dataset Entry?

Each dataset entry in an AI evaluation produces a **binary pass/fail outcome**. This design choice addresses a fundamental question: **Why not use a range of scores (e.g., 0.0 to 1.0) at the dataset entry level?**

#### Rationale for Binary Outcomes

**1. Ranges Create Ambiguity in Test Results**

What does a score of 0.6 mean? Is that acceptable? Without a threshold, scores lack actionability. Binary outcomes provide immediate clarity: the test met expectations or it didn't.

**2. Developers Must Set Thresholds Anyway**

Even if the framework supported ranges, developers would need to decide: "At what score does this test case pass?" This threshold decision is unavoidable. By making it explicit in code, we:
- Force developers to think about acceptable quality levels
- Make the evaluation criteria visible and reviewable
- Allow different thresholds for different test cases based on their importance

**3. Binary Outcomes Match Integration Testing Mental Models**

Integration engineers already think in pass/fail terms:
- Did the API return the expected status code? ✓ or ✗
- Did the integration flow complete successfully? ✓ or ✗
- Did the agent invoke the correct tools? ✓ or ✗

**4. Discrete Labels Reduce Variance When Using an LLM as the Judge**

In some evaluation scenarios, correctness cannot be determined through strict assertions or rule based logic. In these cases, an LLM itself may be used as an evaluator to judge the quality of an agent's output, such as relevance, correctness, or alignment with expected intent. This pattern is commonly referred to as LLM-based evaluation or LLM-as-a-judge.

When the judge itself is an LLM, numeric scoring becomes unstable. The same test case can produce noticeably different numeric ratings across multiple runs even when the inputs are unchanged. A difference such as 78 compared to 82 has no real interpretive value and is mostly noise. Discrete labels such as pass(correct) or fail(wrong) produce far more consistent outcomes because the model must classify instead of choosing an arbitrary point on a large scale. These labels reduce sensitivity to prompt phrasing, create more stable results across repeated evaluations, and make metrics such as accuracy or majority voting easier to compute and interpret.

**5. Binary Outcomes Prevent Outlier Skew in Aggregation**

Using numeric scores in evaluations makes the overall result sensitive to outliers. A small number of extreme values can disproportionately skew the aggregate score, making the evaluation unstable and misleading.

This is why the **Binary Outcomes per Dataset Entry** approach is used. Each dataset entry produces a simple **pass/fail outcome**. This makes aggregation robust, because:

1. Extreme values cannot distort the overall result.
2. Each entry contributes equally to the final outcome.
3. The aggregate pass rate reflects consistent behavior rather than numerical extremes.

In short, binary outcomes make evaluations more stable, interpretable, and resilient to outliers when aggregating results across a dataset.

#### Converting Scores to Binary Outcomes

When a test case requires a scored judgment (e.g., LLM-as-a-judge returning 0.0 to 1.0), the developer implements threshold logic within the test:

```ballerina
    // ... omitted for brevity
    int relevanceScore = getRelavanceScore(query, agentOutput);
    test:assertTrue(relevanceScore >= 0.7, string `Relevance score ${relevanceScore} below threshold 0.7`);
    // Implicitly returns success
    // ... omitted for brevity
```

This approach provides:
- **Flexibility:** Different test cases can use different thresholds
- **Transparency:** The threshold is visible in code, not hidden in framework configuration
- **Composability:** Binary outcomes from diverse test cases can be aggregated cleanly

### Why Confidence Thresholds for Datasets?

The confidence threshold set for the dataset represents the **minimum acceptable pass rate** across all entries. This approach accounts for the inherent non-determinism of AI systems:

- **Realistic Expectations:** AI agents will not achieve 100% accuracy on every input. Setting a confidence threshold (e.g., 80%) acknowledges this while still enforcing a quality bar.
- **Aggregate Performance Matters:** A single failure should not cause the entire evaluation to fail. What matters is whether the agent performs reliably across a representative set of inputs.
- **Prevents Brittle Tests:** Without a confidence threshold, a single flaky LLM response could break the entire test suite. The confidence-based approach makes evaluations more resilient.
- **Enables Baseline Tracking:** The calculated pass rate becomes a baseline for future runs. Teams can track whether performance improves or degrades over time.

## Design

To enable evaluation without relying on any observability infrastructure, the `ballerina/ai` module will introduce a set of new APIs that expose intermediate steps and agent state transitions. These additions allow developers to inspect an agent's reasoning process, tool interactions, and final outputs directly. Using this information, users can write evaluations through input–output–driven testing and behavioral assertions, all within the standard Ballerina testing framework.

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
The above change allows you to retrieve either the agent's string response or the full execution trace.

>**Note:** Any types not explicitly listed here are imported from the `ballerina/ai` module.

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

>**Note:** To better separate these evaluation utility methods from the AI module, we can introduce the above methods in a separate package called ballerina/ai.eval. This will become an independent package from the existing ballerina/aimodule.

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

To achieve this, the test framework could introduce a new annotation.

```ballerina
# Configuration used when running an evaluation.
public type EvaluationConfig record {|
    # Minimum pass rate required for the dataset.
    float confidence;

    # Number of times the evaluation should repeat.
    int iterations = 1;
|};

public annotation EvaluationConfig EvalConfig on function;
```

When the proposed annotation is applied to a test case, the framework treats the whole dataset as one evaluation test. It computes the average outcome and decides whether the test passes or fails based on the configured `confidence` value. The `iteration` field allows the dataset to be evaluated multiple times. If the value is greater than 1, the framework runs the evaluation repeatedly with the same dataset and records the outcome of each run. After completing all runs, it computes the mean of those results. This combined average is then used to decide whether the evaluation meets the required `confidence` level.

After this enhancement, users can write AI evaluation tests with a much cleaner and intuitive syntax:

#### Example of Writing an AI evaluation

1. Evaluating the trajectory of tool calls

```ballerina
import ballerina/ai;
import ballerina/test;

@test:EvalConfig {
    confidence: 0.8 // Confidence Thresholds for Dataset
}
@test:Config {
    dataProvider: toolCallOrderDataSet,
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

isolated function toolCallOrderDataSet() returns ToolCallEvalDataProvider[][] => [
        [{input: "Summarize my unread emails and schedule a follow-up meeting.",
            expectedTools: ["readEmail", "summarizeEmail", "readCalendar", "bookCalendar"]}],
        [{input: "Send an email to Raj and add a calendar invite.",
            expectedTools: ["sendEmail", "bookCalendar"]}]
    ];
    // or load it from a file
```

2. LLM-as-a-Judge Evaluation

For cases where strict assertions are insufficient, developers can use LLM-as-a-judge evaluation with threshold logic:

```ballerina
@test:EvalConfig {
    confidence: 0.85 // Confidence Thresholds for Dataset
}
@test:Config {
    dataProvider: relevanceDataSet,
}
isolated function evaluateAnswerRelevance(RelevanceTestCase entry) returns error? {
    ai:Trace trace = check agent.run(entry.input);
    string answer = check ai:getFinalAnswer(trace);
    
    // LLM-as-a-judge returns a score between 0.0 and 1.0
    float relevanceScore = check ai:evaluateRelevance(answer, entry.expectedContext);
    
    // Convert score to binary pass/fail
    test:assertTrue(relevanceScore >= 0.7, string `Relevance score ${relevanceScore} below threshold 0.7`);
}
```

With this approach, writing AI evaluation tests feels natural, concise, and they integrate seamlessly with the Ballerina test framework.

>**Note:** In addition to the above enhancement, the test report generated via `bal test --test-report` should also be improved to display the confidence score calculated for each evaluation test. This value can then serve as a baseline for future regression testing.

## Limitations

Observability-dependent platforms maintain a persistent store of historical agent runs. This enables powerful capabilities such as:

- Monitoring performance trends over time
- Comparing current results against historical baselines
- Querying and analyzing metrics across versions, tasks, or datasets

While the Ballerina testing framework can replicate the **evaluation logic**, it does **not** provide built-in support for persistent storage, trend analysis, or historical comparisons. These capabilities could be added in the future by exporting evaluation results to an external storage system.

For most integration and deployment scenarios, however, the proposed test-driven evaluation approach is more than sufficient to ensure agent reliability and prevent regressions.

Developers who prefer observability-based evaluation can continue using the existing Ballerina observability provider implementations. When the agent is configured with a compatible provider, frameworks like Arize Phoenix can be integrated seamlessly.

For example:
1. Configure Arize as the observability backend so that agent traces are exported directly to Arize.
2. Use Arize's REST API to run evaluations and submit results back to the Arize platform.

This approach ensures that both **trace-free** and **observability-driven** evaluation workflows remain fully supported.

### Further enhancement to the Ballerina test framework

To overcome the limitation around storing and tracking past evaluation outputs, the Ballerina test framework can be extended with a set of improvements that make evaluation results easier to retain, organize, and analyze over time.

* Support a dedicated directory for storing evaluation reports by using `bal test --test-report --test-report-dir evaluation`. This places all generated reports inside an `evaluation` folder, allowing teams to version and track them through source control.
* Produce a new report file for every test execution that includes a timestamp in its name. This ensures older reports remain intact, making it possible to review historical data and understand how performance changes across versions.
* If a data provider is configured for the evaluation test, include the input values passed to the tests through the data provider. Recording this information makes each report self-contained, allowing developers to fully understand what was evaluated without checking the test sources. If no data provider is configured, the generated report should not include any inputs and should explicitly state that no data provider is configured for that evaluation test.

With these additions, the Ballerina Test framework can serve both immediate regression checks and longer term evaluation tracking.

## Summary of changes required

### Changes to the `ballerina/ai` module

1. **New Record Types**
   - Add `Trace` record to represent agent execution traces
   - Add `Iteration` record to represent individual steps in execution
   - Add `ToolSchema` record to capture tool metadata

2. **Agent API Enhancement**
   - Modify `Agent.run()` method to support type binding with `typedesc<Trace|string>` parameter
   - Return either string response or full `Trace` record based on the type descriptor

### Introduce `ballerina/ai.eval` module

3. **Trace Utility Functions**
   - `getAllToolCalls()` - Extract all function calls from a trace
   - `assertToolCall()` - Verify function call matches expected parameters
   - `hasError()` - Check for errors in execution
   - `getErrors()` - Retrieve all errors from a trace
   - `getFinalAnswer()` - Extract the final agent response
   - `getTotalExecutionTime()` - Calculate execution duration
   - Additional utilities and evaluation prompts for LLM-as-a-judge

### Changes to the Ballerina test framework

1. **Confidence-based Evaluation**
   - Add new `@test:EvalConfig` annotation
   - Implement pass/fail logic based on aggregate performance across dataset (`dataProvider`) entries
   - Calculate pass rate and compare against confidence threshold

2. **Enhanced Test Reporting**
   - Display confidence scores in test reports generated via `bal test --test-report`
   - Show aggregate metrics for evaluation tests (Caculated confidence score)
   - Support `--test-report-dir` flag to specify custom report directory
   - Generate timestamped report files for historical tracking
   - Include `dataProvider` input values in test reports for better traceability

## Conclusion

This proposal demonstrates that AI agents in Ballerina can be evaluated using a lightweight, test-driven approach without relying on observability infrastructure. It allows developers to verify behavior, assert outcomes, and prevent regressions in a CI-friendly, reproducible way. While trace-based frameworks offer historical analysis, this method is sufficient for most integration and deployment scenarios. Observability integration remains optional for teams that need it.