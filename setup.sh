#!/bin/bash
#
# Скрипт для установки на своём сервере AntiZapret VPN и обычного VPN
#
# https://github.com/GubernievS/AntiZapret-VPN
#

export LC_ALL=C

#
# Проверка прав root
if [[ "$EUID" -ne 0 ]]; then
	echo 'Error: You need to run this as root!'
	exit 2
fi

cd /root

#
# Проверка на OpenVZ и LXC
if [[ "$(systemd-detect-virt)" == "openvz" || "$(systemd-detect-virt)" == "lxc" ]]; then
	echo 'Error: OpenVZ and LXC are not supported!'
	exit 3
fi

#
# Проверка версии системы
OS="$(lsb_release -si | tr '[:upper:]' '[:lower:]')"
VERSION="$(lsb_release -rs | cut -d '.' -f1)"

if [[ "$OS" == "debian" ]]; then
	if [[ $VERSION -lt 11 ]]; then
		echo 'Error: Your Debian version is not supported!'
		exit 4
	fi
elif [[ "$OS" == "ubuntu" ]]; then
	if [[ $VERSION -lt 22 ]]; then
		echo 'Error: Your Ubuntu version is not supported!'
		exit 5
	fi
elif [[ "$OS" != "debian" ]] && [[ "$OS" != "ubuntu" ]]; then
	echo 'Error: Your Linux version is not supported!'
	exit 6
fi

#
# Проверка свободного места (минимум 2Гб)
if [[ $(df --output=avail / | tail -n 1) -lt $((2 * 1024 * 1024)) ]]; then
	echo 'Error: Low disk space! You need 2GB of free space!'
	exit 7
fi

echo
echo -e '\e[1;32mInstalling AntiZapret VPN + full VPN...\e[0m'
echo 'OpenVPN + WireGuard + AmneziaWG'
echo 'More details: https://github.com/GubernievS/AntiZapret-VPN'

#
# Спрашиваем о настройках
echo
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
echo -e 'Choose DNS resolvers for \e[1;32mAntiZapret VPN\e[0m (antizapret-*):'
echo '    1) Cloudflare+Quad9  - Recommended by default'
echo '         +Russian *'
echo '    2) Cloudflare+Quad9  - Use if default choice fails to resolve domains'
echo '    3) Comss **          - More details: https://comss.ru/disqus/page.php?id=7315'
echo '    4) Xbox **           - More details: https://xbox-dns.ru'
echo '    5) Malw **           - More details: https://info.dns.malw.link'
echo
echo '  * - Resolvers optimized for users in Russia'
echo ' ** - Enable additional proxying and hide this server IP on some internet resources'
echo '      Use only if this server is geolocated in Russia or problems accessing some internet resources'
until [[ "$ANTIZAPRET_DNS" =~ ^[1-5]$ ]]; do
	read -rp 'DNS choice [1-5]: ' -e -i 1 ANTIZAPRET_DNS
done
echo
echo -e 'Choose DNS resolvers for \e[1;32mfull VPN\e[0m (vpn-*):'
echo '    1) Cloudflare  - Recommended by default'
echo '    2) Quad9       - Use if Cloudflare fails to resolve domains'
echo '    3) Google *    - Use if Cloudflare/Quad9 fails to resolve domains'
echo '    4) AdGuard *   - Use for blocking ads, trackers, malware and phishing websites'
echo '    5) Comss **    - More details: https://comss.ru/disqus/page.php?id=7315'
echo '    6) Xbox **     - More details: https://xbox-dns.ru'
echo '    7) Malw **     - More details: https://info.dns.malw.link'
echo
echo '  * - Resolvers supports EDNS Client Subnet'
echo ' ** - Enable additional proxying and hide this server IP on some internet resources'
echo '      Use only if this server is geolocated in Russia or problems accessing some internet resources'
until [[ "$VPN_DNS" =~ ^[1-7]$ ]]; do
	read -rp 'DNS choice [1-7]: ' -e -i 1 VPN_DNS
done
echo
until [[ "$BLOCK_ADS" =~ (y|n) ]]; do
	read -rp $'Enable blocking ads, trackers, malware and phishing websites in \001\e[1;32m\002AntiZapret VPN\001\e[0m\002 (antizapret-*) based on AdGuard and OISD rules? [y/n]: ' -e -i y BLOCK_ADS
