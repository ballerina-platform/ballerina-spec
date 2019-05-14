@typeParam
private type RecordType record {};
@typeParam
private type StringType string;

# Returns the error's reason string
public function reason(error<StringType> e) returns StringType = external;
# Returns the error's detail record as a frozen mapping
public function detail(error<string,RecordType> e) returns RecordType = external;
# Returns an object representing the stack trace of the error
public function stackTrace(error e) returns object { } = external;