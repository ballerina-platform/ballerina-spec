# Ballerina packages
This is issue #[230](https://github.com/ballerina-platform/ballerina-spec/issues/230): please add comments there.
## Background
When you are learning Ballerina or building a simple program, you usually start with a single .bal file. But when your code grows, you want to structure your code properly. Otherwise, you’ll end up with a messy, unstructured codebase. Such codebases are hard to navigate and understand. 

The code should be written for people to read. The code organization plays a significant role in improving readability. If the people who maintain the code cannot easily navigate the source tree, then that creates many problems. 

*“Programs should be written for people to read, and only incidentally for machines to execute.” -  Abelson & Sussman.*

Today, the first step towards organizing your code is creating a Ballerina project. A project can have multiple Ballerina modules that share the same version and the organization name. The module is the unit of compilation and the unit of sharing in the current system. But as your codebase grows, you tend to face the limitations of the current system. Say you are developing a Ballerina library, and you want to modularize the implementation by breaking the library code into multiple modules. Some modules contain symbols that are part of your API, and some modules are internal, and you don’t want external consumers to use them. The current system does allow you to break your code into multiple modules, but that’s just it. When you want to share your library, you would have to push all such modules to the Ballerina central, even though some are internal modules. As a result, external consumers have access to those internal modules.  

The current project layout is understandable and straightforward. We should not lose this.

This proposal gives semantic meaning to the current project directory. At present, it is just a collection of modules and nothing more. 

# Goals

- Modularize the unit of sharing
- Should not lose the simplicity and understandability of the current system. Today, when you import a module in the source code, the build tool downloads the module from the Ballerina central if it exists. The build tool also manages the version of all imported modules according to the newest acceptable version rule. Users have the option of using a lock file to achieve reproducible builds. 
- Give semantic meaning to the current project directory 

# Ballerina package

A Ballerina package is a collection of related Ballerina modules that are versioned and shared as a single unit.

- All the modules in a package share the same prefix. It is called the package name. 
- The unique name of a package is `orgName/packageName/version`
- The package name can take the form: `identifier`
- A package can have a module with the same name as the package name. It is called the default module of the package. 

Since every module in a given package shares a common prefix (the package name), it would be easier to build tools to figure out the package name from an import declaration. Consider the following import declaration. 

```
import samjs/winery.storage.utils;
```

The module name is `winery.storage.utils`, and the package name is `winery`. 

## Split modules

The split modules condition occurs when a module is available in two or more different packages. This proposal prevents split modules by design. 

## Application packages and library packages

There are two kinds of packages. 

- Application package

- - Another name for an executable program
  - At the moment, we don’t allow pushing or pulling executable programs to or from central. We can evaluate this later. Out of the scope of this proposal. 
  - The default root module is the module with the same name as the package name (default module).
  - Compilation output: `.jar` file

- Library package

- - A library package should have at least one exported module 
  - Library packages can be uploaded to Ballerina central or can be pulled from the central to your local environment. 
  - A library package should have at least one exported module 
  - Compilation output: `.balo` file

# Package layout

The most common case is to have a single Ballerina package in a project. However, for large scale projects, you want to manage multiple packages in your project. The multi-package projects are out of the scope of this proposal. But they can be done as a backward-compatible extension to this proposal. I’ve mentioned a little bit about multi-package modules in the future work section. 

Here is the proposed directory structure for a Ballerina package. 

```
.
├── Ballerina.toml
├── Ballerina.lock
├── Package.md
├── Module.md
├── app.bal
├── utils.bal
├── tests/
│   ├── main_tests.bal
│   ├── utils_tests.bal
│   └── resources/
├── resources/
│   └── app.png
├── modules/
│   ├── model/
│   │  ├── item.bal
│   │  ├── Module.md
│   │  ├── tests/
│   │  │  ├── item_tests.bal
│   │  │  └── resources/
│   │  └── resources/
│   ├── storage/
│   ├── storage.utils/
│   └── utils/
├── integration-tests/
│   ├── integration_tests1.bal
│   ├── integration_tests2.bal
│   └── resources/
└── target/
```

