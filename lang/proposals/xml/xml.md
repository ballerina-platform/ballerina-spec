# XML

Please add comments to the associated issue [#288](https://github.com/ballerina-platform/ballerina-spec/issues/288).

## Purpose of document

*   Serve as basis for implementation, until this is merged into spec
*   Will become a public document in the GitHub repository (e.g. lang/design/xml.md) to serve as a permanent record of rationale
*   Updated until spec release that includes this; frozen thereafter


## Design goals and choices

These are implicit in the 2019R2 design.


### Smooth integration with rest of language

Ballerina including the XML support should feel like a single, coherent language. XML should not feel like a completely separate world. On the other hand, XML needs to be different, otherwise there is no point in having XML as a separate type. 


### XML Infoset only

This works with XML as defined by the XML Recommendation and the XML Infoset. It has no support for the Post-Schema Validation Infoset, introduced by W3C XML Schema.

Going beyond the XML Infoset is possible, but definitely for later.


### Sequences

As in XPath 2 and XQuery. There is no difference between a T and a sequence consisting of a single T; XML sequences are flat i.e. do not contain other XML sequences (although XML sequences contain elements whose children are XML sequences). Whether two sequences are identical depends on whether the constituents of the sequences are identical; a sequence does not have an identity separate 			from its constituents.

Note that a string is also conceptually a sequence.


### Downward-only pointers

In most XML processing systems, an element "knows where it is" in the document, e.g. by having pointers to its parents/siblings. We do not do this.


### Document fragments

Fundamental xml type represents a fragment such as can be found in the content of an XML element. We consider a document just as a special case of a fragment, which is a sequence having exactly one element, optionally followed or preceded by comments and processing instructions. This also works for representing an XML external parsed entity.

This leads to a small problem with whitespace. Whitespace outside the document element is not significant in XML (i.e. not included in the infoset). But whitespace in an XML fragment (such as occurs in content) is significant. We can deal with this by allowing whitespace text before and after the document element in an xml value that represents the document.


### No text nodes

Should not group chars into nodes that have persistent identity.


### Relation to other Ballerina types



*   Mapping value to represent attributes
*   Like strings, in that it is a sequence
*   Similar to error, in that both have a string representing qualified name and a mapping 
    *   error has reason/detail record
    *   element has name/attributes


### Namespaces



*   No namespace tax: if you don't use namespaces, you should not be exposed to namespace-related complexity
*   Represent expanded names as strings in the form “{namespaceUri}localName”
*   Namespace attributes are exposed as regular attributes using the built-in definition of the xmlns prefix as `http://www.w3.org/2000/xmlns/`
*   Leverage similarity to Ballerina qualified names


### Limited use of mutation



*   Membership of sequences not mutable
*   An element is mutable by changing its attributes or its children.
*   TBD for comments/PIs


## Core features


### Value space

xml is its own distinct basic type, which does not overlap with any other basic type.

xml values are sequences of zero or more items, where an item is one of the following



*   element
*   text item consisting of characters
*   processing instruction
*   comment

A sequence consisting of a single item X is the same value as that single item X.

To put it another way, xml value space contains what is allowed by the following rules:



*   empty xml sequence is in the value space
*   single item is in the value space
*   concatenation of any two values in the value space is also in the value space

An element item contains



*   a name, which is a value of type string
*   attributes, representing as a mapping value of type `map<string>`; creating an element item also automatically creates its attribute mapping; these mappings have the additional feature that they preserve order (although order it not part of their shape)
*   children sequence, which is a value of type xml

The above is the same as 2019R2 value space.

Text item semantics are explained separately in the next section.


#### Rationale

One important design issue is whether empty sequence and () should be the same value? Short answer: no.

Compare



*   result when map does not have an entry with key "X" - ()
*   result when element does not have a child element "X" - empty XML sequence

Assuming we have some XPath-like navigation syntax (see below), then foo/bar/baz will return empty XML sequence when there are no matching elements. We want this to compose nicely with `?.` map access syntax for attributes which can be applied to nil and returns nil, so you can say `foo/bar/baz?.att` and get nil if the attribute does not exist.

`()` works nicely as a syntax for an empty sequence.

value:toString does the same thing (empty string).

Problem: if empty xml is same as nil, then empty xml:Text is same as nil; so implicit conversion of xml:Text to string will involve converting nil to an empty string, but we don't in general (I think) want implicit conversion of nil to empty string. So it would not work well to have both:



*   empty XML sequence === nil
*   implicit conversion from xml:Text to string

If we were not concerned about familiarity/JSON interop, we could identify empty string and nil, but we are so we can't.


### Text item semantics

A text item that forms part of an xml sequence always has one or more characters. An xml value never has consecutive text items. To put it another way, sequence concatenation always concatenates adjacent text items. Text items correspond to maximal character sequences within the xml sequence. This means that the grouping of an xml sequence into characters never provides additional information.

All operations that iterate over an xml sequence treat a text item as a single unit. All  operations that use integer indices to provide access to an xml sequence count a text item as a single unit.

Note that an xml sequence consisting of a single text item is distinct from a string


#### Rationale


##### Chunking

Logically an XML element contains individual characters, which are not grouped into large chunks. For the purposes of providing access to those characters, two approaches are possible:



*   each character is treated as a single unit
*   consecutive characters are grouped together into chunks, where each chunk is as big as possible (i.e. you never have two consecutive chunks)

The difference between these two approaches shows up in two groups of operations:



*   indexing operations, which use an integer to access members of a sequence by position, specifically E[n], xml:slice and xml:length functions
*   iteration operators, which iterate over the members of the sequence, specifically foreach and the xml:map, xml:forEach and xml:filter functions

2019R2 says both groups take the first (single character) approach. This is good for indexing, because you can use slice to access any possible subsequence, but is problematic for iteration, because often you want to access chunks in order to perform some operation on the chunk as a whole.

Obviously, all the operations in a group need to follow the same approach. For example, the foreach statement has to be consistent with the xml:forEach function. So the possible solutions seem to me to be the following:



1. Use the chunked approach for both groups. If we do this, we should define the value space of xml as having text items that are strings, with the constraint that there no consecutive text items (i.e. consecutive chars are merged into strings when the sequence is constructed)
2. Keep the single character approach for both groups of operations, but allow the user to say e.g. x.chunks().map(f) to get a chunked view of the sequence. The xml:chunks function would return an object that provided this chunked view for both iteration and indexing (via __get method) operations.  If we do this we should have an xml:Char type that represents a single character.	
3. Use the chunked approach for the iteration group but the single character approach for the indexing groups

I think we should eliminate option C: indexing and iteration are consistent in all other basic types that support both kinds of operation; also it is not clear how to explain the typing of the chunked functions.

This leaves A and B. 

Option B is perhaps purer, and is more consistent with string.

But I think I prefer A for three reasons



*   simplicity
*   convenience: you almost always want chunked iteration
*   whitespace: it is generally only safe to strip whitespace automatically when a whole chunk is whitespace; for element typing in the future, we need to be able to have a type that expresses the constraint that a whole chunk is whitespace   


##### XML text item vs string

These are very similar in that they both represent a sequence of characters, but there are differences:



*   value:toString behaves differently
*   string allows code points that are not allowed in XML

XML text item is sort of like a subtype of string (in the OO sense) but it is hard to fit into our model of types as sets of values. In particular it is hard to fit into our concept of the universe of values being partitioned by basic types. So I think it is easier to model this relationship by allowing an implicit conversion from text item to string (see below).


### Mutation and identity semantics

An empty sequence has value semantics like (). An empty sequence is always represented by an identical value. An empty sequence is === to any other empty sequence.

A text item has semantics like string. Two text items are === if they consist of the same sequence of characters.

An element item is mutable and so has reference semantics



*   Two element items are === if they refer to the same storage.
*   Two element items are == if they have their names, attributes and children are all ==.

The attribute mapping for an element is created at the same time as the element and is immutably tied to the element. The members of the mapping can be modified but it is not possible to change the attribute mapping to be another mapping. The inherent type of the attribute mapping should only allow entries that would be allowed as attributes by XML.

Processing instruction and comment items are treated as mutable and with reference semantics, similar to element items.

Sequences have hybrid semantics that depend on their constituent items:



*   two sequences are == if they have the same length and their constituent items are all ==
*   two sequences are === if they have the same length and their constituent items are all ===

The individual element items comprising a sequence can be mutated, but the sequence itself cannot be mutated i.e. which items comprise the sequence is fixed when the sequence is created.


#### Rationale

Strings do not have an identity separate from their value:


```
assert("x" === "x" + "");
assert("xy" === "x" + "y");
```


XML values containing text should be like strings as regards identity:


```
assert(xml`x` === xml`x` + xml``);
assert(xml`xy` === xml`x` + xml`y`);
```


This makes chunking work cleanly.


```
assert(xml`x<!-- comment -->y`.text().length() === 1)
```


Empty sequences should be like nil as regards identity


```
assert(xml`` === xml``);
```


The identity of an XML sequence consisting only of an element is the same as the identity of an element, because a sequence consisting of as single element is the same value as a single  element. So


```
xml e = xml`<e/>`;
assert(e === e + xml``);
assert(e === xml`${e}`);
```


Both strings and XML are sequences not lists (this difference is fundamental). You get the universe of strings by taking characters and empty strings and closing the set under the concatenation operation



*   the empty string is a string
*   a single character c is a string
*   if s1 is a string and s2 is a string, then s1 + s2 is a string

For string identity, we can define the identity rules as



*   an empty string === an empty string
*   a string consisting of a single character c === a string consisting of a single character c
*   if x1 === x2 and y1 === y2, then x1 + x2 === y1 + y2

Similarly for XML:



*   the empty XML sequence is an xml value
*   an XML element is an xml value
*   a XML text character is an xml value
*   if x1 is an xml value and x2 is an xml value, then x1 + x2 is an xml value

The simple, consistent way to define identity is to follow this:



*   an empty XML sequence === an empty XML sequence
*   an xml sequence consisting of a single character c === an xml sequence consisting of a single character c
*   an xml sequence consisting of a single element with storage address x === an xml sequence consisting of a single element with storage address x
*   if x1 === x2 and y1 === y2, then x1 + x2 === y1 + y2

The fundamental point is that a sequence does not have an identity independently of its constituents; to give it such an identity would be inconsistent with the idea that a sequence consisting just of X is the same value as X. Rather the identity of a sequence derives from the identity of its constituents.

This means we have to refine the concept of simple value vs reference value, since sequences are neither. From an identity point of view we have three kinds of value:



*   simple values
*   reference values
*   sequences


### Item-specific subtypes

The basic type is xml.

We introduce predefined types for the following specific subtypes of xml:



1. single element
2. single processing instruction
3. single comment
4. text item consisting of zero or more characters (i.e. text item or empty sequence)

Note that this subtyping is only possible because of the limited mutability of sequences.

For naming these, we use types defined by xml module in lang library:



*   xml:Element
*   xml:ProcessingInstruction
*   xml:Comment
*   xml:Text

The xml lang module would use a special annotation on type to define these (allowed only in lang library, similar to @typeParam, ) e.g.:


```
# Element is a subtype of xml
# known to the compiler by its name
@namedSubtype
type Element xml;
```


xml:Text matches zero or more characters i.e. text item or empty sequence


#### Rationale

Reason for this approach to naming the types:



*   avoids introducing multiple new keywords (xmlelement, xmlcomment), which would be rather strange
    *   names too long
    *   not fundamental enough to deserve being reserved words
*   allows multiple words to be used for xml:ProcessingInstruction
    *   xmlprocessinginstruction would be ghastly
    *   abbreviating processinginstruction as pi inconsistent with commonly used XML standards, which do not use this abbreviation
*   explicit relationship with XML basic type
*   clear from the name that these are names of types 

With this approach, these will syntactically be just identifiers defined as a type, not a reserved word.

(This could be applied to other basic types, e.g. int:Int32 would be useful for Java interop, string:Char might also be useful i.e. string of length 1)

xml:Text should represent zero or more characters (i.e.single text item or empty sequence), because we don't want xml:Text constructor to panic when str is empty.


### Sequence repetition type

We also need a way to express sequences consisting of zero or more items, where each item belongs to a subtype of xml.

Use xml<T>, where T is subtype of xml, meaning an xml sequence consisting of zero or more items of type T. Note that



*   `xml<xml<T>>` is same as `xml<T>`
*   `xml<xml:Text>` is same as `xml:Text`


#### Rationale

This is needed to represent type of various functions: for example, xml:elements returns sequences of xml:Element. Also the iterator function needs to be parameterized in its constituent item types: when you iterate over a sequence of items of some type, the item type needs to be the correct subtype of xml.

Rejected alternative syntaxes



*   repeat<T> unclear how many times to repeat
    *   Google protobuf3 uses terminology of repeated fields (meaning zero or more), so perhaps `repeated<T>` would be OK
*   T* - if this means zero or more times, then T? should mean zero or one times, but it doesn't (unless we make nil the same as the empty sequence, which I don't think we want to do, see above)


