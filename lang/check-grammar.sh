#!/bin/sh
b=build
xsltproc grammar.xsl $b/spec.xml >$b/grammar.xml
# Don't want no i18n
export LC_ALL=C
# Test for characters that should not be in the grammar
sed -e '/<?xml/d
/^<[/]grammar/d
/^<grammar/d
s;<[a-z]*>[^<]*</[a-z]*>;;g
s/0x[0-9A-Fa-f]*//g
s/:=//
s/\.\.//g
s/[][^|*+?()]//g
/^ *$/d' $b/grammar.xml >$b/meta.txt
test -s $b/meta.txt && echo Spurious grammar chars: `cat $b/meta.txt` 1>&2
# Test for duplicate definitions
sed -n -e 's;.*<dfn>\([^<]*\)</dfn>.*;\1;p' $b/grammar.xml | sort > $b/defs.txt
uniq -d $b/defs.txt >$b/dups.txt
test -s $b/dups.txt && echo Duplicate definitions found: `cat $b/dups.txt` 1>&2
sed -e 's/<abbr>/\n<abbr>/g' $b/grammar.xml \
    | sed -n -e 's;.*<abbr>\([^<]*\)</abbr>.*;\1;p' \
    | sort -u >$b/used.txt
join -a 2 -v 2 $b/defs.txt $b/used.txt >$b/undef.txt
test -s $b/undef.txt && echo Undefined references found: `cat $b/undef.txt` 1>&2
join -a 1 -v 1 $b/defs.txt $b/used.txt \
     | grep -v '^TokenWhiteSpace\|module-part$' >$b/unused.txt
test -s $b/unused.txt && echo Unused definitions found: `cat $b/unused.txt` 1>&2
exit 0