done
echo
echo 'Default IP address range:      10.28.0.0/14'
echo 'Alternative IP address range: 172.28.0.0/14'
until [[ "$ALTERNATIVE_IP" =~ (y|n) ]]; do
	read -rp 'Use alternative range of IP addresses? [y/n]: ' -e -i n ALTERNATIVE_IP
done
echo
until [[ "$OPENVPN_80_443_TCP" =~ (y|n) ]]; do
	read -rp 'Use TCP ports 80 and 443 as backup for OpenVPN connections? [y/n]: ' -e -i y OPENVPN_80_443_TCP
done
echo
until [[ "$OPENVPN_80_443_UDP" =~ (y|n) ]]; do
	read -rp 'Use UDP ports 80 and 443 as backup for OpenVPN connections? [y/n]: ' -e -i y OPENVPN_80_443_UDP
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
echo "Warning! Network attack and scan protection may block VPN or third-party applications!"
until [[ "$ATTACK_PROTECTION" =~ (y|n) ]]; do
	read -rp 'Enable network attack and scan protection? [y/n]: ' -e -i y ATTACK_PROTECTION
done
echo
echo "Warning! Torrent guard block VPN traffic for 1 minute on torrent detection!"
until [[ "$TORRENT_GUARD" =~ (y|n) ]]; do
	read -rp $'Enable torrent guard for \001\e[1;32m\002full VPN\001\e[0m\002? [y/n]: ' -e -i y TORRENT_GUARD
done
echo
until [[ "$RESTRICT_FORWARD" =~ (y|n) ]]; do
	read -rp $'Restrict forwarding in \001\e[1;32m\002AntiZapret VPN\001\e[0m\002 to IPs from config/forward-ips.txt and result/route-ips.txt? [y/n]: ' -e -i y RESTRICT_FORWARD
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
until [[ "$AMAZON_INCLUDE" =~ (y|n) ]]; do
	read -rp $'Include Amazon IPs in \001\e[1;32m\002AntiZapret VPN\001\e[0m\002? [y/n]: ' -e -i n AMAZON_INCLUDE
done
echo
until [[ "$HETZNER_INCLUDE" =~ (y|n) ]]; do
	read -rp $'Include Hetzner IPs in \001\e[1;32m\002AntiZapret VPN\001\e[0m\002? [y/n]: ' -e -i n HETZNER_INCLUDE
done
echo
until [[ "$DIGITALOCEAN_INCLUDE" =~ (y|n) ]]; do
	read -rp $'Include DigitalOcean IPs in \001\e[1;32m\002AntiZapret VPN\001\e[0m\002? [y/n]: ' -e -i n DIGITALOCEAN_INCLUDE
done
echo
until [[ "$OVH_INCLUDE" =~ (y|n) ]]; do
	read -rp $'Include OVH IPs in \001\e[1;32m\002AntiZapret VPN\001\e[0m\002? [y/n]: ' -e -i n OVH_INCLUDE
done
echo
until [[ "$GOOGLE_INCLUDE" =~ (y|n) ]]; do
	read -rp $'Include Google IPs in \001\e[1;32m\002AntiZapret VPN\001\e[0m\002? [y/n]: ' -e -i n GOOGLE_INCLUDE
done
echo
until [[ "$AKAMAI_INCLUDE" =~ (y|n) ]]; do
	read -rp $'Include Akamai IPs in \001\e[1;32m\002AntiZapret VPN\001\e[0m\002? [y/n]: ' -e -i n AKAMAI_INCLUDE
done
echo
echo 'Preparing for installation, please wait...'

#
# Ожидание пока выполняется apt-get
while pidof apt-get &>/dev/null; do
	echo 'Waiting for apt-get to finish...';
	sleep 5;
done

#
# Отключим фоновые обновления системы
systemctl stop unattended-upgrades &>/dev/null
systemctl stop apt-daily.timer &>/dev/null
systemctl stop apt-daily-upgrade.timer &>/dev/null

