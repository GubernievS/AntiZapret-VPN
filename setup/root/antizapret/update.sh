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

EXCLUDE_IPS_LINK="https://raw.githubusercontent.com/GubernievS/AntiZapret-VPN/main/setup/root/antizapret/config/exclude-ips-dist.txt"
EXCLUDE_IPS_PATH="config/exclude-ips-dist.txt"

INCLUDE_IPS_LINK="https://raw.githubusercontent.com/GubernievS/AntiZapret-VPN/main/setup/root/antizapret/config/include-ips-dist.txt"
INCLUDE_IPS_PATH="config/include-ips-dist.txt"

PARSE_LINK="https://raw.githubusercontent.com/GubernievS/AntiZapret-VPN/main/setup/root/antizapret/parse.sh"
PARSE_PATH="parse.sh"

DOALL_LINK="https://raw.githubusercontent.com/GubernievS/AntiZapret-VPN/main/setup/root/antizapret/doall.sh"
DOALL_PATH="doall.sh"

UPDATE_LINK="https://raw.githubusercontent.com/GubernievS/AntiZapret-VPN/main/setup/root/antizapret/update.sh"
UPDATE_PATH="update.sh"

function download {
	local path=$1
	local link=$2
	echo "Downloading: $path"
	curl -fL "$link" -o "$path.tmp"
	size1="$(stat -c '%s' "$path.tmp")"
	size2="$(curl -fsSLI "$link" | grep -i Content-Length | cut -d ':' -f 2 | sed 's/[[:space:]]//g')"
	if [[ "$size1" != "$size2" ]]; then
		echo "Failed to download $path! Size differs"
		exit 1
	fi
	mv "$path.tmp" "$path"
	if [[ "$path" == *.sh ]]; then
		chmod +x "$path"
	fi
}

download $DUMP_PATH $DUMP_LINK
download $NXDOMAIN_PATH $NXDOMAIN_LINK
download $EXCLUDE_HOSTS_PATH $EXCLUDE_HOSTS_LINK
download $EXCLUDE_REGEXP_PATH $EXCLUDE_REGEXP_LINK
download $INCLUDE_HOSTS_PATH $INCLUDE_HOSTS_LINK
download $INCLUDE_IPS_PATH $INCLUDE_IPS_LINK
download $EXCLUDE_IPS_PATH $EXCLUDE_IPS_LINK
download $PARSE_PATH $PARSE_LINK
download $DOALL_PATH $DOALL_LINK
download $UPDATE_PATH $UPDATE_LINK

iconv -f cp1251 -t utf8 $DUMP_PATH > temp/list.csv

exit 0