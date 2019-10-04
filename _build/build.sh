#!/bin/sh
# build.sh - Build the website

set -eu

if ! [ -d _build ] ; then
	echo 'Error: Must be run from site directory with _build subdir.' >&2
	exit 1
fi

# Include _build in $PATH to use local copy of some tools
PATH="$(pwd)/_build:$PATH"
export PATH

# Remove any previous site to avoid accumulating stale files
rm -fr _site

bundle exec jekyll build "$@"

# Copy files with leading underscore excluded by Jekyll (in programs)
# Currently, only file is one generated by phpdocumentor
find programs -name '_*' | while IFS= read -r FILE; do
    cp -ar -- "$FILE" "_site/$FILE"
done

# Rename blog posts from .html to .xhtml and replace named HTML entities
find _site/bits -name '*.html' | while IFS= read -r FILE; do
    htmlentitynametonum -- "$FILE" > "${FILE%.html}.xhtml"
    rm -- "$FILE"
done

# Replace named HTML entities in non-html files
find _site \( -iname '*.atom' -o -iname '*.rss' \) -print0 | \
	xargs -0r htmlentitynametonum -i --

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

# Check other XML for well-formedness
find _site \( -iname '*.atom' -o -iname '*.rss' -o -iname '*.xml' \) -print0 \
	| xargs -0 -r xmllint --nonet --noout

build-multiviews _site _site

echo Done building site.
