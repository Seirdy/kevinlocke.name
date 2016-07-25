#!/bin/sh
# build.sh - Build the website

set -eux

# trap wrappers since some shells don't call EXIT trap on signals (e.g. dash)
# Use onexit "cmd" then unexit "cmd" around block to ensure cmd is always run
unexit() { eval "$*"; trap "-" EXIT HUP INT KILL PIPE QUIT TERM; }
onexit() { trap "$*; unexit" EXIT HUP INT KILL PIPE QUIT TERM; }

# For determining appropriate levels of parallelism
NPROCS=
if [ -r /proc/cpuinfo ] ; then
	NPROCS=$(grep -c ^processor /proc/cpuinfo)
elif command -v sysctl >/dev/null ; then
	NPROCS=$(sysctl -n hw.ncpu)
fi

if [ -z "$NPROCS" ] ; then
	echo "Warning: Unable to detect number of CPU cores.  Guessing 2."
	NPROCS=2
fi

rm -fr _site

bundle exec jekyll build "$@"

# Copy files with leading underscore excluded by Jekyll (in programs)
# Currently, only file is one generated by phpdocumentor
find programs -name '_*' | while IFS= read -r FILE; do
    cp -ar -- "$FILE" "_site/$FILE"
done

# Rename blog posts from .html to .xhtml
find _site/bits -name '*.html' | while IFS= read -r FILE; do
    mv -- "$FILE" "${FILE%.html}.xhtml"
done

# Remove .xhtml extension from URLs in the sitemap
sed -i 's/\.xhtml<\/loc>/<\/loc>/' _site/sitemap.xml

# Assume vnu.jar is set executable and placed in $PATH if available
if command -v vnu.jar >/dev/null 2>&1 ; then
    # Check that XHTML files are valid XHTML5
    find _site -name '*.xhtml' -print0 | \
        xargs -0 -r vnu.jar --
else
    echo 'Validator.nu command-line client not in $PATH, skipping...' >&2
    echo 'See https://validator.github.io/validator/#usage' >&2

    # Check that XHTML files are valid XML
    find _site -name '*.xhtml' -print0 | \
        xargs -0 -r xmllint --nonet --noout
fi

# Note:  Not checking .html files, which are phpdoc/javadoc

# Generate .html versions of .xhtml pages
find _site -name '*.xhtml' | while IFS= read -r FILE; do
    xsltproc --nodtdattr -o "${FILE%.xhtml}.html" _build/xhtmltohtml.xsl "$FILE"
    # Replace the over-conservative us-ascii charset with utf-8
    perl -pi -e 's/\s*<meta[^>]*http-equiv="Content-Type"[^>]*>\s*/  <meta charset="utf-8" \/>\n/i' -- "${FILE%.xhtml}.html"
done

# Check other XML for well-formedness
find _site \( -iname '*.atom' -o -iname '*.xml' \) -print0 \
	| xargs -0 -r xmllint --nonet --noout

# Pre-compress common text files
COMPRESSIBLE_FILES=$(mktemp -t compressible-files.XXXXXX)
onexit rm "$COMPRESSIBLE_FILES"
find _site \( -iname '*.atom' \
	-o -iname '*.asc' \
	-o -iname '*.css' \
	-o -iname '*.html' \
	-o -iname '*.js' \
	-o -iname '*.pem' \
	-o -iname '*.svg' \
	-o -iname '*.txt' \
	-o -iname '*.vcard' \
	-o -iname '*.vcf' \
	-o -iname '*.xhtml' \
	-o -iname '*.xml' \
	\) -print0 > "$COMPRESSIBLE_FILES"
xargs -0 -r pigz -9 -k < "$COMPRESSIBLE_FILES"
if command -v brotli ; then
	xargs -0 -r '-I{}' -P$((NPROCS+2)) brotli --input '{}' --output '{}.bro' < "$COMPRESSIBLE_FILES"
fi
# Rename original files to .orig so that MultiViews will negotiate the encoding
# when accessing the file with the type extension  (otherwise just serves it)
xargs -0 -r '-I{}' -P$((NPROCS+2)) mv '{}' '{}.orig' < "$COMPRESSIBLE_FILES"

# ErrorDocument does not appear to accept .html.orig.
# Copy to .orig.html for this use.
# (Avoid just .html which would thwart encoding negotiation of .html type).
for FILE in _site/[0-9][0-9][0-9].html.orig ; do
	ln "$FILE" "${FILE%.html.orig}.orig.html"
done

echo Done building site.
