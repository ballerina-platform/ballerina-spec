# 1348: Decouple bal tools from the distribution

- **Authors** - Asma Jabir
- **Reviewed by** - TBD 
- **Created date** - 28 Apr, 2025
- **Updated date** - 28 Apr, 2025
- **Issue** - [1348](https://github.com/ballerina-platform/ballerina-spec/issues/1348)
- **State** - Proposed

## Summary
This proposal suggests decoupling commonly used Ballerina CLI tools (`bal openapi`, `bal graphql`, `bal grpc`, `bal persist`) from the main Ballerina distribution. The goal is to enable independent development, faster bug fixes, and more frequent feature releases without requiring a full distribution release. This change will involve introducing a plugin architecture that allows these tools and their associated components (e.g., compiler plugins, VSCode features) to be maintained and released separately.

## Motivation
The current Ballerina distribution includes several CLI tools such as `bal openapi`, `bal graphql`, `bal grpc`, and `bal persist` as part of the distribution. These tools, along with their compiler plugins and VSCode integration components, rely on Java dependencies that are bundled inside `<distribution>/bre/lib`.

As a result, even small fixes or feature updates to these tools require a full distribution release. This tight coupling limits our ability to iterate quickly, deliver timely improvements, and maintain each tool independently. Decoupling these tools from the distribution will introduce flexibility in tool development and release workflows, making Ballerina more modular and easier to maintain.

## Problems Addressed
* **Slow delivery cycles:** Updates to CLI tools cannot be released independently; they require a full distribution release, delaying fixes and enhancements.
* **Limited ownership due to tight coupling to the distribution:** Java dependencies shared between CLI tools, compiler plugins, and the VSCode extension are bundled in the distribution, making independent updates infeasible.
* **Barriers to experimentation:** Releasing experimental or beta versions of tools is cumbersome due to distribution coupling.
* **Increased maintenance complexity:** Changes in one tool or plugin may necessitate a full test and validation cycle across the entire distribution.

## Goals
The primary objective of this proposal is to decouple the release cycles of the IDL tools and LS extensions from the Ballerina distribution, enabling independent releases without requiring a new distribution version.

* Introduce a plugin architecture to externalize IDL-specific tools and their Java dependencies from the distribution.
* Enable the bal CLI to discover and run tools that are updated independently.
* Allow CLI tools, compiler plugins, and VSCode extensions associated with these tools to be maintained and released independently.
* Ensure backward compatibility and ease of migration for users.

## Non-Goals
* This proposal does not cover a redesign of the tool functionalities themselves; the focus is on packaging and distribution strategy.
* Introduce modifications that would disrupt existing functionality

## Design
The proposed design includes:
1. **CLI tool decoupling mechanism**
   Enhance the bal CLI to support a standardized mechanism for discovering and executing tools (e.g., bal-openapi, bal-grpc).

2. **Compiler plugin decoupling**
   Compiler plugins associated with each tool should be packaged within the plugin or separately installable, with clear documentation on compatibility with Ballerina versions.

3. **Language server extension decoupling**
   Move tool-specific support in the LS extension to optional extensions or update mechanisms that fetch required dependencies on demand.

### CLI tool decoupling mechanism

#### Implementation of the tool

**Current architecture**

Currently, these tools are implemented as JARs and shipped with the distribution in the `<BAL_HOME>/bre/lib` directory. Updating the tools requires a distribution release.

**Proposed  architecture**

With the proposed design, tool authors will write the tool and package it as a BALA and release it to Ballerina Central.
1. A tool must be created as a Ballerina package of type `tool` (must contain the BalTool.toml).
2. A tool package can contain:
   - A CLI command
   - A build tool (which can be automated into the package build process)
3. All necessary JAR files should be included within the package.
   For example,
   - The OpenAPI tool package will provide:
   - The `bal openapi` command
   - The openapi build tool (e.g client generation)
   - The following JARs will be required to be in the OpenAPI tool package
     - openapi-cli JAR
     - openapi-bal-task JAR
     - openapi-core JAR
     - ballerina-to-openapi util JAR

#### Release process

This design enforces tools to have independent releases without having to release the entire distribution. 

* A tool can be pushed to the Ballerina Central repository using the `bal pack` command followed by `bal push`.
* A tool package must be versioned according to the semantic versioning rules.
* During a distribution release, the latest compatible tool version will be packed into the distribution.
* As a best practice, the package name of the tool must have the prefix `tool_` (e.g. tool_openapi)
* A tool version is compatible with the distribution it is created with and also with newer distributions.

### Compiler plugin decoupling

1. Package-provided plugins
   * Shipped in a BALA
   * Executed on projects that import this package
   * Requires dependencies from the distribution
2. In-built plugins
   * Shipped with the distribution
   * Executed on every project
   * Requires dependencies from the distribution

This proposal focuses on isolating the package-provided compiler plugins from the distribution.

**Current architecture**

A package author publishes a compiler plugin in a BALA and publishes it to Ballerina Central.

When a compiler plugin is imported, it is executed with the following dependencies added to the classpath:
1. Dependencies declared in the `CompilerPlugin.toml`
2. `$BALLERINA_HOME"/bre/lib/` for compiler APIs and in-built IDL dependencies
If a dependency shipped with the BALA is also available in the distribution (`$BALLERINA_HOME"/bre/lib/`), the one in the distribution takes precedence. This can happen for IDL-specific dependencies. Therefore, the compiler plugins that have these kinds of dependencies require a distribution release. 

**Proposed architecture**

In the proposed architecture, if there is an overlapping dependency, the one provided by the BALA takes precedence. This will allow us to completely decouple the release of package-provided compiler plugins.

### Language server extensions decoupling

**Current architecture**

When VSCode is launched, all IDL tooling-related util JARs and other required platform dependencies are loaded to the system classpath from the distribution (`"$BALLERINA_HOME"/bre/lib/`).

**Proposed architecture**

All LS specific utilities will be packaged in the tool package. All LS functionalities will be facilitated through the tool CLI commands.

## Alternatives
* Continue packaging tools with the distribution and accept slower release cycles.
* Decouple only selected tools (e.g., CLI tools), but this leads to an inconsistent user experience and limited long-term value.

## Testing
* Test the compatibility of independently released tools with various versions of the distributions.
* Regression testing to ensure existing projects using current CLI tools work as expected during and after the migration.
* Integration testing with CLI, VSCode features, and CI/CD environments.

## Risks and Assumptions

### Risks
* Increased complexity in managing and maintaining separate release pipelines.
* Potential initial user confusion during transition due to changing installation and usage patterns.

### Assumptions
* Teams owning each tool will take responsibility for its lifecycle management.
* Adequate documentation and migration guides will suffice to ease adoption.

## Dependencies
* Changes to the bal CLI to support plugin discovery and execution.
* Updates to the build and release infrastructure to support decoupled packaging.
* Coordinate with the CLI tool, compiler-plugin, and VSCode extension maintainers for corresponding changes.

## Future Work
* Extend the plugin system to support third-party community-contributed tools.
