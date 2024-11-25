#!/bin/bash
#
# Скрипт для установки на своём сервере AntiZapret VPN и обычного VPN
#
# https://github.com/GubernievS/AntiZapret-VPN
#

#
# Удаление или перемещение файлов и папок при обновлении
systemctl stop openvpn-generate-keys &>/dev/null
systemctl disable openvpn-generate-keys &>/dev/null
systemctl stop openvpn-server@antizapret &>/dev/null
systemctl disable openvpn-server@antizapret &>/dev/null
rm -f /etc/knot-resolver/knot-aliases-alt.conf
rm -f /etc/sysctl.d/10-conntrack.conf
rm -f /etc/sysctl.d/20-network.conf
rm -f /etc/systemd/network/eth.network
rm -f /etc/systemd/network/host.network
rm -f /etc/systemd/system/openvpn-generate-keys.service
rm -f /etc/openvpn/server/antizapret.conf
rm -f /etc/openvpn/server/logs/*
rm -f /etc/openvpn/server/keys/dh2048.pem
rm -f /etc/openvpn/client/templates/*
rm -f /etc/wireguard/templates/*
rm -f /etc/apt/sources.list.d/amnezia*
rm -f /var/lib/knot-resolver/*
rm -f /usr/share/keyrings/amnezia.gpg
rm -f /root/upgrade.sh
rm -f /root/generate.sh
rm -f /root/Enable-OpenVPN-DCO.sh
rm -f /root/upgrade-openvpn.sh
rm -f /root/*.ovpn
rm -f /root/*.conf
rm -rf /root/easy-rsa-ipsec
rm -rf /root/.gnupg
rm -rf /root/dnsmap
rm -rf /root/antizapret/dnsmap
if [[ -d "/root/easy-rsa-ipsec/easyrsa3/pki" ]]; then
	mkdir -p /root/easyrsa3
	mv -f /root/easy-rsa-ipsec/easyrsa3/pki /root/easyrsa3/pki &>/dev/null
fi
mv -f /root/openvpn /usr/local/src/openvpn &>/dev/null
mv -f /etc/knot-resolver/blocked-hosts.conf /etc/knot-resolver/hosts.conf &>/dev/null
apt-get purge python3-dnslib gnupg2 amneziawg &>/dev/null

#
# Завершим выполнение скрипта при ошибке
set -e

#
# Обработка ошибок
handle_error() {
	echo ""
	echo -e "\e[1;31mError occurred at line $1 while executing: $2\e[0m"
	echo ""
	echo "$(lsb_release -d | awk -F'\t' '{print $2}') $(uname -r) $(date)"
	exit 1
}
trap 'handle_error $LINENO "$BASH_COMMAND"' ERR

if [[ "$(systemd-detect-virt)" == "openvz" || "$(systemd-detect-virt)" == "lxc" ]]; then
	echo "OpenVZ and LXC is not supported!"
	exit 2
fi

#
# Проверка прав root
if [[ "$EUID" -ne 0 ]]; then
	echo "You need to run this as root permission!"
	exit 3
fi

SCRIPT_DIR=$(dirname "$(readlink -f "$0")")
cd /root

#
# Проверка версии системы
OS=$(lsb_release -si | tr '[:upper:]' '[:lower:]')
VERSION=$(lsb_release -rs | cut -d '.' -f1)

if [[ $OS == "debian" ]]; then
	if [[ $VERSION -lt 11 ]]; then
		echo "Your version of Debian is not supported!"
		exit 4
	fi
elif [[ $OS == "ubuntu" ]]; then
	if [[ $VERSION -lt 22 ]]; then
		echo "Your version of Ubuntu is not supported!"
		exit 5
	fi
elif [[ $OS != "debian" ]] && [[ $OS != "ubuntu" ]]; then
	echo "Your version of Linux is not supported!"
	exit 6
fi

echo ""
echo -e "\e[1;32mInstalling AntiZapret VPN + traditional VPN...\e[0m"
echo "OpenVPN + WireGuard + AmneziaWG"
echo ""

PATCH=""
ALGORITHM=""
DCO=""
ADBLOCK=""
DNS=""
IP=""
TCP=""
UDP=""
DUPLICATE=""

#
# Спрашиваем о настройках
until [[ $PATCH =~ (y|n) ]]; do
	read -rp "Install anti-censorship patch for OpenVPN (UDP only)? [y/n]: " -e -i y PATCH
done
if [[ "$PATCH" == "y" ]]; then
	echo ""
	echo "Choose a version of the anti-censorship patch for OpenVPN (UDP only):"
	echo "    1) Strong     - Recommended by default"
	echo "    2) Error-free - If the Strong patch causes a connection error on your device or Mikrotik router"
	until [[ $ALGORITHM =~ ^[1-2]$ ]]; do
		read -rp "Version choice [1-2]: " -e -i 1 ALGORITHM
	done
fi
echo ""
echo "OpenVPN DCO lowers CPU load, saves battery on mobile devices, boosts data speeds, and only supports AES-128-GCM and AES-256-GCM encryption protocols"
until [[ $DCO =~ (y|n) ]]; do
	read -rp "Turn on OpenVPN DCO? [y/n]: " -e -i y DCO
done
echo ""
until [[ $ADBLOCK =~ (y|n) ]]; do
	read -rp $'Enable block ads, trackers and phishing in \e[1;32mAntiZapret VPN\e[0m (antizapret-*)? [y/n]: ' -e -i y ADBLOCK
done
echo ""
echo -e "Choose DNS resolvers for \e[1;32mtraditional VPN\e[0m (vpn-*):"
echo "    1) Cloudflare+Google - The fastest and most reliable - Recommended by default"
echo "    2) Yandex Basic      - Use for problems loading sites from Russia"
echo "    3) AdGuard+replica   - For blocking ads, trackers and phishing"
until [[ $DNS =~ ^[1-3]$ ]]; do
	read -rp "DNS choice [1-3]: " -e -i 1 DNS
done
echo ""
echo "Default IP address range:      10.28.0.0/14"
echo "Alternative IP address range: 172.28.0.0/14"
until [[ $IP =~ (y|n) ]]; do
	read -rp "Use alternative range of IP addresses? [y/n]: " -e -i n IP
done
echo ""
until [[ $TCP =~ (y|n) ]]; do
	read -rp "Use TCP ports 80 and 443 as backup for OpenVPN connections? [y/n]: " -e -i y TCP
done
echo ""
until [[ $UDP =~ (y|n) ]]; do
	read -rp "Use UDP ports 80 and 443 as backup for OpenVPN connections? [y/n]: " -e -i y UDP
done
echo ""
until [[ $DUPLICATE =~ (y|n) ]]; do
	read -rp "Deny multiple clients connecting to OpenVPN with a duplicate configuration file (*.ovpn)? [y/n]: " -e -i n DUPLICATE
done
echo ""

#
# Удалим скомпилированный патченный OpenVPN
if [[ -d "/usr/local/src/openvpn" ]]; then
	make -C /usr/local/src/openvpn uninstall || true
	rm -rf /usr/local/src/openvpn
fi

apt-get update
DEBIAN_FRONTEND=noninteractive apt-get install --reinstall -y curl gpg procps

#
# Отключим ipv6
if [ -f /proc/sys/net/ipv6/conf/all/disable_ipv6 ]; then
	sysctl -w net.ipv6.conf.all.disable_ipv6=1
fi

#
# Добавляем репозитории
mkdir -p /etc/apt/keyrings

#
# Knot Resolver
curl -fsSL https://pkg.labs.nic.cz/gpg -o /usr/share/keyrings/cznic-labs-pkg.gpg
echo "deb [signed-by=/usr/share/keyrings/cznic-labs-pkg.gpg] https://pkg.labs.nic.cz/knot-resolver $(lsb_release -cs) main" > /etc/apt/sources.list.d/cznic-labs-knot-resolver.list

#
# OpenVPN
curl -fsSL https://swupdate.openvpn.net/repos/repo-public.gpg | gpg --dearmor > /etc/apt/keyrings/openvpn-repo-public.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/openvpn-repo-public.gpg] https://build.openvpn.net/debian/openvpn/release/2.6 $(lsb_release -cs) main" > /etc/apt/sources.list.d/openvpn-aptrepo.list

#
# Обновляем систему
apt-get update
DEBIAN_FRONTEND=noninteractive apt-get full-upgrade -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold"

#
# Ставим необходимые пакеты
DEBIAN_FRONTEND=noninteractive apt-get install --reinstall -y git openvpn iptables easy-rsa ferm gawk knot-resolver idn sipcalc python3-pip wireguard diffutils dnsutils
apt-get autoremove -y
apt-get autoclean
PIP_BREAK_SYSTEM_PACKAGES=1 pip3 install --force-reinstall dnslib

#
# Сохраняем пользовательские настройки и пользовательский обработчик custom.sh
mv -f /root/antizapret/config/* $SCRIPT_DIR/setup/root/antizapret/config || true
mv -f /root/antizapret/custom.sh $SCRIPT_DIR/setup/root/antizapret/custom.sh || true

#
# Восстанавливаем из бэкапа пользователей vpn
mv -f /root/easyrsa3 $SCRIPT_DIR/setup/etc/openvpn || true
mv -f /root/wireguard/antizapret.conf $SCRIPT_DIR/setup/etc/wireguard || true
mv -f /root/wireguard/vpn.conf $SCRIPT_DIR/setup/etc/wireguard || true
mv -f /root/wireguard/key $SCRIPT_DIR/setup/etc/wireguard || true
rm -rf /root/wireguard

#
# Копируем нужные файлы и папки, удаляем не нужные
find "$SCRIPT_DIR" -name '.gitkeep' -delete
rm -rf /root/antizapret
cp -r $SCRIPT_DIR/setup/* /
rm -rf $SCRIPT_DIR

#
# Выставляем разрешения на запуск скриптов
find /root -name "*.sh" -execdir chmod +x {} +
chmod +x /root/antizapret/proxy.py

#
# Используем альтернативные диапазоны ip-адресов
# 10.28.0.0/14 => 172.28.0.0/14
if [[ "$IP" = "y" ]]; then
	sed -i 's/10\./172\./g' /root/antizapret/proxy.py
	sed -i 's/10\./172\./g' /etc/openvpn/server/*.conf
	sed -i 's/10\./172\./g' /etc/knot-resolver/kresd.conf
	sed -i 's/10\./172\./g' /etc/ferm/ferm.conf
	sed -i 's/10\./172\./g' /etc/wireguard/templates/*.conf
	find /etc/wireguard -name '*.conf' -exec sed -i 's/s = 10\./s = 172\./g' {} +
else
	find /etc/wireguard -name '*.conf' -exec sed -i 's/s = 172\./s = 10\./g' {} +
fi

#
# Не блокируем рекламу, трекеры и фишинг в AntiZapret VPN
if [[ "$ADBLOCK" = "n" ]]; then
	sed -i '/adblock-hosts\.rpz/s/^/--/' /etc/knot-resolver/kresd.conf
fi

#
# Настраиваем DNS в обычном VPN
if [[ "$DNS" = "2" ]]; then
	sed -i '/push "dhcp-option DNS 1\.1\.1\.1"/,+3c push "dhcp-option DNS 77.88.8.8"\npush "dhcp-option DNS 77.88.8.1"' /etc/openvpn/server/vpn*.conf
	sed -i "s/1.1.1.1, 1.0.0.1, 8.8.8.8, 8.8.4.4/77.88.8.8, 77.88.8.1/" /etc/wireguard/templates/vpn-client*.conf
elif [[ "$DNS" = "3" ]]; then
	sed -i '/push "dhcp-option DNS 1\.1\.1\.1"/,+3c push "dhcp-option DNS 94.140.14.14"\npush "dhcp-option DNS 94.140.15.15"\npush "dhcp-option DNS 76.76.2.44"\npush "dhcp-option DNS 76.76.10.44"' /etc/openvpn/server/vpn*.conf
	sed -i "s/1.1.1.1, 1.0.0.1, 8.8.8.8, 8.8.4.4/94.140.14.14, 94.140.15.15, 76.76.2.44, 76.76.10.44/" /etc/wireguard/templates/vpn-client*.conf
fi

#
# Не используем резервные порты 80 и 443 для OpenVPN TCP
if [[ "$TCP" = "n" ]]; then
	sed -i '/ \(80\|443\) tcp/s/^/#/' /etc/openvpn/client/templates/*.conf
	sed -i '/tcp.* \(80\|443\)/s/^/#/' /etc/ferm/ferm.conf
fi

#
# Не используем резервные порты 80 и 443 для OpenVPN UDP
if [[ "$UDP" = "n" ]]; then
	sed -i '/ \(80\|443\) udp/s/^/#/' /etc/openvpn/client/templates/*.conf
	sed -i '/udp.* \(80\|443\)/s/^/#/' /etc/ferm/ferm.conf
fi

#
# Запрещаем несколько одновременных подключений к OpenVPN для одного клиента
if [[ "$DUPLICATE" = "y" ]]; then
	sed -i '/duplicate-cn/s/^/#/' /etc/openvpn/server/*.conf
fi

#
# Проверяем доступность DNS серверов для proxy.py и выберем первый рабочий
DNS_SERVERS="127.0.0.53 1.1.1.1 1.0.0.1 8.8.8.8 8.8.4.4"
for DNS_SERVER in $DNS_SERVERS; do
	if dig @$DNS_SERVER fb.com +short +dnssec &>/dev/null; then
		sed -i "s/127\.0\.0\.53/$DNS_SERVER/g" /root/antizapret/proxy.py
		break
	fi
done

#
# Создаем список исключений IP-адресов
/root/antizapret/parse.sh ip

#
# Настраиваем сервера OpenVPN и WireGuard/AmneziaWG для первого запуска
# Пересоздаем для всех существующих пользователей файлы подключений в папке /root/vpn
# Если пользователей нет, то создаем новых пользователей 'antizapret-client' для OpenVPN и WireGuard/AmneziaWG
/root/add-client.sh init

#
# Включим нужные службы
systemctl enable kresd@1
systemctl enable dnsmap
systemctl enable antizapret-update.service
systemctl enable antizapret-update.timer
systemctl enable openvpn-server@antizapret-udp
systemctl enable openvpn-server@antizapret-tcp
systemctl enable openvpn-server@vpn-udp
systemctl enable openvpn-server@vpn-tcp
systemctl enable wg-quick@antizapret
systemctl enable wg-quick@vpn

#
# Отключим ненужные службы
systemctl disable ufw &>/dev/null || true
systemctl disable firewalld &>/dev/null || true

#
# Сохраним текущие правила iptables для ferm
import-ferm > /etc/ferm/iptables.conf || true

ERRORS=""

if [[ "$PATCH" = "y" ]]; then
	if ! /root/patch-openvpn.sh "$ALGORITHM"; then
		ERRORS+="\n\e[1;31mAnti-censorship patch for OpenVPN has not installed!\e[0m Please run './patch-openvpn.sh' after rebooting\n"
	fi
fi

if [[ "$DCO" = "y" ]]; then
	if ! /root/enable-openvpn-dco.sh; then
		ERRORS+="\n\e[1;31mOpenVPN DCO has not enabled!\e[0m Please run './enable-openvpn-dco.sh' after rebooting\n"
	fi
fi

# Если есть ошибки, выводим их
if [[ -n "$ERRORS" ]]; then
	echo -e "$ERRORS"
fi

echo ""
echo -e "\e[1;32mAntiZapret VPN + traditional VPN successful installation!\e[0m"
echo ""
echo "Rebooting..."

#
# Перезагружаем
reboot