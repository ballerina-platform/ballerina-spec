# Sum of all the arguments
# 0 if no args
public function sum(int... ns) returns int = external;

# Maximum of all the arguments
# XXX should we allow no args?
public function max(int n, int... ns) returns int = external;

# Minimum of all the arguments
# XXX should we allow no args?
public function min(int n, int... ns) returns int = external;