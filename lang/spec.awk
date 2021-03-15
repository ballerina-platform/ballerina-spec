# Add markup to <pre class="grammar"> elements.
# Include langlib source files in the document.
# Non-terminal definitions are wrapped with <dfn>
# Non-termimal references are wrapped with <abbr>
# For portability, we avoid using any GNU awk extensions

/^(<pre +)?class *= *"grammar" *>/,/^<\/pre>/ {
    if (/(<pre)?[^<>]*"grammar" *>/) {
	i = index($0, ">");
	result = substr($0, 1, i - 1);
	rest = substr($0, i);
    }
    else {
	rest = $0
	result = ""
    }
    for (;;) {
	# Tokenize where tokens are one of
	# - start-tag plus following text up to, but not including, next tag
	# - end-tag
	# - alphanumeric string including - with optional following :=
	i = match(rest, /<[a-z]+>[^<]*|[A-Za-z0-9-]+( *:=)?|<\/[a-z]+>/)
	if (i == 0) {
	    result = (result rest)
	    break
	}
	result = (result substr(rest, 1, i - 1))
	matched = substr(rest, i, RLENGTH)
	rest = substr(rest, i + RLENGTH)
	if (matched ~ /^[A-Za-z]/) {
	    i = index(matched, " ");
	    if (i == 0)
		i = index(matched, ":");
	    if (i == 0)
		result = (result "<abbr>" matched "</abbr>")
	    else
		result = (result "<dfn>" substr(matched, 1, i - 1) \
			  "</dfn>" substr(matched, i))
	}
	else
	    result = (result matched)
    }
    print result
    next
}

/preview<\/h1>/ {
    gsub(/preview<\/h1>/, "preview " date "</h1>")
    print
    next
}

/^<p  *class *= *"langlib">/ {
    match($0, / href *= *"/)
    filename = substr($0, RSTART+RLENGTH)
    closeQuote = index(filename, "\"")
    filename = substr(filename, 0, closeQuote - 1)
    print "<pre class=\"langlib\"><![CDATA["
    while ((getline line < filename) > 0) {
	if (index(line, "//") != 1) {
	    print line
	}
    }
    print "]]></pre>"
    next
}

{ print }