## Ballerina.toml 

The Ballerina.toml file describes the package. 

```
[package]
org = "samjs"
name = ”winery”
version = "0.1.0" 
```

## Ballerina.lock

This proposal does not change anything related to the lock file. Refer the following link for more information. 

https://github.com/ballerina-platform/ballerina-spec/blob/master/project/project-spec.md#how-to-get-a-repeatable-build

## package.md and module.md

The `package.md` file provides a human-readable description of a package. This is the first page that you will see when you navigate to the package in Ballerina central. 

The `module.md` file provides a human-readable description of a module. When you visit a package in Ballerina central, you should see all the exported modules of that package. This is the first page you will see when you navigate an exported module of a package. 

## Module layout

Here is the proposed layout of a module.

```
.
├── app.bal
├── utils.bal
├── tests/
│  ├── main_tests.bal
│  ├── utils_tests.bal
│  └── resources/
│      └── test_res.json
└── resources/
    └── app.png

```

A module directory contains source files and other resources. There are two kinds of sources: sources and test sources. Similarly, there are two kinds of resources: resources and test resources. 

- The source files of a module can be placed at the root of the module directory. 
- The` tests` directory contains unit tests of the module, and they test the module in isolation. The module-level test cases have access to the symbols with module-level visibility.
- The .bal files in directories except the root directory of the module and tests directory are not considered as the sources: Ballerina compiler must ignore such .bal files. 
- The `resources` directory can be used to store all module resources such as images, default configs, etc. 

### The default module 

It is common in small projects to have only one module(default) in a package. Therefore this proposal optimizes the layout for that case. As a result, the default module’s content can be placed directly in the root of the package directory. 

The package name which is specified in the Ballerina.toml file is also the name of the default module. 

```
.
├── Ballerina.toml
├── Ballerina.lock
├── Package.md
├── Module.md
├── app.bal
├── utils.bal
├── tests/
│   ├── main_tests.bal
│   ├── utils_tests.bal
│   └── resources/
│      └── test_res.json
├── resources/
│   └── app.png
└── target/
```

The directories `tests`, `resources`, `modules` and `target` are considered reserved. Users are not allowed to use reserved directory names when creating directories inside the package. 

To maintain the consistency the default module and other modules should have the same layout.

### The modules directory

This proposal enables you to organize the source code of a package as multiple modules. The default module’s layout is described in the above section. This section describes the layout of other modules.

The top-level modules directory contains all the other modules. Each immediate sub-directory of the modules directory becomes a Ballerina module and the subdirectory name becomes the module name. Therefore the subdirectory name should be a valid Ballerina identifier. 

```
.
├── app.bal
├── utils.bal
└── modules/
    ├── model/
    ├── storage/
    ├── storage.utils/
    └── utils/

```

Say that the package name is `winery` and the following is the list of module names based on the above directory structure.

- `winery` (default module)
- `winery.model`
- `winery.storage`
- `winery.storage.utils`
- `winery.utils`

### Importing modules of the same package

The following is the structure of an import declaration in Ballerina

```
import-decl := import [org-name /] module-name [version sem-ver] [as import-prefix]
```

When importing a module in the same package, the module-name with or without the org-name should be used. 

- The module-name of the default module is the package name.
- The module-name of a module in modules directory is `package-name.directory-name`. 

**Case 1:** Importing the default module in another module. 

`import samjs/winery;`

The organization name is optional because all the modules are part of the same package.

`import winery;`

**Case 2:** Importing a module of the same package in the default module. The organization name is optional here as well.

`import winery.utils;`

## The integration-tests directory

The integration test sources and resources of a package go here. Integration tests can be considered external to the package, and such tests have access only to the public API of the package. 

