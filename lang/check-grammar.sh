#!/bin/sh
b=build
xsltproc grammar.xsl spec.html >$b/grammar.xml
# Don't want no i18n
export LC_ALL=C
sed -n -e 's/^\([A-Za-z][-A-Za-z0-9]*\) :=.*/\1/p' $b/grammar.xml | sort > $b/defs.txt
uniq -d $b/defs.txt >$b/dups.txt
test -s $b/dups.txt && echo Duplicate definitions found: `cat $b/dups.txt` 1>&2
# DPH FTW!
sed -e '/^</d
/ :=/s/^\(.*\):=//
s;<code>[^<]*</code>; ;g
s;<em>[^<]*</em>; ;g
s/0x[0-9A-Fa-f]*//g
s/[][()|*^?+]/ /g
s/\.\./ /g
s/  */ /g
s/^  *//
s/ * $//
s/ /\n/g
/^ *$/d' $b/grammar.xml | sort -u >$b/used.txt
join -a 2 -v 2 $b/defs.txt $b/used.txt >$b/undef.txt
test -s $b/undef.txt && echo Undefined references found: `cat $b/undef.txt` 1>&2
join -a 1 -v 1 $b/defs.txt $b/used.txt \
     | grep -v '^TokenWhiteSpace\|module-part$' >$b/unused.txt
test -s $b/unused.txt && echo Unused definitions found: `cat $b/unused.txt` 1>&2