### Existing operators



*   E1 + E2 does concatenation as with strings
*   E1 == E2, E1 != E2 does shape equality, inequality
*   E1 === E1, E1 !== E2 does identity
*   E[n] returns n-th item (empty sequence if out of range)
*   foreach iterates over items


### XML literals

As in 2019R2 spec. Key design points



*   Parse and namespace process at compile-time.
*   Defined in terms of XML syntax specified by XML Recommendation
*   Two stage parse
    *   Substitutions
    *   XML 
*   Element names and attribute names (including expanded names) are fixed at parse time
*   Substitution happens at infoset level


### Constructors

Structured types in Ballerina have a constructor that can be used both to construct the value and, in binding/match patterns to destructure the value. This should work for the XML types also. As with other types, this allows construction of compile-time constants (which would not be possible with functions).

Use each of the type names as constructors:



*   xml:Element(name[, attributes[, content]]) 
*   xml:Text(str)
*   xml:Comment(contentStr)
*   xml:ProcessingInstruction(targetStr, contentStr)

The above would just be more cases of the functional constructor.

The xml:Element constructor differs from the error constructor in that it does not allow attributes to be specified inline.  A new attribute map is created and filled with the specified attributes.

We also allow:



*   xml(x1, x2, x3)

which would concatenate its arguments. Zero arguments are allowed and will construct an empty sequence In a binding pattern, the parameters in the match a single item; ...x can be used to match multiple items.


