# This is intended to be run on POSIX with GNU Make
XSLTPROC=xsltproc
# xmllint is a utility included with libxml2 e.g. in libxml2-utils package
#XMLLINT=xmllint
AWK=awk
SH=sh
BUILDDIR=build
BUILDFILES=$(BUILDDIR)/spec.html

VERSION:=$(shell sed -n -e '/^<h1[ >]/s/.* \(20[12][0-9]R[0-9][0-9]*\)<.*/\1/p' spec.html)

DISTDIR=ballerina-lang-spec-$(VERSION)
ZIPFILE=$(DISTDIR).zip
DISTFILES=spec.html lib/versions.json \
  lib/array.bal lib/decimal.bal lib/error.bal lib/float.bal lib/future.bal \
  lib/int.bal lib/map.bal lib/object.bal lib/stream.bal lib/string.bal \
  lib/table.bal lib/typedesc.bal lib/value.bal lib/xml.bal

all: $(BUILDFILES)

$(BUILDDIR)/spec.html: $(BUILDDIR)/spec.xml spec.xsl 
	echo '<!DOCTYPE html>' >$(BUILDDIR)/spec.html
	$(XSLTPROC) spec.xsl $(BUILDDIR)/spec.xml | \
	  sed -e '/<meta http-equiv/d' >>$(BUILDDIR)/spec.html

$(BUILDDIR)/spec.xml: spec.html spec.awk
	test -d $(BUILDDIR) || mkdir $(BUILDDIR)
	$(AWK) -f spec.awk spec.html >$(BUILDDIR)/spec.xml

check: $(BUILDDIR)/spec.xml
#	$(XMLLINT) -noout -relaxng spec.rng $(BUILDDIR)/spec.xml
	$(SH) check-grammar.sh

clean: FORCE
	-rm -fr $(BUILDDIR)

dist: $(ZIPFILE)

$(ZIPFILE): $(DISTFILES)
	test -d $(DISTDIR) || mkdir $(DISTDIR)
	tar cf - $(DISTFILES) | (cd $(DISTDIR); tar xf -)
	zip $(ZIPFILE) $(addprefix $(DISTDIR)/,$(DISTFILES))

distclean: FORCE
	-rm -fr $(DISTDIR) $(ZIPFILE)

FORCE:

