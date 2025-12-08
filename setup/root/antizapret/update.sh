#!/bin/bash
set -e

# Обработка ошибок
handle_error() {
	echo "$(lsb_release -ds) $(uname -r) $(date --iso-8601=seconds)"
	echo -e "\e[1;31mError at line $1: $2\e[0m"
	exit 1
}
trap 'handle_error $LINENO "$BASH_COMMAND"' ERR

if [[ -n "$1" && "$1" != "ip" && "$1" != "ips" && "$1" != "host" && "$1" != "hosts" && "$1" != "noclear" && "$1" != "noclean" ]]; then
	echo "Ignored invalid parameter: $1"
	set -- ""
fi

echo 'Update AntiZapret VPN files:'

cd /root/antizapret

export LC_ALL=C

rm -f download/*

UPDATE_LINK="https://raw.githubusercontent.com/GubernievS/AntiZapret-VPN/main/setup/root/antizapret/update.sh"
UPDATE_PATH="update.sh"

PARSE_LINK="https://raw.githubusercontent.com/GubernievS/AntiZapret-VPN/main/setup/root/antizapret/parse.sh"
PARSE_PATH="parse.sh"

DOALL_LINK="https://raw.githubusercontent.com/GubernievS/AntiZapret-VPN/main/setup/root/antizapret/doall.sh"
DOALL_PATH="doall.sh"

DOMAIN_LINK="https://antifilter.download/list/domains.lst"
DOMAIN_PATH="download/domain.txt"

DOMAIN2_LINK="https://community.antifilter.download/list/domains.lst"
DOMAIN2_PATH="download/domain-2.txt"

RPZ_LINK="https://raw.githubusercontent.com/GubernievS/AntiZapret-VPN/main/setup/root/antizapret/download/rpz.txt"
RPZ_PATH="download/rpz.txt"

RPZ2_LINK="https://raw.githubusercontent.com/GubernievS/AntiZapret-VPN/main/setup/root/antizapret/download/rpz2.txt"
RPZ2_PATH="download/rpz2.txt"

INCLUDE_HOSTS_LINK="https://raw.githubusercontent.com/GubernievS/AntiZapret-VPN/main/setup/root/antizapret/download/include-hosts.txt"
INCLUDE_HOSTS_PATH="download/include-hosts.txt"

EXCLUDE_HOSTS_LINK="https://raw.githubusercontent.com/GubernievS/AntiZapret-VPN/main/setup/root/antizapret/download/exclude-hosts.txt"
EXCLUDE_HOSTS_PATH="download/exclude-hosts.txt"

REMOVE_HOSTS_LINK="https://raw.githubusercontent.com/GubernievS/AntiZapret-VPN/main/setup/root/antizapret/download/remove-hosts.txt.gz"
REMOVE_HOSTS_PATH="download/remove-hosts.txt"

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

WHATSAPP_IPS_LINK="https://raw.githubusercontent.com/GubernievS/AntiZapret-VPN/main/setup/root/antizapret/download/whatsapp-ips.txt"
WHATSAPP_IPS_PATH="download/whatsapp-ips.txt"

ROBLOX_IPS_LINK="https://raw.githubusercontent.com/GubernievS/AntiZapret-VPN/main/setup/root/antizapret/download/roblox-ips.txt"
ROBLOX_IPS_PATH="download/roblox-ips.txt"

function download {
	local path="${1}"
	local tmp_path="${path}.tmp"
	local link="$2"
	echo "$path"
	curl -fL "$link" -o "$tmp_path" || exit 2
	local_size="$(stat -c '%s' "$tmp_path")"
	header="$(curl -fsSLI "$link")" || exit 3
	remote_size="$(echo "$header" | grep -i content-length | cut -d ':' -f 2 | sed 's/[[:space:]]//g')"
	if [[ "$local_size" != "$remote_size" ]]; then
		echo "Failed to download $path! Size on server is different"
		rm -f "$tmp_path"
		exit 4
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

source setup

if [[ -z "$1" || "$1" == "host" || "$1" == "hosts" || "$1" == "noclear" || "$1" == "noclean" ]]; then
	download "$DOMAIN_PATH" "$DOMAIN_LINK"
	download "$DOMAIN2_PATH" "$DOMAIN2_LINK"
	download $RPZ_PATH $RPZ_LINK
	download $RPZ2_PATH $RPZ2_LINK
	download $INCLUDE_HOSTS_PATH $INCLUDE_HOSTS_LINK
	download $REMOVE_HOSTS_PATH $REMOVE_HOSTS_LINK

	if [[ "$ROUTE_ALL" = "y" ]]; then
		download $EXCLUDE_HOSTS_PATH $EXCLUDE_HOSTS_LINK
	else
		printf '# НЕ РЕДАКТИРУЙТЕ ЭТОТ ФАЙЛ!' > $EXCLUDE_HOSTS_PATH
	fi

	if [[ "$BLOCK_ADS" = "y" ]]; then
		download $INCLUDE_ADBLOCK_HOSTS_PATH $INCLUDE_ADBLOCK_HOSTS_LINK
		download $EXCLUDE_ADBLOCK_HOSTS_PATH $EXCLUDE_ADBLOCK_HOSTS_LINK
		download $ADGUARD_PATH $ADGUARD_LINK
		download $OISD_PATH $OISD_LINK
	else
		> $INCLUDE_ADBLOCK_HOSTS_PATH
		> $EXCLUDE_ADBLOCK_HOSTS_PATH
		> $ADGUARD_PATH
		> $OISD_PATH
	fi
fi

if [[ -z "$1" || "$1" == "ip" || "$1" == "ips" || "$1" == "noclear" || "$1" == "noclean" ]]; then
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

	if [[ "$WHATSAPP_INCLUDE" = "y" ]]; then
		download $WHATSAPP_IPS_PATH $WHATSAPP_IPS_LINK
	fi

	if [[ "$ROBLOX_INCLUDE" = "y" ]]; then
		download $ROBLOX_IPS_PATH $ROBLOX_IPS_LINK
	fi
fi

./custom-update.sh "$1" || true

exit 0