#### Rationale

Key use cases for XML element constructor:



*   construction where element or attribute name not known at compile time (so XML literal cannot be used)
*   destructuring particularly in conjunction with foreach e.g.

    ```
    foreach var xmlelement(name, atts, children) in x.elements() { }

    ```


### Lang library

See [lang.xml module](xml.bal).

### Conversion from xml:Text to string

There is an implicit conversion from xml:Text to string.

A method call with static type xml:Text should lookup in basic type string, if the lookup in basic type xml fails (this is equivalent to doing an implicit conversion on the first argument).

A type cast of `<string> `applied to an xml:Text value should succeed and perform the conversion (as with converting between different numeric types).

Note that this implicit conversion is doing the same as stringValue when applied to xml:Text.


#### Rationale

The separation of string and xml basic types means that we have two types xml:Text and string that are very close in that they both represent a sequence of characters. The differences are very small:



*   value:toString is the identity function on string but escapes significant XML characters for xml:Text, in other words value:toString on xml is doing XML serialization
*   XML 1.1 excludes three Unicode scalar values ( U+0000, U+FFFE and U+FFFF), whereas string allows all Unicode scalar values; XML 1.0 also excludes not just U+0000 but all C0 control characters other than 0x, 0xA and 0xD, so probably xml:Text should disallow these scalar values either, following XML 1.0 or 1.1

