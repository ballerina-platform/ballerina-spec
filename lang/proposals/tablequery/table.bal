// Note that returned RowType values will always be immutable.
@typeParam
type RowType map<anydata|error>;
@typeParam
type RowType1 map<anydata|error>;
@typeParam
type KeyType map<anydata|error>;
@typeParam
type Type any|error;

public function length(table tbl) returns int = external;

public function iterator(table<RowType> tbl)
   returns abstract object {
      public next() returns record {|
         RowType value;
      |}
   } = external;

public function 'map(table<RowType> tbl, function(RowType row) returns RowType1 func)
  returns table<RowType1> = external;

public function forEach(table<RowType> tbl, function(RowType row) returns () func)
   returns () = external;

// Note that filter preserves primary key
public function filter(table<RowType,KeyType> tbl,  function(RowType row) returns boolean func)
  returns table<RowType,KeyType> = external;

public function reduce(table<RowType> m,
                       function(Type accum, RowType val) returns Type func, Type initial)
  returns Type = external;

# Adds to the end of the table
# Panics if inconsistent with inherent type,
# including primary key constraint.
public function add(table<RowType> tbl, RowType row) returns () = external;
// Should this be called `toArray`?
public function rows(table<RowType> tbl) returns RowType[] = external;

// All the same as methods in map module
public function keys(table<RowType,KeyType> tbl) returns KeyType[] = external;
# Panics if the key cannot be removed
public function remove(table<RowType,KeyType>, KeyType key) returns () = external;

public function removeAll(table tbl)  returns () = external;

public function hasKey(table<RowType,KeyType>, KeyType key) returns boolean = external;

# Panics if no value with this key
public function get(table<RowType,KeyType>, KeyType key)
  returns RowType = external;