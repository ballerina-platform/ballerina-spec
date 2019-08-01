// xml module

@namedSubtype
type Element xml;
@namedSubtype
type Text xml;
@namedSubtype
type ProcessingInstruction xml;
@namedSubtype
type Comment xml;

// Specific to Element items
function getAttributes(Element elem) returns map<string> = external;
// also want getChildren lifted over sequences	
public function getChildren(Element elem) returns xml = external;
public function setChildren(Element elem, xml children) = external;

// Applies to Element or ProcessingInstruction items
public function getName(Element|ProcessingInstruction item)
  returns string = external;
// setName has to some XML namespaces management
// to deal with namespace prefixes
public function setName(Element|ProcessingInstruction item, string name) = external;

// Applies to ProcessingInstruction or Comment items
public function getContent(ProcessingInstruction|Comment item)
  returns string = external;
public function setContent(ProcessingInstruction|Comment item, string content) = external;

@typeParam
type ItemType Element|Comment|ProcessingInstruction|Text;
@typeParam
type Type xml;

// applies to sequences
public public function iterator(xml<ItemType> x)
  returns abstract object {
    public next() returns record {| ItemType value; |}?;
} = external;

public function length(xml x) returns int = external;
public function slice(xml<ItemType> x, int startIndex,
                     int endIndex = x.length())
  returns xml<ItemType> = external;

# Returns a sequence containing the items of x
# that are elements and, if `name` is not (),
# have name `name`.
public function elements(xml x, string name = ()) returns xml<Element> = external;

# Returns sequence consisting of all text items in x,
# or an empty sequence if x does not contain any text items.
public function text(xml x) returns Text = external;

# Concatenation of all text and text descendants
# as a single string (same as XPath).
# So xml`this is an <b>important</b> point`.stringValue() ==
# "this is an important point"
# stringValue(x) is defined as follows
# - if x is the empty sequence, the empty string
# - if x is a comment or PI item, the empty string
# - if x is a text item, a string with the item's characters
# - if x is an element item, the stringValue of the children
# - if x is a concatenation of x1 and x2,
#   then stringValue(x1) + stringValue(x2)
# 
# This provides a way to convert xml:Text to string
public function stringValue(xml x) returns string = external;

// Note that func can map an element
// onto two elements or nothing
public function map(xml<ItemType> x,
     function(ItemType item) returns Type func) 
  returns xml<Type> = external;

public function forEach(xml<ItemType> x,
                 function(ItemType item) returns () func) = external;

public function filter(xml<ItemType> x,
                function(ItemType item) returns boolean func)
  returns xml<ItemType> = external;

// More convenience functions

// lift getChildren over sequences
// equivalent to elements(x).map(getChildren)
public function children(xml x) returns xml = external;

# equivalent to children(x).elements(name)
public function elementChildren(xml x, string name = ())
   returns xml<Element> = external;