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
# 3. Дождаться перезагрузки сервера и скопировать файлы подключений (*.ovpn) с сервера из папки /root

set -e

#
# Обработка ошибок
handle_error() {
	echo ""
	echo "Error occurred at line $1 while executing: $2"
	echo ""
	echo "$(lsb_release -d | awk -F'\t' '{print $2}') $(uname -r) $(date)"
	exit 1
}
trap 'handle_error $LINENO "$BASH_COMMAND"' ERR

#
# Проверка прав root
if [[ "$EUID" -ne 0 ]]; then
	echo "You need to run this as root permission!"
	exit 2
fi

#
# Проверка версии системы
ID=$(lsb_release -si | tr '[:upper:]' '[:lower:]')
VERSION=$(lsb_release -rs | cut -d '.' -f1)

if [[ $ID == "debian" ]]; then
	if [[ $VERSION -lt 11 ]]; then
		echo "Your version of Debian is not supported!"
		exit 3
	fi
elif [[ $ID == "ubuntu" ]]; then
	if [[ $VERSION -lt 22 ]]; then
		echo "Your version of Ubuntu is not supported!"
		exit 4
	fi
elif [[ $ID != "debian" ]] && [[ $ID != "ubuntu" ]]; then
	echo "Your version of Linux is not supported!"
	exit 5
fi

echo ""
echo -e "\e[1;32mInstalling AntiZapret VPN + traditional VPN\e[0m"
echo ""
echo "Version from 24.09.2024"
echo ""

#
# Спрашиваем о настройках
echo ""
until [[ $PATCH =~ (y|n) ]]; do
	read -rp "Install anti-censorship patch for OpenVPN? (UDP only) [y/n]: " -e -i y PATCH
done
echo ""
until [[ $DCO =~ (y|n) ]]; do
	read -rp "Turn on OpenVPN DCO? [y/n]: " -e -i y DCO
done
echo ""
echo "AdGuard DNS server is for blocking ads, trackers, malware, and phishing websites"
until [[ $DNS_ANTIZAPRET =~ (y|n) ]]; do
	read -rp $'Use AdGuard DNS for \e[1;32mAntiZapret VPN\e[0m? [y/n]: ' -e -i n DNS_ANTIZAPRET
done
echo ""
echo "AdGuard DNS server is for blocking ads, trackers, malware, and phishing websites"
until [[ $DNS_VPN =~ (y|n) ]]; do
	read -rp $'Use AdGuard DNS for \e[1;32mtraditional VPN\e[0m? [y/n]: ' -e -i n DNS_VPN
done
echo ""
echo "Default IP address range:      10.28.0.0/14"
echo "Alternative IP address range: 172.28.0.0/14"
until [[ $IP =~ (y|n) ]]; do
	read -rp "Use alternative range of IP addresses? [y/n]: " -e -i n IP
done
echo ""

#
# Удалим скомпилированный OpenVPN
if [[ -d "/root/openvpn" ]]; then
	make -C /root/openvpn uninstall || true
	rm -rf /root/openvpn
fi

#
# Добавляем репозитории
mkdir -p /etc/apt/keyrings

apt update
DEBIAN_FRONTEND=noninteractive apt install --reinstall -y gpg curl

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
DEBIAN_FRONTEND=noninteractive apt install --reinstall -y git openvpn iptables easy-rsa ferm gawk knot-resolver idn sipcalc python3-pip
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
# Удаляем исключения из исключений антизапрета
sed -i "/\b\(googleusercontent\|cloudfront\|deviantart\|multikland\|synchroncode\|placehere\|delivembed\)\b/d" /root/antizapret/config/exclude-regexp-dist.awk

#
# Исправляем шаблон для корректной работы gawk начиная с версии 5
sed -i "s/\\\_/_/" /root/antizapret/parse.sh

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
chmod +x /root/dnsmap/proxy.py

#
# Создаем пользователя 'client', его ключи 'antizapret-client', ключи сервера 'antizapret-server' и создаем *.ovpn файлы подключений в /root
/root/add-client.sh client

#
# Добавляем AdGuard DNS в AntiZapret VPN
if [[ "$DNS_ANTIZAPRET" = "y" ]]; then
	sed -i 's/1.1.1.1/94.140.14.14/g' /etc/knot-resolver/kresd.conf
	sed -i 's/1.0.0.1/94.140.15.15/g' /etc/knot-resolver/kresd.conf
fi

#
# Добавляем AdGuard DNS в обычный VPN
if [[ "$DNS_VPN" = "y" ]]; then
	sed -i 's/1.1.1.1/94.140.14.14/g' /etc/openvpn/server/vpn-udp.conf
	sed -i 's/1.0.0.1/94.140.15.15/g' /etc/openvpn/server/vpn-udp.conf
	sed -i 's/1.1.1.1/94.140.14.14/g' /etc/openvpn/server/vpn-tcp.conf
	sed -i 's/1.0.0.1/94.140.15.15/g' /etc/openvpn/server/vpn-tcp.conf
fi

#
# Используем альтернативные диапазоны ip-адресов
# 10.28.0.0/14 => 172.28.0.0/14
if [[ "$IP" = "y" ]]; then
	sed -i 's/10\./172\./g' /root/dnsmap/proxy.py
	sed -i 's/10\./172\./g' /etc/openvpn/server/vpn-udp.conf
	sed -i 's/10\./172\./g' /etc/openvpn/server/vpn-tcp.conf
	sed -i 's/10\./172\./g' /etc/openvpn/server/antizapret-udp.conf
	sed -i 's/10\./172\./g' /etc/openvpn/server/antizapret-tcp.conf
	sed -i 's/10\./172\./g' /etc/knot-resolver/kresd.conf
	sed -i 's/10\./172\./g' /etc/ferm/ferm.conf
fi

#
# Запустим все необходимые службы при загрузке
systemctl enable kresd@1
systemctl enable antizapret-update.service
systemctl enable antizapret-update.timer
systemctl enable dnsmap
systemctl enable openvpn-server@antizapret-udp
systemctl enable openvpn-server@antizapret-tcp
systemctl enable openvpn-server@vpn-udp
systemctl enable openvpn-server@vpn-tcp

if [[ "$PATCH" = "y" ]]; then
	/root/patch-openvpn.sh noreboot
fi

if [[ "$DCO" = "y" ]]; then
	/root/enable-openvpn-dco.sh noreboot
fi

echo ""
echo -e "\e[1;32mAntiZapret VPN + traditional VPN successful installation!\e[0m"
echo "Rebooting..."

#
# Перезагружаем
reboot