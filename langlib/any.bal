// lang.any module
private type PureStructure = (anydata|error)[]|map<anydata|error>;

# A type parameter that is a subtype of `PureStructure`.
# Has the special semantic that when used in a declaration
# all uses in the declaration must refer to same type. 
@typeParam
private type PureStructureType = PureStructure;

// Functions that were previously built-in methods

# Freezes `struct` and returns it
public function clone(PureStructureType struct) returns PureStructureType = external;
# Returns clone of `struct` that is not frozee
public function freeze(PureStructureType struct) returns PureStructureType = external;
public function unfrozenClone(PureStructureType struct) returns PureStructureType = external;
# Tests whether `struct` is frozen
public function isFrozen(PureStructure struct) returns boolean = external;