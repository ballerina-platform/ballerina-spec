// IEEE refers to IEEE 754
// Constants

public const float PI = 3.141592653589793;
public const float E =  2.718281828459045;
public const float NaN = 0.0/0.0;
// XXX This or POSITIVE_INFINITY, NEGATIVE_INFINITY;
public const int Infinity = 1.0/0.0;

# Sum of all the arguments
# +0.0 if no args
# NaN if any arg is NaN
public function sum(float... xn) returns float = external;

# Maximum of all the arguments
# -∞ if no args
# NaN if any arg is NaN
public function max(float... xn) returns float = external;

# Minimum of all the arguments
# +∞ if no args
# NaN if any arg is NaN
public function min(float... xn) returns float = external;

# IEEE abs operation
public function abs(float x) returns float = external;

public function round(float x) returns float = external;

# Largest (closest to +∞) floating point value not greater than `x` that is a mathematical integer
public function floor(float x) returns float = external;

# XXX ceiling or ceil?
# Smallest (closest to -∞) floating point value not less than `x` that is a mathematical integer
public function ceil(float x) returns float = external;

# IEEE squareRoot operation
public function sqrt(float x) returns float = external;

# Cube root
# IEEE rootn(x, 3)
public function cbrt(float x) returns float = external;

# IEEE pow(x, y)
public function pow(float x, float y) returns float = external;

# Natural logarithm
# IEEE log operation
public function log(float x) returns float = external;

# Base 10 log
# IEEE log10 operation
public function log10(float x) returns float = external;

# IEEE exp operation
public function exp(float x) returns float = external;

# IEEE sin operation
public function sin(float x) returns float = external;

# IEEE cos operation
public function cos(float x) returns float = external;

# IEEE tan operation
public function tan(float x) returns float = external;

# IEEE acos operation
public function acos(float x) returns float = external;

# IEEE atan operation
public function atan(float x) returns float = external;

# IEEE asin operation
public function asin(float x) returns float = external;

# IEEE atan2(y, x) operation
public function atan2(float y, float x) returns float = external;

# IEEE sinh operation
public function sinh(float x) returns float = external;

# IEEE cosh operation
public function cosh(float x) returns float = external;

# IEEE tanh operation
public function tanh(float x) returns float = external;