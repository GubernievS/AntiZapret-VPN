#!/bin/bash
set -e

# Обработка ошибок
handle_error() {
	echo "$(lsb_release -ds) $(uname -r) $(date --iso-8601=seconds)"
	echo -e "\e[1;31mError at line $1: $2\e[0m"
	exit 1
}
trap 'handle_error $LINENO "$BASH_COMMAND"' ERR

echo "Update AntiZapret VPN files:"

export LC_ALL=C

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

RPZ_LINK="https://raw.githubusercontent.com/GubernievS/AntiZapret-VPN/main/setup/root/antizapret/download/rpz.txt"
RPZ_PATH="download/rpz.txt"

INCLUDE_HOSTS_LINK="https://raw.githubusercontent.com/GubernievS/AntiZapret-VPN/main/setup/root/antizapret/download/include-hosts.txt"
INCLUDE_HOSTS_PATH="download/include-hosts.txt"

EXCLUDE_HOSTS_LINK="https://raw.githubusercontent.com/GubernievS/AntiZapret-VPN/main/setup/root/antizapret/download/exclude-hosts.txt"
EXCLUDE_HOSTS_PATH="download/exclude-hosts.txt"

INCLUDE_ADBLOCK_HOSTS_LINK="https://raw.githubusercontent.com/GubernievS/AntiZapret-VPN/main/setup/root/antizapret/download/include-adblock-hosts.txt"
INCLUDE_ADBLOCK_HOSTS_PATH="download/include-adblock-hosts.txt"

EXCLUDE_ADBLOCK_HOSTS_LINK="https://raw.githubusercontent.com/GubernievS/AntiZapret-VPN/main/setup/root/antizapret/download/exclude-adblock-hosts.txt"
EXCLUDE_ADBLOCK_HOSTS_PATH="download/exclude-adblock-hosts.txt"

ADGUARD_LINK="https://adguardteam.github.io/AdGuardSDNSFilter/Filters/filter.txt"
ADGUARD_PATH="download/adguard.txt"

OISD_LINK="https://raw.githubusercontent.com/sjhgvr/oisd/refs/heads/main/domainswild2_small.txt"
OISD_PATH="download/oisd.txt"

DISCORD_IPS_LINK="https://raw.githubusercontent.com/GubernievS/AntiZapret-VPN/main/setup/root/antizapret/download/discord-ips.txt"
DISCORD_IPS_PATH="download/discord-ips.txt"

CLOUDFLARE_IPS_LINK="https://raw.githubusercontent.com/GubernievS/AntiZapret-VPN/main/setup/root/antizapret/download/cloudflare-ips.txt"
CLOUDFLARE_IPS_PATH="download/cloudflare-ips.txt"

AMAZON_IPS_LINK="https://raw.githubusercontent.com/GubernievS/AntiZapret-VPN/main/setup/root/antizapret/download/amazon-ips.txt"
AMAZON_IPS_PATH="download/amazon-ips.txt"

HETZNER_IPS_LINK="https://raw.githubusercontent.com/GubernievS/AntiZapret-VPN/main/setup/root/antizapret/download/hetzner-ips.txt"
HETZNER_IPS_PATH="download/hetzner-ips.txt"

DIGITALOCEAN_IPS_LINK="https://raw.githubusercontent.com/GubernievS/AntiZapret-VPN/main/setup/root/antizapret/download/digitalocean-ips.txt"
DIGITALOCEAN_IPS_PATH="download/digitalocean-ips.txt"

OVH_IPS_LINK="https://raw.githubusercontent.com/GubernievS/AntiZapret-VPN/main/setup/root/antizapret/download/ovh-ips.txt"
OVH_IPS_PATH="download/ovh-ips.txt"

TELEGRAM_IPS_LINK="https://raw.githubusercontent.com/GubernievS/AntiZapret-VPN/main/setup/root/antizapret/download/telegram-ips.txt"
TELEGRAM_IPS_PATH="download/telegram-ips.txt"

