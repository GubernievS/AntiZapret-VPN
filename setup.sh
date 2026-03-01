#!/bin/bash
#
# Скрипт для установки на своём сервере AntiZapret VPN + полный VPN
#
# https://github.com/GubernievS/AntiZapret-VPN
#

export LC_ALL=C

# Проверка необходимости перезагрузить
if [[ -f /var/run/reboot-required ]] || pidof apt apt-get dpkg unattended-upgrades >/dev/null 2>&1; then
	echo 'Error: You need to reboot this server before installation!'
	exit 2
fi

# Проверка прав root
if [[ "$EUID" -ne 0 ]]; then
	echo 'Error: You need to run this as root!'
	exit 3
fi

cd /root

# Проверка на OpenVZ и LXC
if [[ "$(systemd-detect-virt)" == 'openvz' || "$(systemd-detect-virt)" == 'lxc' ]]; then
	echo 'Error: OpenVZ and LXC are not supported!'
	exit 4
fi

# Проверка версии системы
OS="$(lsb_release -si | tr '[:upper:]' '[:lower:]')"
VERSION="$(lsb_release -rs | cut -d '.' -f1)"

if [[ "$OS" == 'debian' ]]; then
	if [[ "$VERSION" != '11' ]] && [[ "$VERSION" != '12' ]]; then
		echo "Error: Debian $VERSION is not supported! Only versions 11 and 12 are allowed"
		exit 5
	fi
elif [[ "$OS" == 'ubuntu' ]]; then
	if [[ "$VERSION" != '22' ]] && [[ "$VERSION" != '24' ]]; then
		echo "Error: Ubuntu $VERSION is not supported! Only versions 22 and 24 are allowed"
		exit 6
	fi
else
	echo "Error: Your Linux distribution ($OS) is not supported!"
	exit 7
fi

# Проверка свободного места (минимум 2Гб)
if [[ $(df --output=avail / | tail -n 1) -lt $((2 * 1024 * 1024)) ]]; then
	echo 'Error: Low disk space! You need 2GB of free space!'
	exit 8
fi

# Проверка наличия сетевого интерфейса и IPv4-адреса
DEFAULT_INTERFACE="$(ip route get 1.2.3.4 2>/dev/null | grep -oP 'dev \K\S+')"
if [[ -z "$DEFAULT_INTERFACE" ]]; then
	echo 'Default network interface not found!'
	exit 9
fi

DEFAULT_IP="$(ip route get 1.2.3.4 2>/dev/null | grep -oP 'src \K\S+')"
if [[ -z "$DEFAULT_IP" ]]; then
	echo 'Default IPv4 address not found!'
	exit 10
fi

echo
echo -e '\e[1;32mInstalling AntiZapret VPN + full VPN...\e[0m'
echo 'OpenVPN + WireGuard + AmneziaWG'
echo 'More details: https://github.com/GubernievS/AntiZapret-VPN'
echo

MTU=$(< /sys/class/net/$DEFAULT_INTERFACE/mtu)
if (( MTU < 1500 )); then
	echo "Warning! Low MTU on $DEFAULT_INTERFACE: $MTU"
	echo "Change MTU in OpenVPN and WireGuard configs from 1420 to $((MTU-80)) on this server after installation"
	echo
fi

# Спрашиваем о настройках
echo 'Choose anti-censorship patch for OpenVPN (UDP only):'
echo '    0) None        - Do not install anti-censorship patch, or remove if already installed'
echo '    1) Strong      - Recommended by default'
echo '    2) Error-free  - Use if Strong patch causes connection error, recommended for Mikrotik routers'
until [[ "$OPENVPN_PATCH" =~ ^[0-2]$ ]]; do
	read -rp 'Version choice [0-2]: ' -e -i 1 OPENVPN_PATCH
done
echo
echo 'OpenVPN DCO lowers CPU load, boosts data speeds, and only supports AES-128-GCM, AES-256-GCM and CHACHA20-POLY1305 encryption'
until [[ "$OPENVPN_DCO" =~ (y|n) ]]; do
	read -rp 'Turn on OpenVPN DCO? [y/n]: ' -e -i y OPENVPN_DCO
done
echo
until [[ "$WARP_OUTBOUND" =~ (y|n) ]]; do
	read -rp $'Use Cloudflare WARP for \001\e[1;32m\002all VPN\001\e[0m\002 outbound traffic? [y/n]: ' -e -i n WARP_OUTBOUND
