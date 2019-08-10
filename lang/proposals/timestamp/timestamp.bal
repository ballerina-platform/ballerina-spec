// lang.timestamp module

# A record type representing an instant in time in UTC relative to an epoch.
# It assumes that the epoch occurs at the start of a UTC day (i.e. midnight).
# This has the same information as a timestamp.
# All operations on timestamps can be defined in terms of operations
# on the corresponding `Instant` record.
# `epochDays` is the number of days from the epoch rounded down to the nearest integer.
# `timeOfDaySeconds` is the duration in seconds from the start of the UTC day.
# `timeOfDaySeconds` will be < 86,400 except on a day with a positive leap second,
# when it will be < 86,401.
# Two timestamps are `==` if both fields of the corresponding Instant are `==`.
# Two timestamps are `===` if both fields of the corresponding Instant are `===`.
public type Instant record {|
    int epochDays;
    decimal timeOfDaySeconds;
|};

# A timestamp for the Ballerina epoch.
public const timestamp EPOCH = 2000-01-01T00:00:00Z;

# The year of the Ballerina epoch.
public const int EPOCH_YEAR = 2000;

# The day of week of the EPOCH.
# This can be used with Instant.epochDays to directly compute the day of the week.
public const int EPOCH_DAY_OF_WEEK = 6;

# Returns the Instant of `ts` relative to `EPOCH`.
# So `EPOCH.toInstant()` returns `{ epochDays: 0, timeOfDaySeconds: 0d }`
public function toInstant(timestamp ts) returns Instant = external;

# Returns the timestamp corresponding to `instant`.
# Panics if `instant` does not correspond to any timestamp.
# A positive leap second is allowed for any day that is the last day of a month,
# on any year >= 1972.
# `ts === fromInstant(ts.toInstant())` will be true for any timestamp `ts`.
public function fromInstant(Instant instant) returns timestamp = external;

# Same as `ts.toInstant().epochDays`.
public function epochDays(timestamp ts) returns int = external;

# Same as `ts.toInstant().timeOfDaySeconds`.
public function timeOfDaySeconds(timestamp ts) returns decimal = external;

# Converts a timestamp to a duration in seconds since the epoch.
# This ignores leap seconds.
# For a timestamp that does not occur during a positive leap second,
# it is equivalent to
# `(ts.epochDays() * 86400d) - ts.timeOfDaySeconds()`;
# for a timestamp that does occur during a positive leap second,
# it is equivalent to ts.leapSecond().before.toEpochSeconds().
# Same as `diffSeconds(ts1, EPOCH)`.
public function toEpochSeconds(timestamp ts) returns decimal = external;

# Converts a duration in seconds since the epoch to a timestamp.
# Panics if out of range.
public function fromEpochSeconds(decimal seconds) returns timestamp = external;

# Returns difference in seconds between two timestamps.
# Same as `ts1.toEpochSeconds() - ts2.toEpochSeconds()`.
public function diffSeconds(timestamp ts1, timestamp ts2) returns decimal = external;

# Same as `fromEpochSeconds(ts1.toEpochSeconds() + seconds)`
public function addSeconds(timestamp ts1, decimal seconds) returns timestamp = external;

# Convert from RFC3339 string
# Leap seconds are allowed at the end of a UTC month, for years from 1972 onwards.
public function fromString(string) returns timestamp|error = external;

# Round to `precision` digits of precision.
public function round(timestamp ts, int precision) returns timestamp = external;

// Broken down

# This is the same as datetime:DateTime.
# But we don't want a dependency, so we have a non-public copy here.
type DateTime record {|
    int year;
    int month;
    int day;
    int hour;
    int minute;
    decimal second;
    record {|
        (+1|-1) sign;
        int hour;
        int minute;
    |} offset;
|};

public function fromDateTime(record { *DateTime; } dt) returns timestamp = external;

# Returns a broken down representation of a timestamp.
# The offset field in the returned record will be zero.
public function toDateTime(timestamp ts) returns DateTime = external;

// Leap seconds

# Information about a timestamp that occurred during a positive leap second.
# * `before` - timestamp immediately before the leap second
# * `after` - timestamp immediately after the leap second
# * `elapsed` - part of the leap second that elapsed before the timestamp
# `after` will be a timestamp at the start of UTC day (i.e. 00:00:00) following
# the timestamp.
# The value of `before` depends on the precision of the underlying timestamp `ts`;
# it will be the greatest timestamp before `ts` with a second field that is < 60
# and that has the same precision as `ts`. So if `var leap = ts.leapSecond();`, then
# `ts.timeOfDaySeconds() === leap.before.timeOfDaySeconds() + leap.elapsed`
public type LeapSecond record {|
    timestamp before;
    timestamp after;
    decimal elapsed;
|};

# Returns information about a timestamp that occurred during a positive leap second.
# Returns `()` if the timestamp did not occur during a positive leap second.
public function leapSecond(timestamp ts) returns LeapSecond? = external;
