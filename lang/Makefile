# This is intended to be run on POSIX with GNU Make
XSLTPROC=xsltproc
# xmllint is a utility included with libxml2 e.g. in libxml2-utils package
XMLLINT=xmllint
AWK=awk
SHELL=/bin/bash -o pipefail
SH=sh
BUILDDIR=build
BUILDFILES=$(BUILDDIR)/spec.html $(BUILDDIR)/experimental.html

VERSION:=$(shell sed -n -e '/^<h1[ >]/s/.* \(20[12][0-9]R[0-9][0-9]*\(-[A-Za-z0-9]*\)\?\)<.*/\1/p' spec.html)

DISTDIR=ballerina-lang-spec-$(VERSION)
ZIPFILE=$(DISTDIR).zip
COPYFILES=lib/versions.json \
  lib/array.bal lib/decimal.bal lib/error.bal lib/float.bal lib/future.bal \
  lib/int.bal lib/map.bal lib/object.bal lib/stream.bal lib/string.bal \
  lib/table.bal lib/typedesc.bal lib/value.bal lib/xml.bal \
  style/ballerina-language-specification.css \
  style/ballerina-language-specification.js
DISTFILES=spec.html experimental.html $(COPYFILES)

all: $(BUILDFILES)

$(BUILDDIR)/spec.html: $(BUILDDIR)/spec.xml spec.xsl 
	echo '<!DOCTYPE html>' >$(BUILDDIR)/spec.html
	$(XSLTPROC) spec.xsl $(BUILDDIR)/spec.xml | \
	  sed -e '/<meta http-equiv/d' >>$(BUILDDIR)/spec.html
	tar cf - $(COPYFILES) | (cd $(BUILDDIR)/; tar xf -)

$(BUILDDIR)/spec.xml: spec.html spec.awk
	test -d $(BUILDDIR) || mkdir $(BUILDDIR)
	$(AWK) -f spec.awk spec.html >$(BUILDDIR)/spec.xml


$(BUILDDIR)/experimental.html: experimental.html spec.xsl 
	$(XSLTPROC) spec.xsl experimental.html | \
	  sed -e '/<meta http-equiv/d' >$(BUILDDIR)/experimental.html


check: $(BUILDDIR)/spec.xml
#	$(XMLLINT) -noout -relaxng spec.rng $(BUILDDIR)/spec.xml
	$(SH) check-grammar.sh

clean: FORCE
	-rm -fr $(BUILDDIR)

dist: $(BUILDDIR)/$(ZIPFILE)

$(BUILDDIR)/$(ZIPFILE): $(DISTFILES) $(BUILDFILES)
	test -d $(BUILDDIR)/$(DISTDIR) || mkdir $(BUILDDIR)/$(DISTDIR)
	tar cf - $(COPYFILES) | (cd $(BUILDDIR)/$(DISTDIR)/; tar xf -)
	cp -p $(BUILDFILES) $(BUILDDIR)/$(DISTDIR)/
	cd $(BUILDDIR); zip -q $(ZIPFILE) $(addprefix $(DISTDIR)/,$(DISTFILES))

FORCE:

