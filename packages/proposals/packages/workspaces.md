# 1379: Multi-Package Workspace Support in Ballerina

- Authors - Asma Jabir  
- Reviewed by - TBD  
- Created date - 2025-08-13  
- Updated date - 2025-08-13  
- Issue - [ballerina-platform/ballerina-spec#1379](https://github.com/ballerina-platform/ballerina-spec/issues/1379)  
- State - Submitted 

## Summary

This proposal introduces native support for managing multiple Ballerina packages in a single workspace. This feature enables developers to organize and build interdependent packages together in a monorepo-style structure.

## Motivation

Ballerina currently only supports a single package per project. This becomes limiting for projects that are developed in monorepo-style when managing dependencies that exist in the local filesystem. 

Without workspace support, developers must either rely on a package repository (remote or local) for dependency management, which reduces development efficiency. Most other ecosystems already support this.

## Goals

- Allow developers to define a workspace containing multiple Ballerina packages  
- Support dependency resolution between workspace packages  
- Enhance package commands such as `new`, `build`, `test` for Ballerina workspaces
- Introduce a minimal configuration file for defining the workspace structure  

## Non-Goals

- It does not introduce any backward-incompatible changes to existing package structure and configurations

## Design

### Directory Layout

```bash
my-workspace/
│
├── Ballerina.toml # Defines the workspace
├── service-a/
│     └── Ballerina.toml
│     └── modules/
├── service-b/
│     └── Ballerina.toml
│     └── modules/
└── util
      └── lib-common/
              └── Ballerina.toml
              └── modules/
```
### Workspace Ballerina.toml

```toml
[workspace]
packages = ["service-a", "service-b", "util/lib-common"]

[[repository.maven]]
id = "git_1" 
url = "https://maven.pkg.github.com/xxx/xxx"
username = "xxx"
accesstoken = "xxx"

[build-options]
observability-included = true
sticky = true
```

The packages array defines relative paths to the workspace packages.

### Dependency Resolution Algorithm
* The workspace has higher precedence over the Ballerina Central repository.
* By default, package imports are resolved using the org name and package name within the workspace.
* Version constraints are considered only if a minimum version is specified in the package's Ballerina.toml.
* If a version is specified:
    * The default locking mode is SOFT
    * Users can override it with MEDIUM/HARD/LOCKED
* If a matching package is found in the workspace, the resolution request is not sent to Ballerina Central.
* If a package is available in both the workspace repository and the Ballerina central, the user can force the resolution engine to get it from the Ballerina central by setting the `skipWorkspace` flag of the dependency to `true`.
  ```toml
  [[dependency]]
  org = "myorg"
  name = "foo"
  version = "0.1.0"
  skipWorkspace = true
  ```

### Tooling support

#### CLI

The following commands will be extended to work in a workspace context:
* `bal new --workspace` → creates a new workspace 
    * Creates the BalWorkspace.toml in the provided path
    * Creates a Ballerina project in the workspace directory
* `bal build` → builds all packages in the workspace
    * Generates executables for every package that is not a dependency of another package in the workspace
* `bal test`, `bal pack`, `bal clean`, `bal format`, `bal graph`, also should support similar workspace-aware functionality
* `bal run` requires the specific package in the workspace to run

#### Java APIs

Introduce APIs to facilitate workspace features such as cross-package navigation and auto-complete, and fetching diagnostics
* Introduce a new project kind for workspaces       
* Introduce a dependency resolution API in for workspaces
* Improve the project loading utils to support loading workspaces

## Alternatives

* **Tooling-only workaround**

  IDEs or custom scripts could simulate workspace behavior, but this increases complexity and lacks official support in CLI tools.

* **External build orchestrators**

  Using external tools like Make to coordinate Ballerina builds is non-native and leads to inconsistencies

## Testing
* Integration tests to verify the correct resolution and execution of workspace packages
* CLI command test coverage with and without workspace context
* Regression tests to ensure existing single-package project behavior remains unchanged

## Risks and Assumptions
* Assumes that packages listed in the workspace are well-formed and follow the Ballerina package structure
* Changes in one package might unintentionally affect others in the workspace; proper caching and rebuild strategies are necessary
* The language server need updates to fully support workspace awareness, which may lag behind CLI support

## Dependencies
* No other BEPs currently block this proposal.

## Future Work
* Support grouping and excluding packages in the same workspace.
* Support workspace-level scripts (e.g., pre-build, post-build)
