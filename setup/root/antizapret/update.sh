#!/bin/bash
set -e

HERE="$(dirname "$(readlink -f "${0}")")"
cd "$HERE"

rm -f temp/*

DUMP_LINK="https://raw.githubusercontent.com/zapret-info/z-i/master/dump.csv"
DUMP_PATH="temp/dump.csv"

NXDOMAIN_LINK="https://raw.githubusercontent.com/zapret-info/z-i/master/nxdomain.txt"
NXDOMAIN_PATH="temp/nxdomain.txt"

EXCLUDE_HOSTS_LINK="https://raw.githubusercontent.com/GubernievS/AntiZapret-VPN/main/setup/root/antizapret/config/exclude-hosts-dist.txt"
EXCLUDE_HOSTS_PATH="config/exclude-hosts-dist.txt"

EXCLUDE_REGEXP_LINK="https://raw.githubusercontent.com/GubernievS/AntiZapret-VPN/main/setup/root/antizapret/config/exclude-regexp-dist.awk"
EXCLUDE_REGEXP_PATH="config/exclude-regexp-dist.awk"

INCLUDE_HOSTS_LINK="https://raw.githubusercontent.com/GubernievS/AntiZapret-VPN/main/setup/root/antizapret/config/include-hosts-dist.txt"
INCLUDE_HOSTS_PATH="config/include-hosts-dist.txt"

PARSE_LINK="https://raw.githubusercontent.com/GubernievS/AntiZapret-VPN/main/setup/root/antizapret/parse.sh"
PARSE_PATH="parse.sh"

UPDATE_LINK="https://raw.githubusercontent.com/GubernievS/AntiZapret-VPN/main/setup/root/antizapret/update.sh"
UPDATE_PATH="update.sh"

curl -f --retry 3 --retry-delay 30 --retry-all-errors --compressed -o $DUMP_PATH $DUMP_LINK
iconv -f cp1251 -t utf8 $DUMP_PATH > temp/list.csv
curl -f --retry 3 --retry-delay 30 --retry-all-errors --compressed -o $NXDOMAIN_PATH $NXDOMAIN_LINK
curl -f --retry 3 --retry-delay 30 --retry-all-errors --compressed -o $EXCLUDE_HOSTS_PATH $EXCLUDE_HOSTS_LINK
curl -f --retry 3 --retry-delay 30 --retry-all-errors --compressed -o $EXCLUDE_REGEXP_PATH $EXCLUDE_REGEXP_LINK
curl -f --retry 3 --retry-delay 30 --retry-all-errors --compressed -o $INCLUDE_HOSTS_PATH $INCLUDE_HOSTS_LINK
curl -f --retry 3 --retry-delay 30 --retry-all-errors --compressed -o $PARSE_PATH $PARSE_LINK
# Запустим в фоновом режиме
curl -f --retry 3 --retry-delay 30 --retry-all-errors --compressed -o $UPDATE_PATH $UPDATE_LINK &

exit 0