The situation seems very similar to what we have with numeric types, where there are three basic types that are distinct ways of representing what is essentially the same thing i.e. a number, where the basic types differ only in how certain operations on the values behave.

R2 has a feature/hack whereby iteration automatically converted xml:Text items to strings, but that won't work with the more precise typing of items (at least not without additional typing features).

This means that functions that result in xml sequences consisting only of characters should generally return type xml:Text.

This in turn means that there will be a lot of conversion from xml:Text to string. Up to now, we have avoided all implicit conversions in Ballerina, but I think the right way to address this is by providing an implicit conversion from xml:Text to string. The model the user would have is that xml:Text is a special type of string. Why?



*   if we don't make this work, users will inevitably use value:toString, which will not do what is needed in most situations
*   the user cannot do any text-specific manipulation with xml:Text without converting it to string; this is not the case with int/float/decimal where the useful operations are provided on all datatypes
*   I cannot see forcing the user to make the conversion explicit will help with readability or reducing errors

The alternative to this would be to duplicate many of the built-in methods on string on xml:Text also, but that does not feel appealing.

In the implementation, it should be possible to arrange that in many cases a value of type xml:Text can be used as a string without needed to copy (e.g. there are BString and BXmlSequence interfaces and a value of type xml:Text implements both).

In the other direction, we don't need to allow implicit conversion. Instead function parameters that accept xml can also allow strings in cases where that makes sense (e.g. setChildren). We can also use the `xml:Text(str)` constructor to convert explicitly when necessary.