done
echo
echo -e 'Choose DNS resolvers for \e[1;32mAntiZapret VPN\e[0m (antizapret-*):'
echo '    1) Cloudflare+Quad9  - Recommended by default'
echo '       +MSK-IX+SkyDNS *'
echo '    2) SkyDNS *          - Recommended for expert users if this server IP is registered in SkyDNS'
echo '                           Register account (Family plan) and add this server IP at https://skydns.ru'
echo '    3) Cloudflare+Quad9  - Use if default choice fails to resolve domains'
echo '    4) Comss **          - More details: https://comss.ru/disqus/page.php?id=7315'
echo '    5) XBox **           - More details: https://xbox-dns.ru'
echo '    6) Malw **           - More details: https://info.dns.malw.link'
echo
echo '  * - DNS resolvers optimized for users located in Russia'
echo ' ** - Enable additional proxying and hide this server IP on some internet resources'
echo '      Use only if this server is geolocated in Russia or problems accessing some internet resources'
until [[ "$ANTIZAPRET_DNS" =~ ^[1-6]$ ]]; do
	read -rp 'DNS choice [1-6]: ' -e -i 1 ANTIZAPRET_DNS
done
echo
echo -e 'Choose DNS resolvers for \e[1;32mfull VPN\e[0m (vpn-*):'
echo '    1) Self-hosted  - Use previous DNS choice, recommended by default'
echo '    2) Cloudflare   - Use if Self-hosted fails to resolve domains'
echo '    3) Quad9        - Use if Self-hosted/Cloudflare fails to resolve domains'
echo '    4) Google *     - Use if Self-hosted/Cloudflare/Quad9 fails to resolve domains'
echo '    5) AdGuard *    - Use for blocking ads, trackers, malware and phishing websites'
echo '    6) Comss **     - More details: https://comss.ru/disqus/page.php?id=7315'
echo '    7) XBox **      - More details: https://xbox-dns.ru'
echo '    8) Malw **      - More details: https://info.dns.malw.link'
echo
echo '  * - DNS resolvers support EDNS Client Subnet'
echo ' ** - Enable additional proxying and hide this server IP on some internet resources'
echo '      Use only if this server is geolocated in Russia or problems accessing some internet resources'
until [[ "$VPN_DNS" =~ ^[1-8]$ ]]; do
	read -rp 'DNS choice [1-8]: ' -e -i 1 VPN_DNS
done
echo
until [[ "$BLOCK_ADS" =~ (y|n) ]]; do
	read -rp $'Enable blocking ads, trackers, malware and phishing websites in \001\e[1;32m\002AntiZapret VPN\001\e[0m\002 (antizapret-*) based on AdGuard and OISD rules? [y/n]: ' -e -i y BLOCK_ADS
done
echo
echo 'Default IP address range:     10.28.0.0/15'
echo 'Alternative IP address range: 172.28.0.0/15'
until [[ "$ALTERNATIVE_IP" =~ (y|n) ]]; do
	read -rp 'Use alternative range of IP addresses? [y/n]: ' -e -i n ALTERNATIVE_IP
done
echo
[[ "$ALTERNATIVE_IP" == 'y' ]] && IP=172 || IP=10
echo "Default FAKE IP address range:     $IP.30.0.0/15"
echo 'Alternative FAKE IP address range: 198.18.0.0/15'
until [[ "$ALTERNATIVE_FAKE_IP" =~ (y|n) ]]; do
	read -rp 'Use alternative range of FAKE IP addresses? [y/n]: ' -e -i n ALTERNATIVE_FAKE_IP
done
echo
until [[ "$OPENVPN_BACKUP_TCP" =~ (y|n) ]]; do
	read -rp 'Use TCP ports 80, 443, 504, 508 as backup for OpenVPN connections? [y/n]: ' -e -i n OPENVPN_BACKUP_TCP
done
echo
until [[ "$OPENVPN_BACKUP_UDP" =~ (y|n) ]]; do
	read -rp 'Use UDP ports 80, 443, 504, 508 as backup for OpenVPN connections? [y/n]: ' -e -i y OPENVPN_BACKUP_UDP
done
echo
until [[ "$WIREGUARD_BACKUP" =~ (y|n) ]]; do
	read -rp 'Use ports 540, 580 as backup for WireGuard/AmneziaWG connections? [y/n]: ' -e -i y WIREGUARD_BACKUP
