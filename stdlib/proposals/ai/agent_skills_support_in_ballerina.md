# Agent Skills Support for AI Agents in Ballerina

- Authors
    - @MohamedSabthar
- Reviewed by
    - TBD
- Created date
    - 2026-10-13
- Issue
    - [1509](https://github.com/ballerina-platform/ballerina-spec/issues/1509)
- State
    - Submitted

## Summary

This proposal adds first-class support for [Agent Skills](https://agentskills.io) to the `ai:Agent` in the `ballerina/ai` module. A skill is a self-contained package of instructions and supporting files (a folder with a `SKILL.md` file) that teaches an agent how to perform a specific kind of task. Developers attach skills to an agent through a new `skills` field in `ai:AgentConfiguration`, either by pointing to skill folders on the file system or by defining skills inline in code.

Skills are loaded using **progressive disclosure**: only each skill's name and description are placed in the system prompt, while the full instructions and any reference files are loaded on demand when the model decides it needs them, through two built-in tools managed by the agent. This keeps the context window small regardless of how many skills are installed, and requires no extra wiring from the developer.

## Goals

- Provide first-class, built-in support for Agent Skills in `ai:Agent`, configured with a single field.
- Follow the open Agent Skills format (`SKILL.md` with YAML frontmatter, plus `references/` and `assets/` folders) so that skills written for other agent runtimes work unchanged in Ballerina.
- Keep the model's context small and focused through progressive disclosure: pay for skills only when they are used.
- Require no manual wiring: the agent builds the skill catalog for the system prompt and registers the tools needed to load skills.
- Provide safe, read-only access to skill resource files.

## Motivation

### Reusable knowledge without bloated instructions

Today, the only way to give an `ai:Agent` domain-specific know-how (a company's code review checklist, the steps for filing an expense report, the conventions of an internal API) is to put it into `SystemPrompt.instructions` or to hand-write tools that return that text. Both approaches have problems:

- **Instructions grow without bound.** Every new capability adds more text to the system prompt, which is sent on every LLM call, whether or not the current request needs it. This increases cost and latency, and long, unrelated instructions compete for the model's attention and reduce answer quality.
- **Knowledge is not reusable.** Instructions embedded in Ballerina source cannot easily be shared across agents, teams, or other agent runtimes, and they are hard for non-developers (domain experts, technical writers) to maintain.
- **Ad-hoc loading tools are reinvented.** Developers who want on-demand loading end up writing their own "read this document" tools and their own catalog text, with their own conventions and their own security checks.

Agent Skills address all three. A skill is a folder that domain experts can author and version independently of the agent code, and the format is an open standard shared across the agent ecosystem.

### Why progressive disclosure

An agent may have access to many skills, but a single request typically needs one or two of them. Loading every skill in full would recreate the "bloated instructions" problem. Progressive disclosure gives the model just enough information (name and description) to know *which* skill to use, and lets it pull in the details only when needed. The cost of the system prompt then grows with the number of skills by only a short line per skill, while long instructions and reference documents cost nothing until they are read.

### Why built into the agent

Supporting a skill requires two cooperating parts:

1. A **catalog in the system prompt** that tells the model which skills exist and when to use them.
2. **Tools** that the model calls to load a skill's instructions and resources.

A tool or toolkit can only contribute the second part; it cannot change the system prompt. If skills were offered only as a toolkit, every developer would have to build the catalog text themselves and keep it in sync with the toolkit. Making skills a field of `ai:AgentConfiguration` lets the agent own both parts, so attaching a skill is a one-line change.

## Key Concepts

- **Skill**: A named unit of instructions that teaches the agent how to perform a task. It has a `name`, a `description`, a body of instructions, and optional resource files.
- **`SKILL.md`**: The file that defines a skill. It starts with YAML frontmatter containing `name` and `description`, followed by the instructions as Markdown.
- **Resources**: Supporting files stored next to `SKILL.md`, in the `references/` folder (documentation the model may read) and the `assets/` folder (templates, sample data, and similar files).
- **Skill source**: Where skills come from. This is either a path on the local file system or a skill defined inline in Ballerina code.
- **Skill catalog**: The list of available skills (name and description only) that the agent adds to the system prompt.
- **Activation**: The model loading a skill's full instructions by calling the built-in `activate_skill` tool.

A typical skill folder looks like this:

```
skills/
└── expense-report/
    ├── SKILL.md
    ├── references/
    │   └── policy.md
    └── assets/
        └── template.csv
```

With a `SKILL.md` such as:

```markdown
---
name: expense-report
description: Prepares and validates employee expense reports. Use when the user asks to file, check, or summarize expenses.
---

# Filing an expense report

1. Ask for the date, amount, currency, and category of each expense.
2. Check every item against the limits in `references/policy.md`.
3. Produce the report using the columns in `assets/template.csv`.
```

## Design

### 1. Public API

The following types are added to the `ballerina/ai` module.

```ballerina
# Represents a skill, or a directory of skills, on the local file system in the Agent Skills format.
public type LocalSkillSource record {|
    # Path to a skill directory (a directory that contains a `SKILL.md` file), or to a directory
    # whose immediate sub-directories are skill directories.
    # A relative path is resolved against the current working directory of the running program
    # (the directory from which `bal run` or `java -jar` is executed).
    string path;
|};

# Represents a skill defined inline in code, without a file system.
public type Skill record {|
    # The unique name of the skill
    string name;
    # A short description of what the skill does and when it should be used
    string description;
    # The full instructions returned when the skill is activated
    string instructions;
    # Optional resources, keyed by their relative path (e.g. `references/api.md`), with the content as the value
    map<string> resources = {};
|};

# Represents a source of skills for an agent.
public type SkillSource LocalSkillSource|Skill;
```

`ai:AgentConfiguration` gets a new optional field, `skills`, placed after `tools`. Agents that do not set it behave exactly as they do today:

```ballerina
public type AgentConfiguration record {|
    // ... existing fields omitted for brevity

    # The tools available for the agent
    @display {label: "Tools"}
    (BaseToolKit|ToolConfig|FunctionTool)[] tools = [];

    # Skills available to the agent. Only each skill's name and description are added to the system prompt;
    # the full instructions and resources are loaded on demand through built-in skill tools.
    @display {label: "Skills"}
    SkillSource[] skills?;

    // ... existing fields omitted for brevity
|};
```

`SkillSource` is a union so that new kinds of sources (for example, remote skill repositories) can be added later without changing the field.

### 2. Skill discovery and loading

If `skills` is not set, or is an empty array, nothing is loaded and the agent behaves exactly as it does without this feature (see [When no skills are configured](#when-no-skills-are-configured)). Otherwise, skills are loaded once, when the agent is initialized. Any error is returned from `ai:Agent`'s `init` as an `ai:Error`.

For each `LocalSkillSource`:

- If `path` contains a `SKILL.md` file, it is treated as a **single skill directory**. If that skill is invalid, agent initialization fails.
- Otherwise, `path` is treated as a **parent directory**, and each immediate sub-directory that contains a `SKILL.md` file is loaded as a skill. If one of those skills is invalid, it is skipped and a warning is logged, so that one broken skill does not disable the others.
- If `path` does not exist or cannot be read, agent initialization fails.
- A relative `path` is resolved against the **current working directory of the running program**, not against the Ballerina source file or the project root. For example, if the program is started with `bal run` from `/home/user/finance-agent`, then `{path: "./skills"}` refers to `/home/user/finance-agent/skills`. Use an absolute path, or a path from a configurable variable, when the program may be started from a different directory.
- Paths *inside* a skill are a separate matter: resource paths such as `references/policy.md` are always relative to that skill's own directory (the directory that contains its `SKILL.md`).

For each inline `Skill`, the record is used as-is after the same `name` and `description` validation.

Across all sources, skill names must be unique. If two skills have the same name, the first one (in the order of `skills`) is kept and a warning is logged for the duplicate.

### 3. `SKILL.md` format and validation

- The file must begin with YAML frontmatter delimited by `---` lines.
- The frontmatter must contain `name` and `description`, both non-empty strings. Other frontmatter keys are ignored.
- Everything after the frontmatter is the skill's instructions (the body).
- The skill's **resources** are the files located directly inside its `references/` and `assets/` folders. The list of resources is computed when the skill is loaded; the file contents are read only when requested.

A `SKILL.md` without frontmatter, with malformed YAML, or with a missing or empty `name` or `description` is invalid.

### 4. Progressive disclosure

Progressive disclosure is the core of this design. Skill content is loaded in three levels, and each level is loaded only when the previous one indicates that it is needed.

| Level | What is loaded | When it is loaded | Where it goes | Approximate cost |
|---|---|---|---|---|
| 1. Metadata | `name` and `description` of every skill | Always, at agent initialization | System prompt (skill catalog) | A short line per skill |
| 2. Instructions | The `SKILL.md` body and the list of its resources | When the model calls `activate_skill` | Tool result in the conversation | The size of the body (typically hundreds to a few thousand tokens) |
| 3. Resources | A single file from `references/` or `assets/` | When the model calls `read_skill_resource` | Tool result in the conversation | The size of the file |

#### Why this works

- **Cost scales with use, not with installation.** An agent can have dozens of skills while its base prompt only grows by a short catalog entry per skill. Long reference documents cost nothing unless the model actually reads them.
- **The model stays focused.** Instructions for unrelated tasks do not compete for the model's attention.
- **Skills can be large.** Because resources are loaded one file at a time, a skill can ship extensive reference material without affecting the cost of requests that do not need it.

#### How the model decides what to load

The `description` in the catalog is the only signal the model has for choosing a skill. Skill authors should therefore write descriptions that state both **what** the skill does and **when** it should be used (for example, *"Prepares and validates employee expense reports. Use when the user asks to file, check, or summarize expenses."*).

The catalog text instructs the model to activate a skill before following it, and to read resources only when the skill's instructions refer to them.

#### Level 1: Skill catalog in the system prompt

When at least one skill is configured, the agent appends a `Skills` section to the system prompt it builds from `SystemPrompt.role` and `SystemPrompt.instructions`. The user-provided role and instructions are not modified.

```
# Role
<role>

# Instructions
<instructions>

# Skills
You have access to the following skills. Each skill provides specialized instructions for a specific task.
When a user's request matches a skill's description, call the `activate_skill` tool with the skill's name
to load its full instructions before proceeding. Only read a skill's resources with `read_skill_resource`
when the skill's instructions refer to them.

<available_skills>
  <skill>
    <name>expense-report</name>
    <description>Prepares and validates employee expense reports. Use when the user asks to file, check, or summarize expenses.</description>
  </skill>
  <skill>
    <name>code-review</name>
    <description>Reviews Ballerina code against the team's style guide. Use when the user asks for a code review.</description>
  </skill>
</available_skills>
```

The catalog is generated as XML, so names and descriptions are XML-escaped and cannot break the structure of the prompt.

#### Level 2: Activating a skill

When the model calls `activate_skill` with `name = "expense-report"`, the tool returns:

```
<skill_content name="expense-report">
# Filing an expense report

1. Ask for the date, amount, currency, and category of each expense.
2. Check every item against the limits in `references/policy.md`.
3. Produce the report using the columns in `assets/template.csv`.
</skill_content>

<skill_resources>
  <resource>references/policy.md</resource>
  <resource>assets/template.csv</resource>
</skill_resources>
```

The body is returned exactly as written (it is not XML-escaped), so the Markdown instructions reach the model unchanged. The `<skill_resources>` element is omitted if the skill has no resources.

#### Level 3: Reading a resource

When the model calls `read_skill_resource` with `skillName = "expense-report"` and `resourcePath = "references/policy.md"`, the tool returns the content of that file as text.

#### End-to-end walkthrough

The following shows how a single request flows through the three levels. Each step after the first is an ordinary tool-call iteration of the agent loop.

| Iteration | Message | Content |
|---|---|---|
| — | System | Role, instructions, and the skill catalog (Level 1) |
| — | User | "File my expenses for the Colombo trip: taxi 2500 LKR, hotel 120 USD." |
| 1 | Assistant | Tool call: `activate_skill(name = "expense-report")` |
| 1 | Function | `<skill_content ...>` with the instructions and resource list (Level 2) |
| 2 | Assistant | Tool call: `read_skill_resource(skillName = "expense-report", resourcePath = "references/policy.md")` |
| 2 | Function | The content of `policy.md` (Level 3) |
| 3 | Assistant | The final answer: a validated expense report |

Because skill loading uses ordinary tool calls:

- Each activation or resource read counts as an iteration toward `maxIter`.
- The calls appear in the agent's `Trace` like any other tool call, so they can be inspected and asserted on in evaluations (for example, to check that the agent activated the expected skill).
- They are reported through the existing observability spans.

#### Lifetime of loaded content

- The catalog is part of the system message. It is rebuilt on every run, and memory overflow handling never removes it, so the model always knows which skills exist.
- Activated instructions and resource contents are tool results. They stay in the session's conversation history like any other tool result.
- If memory overflow handling (trimming or summarization) removes those messages, the model can simply activate the skill again from the catalog. The agent does not re-insert them automatically.
- Activation is idempotent: activating the same skill again returns the same content.

#### Trade-offs

Progressive disclosure adds an LLM round trip for each activation or resource read. In return, the base prompt stays small and stable across requests, which reduces cost on every call that does not need a skill and improves focus on those that do. Loading every skill's full instructions into the system prompt up front was considered and rejected (see [Alternatives considered](#alternatives-considered)).

### 5. Built-in skill tools

When at least one skill is configured, the agent registers two built-in tools. They are internal to the agent and are not part of the public API.

#### `activate_skill`

| Parameter | Type | Description |
|---|---|---|
| `name` | `string` | The name of the skill to activate, as listed in the catalog |

Returns the skill's instructions and resource list (see [Level 2](#level-2-activating-a-skill)). If no skill has that name, an error message listing the available skill names is returned to the model, so it can correct itself.

#### `read_skill_resource`

| Parameter | Type | Description |
|---|---|---|
| `skillName` | `string` | The name of the skill that owns the resource |
| `resourcePath` | `string` | The path of the resource relative to the skill directory, e.g. `references/policy.md` |

Returns the content of the resource. The request is rejected, with an error message returned to the model, if any of the following holds:

- No skill has the name `skillName`.
- `resourcePath` does not start with `references/` or `assets/`.
- `resourcePath` contains a `..` segment.
- `resourcePath` is not in the skill's list of resources.
- For local skills, the resolved absolute path is outside the skill's directory (for example, through a symbolic link).

For inline skills, resources are served from the `resources` map in memory.

The tools use snake_case names (`activate_skill`, `read_skill_resource`) to reduce the chance of clashing with user-defined tools, which are conventionally named in camelCase in Ballerina.

### 6. Integration with the agent

- **Tool registration**: The skill tools are added to the agent's tool store together with the user-provided `tools`. If a user tool has the same name as a skill tool, agent initialization fails with the existing duplicate tool name error.
- **System prompt**: The catalog is added when the agent formats its system prompt, both for execution and for observability. `SystemPrompt` itself is unchanged.
- **Maximum iterations**: When `maxIter` is inferred from the number of tools, the two skill tools are included in the count.
- **Human-in-the-loop**: Skill tools only read data, so they never require approval and do not affect the human-in-the-loop approval flow.
- **Observability**: The skill tools are listed with the agent's tools on the create-agent span. In addition, the names of the loaded skills are recorded as a `skills` attribute on that span.

#### When no skills are configured

If `skills` is not set, is an empty array, or no valid skill is found in the given sources, the agent adds nothing related to skills:

- No `Skills` section is added to the system prompt; the prompt is identical to the one built today.
- The `activate_skill` and `read_skill_resource` tools are not registered, so they do not appear in the tool list sent to the model, do not count toward the inferred `maxIter`, and cannot clash with user tool names.
- No `skills` attribute is added to the create-agent span.

This guarantees that existing agents are unaffected by this feature, in behaviour, in token usage, and in observability data.

### 7. Skills, sessions, and memory

- **Skills belong to the agent, not to a session.** Like `tools`, `skills` is configuration. Skills are loaded once during agent initialization and kept in read-only fields of the `ai:Agent` object. Every session handled by the agent sees the same catalog.
- **No new state is stored.** The agent does not keep a record of which skills are active. An activation is simply an `activate_skill` tool call and its result in the session's conversation history, stored in `ai:Memory` like any other tool call. No changes to `ai:Memory` or memory stores are needed.
- **Deployment**: Because skills are loaded from the local file system at initialization and resources are read from disk on demand, every instance of a horizontally scaled application must be deployed with the same skill files.

### 8. Usage examples

#### Loading skills from a directory

```ballerina
import ballerina/ai;

final ai:Agent expenseAgent = check new (
    systemPrompt = {
        role: "Finance Assistant",
        instructions: "Help employees with finance-related tasks."
    },
    model = check ai:getDefaultModelProvider(),
    skills = [{path: "./skills"}]
);
```

#### Defining a skill inline

```ballerina
import ballerina/ai;

final ai:Skill toneSkill = {
    name: "customer-tone",
    description: "Guidelines for the tone of customer-facing replies. Use when drafting a message to a customer.",
    instructions: string `
        - Be polite and concise.
        - Never promise delivery dates; refer to the tracking page instead.
        - See references/phrases.md for approved phrases.`,
    resources: {
        "references/phrases.md": "- \"Thank you for reaching out.\"\n- \"We are happy to help.\""
    }
};

final ai:Agent supportAgent = check new (
    systemPrompt = {role: "Support Agent", instructions: "Answer customer questions."},
    model = check ai:getDefaultModelProvider(),
    skills = [toneSkill]
);
```

#### Using skills together with tools and multiple sources

Skills do not replace tools; an agent can have both. Tools let the agent *act* (call APIs, query systems), while skills tell it *how* to carry out a kind of task, often including which tools to call and in what order. For example, an `incident-response` skill can describe the steps for handling an outage, and those steps can instruct the model to call the agent's `createTicket` and `getOrderStatus` tools.

The example below also shows that `skills` can mix source kinds: a single skill directory, a parent directory containing several skills, and an inline skill. The built-in skill tools are added alongside the user's tools, so the model sees `createTicket`, `getOrderStatus`, `activate_skill`, and `read_skill_resource`.

```ballerina
final ai:Agent agent = check new (
    systemPrompt = {role: "Operations Assistant", instructions: "Help the operations team."},
    model = check ai:getDefaultModelProvider(),
    // Regular tools: functions annotated with `@ai:AgentTool`
    tools = [createTicket, getOrderStatus],
    skills = [
        {path: "./skills/incident-response"}, // a single skill directory
        {path: "./shared-skills"},            // a parent directory with several skills
        toneSkill                             // an inline skill
    ]
);
```

## Security Considerations

- **Read-only access**: The skill tools can only read files; they cannot write, delete, or execute anything.
- **Allow-listed files only**: `read_skill_resource` can only return files that were discovered as resources of a skill during loading. Arbitrary paths are rejected.
- **Path traversal protection**: Paths containing `..` are rejected, and for local skills the resolved absolute path must be inside the skill's directory, which also blocks escapes through symbolic links.
- **No script execution**: The Agent Skills format allows a `scripts/` folder. This proposal does not execute scripts and does not expose `scripts/` contents.
- **Trust in skill content**: Skill instructions become part of the model's context, so skills should be treated with the same trust as the agent's own instructions. Developers should only load skills from sources they control.

## Limitations and Out of Scope

- **Script execution**: Files in a skill's `scripts/` folder are not executed or exposed.
- **Remote skill sources**: Only local file system and inline skills are supported. Loading skills from Git repositories or URLs can be added later as new members of the `SkillSource` union.
- **Changes after initialization**: Skills are loaded once at agent initialization. Changes to skill files on disk are not picked up until the agent is re-created (resource contents, however, are read at request time).

## Alternatives Considered

### Loading all skills into the system prompt

Putting every skill's full instructions in the system prompt would remove the extra round trip per activation. It was rejected because the prompt cost would grow with every installed skill, on every LLM call, and unrelated instructions would compete for the model's attention. This defeats the purpose of skills as a scalable way to extend an agent.

### Exposing skills as a public toolkit

Skills could be offered as a public `ai:SkillsToolKit` that developers add to `tools`. It was rejected because a toolkit cannot add the skill catalog to the system prompt. Developers would have to build the catalog text themselves and keep it consistent with the toolkit, which is error-prone and duplicates logic in every agent.

### Appending the catalog to `instructions`

The catalog could be appended to the user's `instructions` text. It was rejected in favour of a separate `Skills` section, which keeps user-written text and generated text clearly separated in both the prompt and the observability data.

### camelCase tool names

The tools could be named `activateSkill` and `readSkillResource`, following Ballerina naming conventions. snake_case names were preferred to reduce clashes with user-defined tools (see [Design choices and considerations](#design-choices-and-considerations)).

### Note on the AFM implementation

The AFM reference implementation ([wso2/reference-implementations-afm#13](https://github.com/wso2/reference-implementations-afm/pull/13)) already supports Agent Skills, but inside the AFM interpreter itself: it discovers `SKILL.md` folders, appends an `<available_skills>` catalog to the agent's instructions, and registers a private `SkillsToolKit` with `activateSkill` and `readSkillResource` tools. This proposal follows the same skill format and loading behaviour.

It is not ported as a toolkit for the reason described above: a skill needs both a system-prompt catalog and tools, and a toolkit can only provide the tools. Built-in support in `ai:Agent` handles both parts, so any Ballerina agent can use skills with a single field, and the AFM interpreter can later replace its own implementation by passing its skills through the `skills` field.

## Design Choices and Considerations

The following choices were made in this proposal. They are listed here, with the reasoning behind each, so that reviewers can revisit them.

1. **`skills` is optional.** It is an optional field of `ai:AgentConfiguration`, and when it is absent or empty the agent adds nothing related to skills. This keeps the feature fully opt-in and leaves existing agents unchanged.
2. **Both file-based and inline skills are supported.** `LocalSkillSource` covers the standard Agent Skills format, while inline `ai:Skill` records are useful for tests, for small skills that live with the code, and for environments without a writable or bundled file system.
3. **Tool names use snake_case.** `activate_skill` and `read_skill_resource` are used instead of `activateSkill` and `readSkillResource`, to reduce the chance of clashing with user-defined tools, which are conventionally camelCase in Ballerina.
4. **Relative paths resolve against the current working directory.** This is consistent with how other file-based APIs in Ballerina resolve relative paths. Developers who need a fixed location should use an absolute path or a configurable variable.
5. **Missing paths fail; empty directories warn.** A source path that does not exist fails agent initialization, as it almost always indicates a misconfiguration. A parent directory that exists but contains no skills only logs a warning.
6. **The catalog is a separate section of the system prompt.** It is added as its own `Skills` section rather than being appended to `instructions`, so that user-written and generated text stay clearly separated in the prompt and in observability data.

## Summary of changes required

### Changes to the `ballerina/ai` module

- Add the public types `ai:LocalSkillSource`, `ai:Skill`, and `ai:SkillSource`.
- Add the `skills` field to `ai:AgentConfiguration`.
- Add internal logic to discover and validate skills, parse `SKILL.md` frontmatter (using `ballerina/yaml`), and list resources (using `ballerina/file` and `ballerina/io`).
- Add an internal toolkit providing the `activate_skill` and `read_skill_resource` tools, and register it with the agent's tool store when skills are configured.
- Add the skill catalog to the system prompt built by the agent, and record skill names on the create-agent span.

### Tests

- Discovery: single skill directory, parent directory with multiple skills (with `references/` and `assets/`), duplicate names, invalid skill in a single-skill directory, partially invalid parent directory, missing frontmatter, empty directory.
- Catalog: content and XML escaping.
- Tools: successful activation and resource read, unknown skill, path traversal, unlisted resource, inline skills.
- Agent level: using a mock model provider, verify that the system message contains the catalog, that the tool list contains the skill tools, and that a scripted `activate_skill` call returns the skill body in the next iteration.

### Documentation

- Update the module README and changelog with the new `skills` configuration and usage examples.

## Conclusion

This proposal brings Agent Skills to Ballerina as a first-class feature of `ai:Agent`. With a single `skills` field, developers can equip agents with reusable, independently maintained instructions and reference material in an open, portable format. Progressive disclosure keeps the cost and focus of the agent's context under control no matter how many skills are installed, and the built-in tools provide safe, read-only access to skill resources without any extra wiring from the developer.
