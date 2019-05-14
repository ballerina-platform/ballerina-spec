@typeParam
private type RecordType record {};
@typeParam
private type StringType string;

public function reason(error<StringType> e) returns StringType = external;
public function detail(error<string,RecordType> e) returns RecordType = external;
public function stackTrace(error e) returns object { } = external;