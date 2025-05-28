#!/bin/bash
set -e

echo "Update AntiZapret VPN files:"

rm -f /root/antizapret/download/*

UPDATE_LINK="https://raw.githubusercontent.com/GubernievS/AntiZapret-VPN/main/setup/root/antizapret/update.sh"
UPDATE_PATH="update.sh"

PARSE_LINK="https://raw.githubusercontent.com/GubernievS/AntiZapret-VPN/main/setup/root/antizapret/parse.sh"
PARSE_PATH="parse.sh"

DOALL_LINK="https://raw.githubusercontent.com/GubernievS/AntiZapret-VPN/main/setup/root/antizapret/doall.sh"
DOALL_PATH="doall.sh"

HOSTS_LINK_1="https://raw.githubusercontent.com/zapret-info/z-i/master/dump.csv.gz"
HOSTS_PATH_1="download/dump.csv.gz"
#HOSTS_LINK_1="https://svn.code.sf.net/p/zapret-info/code/dump.csv"
#HOSTS_PATH_1="download/dump.csv"

HOSTS_LINK_2="https://antifilter.download/list/domains.lst"
HOSTS_PATH_2="download/domains.lst"

NXDOMAIN_LINK="https://raw.githubusercontent.com/zapret-info/z-i/master/nxdomain.txt"
#NXDOMAIN_LINK="https://svn.code.sf.net/p/zapret-info/code/nxdomain.txt"
NXDOMAIN_PATH="download/nxdomain.txt"

INCLUDE_HOSTS_LINK="https://raw.githubusercontent.com/GubernievS/AntiZapret-VPN/main/setup/root/antizapret/download/include-hosts.txt"
INCLUDE_HOSTS_PATH="download/include-hosts.txt"

EXCLUDE_HOSTS_LINK="https://raw.githubusercontent.com/GubernievS/AntiZapret-VPN/main/setup/root/antizapret/download/exclude-hosts.txt"
EXCLUDE_HOSTS_PATH="download/exclude-hosts.txt"

INCLUDE_IPS_LINK="https://raw.githubusercontent.com/GubernievS/AntiZapret-VPN/main/setup/root/antizapret/download/include-ips.txt"
INCLUDE_IPS_PATH="download/include-ips.txt"

RPZ_LINK="https://raw.githubusercontent.com/GubernievS/AntiZapret-VPN/main/setup/root/antizapret/download/rpz.txt"
RPZ_PATH="download/rpz.txt"

INCLUDE_ADBLOCK_HOSTS_LINK="https://raw.githubusercontent.com/GubernievS/AntiZapret-VPN/main/setup/root/antizapret/download/include-adblock-hosts.txt"
INCLUDE_ADBLOCK_HOSTS_PATH="download/include-adblock-hosts.txt"

EXCLUDE_ADBLOCK_HOSTS_LINK="https://raw.githubusercontent.com/GubernievS/AntiZapret-VPN/main/setup/root/antizapret/download/exclude-adblock-hosts.txt"
EXCLUDE_ADBLOCK_HOSTS_PATH="download/exclude-adblock-hosts.txt"

ADGUARD_LINK="https://adguardteam.github.io/AdGuardSDNSFilter/Filters/filter.txt"
ADGUARD_PATH="download/adguard.txt"

ADAWAY_LINK="https://raw.githubusercontent.com/AdAway/adaway.github.io/master/hosts.txt"
ADAWAY_PATH="download/adaway.txt"

function download {
	local path="/root/antizapret/${1}"
	local tmp_path="${path}.tmp"
	local link=$2
	echo "$path"
	curl -fL "$link" -o "$tmp_path"
	local_size="$(stat -c '%s' "$tmp_path")"
	remote_size="$(curl -fsSLI "$link" | grep -i content-length | cut -d ':' -f 2 | sed 's/[[:space:]]//g')"
	if [[ "$local_size" != "$remote_size" ]]; then
		echo "Failed to download $path! Size on server is different"
		rm -f "$tmp_path"
		exit 1
	fi
	mv -f "$tmp_path" "$path"
	if [[ "$path" == *.sh ]]; then
		chmod +x "$path"
	elif [[ "$path" == *.gz ]]; then
		gunzip -f "$path" || > "${path%.gz}"
	fi
}

download $UPDATE_PATH $UPDATE_LINK
download $PARSE_PATH $PARSE_LINK
download $DOALL_PATH $DOALL_LINK
download $HOSTS_PATH_1 $HOSTS_LINK_1
download $HOSTS_PATH_2 $HOSTS_LINK_2
download $NXDOMAIN_PATH $NXDOMAIN_LINK
download $INCLUDE_HOSTS_PATH $INCLUDE_HOSTS_LINK
download $EXCLUDE_HOSTS_PATH $EXCLUDE_HOSTS_LINK
download $INCLUDE_IPS_PATH $INCLUDE_IPS_LINK
download $RPZ_PATH $RPZ_LINK

source /root/antizapret/setup

if [ "$ANTIZAPRET_ADBLOCK" = "y" ]; then
	download $INCLUDE_ADBLOCK_HOSTS_PATH $INCLUDE_ADBLOCK_HOSTS_LINK
	download $EXCLUDE_ADBLOCK_HOSTS_PATH $EXCLUDE_ADBLOCK_HOSTS_LINK
	download $ADGUARD_PATH $ADGUARD_LINK
	download $ADAWAY_PATH $ADAWAY_LINK
else
	> /root/antizapret/$INCLUDE_ADBLOCK_HOSTS_PATH
	> /root/antizapret/$EXCLUDE_ADBLOCK_HOSTS_PATH
	> /root/antizapret/$ADGUARD_PATH
	> /root/antizapret/$ADAWAY_PATH
fi

###

sed -i 's/adblock-hosts\.rpz/deny.rpz/g' /etc/knot-resolver/kresd.conf
sed -i 's/hosts\.rpz/proxy.rpz/g' /etc/knot-resolver/kresd.conf
cp /etc/knot-resolver/adblock-hosts.rpz /etc/knot-resolver/deny.rpz 2>/dev/null || true
cp /etc/knot-resolver/hosts.rpz /etc/knot-resolver/proxy.rpz 2>/dev/null || true
systemctl restart kresd@*
rm -f /etc/knot-resolver/adblock-hosts.rpz
rm -f /etc/knot-resolver/hosts.rpz

###

exit 0