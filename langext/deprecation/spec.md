# Deprecation design
## Summary
Specify a mechanism to mark Ballerina APIs that are no longer in use.
## Goals 
- Enable to static code analysis tools issue warnings or errors on the usages of obsolete APIs.
- Provide a way for API designers to express reasons for marking a particular API is obsolete.
- Provide a way for API designers to guide users to migrate away from the usages of obsolete API elements, optionally providing one for more replacement API elements.

When marking an API element obsolete, you need to convey both machine-readable information and human-readable information. 
Machine-readable information helps static analysis tools to generate warnings or errors on usages of obsolete API elements. 
Human-readable information helps the clients of the API to migrate away from the obsolete API element. 

This design proposes a built-in annotation for providing machine-readable information and a Markdown convention for providing human-readable information. 

## API Elements 
This document uses the term API element to refer to:
- The module-level symbols with public visibility
- Object members with public visibility (fields and methods) 

### The lifecycle of an API Element 
In this context, we can say there are four stages/levels. 

#### 1. Create the element
The API developer or maintainer introduces a new API element to the API.
 E.g., adding a new public function, public object into the module.
#### 2. Mark it as deprecated, but allow clients to use it. 
API maintainer decides that this element should no longer be used. There can be various reasons to mark something as deprecated. 

API maintainer gives a grace period to migrate away from the deprecated element. The compiler gives a warning on usage.

API docs provide precise human-readable information for clients to migrate their code. 

After some time, the API maintainer decides to end the grace period. Now he can either remove the API element or keep it 
#### 3. Mark it as deprecated, and the clients cannot use it.
API maintainer decides to end the grace period. The API element is still available in the code as well as in API docs. 

The compiler gives an error on usages of API elements that are at this stage. Clients get meaningful error messages saying that this API element is deprecated and no longer available to use. Clients still have access to API docs that contain why the element was deprecated and the replacement options.
#### 4. Remove the element. 

## Machine-readable information
### The `@deprecated` annotation
This specification introduces a new built-in annotation called `@deprecated` to mark an API element that is no longer in use. 

The semantics is that the usage of a deprecated API element is allowed, but the compiler should give a warning.

```ballerina
public const annotation deprecated on source type, source object type, source const, source annotation,
          source function, source parameter, source object function, source object field;
```

### Attachment points
This section lists the attachment points to which the @deprecated annotation can be attached.

The module-level symbols with public visibility:
- `module-type-defn`
- `module-const-decl`
- `annotation-decl`
- `function-defn`

Function and method parameters: 
- `required-param` with public visibility
- `defaultable-param` with public visibility. 

Object members with public visibility:
- `object-method`
- `object-field-descriptor`

### Deprecation warning 
The Ballerina compiler must issue a warning when a deprecated API element is used, except in following cases:
- A deprecated API element is used within another deprecated API element.

## Human-readable information
Specify deprecated API element details in the documentation string as a separate section.

```ballerina
# Adds parameter `x` and parameter `y`
#
# + x - one thing to be added
# + y - another thing to be added
# + return - the sum of them
#
# # Deprecated
# This function has side-effects. It relies on a module-level variable.  
# Users of this function should instead use the function `addNew`
@deprecated {}
function addOld (int x, int y) returns int { return x + y; }
```