done
echo
until [[ "$OPENVPN_DUPLICATE" =~ (y|n) ]]; do
	read -rp 'Allow multiple clients connecting to OpenVPN using same profile file (*.ovpn)? [y/n]: ' -e -i y OPENVPN_DUPLICATE
done
echo
until [[ "$OPENVPN_LOG" =~ (y|n) ]]; do
	read -rp 'Enable detailed logs in OpenVPN? [y/n]: ' -e -i n OPENVPN_LOG
done
echo
until [[ "$SSH_PROTECTION" =~ (y|n) ]]; do
	read -rp 'Enable SSH brute-force protection? [y/n]: ' -e -i y SSH_PROTECTION
done
echo
echo 'Warning! Network attack and scan protection may block VPN or third-party applications!'
until [[ "$ATTACK_PROTECTION" =~ (y|n) ]]; do
	read -rp 'Enable network attack and scan protection? [y/n]: ' -e -i y ATTACK_PROTECTION
done
echo
echo 'Warning! Torrent guard blocks VPN traffic for 1 minute on torrent detection!'
until [[ "$TORRENT_GUARD" =~ (y|n) ]]; do
	read -rp $'Enable torrent guard for \001\e[1;32m\002full VPN\001\e[0m\002? [y/n]: ' -e -i y TORRENT_GUARD
done
echo
until [[ "$RESTRICT_FORWARD" =~ (y|n) ]]; do
	read -rp $'Restrict forwarding in \001\e[1;32m\002AntiZapret VPN\001\e[0m\002 to IPs from config/forward-ips.txt and result/route-ips.txt? [y/n]: ' -e -i y RESTRICT_FORWARD
done
echo
until [[ "$CLIENT_ISOLATION" =~ (y|n) ]]; do
	read -rp $'Enable \001\e[1;32m\002all VPN\001\e[0m\002 client and server isolation? [y/n]: ' -e -i y CLIENT_ISOLATION
done
echo
while read -rp 'Enter valid domain name for this OpenVPN server or press Enter to skip: ' -e OPENVPN_HOST
do
	[[ -z "$OPENVPN_HOST" ]] && break
	[[ -n $(getent ahostsv4 "$OPENVPN_HOST") ]] && break
done
echo
while read -rp 'Enter valid domain name for this WireGuard/AmneziaWG server or press Enter to skip: ' -e WIREGUARD_HOST
do
	[[ -z "$WIREGUARD_HOST" ]] && break
	[[ -n $(getent ahostsv4 "$WIREGUARD_HOST") ]] && break
done
echo
until [[ "$ROUTE_ALL" =~ (y|n) ]]; do
	read -rp $'Route all traffic for domains via \001\e[1;32m\002AntiZapret VPN\001\e[0m\002, excluding Russian domains and domains from config/exclude-hosts.txt? [y/n]: ' -e -i n ROUTE_ALL
done
echo
until [[ "$DISCORD_INCLUDE" =~ (y|n) ]]; do
	read -rp $'Include Discord voice IPs in \001\e[1;32m\002AntiZapret VPN\001\e[0m\002? [y/n]: ' -e -i y DISCORD_INCLUDE
done
echo
until [[ "$CLOUDFLARE_INCLUDE" =~ (y|n) ]]; do
	read -rp $'Include Cloudflare IPs in \001\e[1;32m\002AntiZapret VPN\001\e[0m\002? [y/n]: ' -e -i y CLOUDFLARE_INCLUDE
done
echo
until [[ "$TELEGRAM_INCLUDE" =~ (y|n) ]]; do
	read -rp $'Include Telegram IPs in \001\e[1;32m\002AntiZapret VPN\001\e[0m\002? [y/n]: ' -e -i y TELEGRAM_INCLUDE
done
echo
until [[ "$WHATSAPP_INCLUDE" =~ (y|n) ]]; do
	read -rp $'Include WhatsApp IPs in \001\e[1;32m\002AntiZapret VPN\001\e[0m\002? [y/n]: ' -e -i y WHATSAPP_INCLUDE
done
echo
until [[ "$ROBLOX_INCLUDE" =~ (y|n) ]]; do
	read -rp $'Include Roblox IPs in \001\e[1;32m\002AntiZapret VPN\001\e[0m\002? [y/n]: ' -e -i y ROBLOX_INCLUDE