### Namespaces

The Ballerina xmlns declaration allows for both the declaration of a particular namespace prefix and for a default namespace declaration. These provide a context for the parsing of XML literals.

Namespace declarations also need to work for accessing the documents. In particular, if `ns` is defined as an XML prefix using


```
    xmlns "http://example.com/ns" as ns;
```


then `ns:foo` will behave as a string constant <code>"{[http://example.com/ns}foo](http://example.com/ns}foo)"</code>. This is important for using with the results of getName and getAttributes.


### Maintaining prefixes with namespace attributes

When constructing a Ballerina mapping for the attributes of an XML element information item, the attributes mapping will contain



*   an entry for any namespace declaration that was actually present in the attribute's start-tag (and so in the [namespace attributes] infoset property), and
*   an entry declaring the namespace (computed from the [in-scope namespaces] property) for prefix p, if p is not `xml` and p is used as the prefix of the element information item or of one of its attribute information items.

When a Ballerina xml value is serialized as a string, then there is a corresponding process of omitting namespace attributes that occur in the attribute mapping from the serialization. A prefixed namespace attribute mapping entry is omitted from the serialization if both



*   there is already an in-scope declaration from the parent elements, and
*   it occurs in the expanded name of the element or of one of the attributes

For elements and attributes with expanded names that have a namespace URL, serialization has to choose which prefix to use, and, for elements, whether to use a prefix or the default namespace. In choosing, they must satisfy as many of the following rules in order as possible:



1. Are there one or more choices that will make the element or attribute gets expanded to the correct expanded name using only the namespace attribute declarations present in the Ballerina xml value? If so,
    1. if it's an element, and the default namespace is amongst these choices, use that
    2. otherwise, prefer prefix that has closest declaration in the Ballerina xml (i.e. on the element itself, on the parent etc)
2. Otherwise, are there one or more choices that will make the element or attribute name gets correctly expanded using the declarations already emitted for parent elements together with all the namespace declarations on this element? If so, choose between those options using the same method as 1.
3. Otherwise, generate a default namespace declaration and use no prefix if the following conditions are met
    3. the namespace URI is used in the element name
    4. that namespace URI is not used in an attribute name of this element
    5. the Ballerina xml map does not have a default namespace declaration
4. Otherwise, generate a new namespace prefix
    6. Probably best to generate the same namespace prefix for a given namespace URL throughout the document
    7. If somewhere else in the document there is a namespace prefix declared for a namespace URL, it would be nice to reuse that, but to do so might be problematic from a performance perspective.

If rule 1 cannot be satisfied for an element, then choose no prefix and add a default namespace declaration.

If an element has no namespace URL and a default namespace declaration is in scope, then an `xmlns=""` attribute has to be generated to undeclare the default namespace.


#### Rationale

From a very purist namespace perspective, all that really matters are the expanded names, but in practice people want to preserve prefixes.  We want this to work also when xml elements are extracted from the context where they originally occurred.

Two approaches to namespaces are:



*   represent the entire set of in-scope namespaces
*   represent only the namespace attributes declared

The first approach is conceptually good, but is hard to work with, because it requires elements to have a new component that is not present in the syntax. So we follow a pragmatic blend of the two, where we augment the declared namespaces attributes with the prefixes used in the start-tag.


### xmlns prefix

