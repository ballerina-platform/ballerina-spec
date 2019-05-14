public function length(string s) returns int = external;

public type Iterator abstract object {
    public next() returns record {| string value; |}?;
};

public function iterator(string s) returns Iterator = external;

