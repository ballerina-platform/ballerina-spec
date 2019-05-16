

// XXX this will panic for the most negative value (-2^63 is an int but +2^63 isn't)
// consistent with policy on integer overflow
# Return absolute value of `n`
public function abs(int n) returns int = external;

# Sum of all the arguments
# 0 if no args
public function sum(int... ns) returns int = external;

# Maximum of all the arguments
# XXX should we allow no args?
public function max(int n, int... ns) returns int = external;

# Minimum of all the arguments
# XXX should we allow no args?
public function min(int n, int... ns) returns int = external;