#
# Остановим и выключим обновляемые службы
for service in kresd@ openvpn-server@ wg-quick@; do
	systemctl list-units --type=service --no-pager | awk -v s="$service" '$1 ~ s"[^.]+\\.service" {print $1}' | xargs -r systemctl stop &>/dev/null
	systemctl list-unit-files --type=service --no-pager | awk -v s="$service" '$1 ~ s"[^.]+\\.service" {print $1}' | xargs -r systemctl disable &>/dev/null
done

systemctl stop antizapret &>/dev/null
systemctl disable antizapret &>/dev/null

systemctl stop antizapret-update &>/dev/null
systemctl disable antizapret-update &>/dev/null

systemctl stop antizapret-update.timer &>/dev/null
systemctl disable antizapret-update.timer &>/dev/null

# Остановим и выключим ненужные службы
systemctl stop firewalld &>/dev/null
ufw disable &>/dev/null

systemctl disable firewalld &>/dev/null
systemctl disable ufw &>/dev/null

#
# Удаляем старые файлы и кеш Knot Resolver
rm -rf /var/cache/knot-resolver/*
rm -rf /etc/knot-resolver/*

#
# Удаляем старые файлы OpenVPN и WireGuard
rm -rf /etc/openvpn/server/*
rm -rf /etc/openvpn/client/*
rm -rf /etc/wireguard/templates/*

#
# Удаляем скомпилированный патченный OpenVPN
make -C /usr/local/src/openvpn uninstall &>/dev/null
rm -rf /usr/local/src/openvpn

#
# Отключим IPv6
sysctl -w net.ipv6.conf.all.disable_ipv6=1
sysctl -w net.ipv6.conf.default.disable_ipv6=1
sysctl -w net.ipv6.conf.lo.disable_ipv6=1

#
# Завершим выполнение скрипта при ошибке
set -e

#
# Обработка ошибок
handle_error() {
	echo "$(lsb_release -ds) $(uname -r) $(date --iso-8601=seconds)"
	echo -e "\e[1;31mError at line $1: $2\e[0m"
	exit 1
}
trap 'handle_error $LINENO "$BASH_COMMAND"' ERR

#
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

#
# Папка для ключей
mkdir -p /etc/apt/keyrings

#
# Добавим репозиторий Knot Resolver
curl -fsSL https://pkg.labs.nic.cz/gpg -o /etc/apt/keyrings/cznic-labs-pkg.gpg
echo "deb [signed-by=/etc/apt/keyrings/cznic-labs-pkg.gpg] https://pkg.labs.nic.cz/knot-resolver $(lsb_release -cs) main" > /etc/apt/sources.list.d/cznic-labs-knot-resolver.list

#
# Добавим репозиторий OpenVPN
curl -fsSL https://swupdate.openvpn.net/repos/repo-public.gpg | gpg --dearmor > /etc/apt/keyrings/openvpn-repo-public.gpg
echo "deb [signed-by=/etc/apt/keyrings/openvpn-repo-public.gpg] https://build.openvpn.net/debian/openvpn/release/2.6 $(lsb_release -cs) main" > /etc/apt/sources.list.d/openvpn-aptrepo.list

#
# Добавим репозиторий Debian Backports
if [[ "$OS" == "debian" ]]; then
	if [[ "$VERSION" -ge 12 ]]; then
		echo "deb http://deb.debian.org/debian $(lsb_release -cs)-backports main" > /etc/apt/sources.list.d/backports.list
	elif [[ "$VERSION" -eq 11 ]]; then
		echo "deb http://archive.debian.org/debian $(lsb_release -cs)-backports main" > /etc/apt/sources.list.d/backports.list
	fi
fi

#
# Ставим необходимые пакеты
apt-get update
apt-get install --reinstall -y git openvpn iptables easy-rsa gawk knot-resolver idn sipcalc python3-pip wireguard diffutils socat lua-cqueues ipset irqbalance
apt-get autoremove -y
apt-get clean

#
# Клонируем репозиторий и устанавливаем dnslib
rm -rf /tmp/dnslib
git clone https://github.com/paulc/dnslib.git /tmp/dnslib
PIP_BREAK_SYSTEM_PACKAGES=1 python3 -m pip install --force-reinstall --user /tmp/dnslib

#
# Клонируем репозиторий antizapret
rm -rf /tmp/antizapret
git clone https://github.com/GubernievS/AntiZapret-VPN.git /tmp/antizapret

#
# Сохраняем пользовательские настройки и пользовательские обработчики custom*.sh
cp /root/antizapret/config/* /tmp/antizapret/setup/root/antizapret/config/ &>/dev/null || true
cp /root/antizapret/custom*.sh /tmp/antizapret/setup/root/antizapret/ &>/dev/null || true

#
# Восстанавливаем из бэкапа пользовательские настройки и пользователей OpenVPN и WireGuard
tar -xzf /root/backup*.tar.gz &>/dev/null || true
rm -f /root/backup*.tar.gz &>/dev/null || true
cp -r /root/easyrsa3/* /tmp/antizapret/setup/etc/openvpn/easyrsa3 &>/dev/null || true
cp /root/wireguard/* /tmp/antizapret/setup/etc/wireguard &>/dev/null || true
cp /root/config/* /tmp/antizapret/setup/root/antizapret/config &>/dev/null || true
rm -rf /root/easyrsa3
rm -rf /root/wireguard
rm -rf /root/config

#
# Сохраняем настройки
echo "SETUP_DATE=$(date --iso-8601=seconds)
OPENVPN_PATCH=${OPENVPN_PATCH}
OPENVPN_DCO=${OPENVPN_DCO}
ANTIZAPRET_DNS=${ANTIZAPRET_DNS}
VPN_DNS=${VPN_DNS}
BLOCK_ADS=${BLOCK_ADS}
ALTERNATIVE_IP=${ALTERNATIVE_IP}
OPENVPN_80_443_TCP=${OPENVPN_80_443_TCP}
OPENVPN_80_443_UDP=${OPENVPN_80_443_UDP}
OPENVPN_DUPLICATE=${OPENVPN_DUPLICATE}
OPENVPN_LOG=${OPENVPN_LOG}
SSH_PROTECTION=${SSH_PROTECTION}
ATTACK_PROTECTION=${ATTACK_PROTECTION}
TORRENT_GUARD=${TORRENT_GUARD}
RESTRICT_FORWARD=${RESTRICT_FORWARD}
OPENVPN_HOST=${OPENVPN_HOST}
WIREGUARD_HOST=${WIREGUARD_HOST}
ROUTE_ALL=${ROUTE_ALL}
DISCORD_INCLUDE=${DISCORD_INCLUDE}
CLOUDFLARE_INCLUDE=${CLOUDFLARE_INCLUDE}
TELEGRAM_INCLUDE=${TELEGRAM_INCLUDE}
AMAZON_INCLUDE=${AMAZON_INCLUDE}
HETZNER_INCLUDE=${HETZNER_INCLUDE}
DIGITALOCEAN_INCLUDE=${DIGITALOCEAN_INCLUDE}
OVH_INCLUDE=${OVH_INCLUDE}
GOOGLE_INCLUDE=${GOOGLE_INCLUDE}
AKAMAI_INCLUDE=${AKAMAI_INCLUDE}
DEFAULT_INTERFACE=
DEFAULT_IP=
CLEAR_HOSTS=y" > /tmp/antizapret/setup/root/antizapret/setup

#
# Выставляем разрешения
find /tmp/antizapret -type f -exec chmod 644 {} +
find /tmp/antizapret -type d -exec chmod 755 {} +
find /tmp/antizapret -type f \( -name '*.sh' -o -name '*.py' \) -execdir chmod +x {} +

# Копируем нужное, удаляем не нужное
find /tmp/antizapret -name '.gitkeep' -delete
rm -rf /root/antizapret
cp -r /tmp/antizapret/setup/* /
rm -rf /tmp/dnslib
rm -rf /tmp/antizapret

#
# Настраиваем DNS в AntiZapret VPN
if [[ "$ANTIZAPRET_DNS" == "2" ]]; then
	# Cloudflare+Quad9
	sed -i "s/'62\.76\.76\.62', '62\.76\.62\.76', '195\.208\.4\.1', '195\.208\.5\.1'/'1.1.1.1', '1.0.0.1', '9.9.9.10', '149.112.112.10'/" /etc/knot-resolver/kresd.conf
elif [[ "$ANTIZAPRET_DNS" == "3" ]]; then
	# Comss
	sed -i "s/'62\.76\.76\.62', '62\.76\.62\.76', '195\.208\.4\.1', '195\.208\.5\.1'/'83.220.169.155', '212.109.195.93'/" /etc/knot-resolver/kresd.conf
	sed -i "s/'1\.1\.1\.1', '1\.0\.0\.1', '9\.9\.9\.10', '149\.112\.112\.10'/'83.220.169.155', '212.109.195.93'/" /etc/knot-resolver/kresd.conf
elif [[ "$ANTIZAPRET_DNS" == "4" ]]; then
	# Xbox
	sed -i "s/'62\.76\.76\.62', '62\.76\.62\.76', '195\.208\.4\.1', '195\.208\.5\.1'/'176.99.11.77', '80.78.247.254'/" /etc/knot-resolver/kresd.conf
	sed -i "s/'1\.1\.1\.1', '1\.0\.0\.1', '9\.9\.9\.10', '149\.112\.112\.10'/'176.99.11.77', '80.78.247.254'/" /etc/knot-resolver/kresd.conf
elif [[ "$ANTIZAPRET_DNS" == "5" ]]; then
	# Malw
	sed -i "s/'62\.76\.76\.62', '62\.76\.62\.76', '195\.208\.4\.1', '195\.208\.5\.1'/'46.226.165.53', '64.188.98.242'/" /etc/knot-resolver/kresd.conf
	sed -i "s/'1\.1\.1\.1', '1\.0\.0\.1', '9\.9\.9\.10', '149\.112\.112\.10'/'46.226.165.53', '64.188.98.242'/" /etc/knot-resolver/kresd.conf
fi

#
# Настраиваем DNS в обычном VPN
if [[ "$VPN_DNS" == "2" ]]; then
	# Quad9
	sed -i '/push "dhcp-option DNS 1\.1\.1\.1"/,+1c push "dhcp-option DNS 9.9.9.10"\npush "dhcp-option DNS 149.112.112.10"' /etc/openvpn/server/vpn*.conf
	sed -i 's/1\.1\.1\.1, 1\.0\.0\.1/9.9.9.10, 149.112.112.10/' /etc/wireguard/templates/vpn-client*.conf
elif [[ "$VPN_DNS" == "3" ]]; then
	# Google
	sed -i '/push "dhcp-option DNS 1\.1\.1\.1"/,+1c push "dhcp-option DNS 8.8.8.8"\npush "dhcp-option DNS 8.8.4.4"' /etc/openvpn/server/vpn*.conf
	sed -i 's/1\.1\.1\.1, 1\.0\.0\.1/8.8.8.8, 8.8.4.4/' /etc/wireguard/templates/vpn-client*.conf
elif [[ "$VPN_DNS" == "4" ]]; then
	# AdGuard
	sed -i '/push "dhcp-option DNS 1\.1\.1\.1"/,+1c push "dhcp-option DNS 94.140.14.14"\npush "dhcp-option DNS 94.140.15.15"' /etc/openvpn/server/vpn*.conf
	sed -i 's/1\.1\.1\.1, 1\.0\.0\.1/94.140.14.14, 94.140.15.15/' /etc/wireguard/templates/vpn-client*.conf
elif [[ "$VPN_DNS" == "5" ]]; then
	# Comss
	sed -i '/push "dhcp-option DNS 1\.1\.1\.1"/,+1c push "dhcp-option DNS 83.220.169.155"\npush "dhcp-option DNS 212.109.195.93"' /etc/openvpn/server/vpn*.conf
	sed -i 's/1\.1\.1\.1, 1\.0\.0\.1/83.220.169.155, 212.109.195.93/' /etc/wireguard/templates/vpn-client*.conf
elif [[ "$VPN_DNS" == "6" ]]; then
	# Xbox
	sed -i '/push "dhcp-option DNS 1\.1\.1\.1"/,+1c push "dhcp-option DNS 176.99.11.77"\npush "dhcp-option DNS 80.78.247.254"' /etc/openvpn/server/vpn*.conf
	sed -i 's/1\.1\.1\.1, 1\.0\.0\.1/176.99.11.77, 80.78.247.254/' /etc/wireguard/templates/vpn-client*.conf
elif [[ "$VPN_DNS" == "7" ]]; then
	# Malw
	sed -i '/push "dhcp-option DNS 1\.1\.1\.1"/,+1c push "dhcp-option DNS 46.226.165.53"\npush "dhcp-option DNS 64.188.98.242"' /etc/openvpn/server/vpn*.conf
	sed -i 's/1\.1\.1\.1, 1\.0\.0\.1/46.226.165.53, 64.188.98.242/' /etc/wireguard/templates/vpn-client*.conf
fi

#
# Используем альтернативные диапазоны ip-адресов
# 10.28.0.0/14 => 172.28.0.0/14
if [[ "$ALTERNATIVE_IP" == "y" ]]; then
	sed -i 's/10\.30\./172\.30\./g' /root/antizapret/proxy.py
	sed -i 's/10\.29\./172\.29\./g' /etc/knot-resolver/kresd.conf
	sed -i 's/10\./172\./g' /etc/openvpn/server/*.conf
	sed -i 's/10\./172\./g' /etc/wireguard/templates/*.conf
	find /etc/wireguard -name '*.conf' -exec sed -i 's/s = 10\./s = 172\./g' {} +
else
	find /etc/wireguard -name '*.conf' -exec sed -i 's/s = 172\./s = 10\./g' {} +
fi

#
# Запрещаем несколько одновременных подключений к OpenVPN для одного клиента
if [[ "$OPENVPN_DUPLICATE" == "n" ]]; then
	sed -i '/^duplicate-cn/s/^/#/' /etc/openvpn/server/*.conf
fi

#
# Включим подробные логи в OpenVPN
if [[ "$OPENVPN_LOG" == "y" ]]; then
	sed -i '/^#\(verb\|log\)/s/^#//' /etc/openvpn/server/*.conf
fi

#
# Загружаем и создаем списки исключений IP-адресов
/root/antizapret/doall.sh ip

#
# Настраиваем сервера OpenVPN и WireGuard/AmneziaWG для первого запуска
# Пересоздаем для всех существующих пользователей файлы подключений
# Если пользователей нет, то создаем новых пользователей 'antizapret-client' для OpenVPN и WireGuard/AmneziaWG
/root/antizapret/client.sh 7

#
# Включим обновляемые службы
systemctl enable kresd@1
systemctl enable kresd@2
systemctl enable antizapret
systemctl enable antizapret-update
systemctl enable antizapret-update.timer
systemctl enable openvpn-server@antizapret-udp
systemctl enable openvpn-server@antizapret-tcp
systemctl enable openvpn-server@vpn-udp
systemctl enable openvpn-server@vpn-tcp
systemctl enable wg-quick@antizapret
systemctl enable wg-quick@vpn

ERRORS=""

if [[ "$OPENVPN_PATCH" != "0" ]]; then
	if ! /root/antizapret/patch-openvpn.sh "$OPENVPN_PATCH"; then
		ERRORS+="\n\e[1;31mAnti-censorship patch for OpenVPN has not installed!\e[0m Please run '/root/antizapret/patch-openvpn.sh' after rebooting\n"
	fi
fi

if [[ "$OPENVPN_DCO" == "y" ]]; then
	if ! /root/antizapret/openvpn-dco.sh y; then
		ERRORS+="\n\e[1;31mOpenVPN DCO has not turn on!\e[0m Please run '/root/antizapret/openvpn-dco.sh y' after rebooting\n"
	fi
fi

#
# Если есть ошибки, выводим их
if [[ -n "$ERRORS" ]]; then
	echo -e "$ERRORS"
fi

#
# Создадим файл подкачки размером 1 Гб если его нет
if [[ -z "$(swapon --show)" ]]; then
	set +e
	SWAPFILE="/swapfile"
	SWAPSIZE=1024
	dd if=/dev/zero of=$SWAPFILE bs=1M count=$SWAPSIZE
	chmod 600 "$SWAPFILE"
	mkswap "$SWAPFILE"
	swapon "$SWAPFILE"
	echo "$SWAPFILE none swap sw 0 0" >> /etc/fstab
fi

echo
echo -e '\e[1;32mAntiZapret VPN + full VPN installed successfully!\e[0m'
echo 'Rebooting...'

#
# Перезагружаем
reboot
