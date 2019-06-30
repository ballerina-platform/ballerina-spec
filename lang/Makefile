# This is intended to be run on POSIX with GNU Make
VERSION:=$(shell sed -n -e '/^<h1[ >]/s/.* \(20[12][0-9]R[0-9][0-9]*\)<.*/\1/p' spec.html)

DISTDIR=ballerina-lang-spec-$(VERSION)
ZIPFILE=$(DISTDIR).zip
DISTFILES=spec.html lib/versions.json \
  lib/array.bal lib/decimal.bal lib/error.bal lib/float.bal lib/future.bal \
  lib/int.bal lib/map.bal lib/object.bal lib/stream.bal lib/string.bal \
  lib/table.bal lib/typedesc.bal lib/value.bal lib/xml.bal

$(ZIPFILE): $(DISTFILES)
	test -d $(DISTDIR) || mkdir $(DISTDIR)
	tar cf - $(DISTFILES) | (cd $(DISTDIR); tar xf -)
	zip $(ZIPFILE) $(addprefix $(DISTDIR)/,$(DISTFILES))

clean: FORCE
	-rm -fr $(DISTDIR) $(ZIPFILE)

FORCE: