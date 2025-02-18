# Custom bal tool to bundle services into a single deployment artifact
- Authors
  - Asma Jabir
- Reviewed by
    - Sameera Jayasoma, Shafreen Anfar, Hasitha Aravinda
- Created date
    - 2025-02-19
- Issue
    - [1331](https://github.com/ballerina-platform/ballerina-spec/issues/1331)
- State
    - Submitted

## Summary
Ballerina inherently supports microservices-style deployments, which are well-suited for microservice orchestration platforms like Kubernetes. However, many enterprise users deploy on VMs or Docker, where managing each service as a separate process increases complexity and resource overhead. This proposal aims to provide a solution tailored to such scenarios by enabling consolidated deployments. 

## Goals
* Allow multiple services to run as a single runtime process.
* Facilitate easy deployment in Docker-based and VM environments.
* Provide intuitive configuration through CLI options or a configuration file.

## Design
This proposal introduces a tool to generate code required to group multiple services into one deployable artifact.

The tool,
* Parses the `Ballerina.toml` file to identify the services to consolidate
* Generates the `generated/bundle.bal` file with the shared listener and the service packages imported.
* Generates the `generated/bundle_main.bal` file with a log statement to notify the initialization of the services
* Builds a single deployment artifact (e.g., `.jar` or the docker image) containing all the services.

### Create or update a bundle package 
This proposal suggests 2 options that facilitate users for creating/updating a bundle package.

#### Manual approach
   
By creating a package manually using the `bal new <package-name>`, users can add the bundle tool entry as shown in the below example and into the `Ballerina.toml` and add/remove services as needed by updating the values provided for the `options.services` array.

```toml
[package]
org = "myorg"
name = "bundle"
version = "0.1.0"

[[tool.bundle]]
id = "bundle1"
options.services = ["myorg/svc1", "myorg/svc2"]
```

#### Using the `bal bundle` command
Alternatively, users can install the tool to create and modify the bundle package as shown in the following examples.

```bash
$ bal tool install bundle
```

##### Creating a new bundle package**
```
$ bal bundle create --services myorg/svc1,myorg/svc2 [--name <package-name>]
```
If the name is not provided, the default name for the package is "**bundle**". This creates a new directory and a Ballerina.toml file with the tool entry added similar to the example `Ballerina.toml` file shown in the manual approach.

E.g:

```bash
$ tree bundle
bundle
└── Ballerina.toml
```

##### Adding new services to an existing bundle
```
$ bal bundle add --services myorg/svc3,myorg/svc4
```

##### Removing services from an existing bundle
```
$ bal bundle remove --services myorg/svc2,myorg/svc3
```
### Artifact generation

With the design introduced in this proposal, the `bal build` command supports generating the single deployment artifact OOTB 
as shown below.

```bash
bal build [--cloud]
```
