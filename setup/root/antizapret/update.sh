#!/bin/bash
set -e

HERE="$(dirname "$(readlink -f "${0}")")"
cd "$HERE"

LISTLINK='https://raw.githubusercontent.com/zapret-info/z-i/master/dump.csv'
NXDOMAINLINK='https://raw.githubusercontent.com/zapret-info/z-i/master/nxdomain.txt'
curl -f --fail-early --compressed -o temp/list_orig.csv "$LISTLINK" || exit 1
iconv -f cp1251 -t utf8 temp/list_orig.csv > temp/list.csv
curl -f --fail-early --compressed -o temp/nxdomain.txt "$NXDOMAINLINK" || exit 1

LISTSIZE="$(curl -sI "$LISTLINK" | awk 'BEGIN {IGNORECASE=1;} /content-length/ {sub(/[ \t\r\n]+$/, "", $2); print $2}')"
[[ "$LISTSIZE" != "$(stat -c '%s' temp/list_orig.csv)" ]] && echo "List 1 size differs" && exit 2
LISTSIZE="$(curl -sI "$NXDOMAINLINK" | awk 'BEGIN {IGNORECASE=1;} /content-length/ {sub(/[ \t\r\n]+$/, "", $2); print $2}')"
[[ "$LISTSIZE" != "$(stat -c '%s' temp/nxdomain.txt)" ]] && echo "List 2 size differs" && exit 2

exit 0