Integration tests executed after an executable binary is generated in an application project or after a balo is created in a library project. 

# Managing dependencies of a package

A package can depend on one or more other packages. All such dependencies should be specified in the Ballerina.toml file. 

Suppose the developer imports a module of a package without updating the Ballerina.toml. In that case, ballerina build, ballerina run, ballerina test commands update the `Ballerina.toml` file during the execution. 

What about the removing dependencies listed in the Ballerina.toml file if those packages are not used anymore? The idea here is that we want the current Ballerina tool to keep the dependencies section of the Ballerina.toml file up to date with the source code. We can provide a separate command to update the dependencies section as well. 

# Exported modules

Ballerina packages enable modularizing the unit of sharing by organizing the source code into multiple modules. In addition to that, we need to provide a mechanism to control such modules' visibility outside of the package. 

Ballerina modules offer two visibility regions for module-level constructs:

- All modules - access is allowed for all the modules. i.e., access is not restricted by any means
- Current module - access is limited to the module in which the construct is declared/defined.

By default, all module members are visible only to the module in which they are defined. To make a module member visible to other modules, that member must be marked explicitly with the `public` keyword. 

We can apply the same principle to package members(modules of a package). 

- By default, a module of a package is visible only to the modules in the same package.
- A module must be marked as exported in the Ballerina.toml file to make it visible to other packages.

There are two ways to export a module from a package. 

1. Export a module to all the packages. 
2. Export a module to a known set of packages. This is useful, especially in multi-package projects. 

We can start with the #1 and add #2 when we implement multi-package projects. 

# Ballerina package related commands

We need to update the current project related commands to incorporate the package concept. Here is the list of affected commands. 

## Create a new Ballerina package 

This proposal introduces two ways to create a new package.

1. Initializes an existing directory as a package

`ballerina init `

1. Create a new directory and initialize it as a package.

`ballerina new`

### `ballerina init` command

The init command initializes the current directory as a Ballerina package by creating a new `Ballerina.toml` file. This directory must not have a Ballerina.toml file

`ballerina init [<package>] [-t <template-name>]`

#### package

This command attempts to infer the package name from the current directory name and the inferred name is written to the Ballerina.toml file. Give the package name with init command to stop inferring. 

#### -t | --template

A template can also be specified when creating the new package. If a template is not specified, this command initializes the default module with a 'main' function. 

There are three built-in templates named: `main`, `service`, and `lib`. The service template initializes the default module with a sample HTTP service and the lib template initializes the default module with a sample library.

Custom templates can be downloaded from Ballerina central. 

Example:

```
> mkdir winery
> cd winery
> ballerina init 
  Created a new Ballerina package with name ‘winery
> tree
.
├── Ballerina.toml
└── main.bal
```



### `ballerina new` command

The new command creates a new directory and initializes it as a package. 

`ballerina new <package> [-t <template-name>]`

## Add modules to the current package 

The add commands add a new module inside the modules directory. If the modules directory does not exist, this command should create one. 

Example

  \> ballerina add storage

## Push, pull and search commands

At the moment, these commands work on the module abstractions. We need to change them to work on packages. 

## List dependencies of the current package

We need to provide a command to list the dependencies of a package. 

# Runtime view of packages and modules

TODO

# Multi-package projects

This proposal mainly talks about single-package projects. But as your project grows, you may want to split your package into multiple packages and manage them together (e.g. versioning, dependencies, etc). We can support this requirement as a simple backward-compatible extension to this proposal in the future. 

```
my-project/
├── Ballerina-project.toml
├── package_1/
│  ├── Ballerina.toml
│  ├── Package.md
│  └── modules/
├── package_2/
│  ├── Ballerina.toml
│  ├── Package.md
│  └── modules/
├── package_3/
│  ├── Ballerina.toml
│  ├── Package.md
│  └── modules/
├── LICENSE
└── README.md
```

*Note that multi-module projects are out of the scope of this proposal.*
