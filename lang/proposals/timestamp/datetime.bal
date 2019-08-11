// Standard library date/time module.

// Current time

# Returns a timestamp for the current time.
# `precision` gives the number of digits after the decimal point for seconds
public function now(public int precision = 3) returns timestamp = external;

// Monotonic time

# Returns the number of elapsed seconds since an unspecified epoch
# Values returned by elapsedSeconds() are guaranteed to be monotonically increasing
# i.e. each call will return a  value which will be strictly greater than the previous value
public function elapsedSeconds() returns decimal = external;

// Broken-down time

# Record type representing a calendar date in Gregorian calendar.
# A date is valid if the year is beteen 0 and 9999
# and represents a valid date in the proleptic Gregorien calendar.
# Year 0 means -1 BC.
# Month if value if it is in the range 1 to 12.
# A valid day is always between 1 and 31, but must also be a valid
# day of the month in the Gregorian calendar.
# Corresponds to SQL DATE type.
public type Date record {|
    int year;
    int month;
    int day;
|};

# Record type representing a local time of day using 24-hour clock.
# The `second` field is valid if it is >= 0 and < 61.
# Corresponds to SQL TIME type.
public type Time record {|
    int hour;
    int minute;
    decimal second;
|};

# Record type representing a combination of date and local time.
# Corresponds to SQL TIMESTAMP type.
public type DateTime record {|
    *Date;
    *Time;
|};

# Offset of local time from UTC.
# `hour` must be in the range 0...23
# `minute` must be in the range `0..59`
# `sign` must be `+1` if `hour` and `minute` are both 0.
# The difference between local time and UTC is  `sign * (hour*60 + minute)` minutes.
# This will be positive is local time is ahead of UTC,
# and negative if local time is behind UTC.
# This type should generally be treated as immutable.
public type Offset record {|
    (+1|-1) sign;
    int hour;
    int minute;
|};

# Local time of day together with offset from UTC.
# Corresponds to SQL TIME WITH TIMEZONE type.
public type TimeWithOffset record {|
    *Time;
    Offset offset;
|};

# Date, local time of day and offset from UTC.
# Corresponds to SQL TIMESTAMP WITH TIMEZONE type.
public type DateTimeWithOffset record {|
   *Date;
   *TimeWithOffset;
|};

# ISO 8601 has MONDAY as day 1 and SUNDAY as day 7
# but 0-based starting with Sunday is well-established in programming languages. 
public const int SUNDAY = 0;
public const int MONDAY = 1;
public const int TUESDAY = 2;
public const int WEDNESDAY = 3;
public const int THURSDAY = 4;
public const int FRIDAY = 5;
public const int SATURDAY = 6;

public type DayOfWeek SUNDAY|MONDAY|TUESDAY|WEDNESDAY|THURSDAY|FRIDAY|SATURDAY;

# DateTime together with day of week.
public type FullDateTimeWithOffset record {|
    *DateTime;
    DayOfWeek dayOfWeek;
|};

public const UtcOffset UTC_OFFSET_ZERO = { sign: +1, hours: 0, minutes: 0};

// These are defined so that FullDateTimeWithOffset is a subtype.
public type OpenDate record { *Date; };
public type OpenTime record { *Time; };
public type OpenTimeWithOffset record { *TimeWithOffset; };
public type OpenDateTime record { *DateTime; };
public type OpenDateTimeWithOffset record { *DateTimeWithOffset; };

# Returns if `date` is valid Date, and otherwise returns an error.
# Other functions that have a `date` parameter have a precondition
# that the date is value, and panic if it is not.
public function validDate(OpenDate date) returns OpenDate|error = external;
public function dateToString(OpenDate date) returns string = external;
# Set the date fields in date1 from date2.
public function setDate(OpenDate date1, OpenDate date2) = external;

# Returns `time` if `time` is a valid Time, and otherwise returns an error.
# Other functions that have a `date` parameter have a precondition
# that the date is value, and panic if it is not.
public function validTime(OpenTime time) returns OpenTime|error = external;
public function timeToString(OpenTime time) returns string = external;

// XXX similarly for DateTime, TimeWithOffset, DateTimeWithOffset

public function combine(Date date, Time time, Offset offset) returns DateTime = external;

// Conversion to and from local time in a time-zone

# The `which` field deals with the case where the local time is ambiguous, in the sense
# that there are two timestamps with the same local time.
# The common case of this is when clocks go back at the end of daylight saving time.
# When there are two instants with the same local time, a value for 1 for `which` means that
# the local time refers to the first of them, and a value of 2 means that it refers to the
# second. If the `which` field is missing or `()`, it means that the local time corresponds
# to only one instance. On input, it is allowed for `which` to be non-nil for unambiguous
# local times, in which case it is ignored. However, it is an error for `which` to be `()`
# or missing in ambiguous cases.
public type LocalDateTime {|
    *DateTime;
    (1|2)? which?;
|};

public function breakDown(timestamp ts, TimeZone tz) returns LocalDateTime;
public function makeTimestamp(LocalDateTime dt, TimeZone tz) returns error|timestamp;

// Time zones

public type LocalTimeState record {|
    int standardOffsetMinutes;
    int dstOffsetMinutes; // in addition to standard
    string abbrev;
|};

public type TimeZone abstract object {
    public localTimeState(timestamp ts) returns LocalTimeState;
    # Return discontinuities in local time in the time zone
    # that occur between `begin` and `end` inclusive.
    public findTransitions(timestamp begin, timestamp end) returns timestamp[];
};