The prefix xmlns  is predeclared as a namespace prefix bound to [http://www.w3.org/2000/xmlns/](http://www.w3.org/2000/xmlns/) as in the XML Namespaces Recommendation and cannot be redeclared as either a module prefix or namespace prefix using import or xmlns declarations.


#### Rationale



*   xmlns prefix is preclared in XML
*   users need to be able to add namespace attributes using `xmlns:ns`
*   the xmlns prefix can occur before arbitrary names


### xml prefix

The xml module in the lang library contains const definitions for each allowed attribute in the xml namespace  e.g.


```
    const lang = "{http://www.w3.org/XML/1998/namespace}lang";
```


Also for xml:space and xml:base.

Then if the xml module is imported using the prefix xml, the following will work as expected:


```
    x.getAttributes()[xml:lang] = "en";
```



### Alternative design

In this alternative



*   nil and an empty xml sequence are the same value
*   xml:Element? will thus mean a sequence consisting of zero or one elements
*   sequence repetition can then be done with `T*` rather than `xml<T>`
*   xml:Text should probably match a single text item i.e. one or more characters
*   there is an implicit conversion from a single text item (which is always non-empty) to a string
*   thus `xml:Text?` would be implicitly converted to `string?`
*   xml(str) can create an xml:Text value from a string (i.e. arguments of xml are of type xml|str)
*   Would xml:Text be allowed as a constructor? If so, how would it handle an empty string argument?
*   The type-name xml would describe the union of the xml basic type and nil.
*   The binary + operator applied to values of basic type nil would have to mean concatenation


### Issues



1. One important use case for the XML support is HTML. We need to make sure that the way we do namespaces is not a barrier to convenient use of the XML support to process HTML5.
2. Probably best to predefine xml prefix bound to be bound to xml module (as with xmlns)
3. Cycles are a problem. It makes no sense (and is not useful) for xml values to have cycles. But it is hard to detect when a mutation of an element causes this.
4. Do we need singleton XML types? Other structural types have singleton types. I don’t see the use case for this.
5. Assuming XML empty sequence is different from nil, then do we want a type for it e.g. xml:Empty? We will need this when we do more precise element typing, but not now I think.
6. How should slice function deal with out of range arguments? Error would be more consistent with the rest of the language. Clamping to range would be more consistent with other XML operators (like subscripting)


## Improved navigation


### XPath background

An XPath path expressions interleave three operations:



1. map: for each node in set do something and union the results
2. getChildren() operation
3. select members of the set based on some criteria

What makes this work conveniently is the idea that there's a current node, and expressions are evaluated with the current node.

Note that in XPath


    book/author[1]

gives the first author of each book, not the first author of the first book, i.e. means book/(author[1]) rather than (book/author)[1]. Semantics is for each book,



*   get its children
*   select from them elements with name author
*   select first of elements selected by previous step
*   take the union of the results

In effect, / is doing a map.

Problem is how to control what happens on first step, sometimes want to select from members of sequence without getting children first

Two possible cases for


```
ns:foo/ns:bar

```



*   normal


```
E.elements().map(x => x.getChildren().elements(ns:foo))
            .map(x => x.getChildren().elements(ns:bar))

```



*   root (useful only at first step root)


```
E.elements(ns:foo).map(x => x.getChildren().elements(ns:bar))
```



### Proposed syntax/semantics

Basic idea: `/` means go down a level (from parent to child), as in XPath.

These examples are assuming no default namespace has been declared in Ballerina. Also we are allowing multiple string arguments to the elements function to explain things (we won’t actually want to do this).

`x.<foo>` means x.elements("foo") i.e. select items from x that are elements named foo

`x.<ns:foo>` means x.elements(ns:foo) i.e. select items from x that are elements named ns:foo

`x.<*>` means select element items from x

`x.<ns:*>` means select elements whose names are in namespace ns i.e. matching {namespaceURI}*

`x.<foo|bar>` means x.elements("foo", "bar") i.e. select items from x that are elements named foo or bar

`x[0]` means first item in x 

x.text() means xml:text(x) as usual i.e. select each item from x that is a text item

`x/<ns:foo>` means x.elements().map(x => x.getChildren().elements(ns:foo))

x/<*> means  x.elements().map(x => x.getChildren().elements())

`x/*` means  x.elements().map(x => x.getChildren()) (same as x.children())

`x/**/<ns:foo>` means all descendants named ns:foo (same as Ant and rsync)

`x/<ns:foo>[0]` means  x.elements().map(x => x.getChildren().elements(ns:foo)[0]) rather than x.elements().map(x => x.getChildren().elements(ns:foo))[0] i.e. RHS of / includes [0]

`x/<ns:foo>.slice(0, 2)` means

   x.elements().map(x => x.getChildren().elements(ns:foo).slice(0,2))

`x.<book>/<author|editor>[0]/<firstName>` means


```
   x.elements("book")
    .map(x => x.getChildren().elements("author", "editor")[0])
    .map(x => x.getChildren().elements("firstName")
```


Stuff we probably don't need:

x/.foo() means x.elements().map(x => x.getChildren().foo())

x.<^a|b> means all element children (or all children?) other than a or b

XPath things we cannot do with above syntax:

x/(a|b|text())

(This is quite rare.)


### Better integration with types

In the syntax x.<N> and x/<N>,  N is in effect a special kind of type descriptor for describing a subtype of string, specifically strings that are expanded names. (Thinking of it as a type descriptor also works well with the use of angle brackets.) This special kind of type descriptor is generally useful and should not be restricted to just navigation. In particular, it should be possible to use it with the `is` operator, and to turn it into a value (of type typedesc<string>) so it can be passed to functions (e.g. xml:elements).

The difference between this and normal type descriptors is that an identifier stands for a particular string rather than being a reference to a type definition.  This suggests using a single quote as follows:


```
'<a|b|c> means "a"|"b|"c"
```


i.e. the N in the `x.<N>` syntax can also be used as a type descriptor using `'<N>`. Furthermore this type descriptor can be used anonymously in an expression (without having to first define a named type). So the elements function will become:


```
function elements(xml x,
                  // string in default value is referring to
                  // built-in type name
                  string|typedesc<string> name = string);
type ABC '("A"|"B"|"C");
type ABC '<A|B|C>; // same as previous line 
                   // if no default namespace
x.elements(ABC);
x.elements('<A|B|C>); // same as previous line
```


Within this kind of type descriptor, it would be natural to allow *X to reference a type (as in record and object type descriptors) i.e.


```
'(a|*b|c) means ("a"|b|"c")
```


Furthermore `ns:*` should be useable as a type descriptor (including anonymously), when ns is defined by an xmlns declaration.


### Default namespace

XPath does not have a concept of default namespaces for path expressions: a name without a prefix always refers to a name without a namespace URL. This was for two reasons



*   XSLT 1.0 uses XML namespace declarations to interpret XPath qnames, and the namespace that is convenient as the default XML namespace declaration would not be the same as the namespace that would be convenient for expanding qnames, e..g when the source and result documents use different namespaces;
*   XPath qnames are used not only for element names, but also for attribute names, to which the default namespace is not applied.

Neither of these issues applies to use of identifiers inside `<A>`, so we can apply the Ballerina default xmlns declaration to a name without a prefix.


### Attribute access

Both E1.name and E1?.name should be allowed to provide access to attributes.

Lax typing should allow x.name when x is of type xml and should return an error if x is not of type xml:Element. Maybe nil if x is empty sequence and error otherwise.

Similar for access to fields of error detail record

Assignment to a namespace-qualified attributes

elem.ns:x = "val";

where ns is declared with an XML namespace declaration needs to have the semantic of adding a namespace declaration for prefix ns to the map.


### Element name access

Accessing the element name is at least as important as accessing the element attributes, so if we provide nice syntax for the former, it would make to provide nice syntax for the latter.

Should also work for



*   error reason
*   processing instruction name/target

In the context of XML, the element name can appropriately be thought of as a special unnamed attribute, which suggests the syntax `E1._` (although we could instead of _  use any character not allowed as first char of identifier). It is tempting to make this also work as an lvalue for XML, but



*   it is not clear that it can do the right thing as regards namespace attributes
*   setting the name of an element is very rare compared to getting the name
*   this does not apply to error reason, since errors are immutable

Alternatives



*   `E.$`
*   `E.$name`, `E.$reason`, `E.$target`

Rejected alternatives



*   `E.<>`.
    *   Not quite the right relationship to E.<X>
    *   Not good for error reason.


## Features for future releases

These are beyond the scope of 2019R4, but it is important to have some idea how they might work in order to design the core features.


### Element typing

At the moment there is no way to specify a subtype of xml:Element.

This feature would allow the type of an element to be specified more precisely. Specifically the type of an XML element would have three parts:



1. a type for the element name, which would be a subtype of string
2. a type for the attributes map, which would be a subtype of map<string>, and
3. a type for the element's content

The last of these would be a regular expression over types, each of which are subtypes of xml.

There are a number of issues to work through:



*   how to deal with comments and processing instructions
*   how to deal with insignificant whitespace
*   what kinds of regular expression should be allowed
*   convenient syntax


#### Namespaces and attribute maps

Should allow xmlns and xmlns:* attributes automatically. Should be able to specify allow any number of attributes from a particular namespace e.g. record { string ns:*; } 


#### Regular expressions


#### Syntax

Just simply xml:Element<E,A,C> is problematic:



*   something defined with type definition cannot have parameters (yet)
*   for element name
    *   want to be able to use a (qualified-)identifier, with default namespace applied, as with navigation
*   for attributes
    *   need to deal with namespace attributes
    *   default openness should be different
    *   giving value type as string all the time, feels redundant
*   for children
    *   need to be able to use a regexp, with traditional regexp operators working as expected
    *   do whatever is needed for comments, PIs and insignificant whitespace

Putting attributes on one side, the following syntax is natural for an `element` type descriptor:


```
    element name [ content-model ]
```


where



*   any X allowed in '<X> syntax would be allowed for <code><em>name</em></code>
*   <code><em>content-model</em></code> used type descriptors referring to xml subtypes in conjunction with traditional regexp operators <code>,|*?+</code> (as in DTD content models or RELAX NG)

e.g.


```
type HtmlElement element html [ HeadElement, BodyElement ];
type InlineElement element i|b|em|code [ (inline|Text)* ];
```


I am using square brackets are used because order is significant, and to leverage similarity with tuple types. The square brackets probably cannot be optional, because of ambiguity with array syntax, so an element with no content would need to be something like one of:


```
type BrElement element br [ ];
type BrElement element br [ Empty ];
```


For attributes, I think we want an `attributes` type descriptor that works similarly to record, but



*   allows namespace attributes by defaults
*   deals with openness differently (curly braces being open to anydata is wrong)
*   perhaps avoids need to specify string as type


```
type HtmlAttributes attributes {
   string id?;
   string class;
};

type html element html [
   attributes {
	string class?;
	string id?;
   },
   head, body
];

type inline element i|b|em|code { (inline|Text)* };
```


The question then is how to include the attributes type in the element type. Possibilities are


```
type HtmlElement element html<HtmlAttributes> [
   HeadElement, BodyElement
];
```


What does it mean if you leave out the attributes? I think that should tie in to attribute openness i.e. `element foo []` should mean e`lement foo<attributes {}> []`.

Also need to be able to have a type descriptor for a sequence type (i.e. type-regexp). Syntax could be one of


```
type HtmlContent sequence [ HeadElement, BodyElement ];
type HtmlContent xml<[ HeadElement, BodyElement ]>;
```



#### Comments and processing instructions

When describing the type of the content of an element, comments and processing instructions should not be relevant. Comments and processing instructions should automatically be allowed.

There are two approaches to dealing with. We will use two types to explain this

type Insignificant xml<Comment|ProcessingInstruction>;

type Significant xml<Element|Text>;

Suppose we have an html element and we have a precise type for its content as a head element followed by a body element. There are two sequence types that can arise when processing such an element:



1. a two-item sequence consisting of just an element type for head and an element type for body: call this Tnarrow
2. a sequence that allows any interleaving of Tnarrow and Insignificant: call this Twide

The two approaches are as follows:



1. take Tnarrow as fundamental, and provide a way to construct Twide from Tnarrow
    1. sequence [head, body] means Tnarrow
    2. we can provide an interleave operator (which RELAX NG calls &) to describe Twide as (Tnarrow & Insignificant)
    3. getChildren would be declared like this 

        ```
        function getChildren(element * [ ContentType ])
                   returns ContentType & Insignificant;
        ```


2. take Twide as fundamental, and provide a way to construct Tnarrow from Twide
    4. sequence [head, body] means Twide
    5. we can provide an intersection operator (which TypeScript calls &) to describe Tnarrow as (Twide & Significant)

I suspect we will want an intersection operator elsewhere.


#### Insignificant whitespace

From a typing perspective, we want to ignore text chunks that are entirely white space and that are before a start-tag or after and end-tag. In other words, with a sequence type a reference to an element type E is implicitly a reference to `WS,E,WS` where WS is a type that matches whitespace only text chunks.

Consider


```
<p>
<q>Hello</q> <b>James</b>
</p>
```



### Data types

This complements the previous section. XML is fundamentally just elements and text. The previous section is about more expressive typing for elements; this is about more expressive typing for text.

Effectively, this is supporting the datatyping aspect of PSVI (which is also supported to some extent by RELAX NG).

This would require extending the value space of xml. For example, the type of an attribute value could allow not just string but also other simple types and lists of simple types. Similarly, the content of an XML element could be not just an xml value, but the same kind of thing as an attribute value.

Datatyping for attributes is both easier and more generally useful:



*   even DTDs have some attribute data typing
*   HTML only has data types for attributes not for element content
*   since we handle attributes as a normal Ballerina mapping value, it easily extends to values other than strings


### Explicit XML document support

XXX


