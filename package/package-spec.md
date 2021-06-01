# Ballerina Package Specification

## 1. Introduction

Ballerina is an open-source programming language for the cloud that makes it easier to use, combine, and create network services. For a detailed reference guide on Ballerina, see “Ballerina Langauge Specification”.  

Ballerina programs are built by linking together Ballerina modules, which are namespaces that isolates function definitions, type definitions, constants, variables from other namespaces to achieve encapsulation, modularity, and code reuse. For more details on modules, see section: 3. Program Structure in the language specification.

This document describes a packaging system for Ballerina modules. 

## 2. Notation
Each text file described in this specification is a UTF-8 encoded file.

This specification uses the <code>[identifier](https://ballerina.io/spec/lang/master/#identifier)</code> format as defined in the Ballerina language specification. 

## 3. Packages

A Ballerina package provides a mechanism that allows one or modules to be combined, versioned, and distributed as a single entity.

Packages have both a source and a distribution format. The source format stores the source form of a package's modules in a hierarchical filesystem. The distribution format stores the distribution form of a package's module as a `.zip` file.

### 3.1 Package Repositories

The distribution form of packages can be stored in a package repository. [Ballerina Central](https://central.ballerina.io/) is one such package repository. Within a repository, A package is identified by an organization, package name, and version.

### 3.2 Organizations

An organization is a way of grouping packages that belong to a single person, team, or organization.

```
org-name := identifier
```
The language specification defines allowed characters in an identifier.

### 3.3 Package names

Package names can be hierarchical as defined below:

```
package-name := identifier(.identifier)*
```

### 3.4 Versions

Package versions are semantic, as described in the [SemVer](https://semver.org/) specification. A version can be a release or a [pre-release](https://semver.org/#spec-item-9) version. A release version is called an unstable version if the major version number is zero; otherwise, it is called a stable version. A pre-release version is always an unstable version.

```
version := valid-semver
```

### 3.5 Module names

The module name of every module in a single package contains the package name as a prefix.

```
module-name := package-name [/ sub-module-name]
sub-module-name := identifier(.identifier)*
```

### 3.6. The default module

A package is a collection of modules, and one module in this collection is identified as the default module of a package. The default module name is the same as the package name. 

```
default-module-name := package-name
```

## 4. Source format

This section defines the layout of files and directories of the source format of a package.  

### 4.1 Source code file extension

Ballerina Language specification defines that the source form of a module consists of an ordered collection of one or more source parts; each source part is a sequence of bytes that is the UTF-8 encoding of part of the source code for the module.

This specification defines that each source part of a module should be stored in a file with the `.bal` extension.

### 4.2 Module directory layout 

The layout of a module directory must look like this:

<table>
  <tr>
   <td>Entry
   </td>
   <td>Description
   </td>
   <td>Is optional?
   </td>
  </tr>
  <tr>
   <td><code>/</code>
   </td>
   <td>The root of the module directory. It must include one or more source files (<code>.bal</code>). it is an error if this directory does not contain at least one <code>.bal</code> file.
   </td>
   <td>No
   </td>
  </tr>
  <tr>
   <td><code>/test</code>
   </td>
   <td>Includes zero or more .bal files that contain code to test the module in isolation. The module-level test cases have access to the symbols with module-level visibility.
   </td>
   <td>Yes
   </td>
  </tr>
  <tr>
   <td><code>/test/resources</code>
   </td>
   <td>Includes test resource files.
   </td>
   <td>Yes
   </td>
  </tr>
  <tr>
   <td><code>/resources</code>
   </td>
   <td>Includes resource files.
   </td>
   <td>Yes
   </td>
  </tr>
</table>

The .bal files in directories except for the module’s root directory and tests directory are not considered source files. The implementation of this specification must ignore such .bal files or any other files or sub-directories in a module directory.

### 4.3 Package directory layout

The layout of a package directory must look like this:

<table>
  <tr>
   <td><code>Entry</code>
   </td>
   <td>Description
   </td>
   <td>Is optional?
   </td>
  </tr>
  <tr>
   <td><code>/</code>
   </td>
   <td>The root of the package directory and contains the contents of the default module. This directory must include one or more source files (<code>.bal</code>) that belong to the default module of the package. it is an error if this directory does not contain at least one <code>.bal</code> file.
   </td>
   <td>No
   </td>
  </tr>
  <tr>
   <td><code>/Ballerina.toml</code>
   </td>
   <td>Identifies a directory as a Ballerina package.
   </td>
   <td>No
   </td>
  </tr>
  <tr>
   <td><code>/Dependencies.toml</code>
   </td>
   <td>Includes the dependencies of this package.
   </td>
   <td>Yes
   </td>
  </tr>
  <tr>
   <td><code>/modules</code>
   </td>
   <td>Include other modules of this package. A top-level sub-directory in the <code>/modules</code> directory is a module if it follows the module directory layout rules.
   </td>
   <td>Yes
   </td>
  </tr>
  <tr>
   <td><code>/tests</code>
   </td>
   <td>The <code>/tests</code> directory of the default module
   </td>
   <td>Yes
   </td>
  </tr>
  <tr>
   <td><code>/test/resources</code>
   </td>
   <td>The <code>/test/resources</code> directory of the default module
   </td>
   <td>Yes
   </td>
  </tr>
  <tr>
   <td><code>/resources</code>
   </td>
   <td>The <code>/resources</code> directory of the default module
   </td>
   <td>Yes
   </td>
  </tr>
  <tr>
   <td><code>/Package.md</code>
   </td>
   <td>Describes the packages. 
   </td>
   <td>Yes
   </td>
  </tr>
</table>

The implementation of this specification must ignore other files or sub-directories in a package directory.

### 4.4 Ballerina.toml file

The `Ballerina.toml` file identifies a directory as a package. It also acts as a manifest that contains metadata of a package. The content follows the [TOML specification](https://toml.io/en/v1.0.0). Every `Ballerina.toml` file must contain the following sections:

*   `[package]` - Defines the package
*   `[build-options]` - Options that are applicable when building the package
*   `[platform] `- Platform-specific details

An empty `Ballerina.toml `is a valid file. The default values are used if any of the key/value pairs are missing.

#### 4.4.1 The` [package]` section

This is an optional section. 

#### 4.4.2 The` [build-options]` section

#### 4.4.2 The` [platform]` section

### 4.5 Dependencies.toml file

The `Dependencies.toml` file is an optional file that follows the [TOML specification](https://toml.io/en/v1.0.0).  It contains one or more `[[dependency]]` entries. Each entry specifies a direct package dependency of the package in which this file exists.

The `Dependencies.toml` is automatically generated/updated by the package build tool to keep it up to date with the changes package dependency graph. This file must contain all the directory dependencies of the current package. Any extra information should be removed by the package build tool.

Every `Dependencies.toml` file MUST consist of the following format:

*   `[[dependency]]` - Describes a dependency
    *   `org` - Organization name of the dependency
    *   `name` - Package name of the dependency
    *   `version` - Dependency version
    *   `repository` - Optional Repository name 
