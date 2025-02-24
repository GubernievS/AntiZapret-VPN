#!/bin/bash
set -e

HERE="$(dirname "$(readlink -f "${0}")")"
cd "$HERE"

echo "Update antizapret files:"

rm -f download/*

UPDATE_LINK="https://raw.githubusercontent.com/GubernievS/AntiZapret-VPN/main/legacy/update.sh"
UPDATE_PATH="update.sh"

PARSE_LINK="https://raw.githubusercontent.com/GubernievS/AntiZapret-VPN/main/legacy/parse.sh"
PARSE_PATH="parse.sh"

DOALL_LINK="https://raw.githubusercontent.com/GubernievS/AntiZapret-VPN/main/legacy/doall.sh"
DOALL_PATH="doall.sh"

DUMP_LINK="https://raw.githubusercontent.com/zapret-info/z-i/master/dump.csv.gz"
DUMP_PATH="download/dump.csv.gz"

NXDOMAIN_LINK="https://raw.githubusercontent.com/zapret-info/z-i/master/nxdomain.txt"
NXDOMAIN_PATH="download/nxdomain.txt"

EXCLUDE_HOSTS_AWK_LINK="https://raw.githubusercontent.com/GubernievS/AntiZapret-VPN/main/legacy/exclude-hosts.awk"
EXCLUDE_HOSTS_AWK_PATH="download/exclude-hosts.awk"

INCLUDE_HOSTS_LINK="https://raw.githubusercontent.com/GubernievS/AntiZapret-VPN/main/setup/root/antizapret/download/include-hosts.txt"
INCLUDE_HOSTS_PATH="download/include-hosts.txt"

INCLUDE_IPS_LINK="https://raw.githubusercontent.com/GubernievS/AntiZapret-VPN/main/setup/root/antizapret/download/include-ips.txt"
INCLUDE_IPS_PATH="download/include-ips.txt"

ADBLOCK_LINK="https://adguardteam.github.io/AdGuardSDNSFilter/Filters/filter.txt"
ADBLOCK_PATH="download/adblock-hosts.txt"

function download {
	local path="${HERE}/${1}"
	local link=$2
	local min_size_mb=$3
	echo "$path"
	curl -fL "$link" -o "download/temp"
	local_size="$(stat -c '%s' "download/temp")"
	remote_size="$(curl -fsSLI "$link" | grep -i Content-Length | cut -d ':' -f 2 | sed 's/[[:space:]]//g')"
	if [[ "$local_size" != "$remote_size" ]]; then
		echo "Failed to download $path! Size on server is different"
		exit 1
	fi
	if [[ -n "$min_size_mb" ]]; then
		min_size=$((min_size_mb * 1024 * 1024))
		if [[ "$local_size" -lt "$min_size" ]]; then
			echo "Failed to download $path! File size is less than ${min_size_mb} MB"
			exit 2
		fi
	fi
	mv -f "download/temp" "$path"
	if [[ "$path" == *.sh ]]; then
		chmod +x "$path"
	fi
}

download $UPDATE_PATH $UPDATE_LINK
download $PARSE_PATH $PARSE_LINK
download $DOALL_PATH $DOALL_LINK
download $DUMP_PATH $DUMP_LINK 15
download $NXDOMAIN_PATH $NXDOMAIN_LINK 2
download $EXCLUDE_HOSTS_AWK_PATH $EXCLUDE_HOSTS_AWK_LINK
download $INCLUDE_HOSTS_PATH $INCLUDE_HOSTS_LINK
download $INCLUDE_IPS_PATH $INCLUDE_IPS_LINK
download $ADBLOCK_PATH $ADBLOCK_LINK

gunzip -f "$DUMP_PATH"

exit 0