done
echo
#until [[ "$AMAZON_INCLUDE" =~ (y|n) ]]; do
#	read -rp $'Include Amazon IPs in \001\e[1;32m\002AntiZapret VPN\001\e[0m\002? [y/n]: ' -e -i n AMAZON_INCLUDE
#done
#echo
#until [[ "$HETZNER_INCLUDE" =~ (y|n) ]]; do
#	read -rp $'Include Hetzner IPs in \001\e[1;32m\002AntiZapret VPN\001\e[0m\002? [y/n]: ' -e -i n HETZNER_INCLUDE
#done
#echo
#until [[ "$DIGITALOCEAN_INCLUDE" =~ (y|n) ]]; do
#	read -rp $'Include DigitalOcean IPs in \001\e[1;32m\002AntiZapret VPN\001\e[0m\002? [y/n]: ' -e -i n DIGITALOCEAN_INCLUDE
#done
#echo
#until [[ "$OVH_INCLUDE" =~ (y|n) ]]; do
#	read -rp $'Include OVH IPs in \001\e[1;32m\002AntiZapret VPN\001\e[0m\002? [y/n]: ' -e -i n OVH_INCLUDE
#done
#echo
#until [[ "$GOOGLE_INCLUDE" =~ (y|n) ]]; do
#	read -rp $'Include Google IPs in \001\e[1;32m\002AntiZapret VPN\001\e[0m\002? [y/n]: ' -e -i n GOOGLE_INCLUDE
#done
#echo
#until [[ "$AKAMAI_INCLUDE" =~ (y|n) ]]; do
#	read -rp $'Include Akamai IPs in \001\e[1;32m\002AntiZapret VPN\001\e[0m\002? [y/n]: ' -e -i n AKAMAI_INCLUDE
#done
#echo
echo 'Installation, please wait...'

# Отключим фоновые обновления системы
systemctl stop unattended-upgrades
systemctl stop apt-daily.timer
systemctl stop apt-daily-upgrade.timer

# Остановим и выключим обновляемые службы
systemctl disable --now kresd@1 2>/dev/null
systemctl disable --now kresd@2 2>/dev/null
systemctl disable --now antizapret 2>/dev/null
systemctl disable --now antizapret-update.timer 2>/dev/null
systemctl disable --now antizapret-update 2>/dev/null
systemctl disable --now openvpn-server@antizapret-udp 2>/dev/null
systemctl disable --now openvpn-server@antizapret-tcp 2>/dev/null
systemctl disable --now openvpn-server@vpn-udp 2>/dev/null
systemctl disable --now openvpn-server@vpn-tcp 2>/dev/null
systemctl disable --now wg-quick@antizapret 2>/dev/null
systemctl disable --now wg-quick@vpn 2>/dev/null
systemctl disable --now kres-cache-gc 2>/dev/null

# Удалим ненужные службы
apt-get purge -y ufw
apt-get purge -y firewalld
apt-get purge -y apparmor
apt-get purge -y apport
apt-get purge -y modemmanager
apt-get purge -y snapd
apt-get purge -y upower
apt-get purge -y multipath-tools
apt-get purge -y rsyslog
apt-get purge -y udisks2
apt-get purge -y qemu-guest-agent
apt-get purge -y tuned
apt-get purge -y sysstat
apt-get purge -y acpid
apt-get purge -y fwupd
apt-get purge -y watchdog
apt-get purge -y pcscd
apt-get purge -y packagekit

# SSH protection включён
if [[ "$SSH_PROTECTION" == 'y' ]]; then
	apt-get purge -y fail2ban || true
	apt-get purge -y sshguard || true
fi

