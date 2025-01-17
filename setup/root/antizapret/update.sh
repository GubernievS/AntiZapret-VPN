#!/bin/bash
set -e

HERE="$(dirname "$(readlink -f "${0}")")"
cd "$HERE"

echo "Update AntiZapret VPN files:"

rm -f download/*

UPDATE_LINK="https://raw.githubusercontent.com/GubernievS/AntiZapret-VPN/main/setup/root/antizapret/update.sh"
UPDATE_PATH="update.sh"

PARSE_LINK="https://raw.githubusercontent.com/GubernievS/AntiZapret-VPN/main/setup/root/antizapret/parse.sh"
PARSE_PATH="parse.sh"

DOALL_LINK="https://raw.githubusercontent.com/GubernievS/AntiZapret-VPN/main/setup/root/antizapret/doall.sh"
DOALL_PATH="doall.sh"

DUMP_LINK="https://raw.githubusercontent.com/zapret-info/z-i/master/dump.csv.gz"
DUMP_PATH="download/dump.csv.gz"

NXDOMAIN_LINK="https://raw.githubusercontent.com/zapret-info/z-i/master/nxdomain.txt"
NXDOMAIN_PATH="download/nxdomain.txt"

INCLUDE_HOSTS_LINK="https://raw.githubusercontent.com/GubernievS/AntiZapret-VPN/main/setup/root/antizapret/download/include-hosts.txt"
INCLUDE_HOSTS_PATH="download/include-hosts.txt"

INCLUDE_IPS_LINK="https://raw.githubusercontent.com/GubernievS/AntiZapret-VPN/main/setup/root/antizapret/download/include-ips.txt"
INCLUDE_IPS_PATH="download/include-ips.txt"

ADGUARD_LINK="https://adguardteam.github.io/AdGuardSDNSFilter/Filters/filter.txt"
ADGUARD_PATH="download/adguard.txt"

ADAWAY_LINK="https://raw.githubusercontent.com/AdAway/adaway.github.io/master/hosts.txt"
ADAWAY_PATH="download/adaway.txt"

function download {
	local path="${HERE}/${1}"
	local link=$2
	local min_size_mb=$3
	echo "$path"
	curl -fL "$link" -o "download/temp"
	local_size="$(stat -c '%s' "download/temp")"
	remote_size="$(curl -fsSLI "$link" | grep -i content-length | cut -d ':' -f 2 | sed 's/[[:space:]]//g')"
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
download $DUMP_PATH $DUMP_LINK 16
download $NXDOMAIN_PATH $NXDOMAIN_LINK 2
download $INCLUDE_HOSTS_PATH $INCLUDE_HOSTS_LINK
download $INCLUDE_IPS_PATH $INCLUDE_IPS_LINK
download $ADGUARD_PATH $ADGUARD_LINK
download $ADAWAY_PATH $ADAWAY_LINK

gunzip -f "$DUMP_PATH" || { echo "Error unpacking $DUMP_PATH"; exit 3; }

exit 0