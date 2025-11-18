# 1340: Git-Based Indexing Mechanism for Ballerina Package Resolution

- **Authors** - Asma Jabir, Dilhasha Nazeer, Gayal Dassanayake
- **Reviewed by** - TBD 
- **Created date** - 11 March, 2025
- **Updated date** - 11 March, 2025
- **Issue** - [1340](https://github.com/ballerina-platform/ballerina-spec/issues/1340)
- **State** - Proposed

## Summary
This proposal introduces a Git-based indexing mechanism to improve the Ballerina package resolution process by reducing dependency on Ballerina Central. The proposed approach allows for package resolution using an indexed repository stored in a Git-based structure, enabling support for private repositories and improving compilation efficiency.

## Motivation
The current package resolution process heavily depends on Ballerina Central, which maintains all package metadata and performs compatibility checks during compilation. However, this approach poses challenges for users in restricted corporate environments who need to maintain packages in custom repositories. 

### Problems Addressed:
- **Restricted corporate environments**: Users need the ability to resolve packages from private, in-house repositories without depending on Ballerina Central.
- **Performance improvements**: Reducing the number of resolution requests to Ballerina Central can improve compilation time.
- **Scalability & flexibility**: Enabling Git-based indexing provides a decentralized way to store package metadata, making resolution more efficient.

## Goals
- Implement an indexing mechanism that enables package resolution without depending on Ballerina Central.
- Support package resolution from private repositories hosted in-house.
- Improve compilation time by reducing resolution requests to Ballerina Central.
- Ensure backward compatibility in package resolution logic while introducing a new index-based approach for metadata retrieval.

## Non-Goals
- This proposal does not eliminate the use of Ballerina Central but enhances its capabilities with a Git-based index.
- The existing `bal push` mechanism will be extended to update the Git-based index.
- This proposal ensures compatibility with previous distributions and does not introduce modifications that would disrupt existing functionality.

## Design
This proposal introduces a Git-based indexing mechanism that organizes package metadata in a structured Git repository. Instead of relying solely on Ballerina Central for metadata retrieval, package resolution will be performed using an indexed repository stored in a Git-based structure.

A local package index is maintained on the user's machine, ensuring fast lookups and offline package resolution. This local index is synchronized with a remote Git index, ensuring that package metadata remains up to date.

### **Index for Packages in Ballerina Central**
A public Git repository under the `ballerina-platform` organization will serve as the central index for packages published to Ballerina Central. The index will be exclusively maintained for public packages.

### **Index for Custom Repositories**
Users who rely on custom repositories will have the ability to create a separate Git repository for their package metadata. This index can then be specified in the `<USER_HOME>/.ballerina/Settings.toml` file with repository configurations.

#### Example Configuration:
```toml
[[repository.maven]]
id = "<repository-id>" # This ID is used when pushing/pulling packages
url = "<repository-url>"
username = "<username>/<userId>"
accesstoken = "<password>/<accesstoken>"
index = "https://github.com/azinneera/index/blob/bal/"
indexUsername = "<index-username>"
indexAccessToken = "<index-accesstoken>"
```

With this improvement, custom repositories can support version discovery and automated resolution, similar to Ballerina Central.

### **Maintaining Backward Compatibility**
To maintain backward compatibility, the newly introduced index-related configurations will be optional. If the index is not provided, the exact version will be resolved from the custom repository.

### **Git Repository Layout**
```
<root>/<org>/<name>/index.jsonl
```
Example:
```
ballerina
├── auth
│   └── index.jsonl
├── avro
│   └── index.jsonl
├── cache
│   └── index.jsonl
├── cloud
│   └── index.jsonl
```

### **Package Index File - Index.jsonl**
Each `index.jsonl` file follows the JSON Lines format, where each line represents one version of a package.

#### Example Package Entry:
```json
{
    "org": "ballerina",
    "name": "auth",
    "version": "2.8.0",
    "platform": "java11",
    "ballerina_version": "2201.5.0",
    "is_deprecated": false,
    "deprecation_message": "",
    "modules": [
        { "name": "auth" }
    ],
    "dependencies": [
        { "org": "ballerina", "name": "crypto", "version": "2.3.1" },
        { "org": "ballerina", "name": "log", "version": "2.7.1" }
    ]
}
```

### **Updating the Git Index**
The Git-based package index is automatically updated when a package is published using the `bal push` command.

#### **Updating the Index for Ballerina Central**
- When a package is pushed to Ballerina Central, the index update is handled server-side.

#### **Updating the Index for Custom Repositories**
- For custom repositories, the update process is handled by the Ballerina CLI, using the `indexUsername` and `indexAccessToken` provided in `Settings.toml`.

### **Local Cache for Optimized Package Resolution**
A local cache of the index will be maintained in `<USER_HOME/.ballerina>` to enable efficient and offline package resolution. 

### **Dependency Graph and Resolution Process**
The package resolution process involves fetching the index, constructing a dependency graph, and resolving dependencies efficiently. The dependency graph ensures that:
- All required dependencies are included
- Version conflicts are handled dynamically
- Cyclic dependencies are detected and reported

## Alternatives

### **Sparse-Based Index**
A sparse-based index was considered but not chosen due to the following reasons:
- Implementing custom repositories with the sparse approach requires an HTTP service to expose the index, adding significant complexity compared to the Git approach.
- The Git approach can be problematic when the number of packages reach ~100,000. However, Ballerina currently has fewer than 1,750 packages, making performance concerns negligible in the foreseeable future.
- To gain the full performance benefits of a sparse index, additional improvements such as parallel requests, server support for pipelining, and HTTP/2 are required.

## Testing
- **Unit tests**: To verify index retrieval, dependency resolution, and backward compatibility.
- **Integration tests**: Validate interactions with Ballerina Central and custom repositories.
- **Performance benchmarks**: Measure the impact on compilation times.

## Risks and Assumptions
### Risks
- Users may find it challenging to set up their own Git-based index, particularly those unfamiliar with Git repository management.
- As the number of packages grows, the performance of the Git-based indexing approach needs to be continuously evaluated to prevent slowdowns.

### Assumptions
- Most organizations are familiar with setting up and maintaining a Git repository, reducing the onboarding effort for custom repositories.
- The number of Ballerina packages is expected to grow gradually, allowing optimizations to be introduced over time as needed.

## Dependencies
- Relies on Git repositories for indexing.
- Requires modifications to the Ballerina CLI to support the index mechanism.

## Future Work
- Decouple the indexing of private packages from the Ballerina Central.
