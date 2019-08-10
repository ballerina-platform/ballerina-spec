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
public type LocalTime record {|
    int hour;
    int minute;
    decimal second;
|};

# Record type representing a combination of date and local time.
# Corresponds to SQL TIMESTAMP type.
public type DateLocalTime record {|
    *Date;
    *LocalTime;
|};

# Offset of local time from UTC.
# `hour` must be in the range 0...23
# `minute` must be in the range `0..59`
# `sign` must be `+1` if `hour` and `minute` are both 0.
# The difference between local time and UTC is  `sign * (hour*60 + minute)` minutes.
# This will be positive is local time is ahead of UTC,
# and negative if local time is behind UTC.
# This type should generally be treated as immutable.
public type UtcOffset record {|
    (+1|-1) sign;
    int hour;
    int minute;
|};

# Local time of day together with offset from UTC.
# Corresponds to SQL TIME WITH TIMEZONE type.
public type Time record {|
    *LocalTime;
    UtcOffset offset;
|};

# Date, local time of day and offset from UTC.
# Corresponds to SQL TIMESTAMP WITH TIMEZONE type.
public type DateTime record {|
   *Date;
   *Time;
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
public type FullDateTime record {|
    *DateTime;
    DayOfWeek dayOfWeek;
|};

public const UtcOffset UTC_OFFSET_ZERO = { sign: +1, hours: 0, minutes: 0};

// These are defined so that FullDateTime is a subtype.
public type DateSource record { *Date; };
public type LocalTimeSource record { *LocalTime; };
public type TimeSource record { *Time; };
public type DateLocalTimeSource record { *DateLocalTime; };
public type DateTimeSource record { *DateTime; };

# Returns if `date` is valid Date, and otherwise returns an error.
# Other functions that have a `date` parameter have a precondition
# that the date is value, and panic if it is not.
public function validDate(DateSource date) returns DateSource|error = external;
public function dateToString(DateSource date) returns string = external;
# Set the date fields in date1 from date2.
public function setDate(DateSource date1, DateSource date2) = external;

# Returns `time` if `time` is a valid Time, and otherwise returns an error.
# Other functions that have a `date` parameter have a precondition
# that the date is value, and panic if it is not.
public function validTime(TimeSource time) returns TimeSource|error = external;
public function timeToString(TimeSource time) returns string = external;

// XXX similarly for LocalTime, LocalDateTime, DateTime

public function combine(Date date, LocalTime localTime, UtcOffset offset) returns DateTime = external;
