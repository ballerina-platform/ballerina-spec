# Supplying values to configurable variables 

This document defines how to supply values to configurable variables using TOML syntax and command-line arguments.

## Configurable variables

Configurable variables should be of type `anydata & readonly.`

```
anydata : =  () | boolean | int | float | decimal | string | xml
             | anydata[] | map<anydata> | table<map<anydata>>
```

## Structured identifiers

The language defines a _structured identifier_ to a configurable variable. It contains the module name and the configurable variable name. 

The platform needs to define one or more concrete syntaxes for associating an `anydata` value with a _structured identifier_.

The platform supports the following syntaxes to supply configurable values: 
*   TOML
*   command-line arguments

## Toml Syntax 

TOML is a minimal configuration file format with key/value pairs and collections of such key/values pairs (tables). Configuration values should be specified in TOML syntax in a file with `.toml` extension as key/value pairs, tables, and an array of tables. 

Note that values cannot be supplied to configurable variables with nil and mapping types via TOML syntax. Here are the supported types.

Define type T as:


```
type T boolean | int | float | decimal | string | xml
        | anydata[] | table<map<anydata>>
```


Values can be supplied to configurable variables with type `T?` via TOML syntax.

Limitations



*   Some float values cannot be represented in TOML. 
    *   [https://github.com/toml-lang/toml/issues/55](https://github.com/toml-lang/toml/issues/55)
    *   JSON has the same limitations anyway


### TOML keys

Here is the structure of TOML [keys](https://toml.io/en/v1.0.0#keys) allowed in TOML files.


```
    key := simpleKey | dottedKey
    simpleKey := bareKey | quotedKey
    dottedKey := simpleKey (. simpleKey)+
```


A structured identifier is mapped to a [key](https://toml.io/en/v1.0.0#keys) in TOML as follows:


```
    key:= [[orgName .] moduleName .] varName
    varName := simpleKey
    moduleName := dottedKey
    orgName := simpleKey
```


Design notes:

*   The `orgName` and `moduleName` are optional only for configurable variables defined in the root module of the program
*   The `orgName` is optional only for configurable variables defined in the root package of the program.
*   This design works for configurable variables in a single source file as well. This was not a strict requirement.

Here are some examples:


```
	port = 9090
```

```
    myapp.port = 9090
```

```
    ballerina.log.format = "logfmt"
    ballerina.log.level = "ERROR"
```


This can also be written using TOML table syntax.

```
    [myapp]
    port = 9090
```

```
    [ballerina.log]
    format = "logfmt"
    level = "ERROR"
```

Conceptually a Ballerina module is represented as a table(collection of key/value pairs) in TOML. 


### Resolving the module and configurable variable from a TOML Key

A TOML key consists of one or more parts. Each part is a `simpleKey. `The resolution algorithm is described for keys with one, two, and three or more parts.

A TOML key with one part and two parts always identify a configurable variable defined in the root module of the program. Report an error if there is no such variable.

```	
    port = 9090
```
```
	myapp.port = 9090
```
```
	[myapp]
	port = 9090
```


Toml keys with three or more parts:

```
	p.q.r.s = 5

```



*   A linked Ballerina program is a collection of modules. 
*   If `p` - first part of the key - matches with an organization in the program, find the configurable variable `s`, in the module `q.r`. If there is no such variable or module report an error.
*   If `p` does not match with an organization in the program, then `p.q.r` should be a module in the root package of the program. If there is no such variable or module report an error.


### Resolving ambiguities

An ambiguity can occur when there exists an organization with the same name as the root package name or the first part of the hierarchical root package name.

Say organization name is `p` and the root package name is also `p` and the user wants to configure a variable defined in the module `p.q` which is part of the root package `p`.

We can resolve this by forcing the user to specify an organization for the root package. 


### Locating TOML fjiles
The following rules are applicable when running a Ballerina program with `java -jar`, `bal run` commands:

*   Look for the environment variable `BAL_CONFIG_FILES`. It should provide a list of paths to `.toml` files.
    *   The list paths are seperated by the OS-specific separator.
    *   If a key is specified in one or more `.toml` files, use the following mechanism to resolve the confict:
        *   Let `A.toml` and `B.toml` be two TOML files specified in the `BAL_CONFIG_FILES` environment variable and `A.toml` is specified before the `B.toml` in the path list. If key `K` is defined in both toml files, then pick the value in `A.toml` and ingore the value in `B.toml`.
    *   The default value of `BAL_CONFIG_FILES` is `./Config.toml`. 
*   If not, look for the environment variable `BAL_CONFIG_DATA`. It should provide the TOML content.
*   If not, look for a `Config.toml` file using the path available in the default value of the `BAL_CONFIG_FILES` envionment variable. 

The following rules are applicable when running units tests of a module with `bal test` command:
*   Look for the Config.toml file in the corresponding module test directory root.

## Command-line arguments

Configurable values can be supplied with the built-in command-line option `-C`, 


```
-Ckey=value
```


Key syntax: 


```
key:= [[org .] module .] variable
```


Define `S` as: 


```
type S boolean | int | float | decimal | string | xml 
```


In the first phase, only the configurable variables with type `S? `are supported`. `We can support `anydata[], map&lt;anydata> and table&lt;map&lt;anydata>> `later as needed`.`

The` toString()` representation of the value can be provided with the -C option.


<table>
  <tr>
   <td>Type of value
   </td>
   <td>Representation of the value
   </td>
   <td>Parse 
   </td>
  </tr>
  <tr>
   <td>boolean
   </td>
   <td><code>toString()</code>
   </td>
   <td><code>boolean:fromString()</code>
   </td>
  </tr>
  <tr>
   <td>string 
   </td>
   <td><code>toString()</code>
   </td>
   <td>use as-is
   </td>
  </tr>
  <tr>
   <td>int
   </td>
   <td><code>toString()</code>
   </td>
   <td><code>int:fromString()</code>
   </td>
  </tr>
  <tr>
   <td>float
   </td>
   <td><code>toString()</code>
   </td>
   <td><code>float:fromString()</code>
   </td>
  </tr>
  <tr>
   <td>decimal
   </td>
   <td><code>toString()</code>
   </td>
   <td><code>decimal:fromString()</code>
   </td>
  </tr>
  <tr>
   <td>xml
   </td>
   <td><code>toString()</code>
   </td>
   <td><code>xml:fromString()</code>
   </td>
  </tr>
</table>


Notes:
*   Nil value cannot be provided with this design
*   The rules for resolving a configurable variable from a command-line argument key and from a TOML key are the same. 
*   A value supplied via a command-line arg gets the priority over a value supplied via TOML for a given `configurable` variable.