# Удаляем кэш Knot Resolver
rm -rf /var/cache/knot-resolver/*
rm -rf /var/cache/knot-resolver2/*

# Удаляем старые файлы OpenVPN и WireGuard
rm -rf /etc/openvpn/server/*
rm -rf /etc/openvpn/client/*
rm -rf /etc/wireguard/templates/*

# Удаляем скомпилированный патченный OpenVPN
make -C /usr/local/src/openvpn uninstall
rm -rf /usr/local/src/openvpn

# Отключим IPv6
sysctl -w net.ipv6.conf.all.disable_ipv6=1
sysctl -w net.ipv6.conf.default.disable_ipv6=1
sysctl -w net.ipv6.conf.lo.disable_ipv6=1

# Удаляем переопределённые параметры ядра
sed -i '/^$/!{/^#/!d}' /etc/sysctl.conf

# Принудительная загрузка модуля nf_conntrack
echo 'nf_conntrack' > /etc/modules-load.d/nf_conntrack.conf

# Завершим выполнение скрипта при ошибке
set -e

# Обработка ошибок
handle_error() {
	echo "$(lsb_release -ds) $(uname -r) $(date --iso-8601=seconds)"
	echo -e "\e[1;31mError at line $1: $2\e[0m"
	exit 1
}
trap 'handle_error $LINENO "$BASH_COMMAND"' ERR

# Обновляем систему
rm -rf /etc/apt/sources.list.d/cznic-labs-knot-resolver.list
rm -rf /etc/apt/sources.list.d/openvpn-aptrepo.list
rm -rf /etc/apt/sources.list.d/backports.list
export DEBIAN_FRONTEND=noninteractive
apt-get clean
apt-get update
dpkg --configure -a
apt-get install --fix-broken -y
apt-get dist-upgrade -y
apt-get install --reinstall -y curl gpg

# Папка для ключей
mkdir -p /etc/apt/keyrings

# Добавим репозиторий Knot Resolver
curl -fL --connect-timeout 30 https://pkg.labs.nic.cz/gpg -o /etc/apt/keyrings/cznic-labs-pkg.gpg
echo "deb [signed-by=/etc/apt/keyrings/cznic-labs-pkg.gpg] https://pkg.labs.nic.cz/knot-resolver $(lsb_release -cs) main" > /etc/apt/sources.list.d/cznic-labs-knot-resolver.list

# Добавим репозиторий OpenVPN
curl -fL --connect-timeout 30 https://swupdate.openvpn.net/repos/repo-public.gpg | gpg --yes --dearmor -o /etc/apt/keyrings/openvpn-repo-public.gpg
echo "deb [signed-by=/etc/apt/keyrings/openvpn-repo-public.gpg] https://build.openvpn.net/debian/openvpn/release/2.6 $(lsb_release -cs) main" > /etc/apt/sources.list.d/openvpn-aptrepo.list

# Добавим репозиторий Debian Backports
if [[ "$OS" == 'debian' ]]; then
	if [[ "$VERSION" -ge 12 ]]; then
		echo "deb http://deb.debian.org/debian $(lsb_release -cs)-backports main" > /etc/apt/sources.list.d/backports.list
	elif [[ "$VERSION" -eq 11 ]]; then
		echo "deb http://archive.debian.org/debian $(lsb_release -cs)-backports main" > /etc/apt/sources.list.d/backports.list
	fi
fi

# Ставим необходимые пакеты
apt-get update
apt-get install --reinstall -y git openvpn iptables easy-rsa gawk knot-resolver idn sipcalc python3-pip wireguard diffutils socat lua-cqueues ipset irqbalance unattended-upgrades jq
apt-get autoremove --purge -y
apt-get clean
dpkg-reconfigure -f noninteractive unattended-upgrades

# Клонируем репозиторий и устанавливаем dnslib
rm -rf /tmp/dnslib
git clone https://github.com/paulc/dnslib.git /tmp/dnslib
PIP_BREAK_SYSTEM_PACKAGES=1 python3 -m pip install --force-reinstall --user /tmp/dnslib

# Клонируем репозиторий antizapret
rm -rf /tmp/antizapret
git clone https://github.com/GubernievS/AntiZapret-VPN.git /tmp/antizapret

# Сохраняем пользовательские настройки и обработчики custom*.sh
cp /root/antizapret/config/*.txt /tmp/antizapret/setup/root/antizapret/config/ || true
cp /root/antizapret/custom*.sh /tmp/antizapret/setup/root/antizapret/ || true
cp /etc/knot-resolver/*.lua /tmp/antizapret/setup/etc/knot-resolver/ || true

# Восстанавливаем из бэкапа пользовательские настройки и обработчики custom*.sh, пользователей OpenVPN и WireGuard
tar -xzf /root/backup*.tar.gz || true
rm -f /root/backup*.tar.gz || true

cp -r /root/easyrsa3/* /tmp/antizapret/setup/etc/openvpn/easyrsa3/ || true
cp /root/wireguard/* /tmp/antizapret/setup/etc/wireguard/ || true
cp /root/config/* /tmp/antizapret/setup/root/antizapret/config/ || true
cp /root/knot-resolver/* /tmp/antizapret/setup/etc/knot-resolver/ || true
cp /root/custom/* /tmp/antizapret/setup/root/antizapret/ || true

rm -rf /root/easyrsa3
rm -rf /root/wireguard
rm -rf /root/config
rm -rf /root/knot-resolver
rm -rf /root/custom

# Сохраняем настройки
echo "SETUP_DATE=$(date --iso-8601=seconds)
OPENVPN_PATCH=$OPENVPN_PATCH
OPENVPN_DCO=$OPENVPN_DCO
WARP_OUTBOUND=$WARP_OUTBOUND
ANTIZAPRET_DNS=$ANTIZAPRET_DNS
VPN_DNS=$VPN_DNS
BLOCK_ADS=$BLOCK_ADS
ALTERNATIVE_IP=$ALTERNATIVE_IP
ALTERNATIVE_FAKE_IP=$ALTERNATIVE_FAKE_IP
OPENVPN_BACKUP_TCP=$OPENVPN_BACKUP_TCP
OPENVPN_BACKUP_UDP=$OPENVPN_BACKUP_UDP
WIREGUARD_BACKUP=$WIREGUARD_BACKUP
OPENVPN_DUPLICATE=$OPENVPN_DUPLICATE
OPENVPN_LOG=$OPENVPN_LOG
SSH_PROTECTION=$SSH_PROTECTION
ATTACK_PROTECTION=$ATTACK_PROTECTION
TORRENT_GUARD=$TORRENT_GUARD
RESTRICT_FORWARD=$RESTRICT_FORWARD
CLIENT_ISOLATION=$CLIENT_ISOLATION
OPENVPN_HOST=$OPENVPN_HOST
WIREGUARD_HOST=$WIREGUARD_HOST
ROUTE_ALL=$ROUTE_ALL
DISCORD_INCLUDE=$DISCORD_INCLUDE
CLOUDFLARE_INCLUDE=$CLOUDFLARE_INCLUDE
TELEGRAM_INCLUDE=$TELEGRAM_INCLUDE
WHATSAPP_INCLUDE=$WHATSAPP_INCLUDE
ROBLOX_INCLUDE=$ROBLOX_INCLUDE
AMAZON_INCLUDE=$AMAZON_INCLUDE
HETZNER_INCLUDE=$HETZNER_INCLUDE
DIGITALOCEAN_INCLUDE=$DIGITALOCEAN_INCLUDE
OVH_INCLUDE=$OVH_INCLUDE
GOOGLE_INCLUDE=$GOOGLE_INCLUDE
AKAMAI_INCLUDE=$AKAMAI_INCLUDE
CLEAR_HOSTS=y
DEFAULT_INTERFACE=
OUT_INTERFACE=
OUT_IP=
IP=
FAKE_IP=" > /tmp/antizapret/setup/root/antizapret/setup

# Создаем папки для кэша Knot Resolver
mkdir -p /var/cache/knot-resolver
mkdir -p /var/cache/knot-resolver2
chown -R knot-resolver:knot-resolver /var/cache/knot-resolver
chown -R knot-resolver:knot-resolver /var/cache/knot-resolver2

# Выставляем разрешения
find /tmp/antizapret -type f -exec chmod 644 {} +
find /tmp/antizapret -type d -exec chmod 755 {} +
find /tmp/antizapret/setup/root/antizapret -type f -exec chmod +x {} +
find /tmp/antizapret/setup/etc/openvpn/server/scripts -type f -exec chmod +x {} +

# Копируем нужное, удаляем не нужное
find /tmp/antizapret -name '.gitkeep' -delete
rm -rf /root/antizapret
cp -r /tmp/antizapret/setup/* /
rm -rf /tmp/dnslib
rm -rf /tmp/antizapret

# Настраиваем DNS в AntiZapret VPN
if [[ "$ANTIZAPRET_DNS" == '2' ]]; then
	# SkyDNS
	sed -i "s/{'62\.76\.76\.62', '62\.76\.62\.76', '193\.58\.251\.251'}/'193.58.251.251'/" /etc/knot-resolver/kresd.conf
	sed -i "s/{'1\.1\.1\.1', '1\.0\.0\.1', '9\.9\.9\.10', '149\.112\.112\.10'}/'193.58.251.251'/" /etc/knot-resolver/kresd.conf
elif [[ "$ANTIZAPRET_DNS" == '3' ]]; then
	# Cloudflare+Quad9
	sed -i "s/'62\.76\.76\.62', '62\.76\.62\.76', '193\.58\.251\.251'/'1.1.1.1', '1.0.0.1', '9.9.9.10', '149.112.112.10'/" /etc/knot-resolver/kresd.conf
elif [[ "$ANTIZAPRET_DNS" == '4' ]]; then
	# Comss
	sed -i "s/'62\.76\.76\.62', '62\.76\.62\.76', '193\.58\.251\.251'/'83.220.169.155', '212.109.195.93', '195.133.25.16'/" /etc/knot-resolver/kresd.conf
	sed -i "s/'1\.1\.1\.1', '1\.0\.0\.1', '9\.9\.9\.10', '149\.112\.112\.10'/'83.220.169.155', '212.109.195.93', '195.133.25.16'/" /etc/knot-resolver/kresd.conf
elif [[ "$ANTIZAPRET_DNS" == '5' ]]; then
	# XBox
	sed -i "s/'62\.76\.76\.62', '62\.76\.62\.76', '193\.58\.251\.251'/'176.99.11.77', '80.78.247.254', '31.192.108.180'/" /etc/knot-resolver/kresd.conf
	sed -i "s/'1\.1\.1\.1', '1\.0\.0\.1', '9\.9\.9\.10', '149\.112\.112\.10'/'176.99.11.77', '80.78.247.254', '31.192.108.180'/" /etc/knot-resolver/kresd.conf
elif [[ "$ANTIZAPRET_DNS" == '6' ]]; then
	# Malw
	sed -i "s/'62\.76\.76\.62', '62\.76\.62\.76', '193\.58\.251\.251'/'84.21.189.133', '193.23.209.189'/" /etc/knot-resolver/kresd.conf
	sed -i "s/'1\.1\.1\.1', '1\.0\.0\.1', '9\.9\.9\.10', '149\.112\.112\.10'/'84.21.189.133', '193.23.209.189'/" /etc/knot-resolver/kresd.conf
fi

# Настраиваем DNS в full VPN
if [[ "$VPN_DNS" == '3' ]]; then
	# Quad9
	sed -i '/push "dhcp-option DNS 1\.1\.1\.1"/,+1c push "dhcp-option DNS 9.9.9.10"\npush "dhcp-option DNS 149.112.112.10"' /etc/openvpn/server/vpn*.conf
	sed -i 's/1\.1\.1\.1, 1\.0\.0\.1/9.9.9.10, 149.112.112.10/' /etc/wireguard/templates/vpn-client*.conf
elif [[ "$VPN_DNS" == '4' ]]; then
	# Google
	sed -i '/push "dhcp-option DNS 1\.1\.1\.1"/,+1c push "dhcp-option DNS 8.8.8.8"\npush "dhcp-option DNS 8.8.4.4"' /etc/openvpn/server/vpn*.conf
	sed -i 's/1\.1\.1\.1, 1\.0\.0\.1/8.8.8.8, 8.8.4.4/' /etc/wireguard/templates/vpn-client*.conf
elif [[ "$VPN_DNS" == '5' ]]; then
	# AdGuard
	sed -i '/push "dhcp-option DNS 1\.1\.1\.1"/,+1c push "dhcp-option DNS 94.140.14.14"\npush "dhcp-option DNS 94.140.15.15"' /etc/openvpn/server/vpn*.conf
	sed -i 's/1\.1\.1\.1, 1\.0\.0\.1/94.140.14.14, 94.140.15.15/' /etc/wireguard/templates/vpn-client*.conf
elif [[ "$VPN_DNS" == '6' ]]; then
	# Comss
	sed -i '/push "dhcp-option DNS 1\.1\.1\.1"/,+1c push "dhcp-option DNS 83.220.169.155"\npush "dhcp-option DNS 212.109.195.93"\npush "dhcp-option DNS 195.133.25.16"' /etc/openvpn/server/vpn*.conf
	sed -i 's/1\.1\.1\.1, 1\.0\.0\.1/83.220.169.155, 212.109.195.93, 195.133.25.16/' /etc/wireguard/templates/vpn-client*.conf
elif [[ "$VPN_DNS" == '7' ]]; then
	# XBox
	sed -i '/push "dhcp-option DNS 1\.1\.1\.1"/,+1c push "dhcp-option DNS 176.99.11.77"\npush "dhcp-option DNS 80.78.247.254"\npush "dhcp-option DNS 31.192.108.180"' /etc/openvpn/server/vpn*.conf
	sed -i 's/1\.1\.1\.1, 1\.0\.0\.1/176.99.11.77, 80.78.247.254, 31.192.108.180/' /etc/wireguard/templates/vpn-client*.conf
elif [[ "$VPN_DNS" == '8' ]]; then
	# Malw
	sed -i '/push "dhcp-option DNS 1\.1\.1\.1"/,+1c push "dhcp-option DNS 84.21.189.133"\npush "dhcp-option DNS 193.23.209.189"' /etc/openvpn/server/vpn*.conf
	sed -i 's/1\.1\.1\.1, 1\.0\.0\.1/84.21.189.133, 193.23.209.189/' /etc/wireguard/templates/vpn-client*.conf
fi

# Используем альтернативные диапазоны подменных IPv4-адресов
# 10(172).28.0.0/15 => 198.18.0.0/15
if [[ "$ALTERNATIVE_FAKE_IP" == 'y' ]]; then
	sed -i 's/10\.30\./198\.18\./g' /root/antizapret/proxy.py
fi

# Используем альтернативные диапазоны IPv4-адресов
# 10.28.0.0/15 => 172.28.0.0/15
if [[ "$ALTERNATIVE_IP" == 'y' ]]; then
	sed -i 's/10\./172\./g' /root/antizapret/proxy.py
	sed -i 's/10\./172\./g' /etc/knot-resolver/kresd.conf
	sed -i 's/10\./172\./g' /etc/openvpn/server/*.conf
	sed -i 's/10\./172\./g' /etc/wireguard/templates/*.conf
	find /etc/wireguard -name '*.conf' -exec sed -i 's/s = 10\./s = 172\./g' {} +
else
	find /etc/wireguard -name '*.conf' -exec sed -i 's/s = 172\./s = 10\./g' {} +
fi

# Запрещаем несколько одновременных подключений к OpenVPN для одного клиента
if [[ "$OPENVPN_DUPLICATE" == 'n' ]]; then
	sed -i '/duplicate/s/^/#/' /etc/openvpn/server/*.conf
fi

# Включим подробные логи в OpenVPN
if [[ "$OPENVPN_LOG" == 'y' ]]; then
	sed -i '/^#\(verb\|log\)/s/^#//' /etc/openvpn/server/*.conf
fi

# Загружаем и создаем списки исключений
/root/antizapret/doall.sh noclear

# Настраиваем сервера OpenVPN и WireGuard/AmneziaWG для первого запуска
# Пересоздаем для всех существующих пользователей файлы подключений
# Если пользователей нет, то создаем новых пользователей 'antizapret-client' для OpenVPN и WireGuard/AmneziaWG
/root/antizapret/client.sh 7

# Включим/выключим обновляемые службы
systemctl enable kresd@1
systemctl enable kresd@2
systemctl enable antizapret
systemctl enable antizapret-update.timer
systemctl enable antizapret-update
systemctl enable openvpn-server@antizapret-udp
systemctl enable openvpn-server@antizapret-tcp
systemctl enable openvpn-server@vpn-udp
systemctl enable openvpn-server@vpn-tcp
systemctl enable wg-quick@antizapret
systemctl enable wg-quick@vpn
systemctl mask kres-cache-gc
systemctl disable kres-cache-gc

ERRORS=

if [[ "$OPENVPN_PATCH" != '0' ]]; then
	if ! /root/antizapret/patch-openvpn.sh "$OPENVPN_PATCH"; then
		ERRORS+="\n\e[1;31mAnti-censorship patch for OpenVPN has not installed!\e[0m Please run '/root/antizapret/patch-openvpn.sh' after rebooting\n"
	fi
fi

if [[ "$OPENVPN_DCO" == 'y' ]]; then
	if ! /root/antizapret/openvpn-dco.sh y; then
		ERRORS+="\n\e[1;31mOpenVPN DCO has not turn on!\e[0m Please run '/root/antizapret/openvpn-dco.sh y' after rebooting\n"
	fi
fi

# Если есть ошибки, выводим их
if [[ -n "$ERRORS" ]]; then
	echo -e "$ERRORS"
fi

# Создадим файл подкачки размером 1 Гб если его нет
if [[ -z "$(swapon --show)" ]]; then
	set +e
	SWAPFILE=/swapfile
	SWAPSIZE=1024
	dd if=/dev/zero of=$SWAPFILE bs=1M count=$SWAPSIZE
	chmod 600 $SWAPFILE
	mkswap $SWAPFILE
	swapon $SWAPFILE
	echo $SWAPFILE none swap sw 0 0 >> /etc/fstab
fi

# Перезагружаем
echo
echo -e '\e[1;32mAntiZapret VPN + full VPN installed successfully!\e[0m'
echo 'Rebooting...'

reboot