#!/bin/bash
set -e

HERE="$(dirname "$(readlink -f "${0}")")"
cd "$HERE"

rm -f temp/*

DUMP_LINK='https://raw.githubusercontent.com/zapret-info/z-i/master/dump.csv'
DUMP_PATH='temp/dump.csv'

NXDOMAIN_LINK='https://raw.githubusercontent.com/zapret-info/z-i/master/nxdomain.txt'
NXDOMAIN_PATH='temp/nxdomain.txt'

EXCLUDE_HOSTS_LINK='https://raw.githubusercontent.com/GubernievS/AntiZapret-VPN/main/setup/root/antizapret/config/exclude-hosts-dist.txt'
EXCLUDE_HOSTS_PATH='config/exclude-hosts-dist.txt'

EXCLUDE_REGEXP_LINK='https://raw.githubusercontent.com/GubernievS/AntiZapret-VPN/main/setup/root/antizapret/config/exclude-regexp-dist.awk'
EXCLUDE_REGEXP_PATH='config/exclude-regexp-dist.awk'

INCLUDE_HOSTS_LINK='https://raw.githubusercontent.com/GubernievS/AntiZapret-VPN/main/setup/root/antizapret/config/include-hosts-dist.txt'
INCLUDE_HOSTS_PATH='config/include-hosts-dist.txt'

curl -f --fail-early --compressed -o $DUMP_PATH $DUMP_LINK || exit 1
curl -f --fail-early --compressed -o $NXDOMAIN_PATH $NXDOMAIN_LINK || exit 1
curl -f --fail-early --compressed -o $EXCLUDE_HOSTS_PATH $EXCLUDE_HOSTS_LINK || exit 1
curl -f --fail-early --compressed -o $EXCLUDE_REGEXP_PATH $EXCLUDE_REGEXP_LINK || exit 1
curl -f --fail-early --compressed -o $INCLUDE_HOSTS_PATH $INCLUDE_HOSTS_LINK || exit 1

SIZE="$(curl -sI "$DUMP_LINK" | awk 'BEGIN {IGNORECASE=1;} /content-length/ {sub(/[ \t\r\n]+$/, "", $2); print $2}')"
[[ "$SIZE" != "$(stat -c '%s' $DUMP_PATH)" ]] && echo "$DUMP_PATH size differs" && exit 2

SIZE="$(curl -sI "$NXDOMAIN_LINK" | awk 'BEGIN {IGNORECASE=1;} /content-length/ {sub(/[ \t\r\n]+$/, "", $2); print $2}')"
[[ "$SIZE" != "$(stat -c '%s' $NXDOMAIN_PATH)" ]] && echo "$NXDOMAIN_PATH size differs" && exit 2

SIZE="$(curl -sI "$EXCLUDE_HOSTS_LINK" | awk 'BEGIN {IGNORECASE=1;} /content-length/ {sub(/[ \t\r\n]+$/, "", $2); print $2}')"
[[ "$SIZE" != "$(stat -c '%s' $EXCLUDE_HOSTS_PATH)" ]] && echo "$EXCLUDE_HOSTS_PATH size differs" && exit 2

SIZE="$(curl -sI "$EXCLUDE_REGEXP_LINK" | awk 'BEGIN {IGNORECASE=1;} /content-length/ {sub(/[ \t\r\n]+$/, "", $2); print $2}')"
[[ "$SIZE" != "$(stat -c '%s' $EXCLUDE_REGEXP_PATH)" ]] && echo "$EXCLUDE_REGEXP_PATH size differs" && exit 2

SIZE="$(curl -sI "$INCLUDE_HOSTS_LINK" | awk 'BEGIN {IGNORECASE=1;} /content-length/ {sub(/[ \t\r\n]+$/, "", $2); print $2}')"
[[ "$SIZE" != "$(stat -c '%s' $INCLUDE_HOSTS_PATH)" ]] && echo "$INCLUDE_HOSTS_PATH size differs" && exit 2

iconv -f cp1251 -t utf8 temp/dump.csv > temp/list.csv

exit 0