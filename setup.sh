#!/bin/bash
#
# Скрипт для автоматического развертывания AntiZapret VPN + обычный VPN
#
# https://github.com/GubernievS/AntiZapret-VPN
#
# Протестировано на Ubuntu 22.04/24.04 и Debian 11/12 - Процессор: 1 core Память: 1 Gb Хранилище: 10 Gb
#
# Установка:
# 1. Устанавливать на Ubuntu 22.04/24.04 или Debian 11/12 (рекомендуется Ubuntu 24.04)
# 2. В терминале под root выполнить:
# apt update && apt install -y git && git clone https://github.com/GubernievS/AntiZapret-VPN.git tmp && chmod +x tmp/setup.sh && tmp/setup.sh
# 3. Дождаться перезагрузки сервера и скопировать файлы подключений (*.ovpn и *.conf) с сервера из папки /root

#
# Удаление или перемещение файлов и папок при обновлении
systemctl stop openvpn-generate-keys 2> /dev/null
systemctl disable openvpn-generate-keys 2> /dev/null
systemctl stop openvpn-server@antizapret 2> /dev/null
systemctl disable openvpn-server@antizapret 2> /dev/null
rm -f /etc/sysctl.d/10-conntrack.conf
rm -f /etc/systemd/network/eth.network
rm -f /etc/systemd/network/host.network
rm -f /etc/systemd/system/openvpn-generate-keys.service
rm -f /etc/openvpn/server/antizapret.conf
rm -f /etc/openvpn/server/logs/*
rm -f /etc/openvpn/client/templates/openvpn-udp-unified.conf
rm -f /etc/openvpn/client/templates/openvpn-tcp-unified.conf
rm -f /root/upgrade.sh
rm -f /root/generate.sh
rm -f /root/Enable-OpenVPN-DCO.sh
rm -f /root/upgrade-openvpn.sh
if [ -d "/root/easy-rsa-ipsec/easyrsa3/pki" ]; then
	mkdir /root/easyrsa3
	mv /root/easy-rsa-ipsec/easyrsa3/pki /root/easyrsa3/pki
fi
rm -rf /root/easy-rsa-ipsec
apt purge python3-dnslib > /dev/null 2>&1
systemctl daemon-reload

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
echo "OpenVPN + WireGuard"
echo "Version from 30.09.2024"

#
# Спрашиваем о настройках
echo ""
until [[ $PATCH =~ (y|n) ]]; do
	read -rp "Install anti-censorship patch for OpenVPN (UDP only)? [y/n]: " -e -i y PATCH
done
if [[ "$PATCH" == "y" ]]; then
	echo ""
	echo "Choose a version of the anti-censorship patch for OpenVPN (UDP only):"
	echo "    1) Strong     - Recommended for default"
	echo "    2) Error-free - If the strong patch causes a connection error on your device or router"
	until [[ $ALGORITHM =~ ^[1-2]$ ]]; do
		read -rp "Version choice [1-2]: " -e -i 1 ALGORITHM
	done
fi
echo ""
until [[ $DCO =~ (y|n) ]]; do
	read -rp "Turn on OpenVPN DCO? [y/n]: " -e -i y DCO
done
echo ""
echo "AdGuard DNS server is for blocking ads, trackers and phishing websites"
until [[ $DNS_ANTIZAPRET =~ (y|n) ]]; do
	read -rp $'Use AdGuard DNS for \e[1;32mAntiZapret VPN\e[0m (antizapret-*)? [y/n]: ' -e -i n DNS_ANTIZAPRET
done
echo ""
echo "AdGuard DNS server is for blocking ads, trackers and phishing websites"
until [[ $DNS_VPN =~ (y|n) ]]; do
	read -rp $'Use AdGuard DNS for \e[1;32mtraditional VPN\e[0m (vpn-*)? [y/n]: ' -e -i n DNS_VPN
done
echo ""
echo "Default IP address range:      10.28.0.0/14"
echo "Alternative IP address range: 172.28.0.0/14"
until [[ $IP =~ (y|n) ]]; do
	read -rp "Use alternative range of IP addresses? [y/n]: " -e -i n IP
done
echo ""

#
# Удалим скомпилированный патченный OpenVPN
if [[ -d "/root/openvpn" ]]; then
	make -C /root/openvpn uninstall || true
	rm -rf /root/openvpn
fi

#
# Добавляем репозитории
mkdir -p /etc/apt/keyrings

apt update
DEBIAN_FRONTEND=noninteractive apt install --reinstall -y gnupg2 curl

#
# Knot-Resolver
curl -fsSL https://pkg.labs.nic.cz/gpg -o /usr/share/keyrings/cznic-labs-pkg.gpg
echo "deb [signed-by=/usr/share/keyrings/cznic-labs-pkg.gpg] https://pkg.labs.nic.cz/knot-resolver $(lsb_release -cs) main" > /etc/apt/sources.list.d/cznic-labs-knot-resolver.list

#
# OpenVPN
curl -fsSL https://swupdate.openvpn.net/repos/repo-public.gpg | gpg --dearmor > /etc/apt/keyrings/openvpn-repo-public.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/openvpn-repo-public.gpg] https://build.openvpn.net/debian/openvpn/release/2.6 $(lsb_release -cs) main" > /etc/apt/sources.list.d/openvpn-aptrepo.list

#
# Обновляем систему
apt update
DEBIAN_FRONTEND=noninteractive apt full-upgrade -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold"
apt autoremove -y

#
# Ставим необходимые пакеты
DEBIAN_FRONTEND=noninteractive apt install --reinstall -y git openvpn iptables easy-rsa ferm gawk knot-resolver idn sipcalc python3-pip wireguard
PIP_BREAK_SYSTEM_PACKAGES=1 pip3 install --force-reinstall  dnslib

#
# Сохраняем пользовательские конфигурации в файлах *-custom.txt
mv /root/antizapret/config/*-custom.txt /root || true

#
# Обновляем antizapret до последней версии из репозитория
rm -rf /root/antizapret
git clone https://bitbucket.org/anticensority/antizapret-pac-generator-light.git /root/antizapret

#
# Восстанавливаем пользовательские конфигурации
mv /root/*-custom.txt /root/antizapret/config || true

#
# Копируем нужные файлы и папки, удаляем не нужные
script_dir=$(dirname "$(readlink -f "$0")")
find /root/antizapret -name '*.gitkeep' -delete
rm -rf /root/antizapret/.git
find $script_dir -name '*.gitkeep' -delete
cp -r $script_dir/setup/* / 
rm -rf $script_dir

#
# Выставляем разрешения на запуск скриптов
find /root -name "*.sh" -execdir chmod u+x {} +
chmod u+x /root/dnsmap/proxy.py

#
# Используем альтернативные диапазоны ip-адресов
# 10.28.0.0/14 => 172.28.0.0/14
if [[ "$IP" = "y" ]]; then
	sed -i 's/10\./172\./g' /root/dnsmap/proxy.py
	sed -i 's/10\./172\./g' /etc/openvpn/server/*.conf
	sed -i 's/10\./172\./g' /etc/knot-resolver/kresd.conf
	sed -i 's/10\./172\./g' /etc/ferm/ferm.conf
	sed -i 's/10\./172\./g' /etc/wireguard/templates/*.conf
	find /etc/wireguard -name '*.conf' -exec sed -i 's/s = 10\./s = 172\./g' {} +
else
	find /etc/wireguard -name '*.conf' -exec sed -i 's/s = 172\./s = 10\./g' {} +
fi

#
# Добавляем AdGuard DNS в AntiZapret VPN
if [[ "$DNS_ANTIZAPRET" = "y" ]]; then
	sed -i "s/'1.1.1.1', '1.0.0.1'/'94.140.14.14', '94.140.15.15', '76.76.2.44', '76.76.10.44'/" /etc/knot-resolver/kresd.conf
fi

#
# Добавляем AdGuard DNS в обычный VPN
if [[ "$DNS_VPN" = "y" ]]; then
	sed -i '/push "dhcp-option DNS 1\.1\.1\.1"/,+1c push "dhcp-option DNS 94.140.14.14"\npush "dhcp-option DNS 94.140.15.15"\npush "dhcp-option DNS 76.76.2.44"\npush "dhcp-option DNS 76.76.10.44"' /etc/openvpn/server/vpn*.conf
	sed -i "s/1.1.1.1, 1.0.0.1/94.140.14.14, 94.140.15.15, 76.76.2.44, 76.76.10.44/" /etc/knot-resolver/kresd.conf /etc/wireguard/templates/vpn-client.conf
fi

#
# Создаем в OpenVPN пользователя 'antizapret-client' и создаем *.ovpn файлы подключений в /root
/root/add-client.sh ovpn antizapret-client

#
# Создаем в WireGuard несколько пользователей 'antizapret-client' и создаем *.conf файлы подключений в /root
/root/add-client.sh wg antizapret-client1
/root/add-client.sh wg antizapret-client2
/root/add-client.sh wg antizapret-client3

#
# Включим все нужные службы
systemctl enable kresd@1
systemctl enable antizapret-update.service
systemctl enable antizapret-update.timer
systemctl enable dnsmap
systemctl enable openvpn-server@antizapret-udp
systemctl enable openvpn-server@antizapret-tcp
systemctl enable openvpn-server@vpn-udp
systemctl enable openvpn-server@vpn-tcp
systemctl enable wg-quick@antizapret
systemctl enable wg-quick@vpn

#
# Отключим ненужные службы
if systemctl list-unit-files | grep -q "^ufw.service"; then
	systemctl disable ufw
fi

if [[ "$PATCH" = "y" ]]; then
	/root/patch-openvpn.sh "$ALGORITHM"
fi

if [[ "$DCO" = "y" ]]; then
	if ! /root/enable-openvpn-dco.sh; then
	echo ""
	echo -e "\e[1;31mOpenVPN DCO has not enabled!\e[0m Please run './enable-openvpn-dco.sh' after rebooting"
fi
fi

echo ""
echo -e "\e[1;32mAntiZapret VPN + traditional VPN successful installation!\e[0m"
echo ""
echo "Rebooting..."

#
# Перезагружаем
reboot