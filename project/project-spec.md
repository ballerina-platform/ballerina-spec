# Ballerina Project Specification

A Ballerina project helps you to manage a complex ballerina program in a modular way. This specification will define how to structure and configure a Ballerina project. Also the specification will define the functionality of the CLI tools ships with ballerina distribution.


[TOC]



# Single source files {#single-source-files}

You can write a ballerina program in a single source file and it needs to have the following two requirements to be a ballerina program.



1. It should end with the `.bal` extension.
2. And it should have an entry point. In Ballerina an entry point is either a main method or a service (that is attached to a listener).

If the source file doesn't have an entry point it is pretty much useless. Also, a single source file is contained to the specific file so the symbols defined in the file will not be visible to other ballerina files.

You can run a single source file using the `ballerina run` command.
```
$ ballerina run single_source.bal
```
To build a single source program use the `ballerina build` command.
```
$ ballerina build single_source.bal
```
When you build the program it will create an executable file in the current directory.

If a ballerina file is part of a ballerina module it is not considered as a single source file and you will not be able to run or build it directly.


# Ballerina Module {#ballerina-module}

When you write large programs often you would want to organize your code into shareable units. In Ballerina, you can divide your program into such units which are called Ballerina modules. 

A Ballerina module is a collection of source parts (ie. functions, objects, services, etc..) which can be compiled to a binary representation and shared through a Ballerina module repository ( like Ballerina central ). A module stored in a repository can then be imported and used as a library to build other programs. 

A Ballerina module is a directory containing Ballerina files that reside in a Ballerina project. You need to create a Ballerina project in order to create a Ballerina module. 


# Ballerina Project {#ballerina-project}

A Ballerina project allows you to define and manage one or many Ballerina modules. If you want to create a library (sharable Ballerina module) or a complex program you should start by creating a Ballerina project. 

To create a Ballerina project you can use the ballerina new command.
```
$ ballerina new &lt;project-name>
```
You need to pass the project directory name as the first argument, the new command will create a project directory with the given name. 

Ballerina project cannot reside in another ballerina project. If you run ballerina new inside a ballerina project directory or in a subpath of a ballerina project it will give an error.


## Creating a module in a project {#creating-a-module-in-a-project}

Once you initialize a project to create a module simply create a directory inside the source ( src ) directory. The name of the directory should be the name of the module. Inside the module directory you can create ballerina files which belong to the module. 


```
project-root/src$ mkdir <moduleName>
project-root/src$ cd <moduleName>
project-root/src/moduleName$ touch order_service.bal
```


Ballerina also allows you to create modules with a predefined set of templates which will help you to scaffold your project quickly. 


## Create modules from predefined templates {#create-modules-from-predefined-templates}

You can use a ballerina add tool to quickly create a purposeful module. Let's look at an example command. 


```
project-root$ ballerina add [-t | --template <tname>] <modulename>
```


The above command will create a new module with a main in it. It will also create a module structure including test files.

By default the scaffold tool will generate a module with a main function. If you want you can use a different template to create a module. You can use the `-t `,` --template `option to pass in the module template you want to use. 


```
project-root$ ballerina add moduleName -t service
```


The above command will add a new module with an HTTP service.


## Ballerina Project Structure {#ballerina-project-structure}

Let's check out what the new command generated for us.


```
project-name/
- Ballerina.toml
- src/
-- mymodule/
--- Module.md      <- module level documentation
--- main.bal       <- Contains default main method.
--- resources/     <- resources for the module (available at runtime)
--- tests/         <- tests for this module (e.g. unit tests)
---- testmain.bal  <- test file for main
---- resources/    <- resources for these tests
- tests/
-- *.bal           <- integration test code
-- resources/      <- integration test resources
- .gitignore       <- git ignore file
```


**Ballerina.toml**

At the top of the list, you have the “Ballerina.toml” manifest file. This file is used by the compiler to identify a ballerina project directory. Please note that the `B` is capital in the Ballerina.toml file.

