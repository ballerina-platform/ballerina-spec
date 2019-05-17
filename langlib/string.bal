public function length(string str) returns int = external;

public function iterator(string str) returns abstract object {
    public next() returns record {| string value; |}?;
} = external;

# Concatenate all the `strs`. Empty string if empty.
public function concat(string... strs) return str;

public function codePointAt(string str, int i) returns int = external;
public function substring(string str, int start, int end = str.length()) returns string = external;
// Lexicographically compare strings using their Unicode code points
// This will allow strings to be ordered in a consistent and well-defined way,
// but the ordering will not typically be consistent with cultural expectations
// for sorted order.
public function codePointCompare(string str1, string str2) returns int = external;

public function join(string separator, string... strs) returns string = external;

# Returns the index of the first occurrence of `substr` in the part of the `str` starting at `startIndex`
# or nil if it does not occur
public function indexOf(string str, string substr, int start = 0) returns int? = extern;
public function startsWith(string str, string substr) returns boolean = extern;
public function endsWith(string str, string substr) returns boolean = extern;

// Standard lib (not lang lib) should have a Unicode module (or set of modules)
// to deal with Unicode properly. These will need to be updated as each
// new Unicode version is released.
# Return A-Z into a-z and leave other characters unchanged
public function toLowerAscii(string str) returns string = extern;
# Return a-z into A-Z and leave other characters unchanged
public function toUpperAscii(string str) returns string = extern;
# Remove ASCII white space characters (0x9...0xD, 0x20) from start and end of `str`
public function trim(string str) returns string = extern;

