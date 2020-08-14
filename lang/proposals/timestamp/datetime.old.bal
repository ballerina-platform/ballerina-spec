// Sketch of date/time for the stdlib

import ballerina/lang.timestamp as ts;

type Date tsd:Date;
type TimeOfDay ts:TimeOfDay;
type ZoneOffset ts:ZoneOffset;

# Record type representing combination of calendar date and time of day with offset from UTC.
type OffsetDateTime record {|
    Date date;
    TimeOfDay time;
    ZoneOffset offset;
|};

type OffsetDate record {|
    Date date;
    ZoneOffset offset;
|};

type OffsetTimeOfDay record {|
    TimeOfDay time;
    ZoneOffset offset;
|};

const ZoneOffset ZONE_OFFSET_ZERO = { sign: +1, hours: 0, minutes: 0 };


# Record type representing time duration
# This is equivalent to some number of seconds.
type Duration record {|
   Sign sign?;
   int weeks?
   int days?;
   int hours?;
   int minutes?;
   decimal seconds?;
|};

type Seconds decimal;

public function toSeconds(public int weeks = 0,
                          public int days = 0,
                          public int hours = 0,
                          public int minutes = 0,
                          public decimal seconds = 0)
    returns decimal = external;