**Source Directory - src/**

The init command will also create a src directory where you can keep ballerina modules belonging to the project. 

We recommend not to keep any files or directories which are not ballerina modules inside the src directory.

**Module Directory - mymodule**

Ballerina module is a directory inside a ballerina project’s src directory containing ballerina files. The name of the module is the name of the directory which you can rename if you need to change the module name. To create another module simply create a new directory in the src directory and add one or more ballerina files.

The name of the module should be a valid identifier as defined in Ballerina language [[1]](https://htmlpreview.github.io/?https://raw.githubusercontent.com/ballerina-platform/ballerina-spec/v2019R1/lang/spec.html#lexical_structure) spec. If a module name is not a valid identifier the compiler will give an error. 

**Module.md**

Inside the module directory, you have the Module.md file which acts as a Readme file for the module. This will be used as the index page of a module’s API documentation by the ballerina documentation generator. Also, this will be the first page that users will see when they view the module in ballerina central. 

**Ballerina Files - main.bal**

The main.bal is the file that you would write your code. If you want you can rename the main.bal file as you wish. Also, you can split up the ballerina code into multiple files inside the module directory. Furthermore, you can have an arbitrary directory structure inside the module directory to organize the ballerina files. 

When the module is compiled all the ballerina files inside the module directory will belong to the same scope. Hence you cannot define symbols with the same name in two different files within the same module ( ie. you cannot have two functions with the same name in separate files in the same module ).

Then there are two reserved directories within a module namely resources and test. Hereby reserved means you cannot place bal files related to the module inside them. 

**Module Resources - resources**

Resources directory is there to keep any files that you would want to ship with the compiled module. All the files in here will get packed with the module when you compile it. And in the runtime, you can access these files via an API. 

**Module Tests - tests**

Test directory inside the module is used to keep your module test files. The create command will generate test-main.bal file to test the main function generated by the create command. You can have a look at it to get an idea on how to write ballerina tests. You can have any number of ballerina files in tests directory and there are no filename conventions here. Test directory again has a resources directory where you can keep resource files used for testing. 

**Target Directory**

The target directory will be the place where all the files get generated during compile. This directory will be automatically created by the compiler if it is not there. Also as a practice, we ignore it from version control. As mentioned above, target is a reserved directory and cannot be used as a module.

**Integration Test**

The project root will have a test directory which houses any integration tests of the project. All the modules in the project will be visible to the tests under this directory. 

**Git Ignore**

The init command will create a .gitignore file with default ignore paths. By default the content of the .gitignore file will be as follows. 


```
target
```


**Additional files** 

Apart from above, a project root directory can contain any other files. For example, if the project root is considered as the git root you can keep files such as Readme.md and other git related config files. 


## Compiling a Ballerina Module {#compiling-a-ballerina-module}

A ballerina module can be compiled into a library. When you compile a module into a library you can share it with other programs via a ballerina repository. To compile a module you can use the ballerina compile command. 


```
project-dir$ ballerina compile <module_name>
```


Here the ballerina compile command should be issued from the ballerina project directory. If you want to compile all the modules in a ballerina project omit the module name 


```
project-dir$ ballerina compile
```


When you compile all the modules ballerina compile command will figure out the build sequence automatically. If there are cyclic dependencies it will give an error and quit. 

If the module is intended to be used by other programs it should have at least one public construct (functions, objects, records, constants, etc). It may or may not have an entry point. 

You can also compile modules which have entry points but on public constructs. You will not be able to import and use these libraries in other programs but you can build them into binary programs. We will cover this later in the spec. 

Once you run the compile command if the module source file didn’t have any compile-time errors it will generate a “balo” file inside the target directory in the project. If you compile all the modules in the project it will generate balo files for all of them in the target directory. 

If you open the target directory after running compile you would typically find the following set of files and directories. 


```
project-name/
- Ballerina.toml
- src/
-- module1/
-- module2/
- target/         <- directory for compile/build output
-- bin/           <- Executables will be created here
-- balo/          <- .balo files one per built module
--- module1.balo  <- balo object of module1
--- module2.balo  <- balo object of module2
-- apidocs/
--- module1/      <- directory containing the HTML files for API docs 
                     of module1
--- module2/
-- kubernetes/    <- output of kubernetes compiler extension if used
-- potato/        <- output of potato compiler extension
-- cache          <- BIR cache directory
```


You can use -o | --offline flag to compile the modules offline. This will search balo’s from the local cache instead of fetching from central. If the dependency is not found it will result in an error specifying the missing dependencies. 


## Publishing a Ballerina Module {#publishing-a-ballerina-module}

A compiled module can be shared via Ballerina Central. Ballerina Central is a module registry where you can publish your ballerina modules. These published modules can then be imported and used in other ballerina programs. 

Before you can publish to Ballerina Central you first need to register an organization name in central. All the modules that you publish will be listed under a particular organization. Please refer to the Ballerina Central spec on how to create and configure organizations. 

To publish a module first open up the Ballerina.toml in your project directory and specify the following.


```toml
orgName= "wso2"
Version= "1.2.3"
license= "Apache-2.0"
authors= ["WSO2"]
keywords= ["ballerina", "Twitter", "endpoint", "connector"]
repository= "https://github.com/wso2-ballerina/module-twitter"
```


Here the organization name and version are mandatory to publish a module. You can specify the rest of the attributes as you wish but we encourage you to provide them as much as possible so that users will be able to easily find and understand about the module.

The name of the organization should be a valid identifier as defined in Ballerina language [[1]](https://htmlpreview.github.io/?https://raw.githubusercontent.com/ballerina-platform/ballerina-spec/v2019R1/lang/spec.html#lexical_structure) spec. If an organization name is not a valid identifier the compiler will give an error. 

The version number provided should conform to semver spec [[2]](https://semver.org/spec/v2.0.0.html). If it is not semver the push command will fail.

Once you provide the above details use the ballerina push command to publish the module into central. 


```
project-dir$ ballerina push <module_name>
```


Here you can omit the module name to publish all the modules inside the project. If multiple modules are pushed with the single command the push of multiple modules will be atomic, if one fails to push all the modules will not be published. 

If the modules are not compiled already and no balo files are found in the target directory the push command will output an error “Module(s) not found, please run ballerina compile before pushing.”. 

If you have compiled the modules and the source has changed after the compile, if you issue a push command it will give an error mentioning “Source has changed since the last compile. Please rebuild and push or use --skip-source-check to push anyway”. And users can ignore the warning and push by using --skip-source-check flag. 


## Importing a Module {#importing-a-module}

A library module can be imported in other ballerina programs. When you import a module all the public constructs will become available in the current program scope.


### Importing a module from central {#importing-a-module-from-central}

To import a module from central you can use the import statement followed by organization name and the module name like below.


```ballerina
import wos2/twitter;
```


Once you import you can refer to the public constructs of the module using the module name followed with a colon. ie. twitter:SomeName

If two modules have the same name but different organizations you can assign an alias to one module so that the module would not conflict.


```ballerina
import wso2/twitter as <alias>;
import wso2/twitter as tw;
```


Then you can refer to a declaration in a module with the alias. Ie  tw:SomeName.

In the import command if you haven’t specified a version ballerina will download the latest version of the module from the central. If you need to import a specific version you can specify it in the import command as follows.


```ballerina
import wso2/twitter version 2.3.0;
```



### Importing modules in the project directory. {#importing-modules-in-the-project-directory}

If you want to import a module which is in the same project you do not need to specify the org name. But even if you specify the organization name in Ballerina.toml it will work. 

Let's say we have two modules named foo and bar in the project inside the foo module you can import module bar as follows. 

import bar;

Specifying a version for modules in the same project will result in an error since all the time it will use the latest compiled version of the specific module.


## Running & Building a ballerina module. {#running-&-building-a-ballerina-module}

If a ballerina module has an entry point we consider it as a ballerina program which you can either run directly or build into a binary program. 

To build a binary executable from the module use the build command. Make sure you run the build command from the ballerina project directory.


```
project-dir$ ballerina build
```


The above command will build all the modules in the project directory which has an entry point and create executables in the target directory. The generated executables will be placed in the “target/bin” directory. If you want to build a specific module pass the module name to build command as follows. 


```
project-dir$ ballerina build <module_name>
```


If you want to build a program from a module in a repository use the build command with the module’s organization name followed with the module name. Here you can issue the build command in any directory and the executable will be created in the current directory.

To run the module directly use the ballerina run command followed with the module name. Make sure you run the command from the ballerina project root. 


```
project-dir$ ballerina run [<module_name>]
```


The above command will first build the given module and then execute the generated executable. If the project only has one module with an entry point you omit the module name. 


## Dependency management. {#dependency-management}

When you have a lot of dependencies in a program it becomes challenging to manage them and keep them up to date. Ballerina comes with a set of features that will help you to manage dependencies easily.


### Imports without versions {#imports-without-versions}

If a ballerina program imports other modules and does not specify a version, the Ballerina compile or build command will always download the latest version of the specific module. Here the latest version can be a major minor or patch version of the module.


### Versioned Imports {#versioned-imports}

If you import a specific version of a module ballerina will fetch the corresponding versions from the repository to build or compile. 

If you build a library module with specific version dependencies the version information will be preserved in the balo. When you import this module and use it in another program and compile the specific versions of the transitive dependencies will be fetched.


### Managing dependency versions in a Ballerina Project {#managing-dependency-versions-in-a-ballerina-project}

If you are working with a ballerina project with multiple modules often you would want to manage the dependency versions at a single place instead of specifying the versions inside each module. Ballerina supports the above by allowing you to specify the dependency versions in the Ballerina.toml file. 

In the Ballerina.toml file you can specify the import module versions as follows. 


```
[dependencies]
"wso2/twitter"= "2.3.4"
"wso2/github"= "0.9.21"
```


In Ballerina.toml `dependencies` will be a map of dependent modules.  Here the key will be the module name with the organization and the value will be a version range.


### Path Dependency.  {#path-dependency}

Often you would want to depend on a module of another project which you haven’t pushed to the central. The above can be achieved using a path dependency. Following is an example of a path dependency. 


```
[dependencies]
"wso2/twitter"= { path = "/path/to/twitter.balo" }
"wso2/github"= "0.9.21"
```


Here instead of the module version, you need to provide the path to the balo file of the dependent module. 

When there is a path dependency the compiler will pick the balo from the provided path. If the balo is not found the compiler will give an error.

It is not possible to push a module to central when there are dependencies resolved by path. To push a module to central the dependencies need to have a version. This enforces dependent modules to be pushed to central.

Version is ignored when the path is given to the balo.


### How to get a repeatable build  {#how-to-get-a-repeatable-build}

As mentioned above ballerina will download the latest versions of dependencies before the build. But sometimes your program might break with the new version of a dependency ( ie. due to API changes ). This will lead to some complications like the build might pass locally in your machine but fails in CICD due to a new library version. 

As a solution to the above problem ballerina allows you to lock all dependencies ( immediate and transitive ) to specific versions. Use the --lock option in compile or build command to lock the dependencies.


```
project-dir$ ballerina build --lock
```


When you run the build/compile with the ``--lock`` option it will create a `ballerina.lock` file in the project directory. Ballerina.lock file will contain all the versions of the dependencies used for the build. Hereafter if the ballerina.lock file exists the ballerina build/compile command will use the versions in the ballerina.lock instead of fetching the latest versions of the dependencies. 

You can commit the `ballerina.lock` file into your version control system so that other team members or CICD systems can recreate the same build. 

If the `ballerina.lock` is already present when you issue the ``--lock`` option it will use the existing `ballerina.lock` file instead of overwriting with a new one. 

If you want to update the dependencies in a lock file simply delete the `ballerina.lock` file and rerun the build/compile command with `--lock` option.

If you have a lock file and you change the versions in the Ballerina.toml or in Ballerina source, compile or build command will update the lock file automatically. 


## Running Tests {#running-tests}

If you have written tests in a module the tests will be run by default when you compile/build a module. If you want to skip running tests you can use the `--skip-test` flag. Here the compiler will first compile the module and run the test against the compiled artifact. 

If you build or compile the full project ballerina will run integration tests defined in the project test directory after compiling the modules. Use  `--skip-test `flag to skip running integration tests.

If you are writing a single source bal file you can define the test in the same file. 


# Caches {#caches}

Ballerina will maintain several caches to speed up the compile and build process. Following artifacts will be cached by Ballerina.

*   BALO files fetched from central.
*   BIR files generated during the compile.

Here the balo cache will be common across any version of ballerina and BIR and JAR cache will be ballerina version specific.  


### Balo cache {#balo-cache}

Balo cache is responsible for keeping BALOs of dependent modules. And in ballerina BALOs will be cached in two main locations.


1. There will be a BALO cache inside the ballerina distribution. It will contain the BALOs of libraries that will get packed into the distribution. All the standard library BALOs will be in here. This is populated during the time of the distribution build and will not get changed.
2. The second cache will be in the user's home directory. This will be used to cache BALOs fetched from central. The directory structure will be as follows. 

        ```
        ~/.ballerina/
        - balo-cache/
        -- org1/
        --- foo-2019r4-any-1.0.0.balo
        --- foo-2019r4-any-1.1.0.balo
        --- bar-2019r4-any-0.9.0.balo
        -- org2/
        ```


### BIR Cache {#bir-cache}



*   BIR files of the standard library that get packed into a distribution will be generated during the distribution build time.  
*   The BIR files of the other dependencies will be kept inside the target directory if you are compiling a project. 
*   If you are compiling a single file BIRs will be created in the tmp directory.
*   BIRs created by the language server will also be kept at the same cache location.


# Ballerina Module Repository. {#ballerina-module-repository}

Ballerina module repository is a collection of compiled ballerina modules. Ballerina central is the main module repository for Ballerina developers. Ballerina central will be the only hosted module repository that ballerina supports as of now.



# Ballerina Manifest File {#ballerina-manifest-file}

Ballerina Manifest Type Definition


``` ballerina
type Dependency record {
	string? version;
	string path;
};

Type Library record {
     string path;
     String[] module;
     string? artafactId;
     string? version;
     string? groupId;
}

type ProjectConfig record {
	string orgName;
	string version;
	string license = "";
	string[] authors = [];
	string repository = "";
	string[] keywords = [];
	map<string | Dependency> dependencies = {};
record {|
    string target;
    Library[] libraries;
|} platform;
};
```


Example Value:


```toml
[project]
orgName= "wso2"
version= "1.2.3"
license= "Apache-2.0"
authors= ["WSO2"]
keywords= ["key1", "key2"]
repository= "https://github.com/wso2-ballerina/module-twitter"

[dependencies]
"wso2/twitter"= "2.3.4"
"wso2/github"= { path = "path/to/github.balo", version = "1.2.3"}

[platform]
target = "java8"

  [[platform.libraries]]
  path = "path/to/toml4j.jar"
  modules = ["module1"]
  artafactId = toml4j
  version = "0.7.2"
  groupId = "com.moandjiezana.toml"

  [[platform.libraries]]
  path = "path/to/swagger.jar"
  modules = [ "module1", "module2"]
  artafactId = swagger
  version = "0.7.2"
  groupId = "swagger.io"

  [[platform.libraries]]
  path = "path/to/json.jar"
  modules = [ "module1", "module2"]
  artafactId = json
  version = "0.7.2"
  groupId = "json.org"
```



# Module Template {#module-template}

A template is used by ballerina add command to create a new module. You can define your custom template and share through Ballerina central. A module template is a Ballerina module that we tag as a template.

To create a new template do the following



*   You need to create a Ballerina project. 
*   Create a new module and include template files.
*   In Ballerina.toml specify the module as a template.


```
[project]
orgName= "wso2"
version= "1.1.0"
templates= ["aggregator", <module-name>]

```



*   Once you complete the template you can build and push to central.

To use the template



*   Pull the template from central 
    ```
        $ ballerina pull wso2/aggregator
    ```
*   Then use it with the add command

    ```
    $ ballerina add myAggregator -t wso2/aggregator   <- default to latest version
    $ ballerina add myAggregator -t wso2/aggregator:1.2.3

    ```

A template module will be platform independent and will work with any platform. Platform libraries that you defined for a template module will be ignored. And the build will not create an executable for template modules even if they have entry points. 

The balo created for template will deviate from a standard balo from the following. 



*   Balo metadata will have a flag to identify the balo is a template.
*   Balo source will contain test files as well. 