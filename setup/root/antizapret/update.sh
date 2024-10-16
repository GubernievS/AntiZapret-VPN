#!/bin/bash
set -e

HERE="$(dirname "$(readlink -f "${0}")")"
cd "$HERE"

echo "Update antizapret files"

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

INCLUDE_IPS_LINK="https://raw.githubusercontent.com/GubernievS/AntiZapret-VPN/main/setup/root/antizapret/config/include-ips-dist.txt"
INCLUDE_IPS_PATH="config/include-ips-dist.txt"

PARSE_LINK="https://raw.githubusercontent.com/GubernievS/AntiZapret-VPN/main/setup/root/antizapret/parse.sh"
PARSE_PATH="parse.sh"

DOALL_LINK="https://raw.githubusercontent.com/GubernievS/AntiZapret-VPN/main/setup/root/antizapret/doall.sh"
DOALL_PATH="doall.sh"

UPDATE_LINK="https://raw.githubusercontent.com/GubernievS/AntiZapret-VPN/main/setup/root/antizapret/update.sh"
UPDATE_PATH="update.sh"

echo "Downloading: $DUMP_PATH"
curl -f --retry 3 --retry-delay 30 --retry-all-errors --compressed -o $DUMP_PATH $DUMP_LINK
iconv -f cp1251 -t utf8 $DUMP_PATH > temp/list.csv

echo "Downloading: $NXDOMAIN_PATH"
curl -f --retry 3 --retry-delay 30 --retry-all-errors --compressed -o $NXDOMAIN_PATH $NXDOMAIN_LINK

echo "Downloading: $EXCLUDE_HOSTS_PATH"
curl -f --retry 3 --retry-delay 30 --retry-all-errors --compressed -o $EXCLUDE_HOSTS_PATH $EXCLUDE_HOSTS_LINK

echo "Downloading: $EXCLUDE_REGEXP_PATH"
curl -f --retry 3 --retry-delay 30 --retry-all-errors --compressed -o $EXCLUDE_REGEXP_PATH $EXCLUDE_REGEXP_LINK

echo "Downloading: $INCLUDE_HOSTS_PATH"
curl -f --retry 3 --retry-delay 30 --retry-all-errors --compressed -o $INCLUDE_HOSTS_PATH $INCLUDE_HOSTS_LINK

echo "Downloading: $INCLUDE_IPS_PATH"
curl -f --retry 3 --retry-delay 30 --retry-all-errors --compressed -o $INCLUDE_IPS_PATH $INCLUDE_IPS_LINK

echo "Downloading: $PARSE_PATH"
curl -f --retry 3 --retry-delay 30 --retry-all-errors --compressed -o $PARSE_PATH $PARSE_LINK

echo "Downloading: $DOALL_PATH"
curl -f --retry 3 --retry-delay 30 --retry-all-errors --compressed -o $DOALL_PATH $DOALL_LINK

echo "Downloading: $UPDATE_PATH"
curl -f --retry 3 --retry-delay 30 --retry-all-errors --compressed -o $UPDATE_PATH $UPDATE_LINK

exit 0