GOOGLE_IPS_LINK="https://raw.githubusercontent.com/GubernievS/AntiZapret-VPN/main/setup/root/antizapret/download/google-ips.txt"
GOOGLE_IPS_PATH="download/google-ips.txt"

AKAMAI_IPS_LINK="https://raw.githubusercontent.com/GubernievS/AntiZapret-VPN/main/setup/root/antizapret/download/akamai-ips.txt"
AKAMAI_IPS_PATH="download/akamai-ips.txt"

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
		exit 2
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

source /root/antizapret/setup

if [[ -z "$1" || "$1" == "host" || "$1" == "hosts" ]]; then
	download $HOSTS_PATH_1 $HOSTS_LINK_1
	( download "$HOSTS_PATH_2" "$HOSTS_LINK_2" ) || > "$HOSTS_PATH_2"
	download $NXDOMAIN_PATH $NXDOMAIN_LINK
	download $RPZ_PATH $RPZ_LINK
	download $INCLUDE_HOSTS_PATH $INCLUDE_HOSTS_LINK

	if [[ "$ROUTE_ALL" = "y" ]]; then
		download $EXCLUDE_HOSTS_PATH $EXCLUDE_HOSTS_LINK
	else
		printf '# НЕ РЕДАКТИРУЙТЕ ЭТОТ ФАЙЛ!' > /root/antizapret/$EXCLUDE_HOSTS_PATH
	fi

	if [[ "$BLOCK_ADS" = "y" ]]; then
		download $INCLUDE_ADBLOCK_HOSTS_PATH $INCLUDE_ADBLOCK_HOSTS_LINK
		download $EXCLUDE_ADBLOCK_HOSTS_PATH $EXCLUDE_ADBLOCK_HOSTS_LINK
		download $ADGUARD_PATH $ADGUARD_LINK
		download $OISD_PATH $OISD_LINK
	else
		> /root/antizapret/$INCLUDE_ADBLOCK_HOSTS_PATH
		> /root/antizapret/$EXCLUDE_ADBLOCK_HOSTS_PATH
		> /root/antizapret/$ADGUARD_PATH
		> /root/antizapret/$OISD_PATH
	fi
fi

if [[ -z "$1" || "$1" == "ip" || "$1" == "ips" ]]; then
	if [[ "$DISCORD_INCLUDE" = "y" ]]; then
		download $DISCORD_IPS_PATH $DISCORD_IPS_LINK
	fi

	if [[ "$CLOUDFLARE_INCLUDE" = "y" ]]; then
		download $CLOUDFLARE_IPS_PATH $CLOUDFLARE_IPS_LINK
	fi

	if [[ "$AMAZON_INCLUDE" = "y" ]]; then
		download $AMAZON_IPS_PATH $AMAZON_IPS_LINK
	fi

	if [[ "$HETZNER_INCLUDE" = "y" ]]; then
		download $HETZNER_IPS_PATH $HETZNER_IPS_LINK
	fi

	if [[ "$DIGITALOCEAN_INCLUDE" = "y" ]]; then
		download $DIGITALOCEAN_IPS_PATH $DIGITALOCEAN_IPS_LINK
	fi

	if [[ "$OVH_INCLUDE" = "y" ]]; then
		download $OVH_IPS_PATH $OVH_IPS_LINK
	fi

	if [[ "$TELEGRAM_INCLUDE" = "y" ]]; then
		download $TELEGRAM_IPS_PATH $TELEGRAM_IPS_LINK
	fi

	if [[ "$GOOGLE_INCLUDE" = "y" ]]; then
		download $GOOGLE_IPS_PATH $GOOGLE_IPS_LINK
	fi

	if [[ "$AKAMAI_INCLUDE" = "y" ]]; then
		download $AKAMAI_IPS_PATH $AKAMAI_IPS_LINK
	fi
fi

exit 0