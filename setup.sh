#!/bin/bash
#
# Скрипт для установки на своём сервере AntiZapret VPN и обычного VPN
#
# https://github.com/GubernievS/AntiZapret-VPN
#

#
# Проверка прав root
if [[ "$EUID" -ne 0 ]]; then
	echo "Error: You need to run this as root!"
	exit 1
fi

cd /root

#
# Проверка на OpenVZ и LXC
if [[ "$(systemd-detect-virt)" == "openvz" || "$(systemd-detect-virt)" == "lxc" ]]; then
	echo "Error: OpenVZ and LXC are not supported!"
	exit 2
fi

#
# Проверка версии системы
OS=$(lsb_release -si | tr '[:upper:]' '[:lower:]')
VERSION=$(lsb_release -rs | cut -d '.' -f1)

if [[ $OS == "debian" ]]; then
	if [[ $VERSION -lt 11 ]]; then
		echo "Error: Your version of Debian is not supported!"
		exit 3
	fi
elif [[ $OS == "ubuntu" ]]; then
	if [[ $VERSION -lt 22 ]]; then
		echo "Error: Your version of Ubuntu is not supported!"
		exit 4
	fi
elif [[ $OS != "debian" ]] && [[ $OS != "ubuntu" ]]; then
	echo "Error: Your version of Linux is not supported!"
	exit 5
fi

#
# Проверка свободного места (минимум 2Гб)
if [[ $(df --output=avail / | tail -n 1) -lt $((2 * 1024 * 1024)) ]]; then
	echo "Error: Low disk space! You need 2GB of free space!"
	exit 6
fi

echo ""
echo -e "\e[1;32mInstalling AntiZapret VPN + traditional VPN...\e[0m"
echo "OpenVPN + WireGuard + AmneziaWG"

#
# Спрашиваем о настройках
echo ""
echo "Choose a version of the anti-censorship patch for OpenVPN (UDP only):"
echo "    0) None       - Do not install the anti-censorship patch, or remove if already installed"
echo "    1) Strong     - Recommended by default"
echo "    2) Error-free - Use if the Strong patch causes a connection error, recommended for Mikrotik routers"
until [[ "$OPENVPN_PATCH" =~ ^[0-2]$ ]]; do
	read -rp "Version choice [0-2]: " -e -i 1 OPENVPN_PATCH
done
echo ""
echo "OpenVPN DCO lowers CPU load, saves battery on mobile devices, boosts data speeds, and only supports AES-128-GCM, AES-256-GCM and CHACHA20-POLY1305 encryption protocols"
until [[ "$OPENVPN_DCO" =~ (y|n) ]]; do
	read -rp "Turn on OpenVPN DCO? [y/n]: " -e -i y OPENVPN_DCO
done
echo ""
echo -e "Choose DNS resolvers for \e[1;32mAntiZapret VPN\e[0m (antizapret-*):"
echo "    1) Standard  - Recommended by default"
echo "                   Blocked domains: Cloudflare + Quad9 (1.1.1.1, 1.0.0.1, 9.9.9.10, 149.112.112.10)"
echo "                   Not blocked domains: Yandex (77.88.8.8, 77.88.8.1)"
echo "    2) Comss.one - Use only for problems accessing blocked internet resources!"
echo "                   Use only if this server is geolocated in Russia, China, Iran, Syria, etc!"
echo "                   Enable additional proxying and hide this server IP on blocked internet resources"
echo "                   Enable blocking ads, trackers, malware and phishing websites (not customizable)"
echo "                   See more: https://www.comss.ru/page.php?id=7315"
echo "                   Blocked & not blocked domains: Comss.one (83.220.169.155, 212.109.195.93)"
echo "    3) No Yandex - Do not use Yandex - not recommended"
echo "                   Blocked & not blocked domains: Cloudflare + Quad9 (1.1.1.1, 1.0.0.1, 9.9.9.10, 149.112.112.10)"
until [[ "$ANTIZAPRET_DNS" =~ ^[1-3]$ ]]; do
	read -rp "DNS choice [1-3]: " -e -i 1 ANTIZAPRET_DNS
done
echo ""
echo -e "Choose DNS resolvers for \e[1;32mtraditional VPN\e[0m (vpn-*):"
echo "    1) Cloudflare + Quad9 - The fastest and most reliable - Recommended by default"
echo "                            (1.1.1.1, 1.0.0.1, 9.9.9.10, 149.112.112.10)"
echo "    2) Yandex             - Use for problems accessing internet resources from Russia"
echo "                            (77.88.8.8, 77.88.8.1)"
echo "    3) AdGuard            - Use for blocking ads, trackers, malware and phishing websites"
echo "                            (94.140.14.14, 94.140.15.15, 76.76.2.44, 76.76.10.44)"
until [[ "$VPN_DNS" =~ ^[1-3]$ ]]; do
	read -rp "DNS choice [1-3]: " -e -i 1 VPN_DNS
done
if [[ "$ANTIZAPRET_DNS" -eq 2 ]]; then
	ANTIZAPRET_ADBLOCK=n
else
	echo ""
	until [[ "$ANTIZAPRET_ADBLOCK" =~ (y|n) ]]; do
		read -rp $'Enable blocking of ads, trackers and phishing in \e[1;32mAntiZapret VPN\e[0m (antizapret-*) based on AdGuard and AdAway rules? [y/n]: ' -e -i y ANTIZAPRET_ADBLOCK
	done
fi
echo ""
echo "Default IP address range:      10.28.0.0/14"
echo "Alternative IP address range: 172.28.0.0/14"
until [[ "$ALTERNATIVE_IP" =~ (y|n) ]]; do
	read -rp "Use alternative range of IP addresses? [y/n]: " -e -i n ALTERNATIVE_IP
done
echo ""
until [[ "$OPENVPN_80_443_TCP" =~ (y|n) ]]; do
	read -rp "Use TCP ports 80 and 443 as backup for OpenVPN connections? [y/n]: " -e -i y OPENVPN_80_443_TCP
done
echo ""
until [[ "$OPENVPN_80_443_UDP" =~ (y|n) ]]; do
	read -rp "Use UDP ports 80 and 443 as backup for OpenVPN connections? [y/n]: " -e -i y OPENVPN_80_443_UDP
done
echo ""
until [[ "$OPENVPN_DUPLICATE" =~ (y|n) ]]; do
	read -rp "Allow multiple clients connecting to OpenVPN using the same profile file (*.ovpn)? [y/n]: " -e -i y OPENVPN_DUPLICATE
done
echo ""
until [[ "$OPENVPN_LOG" =~ (y|n) ]]; do
	read -rp "Enable detailed logs in OpenVPN? [y/n]: " -e -i n OPENVPN_LOG
done
echo ""
until [[ "$INSTALL_SSHGUARD" =~ (y|n) ]]; do
	read -rp "Install SSHGuard to protect this server from brute-force attacks on SSH? [y/n]: " -e -i y INSTALL_SSHGUARD
done
echo ""
echo "Warning! Network attack and scan protection may block the work of VPN or third-party applications!"
until [[ "$PROTECT_SERVER" =~ (y|n) ]]; do
	read -rp "Enable network attack and scan protection for this server? [y/n]: " -e -i y PROTECT_SERVER
done
echo ""
echo "Preparing for installation, please wait..."

#
# Ожидание пока выполняется apt-get
while pidof apt-get &>/dev/null; do
	echo "Waiting for apt-get to finish...";
	sleep 5;
done

#
# Отключим фоновые обновления системы
systemctl stop unattended-upgrades &>/dev/null
systemctl stop apt-daily.timer &>/dev/null
systemctl stop apt-daily-upgrade.timer &>/dev/null

#
# Удаление или перемещение файлов и папок при обновлении
systemctl stop openvpn-generate-keys &>/dev/null
systemctl disable openvpn-generate-keys &>/dev/null
systemctl stop openvpn-server@antizapret &>/dev/null
systemctl disable openvpn-server@antizapret &>/dev/null
systemctl stop dnsmap &>/dev/null
systemctl disable dnsmap &>/dev/null
systemctl stop ferm &>/dev/null
systemctl disable ferm &>/dev/null
systemctl stop openvpn-server@antizapret-no-cipher &>/dev/null
systemctl disable openvpn-server@antizapret-no-cipher &>/dev/null

rm -f /etc/sysctl.d/10-conntrack.conf
rm -f /etc/sysctl.d/20-network.conf
rm -f /etc/sysctl.d/99-antizapret.conf
rm -f /etc/systemd/network/eth.network
rm -f /etc/systemd/network/host.network
rm -f /etc/systemd/system/openvpn-generate-keys.service
rm -f /etc/systemd/system/dnsmap.service
#rm -f /etc/apt/sources.list.d/amnezia*
#rm -f /usr/share/keyrings/amnezia.gpg
rm -f /root/upgrade.sh
rm -f /root/generate.sh
rm -f /root/Enable-OpenVPN-DCO.sh
rm -f /root/upgrade-openvpn.sh
rm -f /root/create-swap.sh
rm -f /root/disable-openvpn-dco.sh
rm -f /root/enable-openvpn-dco.sh
rm -f /root/patch-openvpn.sh
rm -f /root/add-client.sh
rm -f /root/delete-client.sh
rm -f /root/*.ovpn
rm -f /root/*.conf

if [[ -d "/root/easy-rsa-ipsec/easyrsa3/pki" ]]; then
	mkdir -p /root/easyrsa3
	mv -f /root/easy-rsa-ipsec/easyrsa3/pki /root/easyrsa3/pki &>/dev/null
fi
mv -f /root/antizapret/custom.sh /root/antizapret/custom-doall.sh &>/dev/null

rm -rf /root/vpn
rm -rf /root/easy-rsa-ipsec
rm -rf /root/.gnupg
rm -rf /root/dnsmap
rm -rf /root/openvpn
rm -rf /etc/ferm

apt-get purge -y python3-dnslib &>/dev/null
apt-get purge -y gnupg2 &>/dev/null
apt-get purge -y ferm &>/dev/null
apt-get purge -y libpam0g-dev &>/dev/null
#apt-get purge -y amneziawg &>/dev/null

#
# Остановим и выключим обновляемые службы
systemctl stop kresd@1 &>/dev/null
systemctl stop kresd@2 &>/dev/null
systemctl stop antizapret &>/dev/null
systemctl stop antizapret-update.service &>/dev/null
systemctl stop antizapret-update.timer &>/dev/null
systemctl stop openvpn-server@antizapret-udp &>/dev/null
systemctl stop openvpn-server@antizapret-tcp &>/dev/null
systemctl stop openvpn-server@vpn-udp &>/dev/null
systemctl stop openvpn-server@vpn-tcp &>/dev/null
systemctl stop wg-quick@antizapret &>/dev/null
systemctl stop wg-quick@vpn &>/dev/null

systemctl disable kresd@1 &>/dev/null
systemctl disable kresd@2 &>/dev/null
systemctl disable antizapret &>/dev/null
systemctl disable antizapret-update.service &>/dev/null
systemctl disable antizapret-update.timer &>/dev/null
systemctl disable openvpn-server@antizapret-udp &>/dev/null
systemctl disable openvpn-server@antizapret-tcp &>/dev/null
systemctl disable openvpn-server@vpn-udp &>/dev/null
systemctl disable openvpn-server@vpn-tcp &>/dev/null
systemctl disable wg-quick@antizapret &>/dev/null
systemctl disable wg-quick@vpn &>/dev/null

# Остановим и выключим ненужные службы
systemctl stop firewalld &>/dev/null
ufw disable &>/dev/null

systemctl disable firewalld &>/dev/null
systemctl disable ufw &>/dev/null

#
# Удаляем старые файлы и кеш knot-resolver
rm -rf /var/cache/knot-resolver/*
rm -rf /etc/knot-resolver/*
rm -rf /var/lib/knot-resolver/*

#
# Удаляем старые файлы openvpn
rm -rf /etc/openvpn/server/*
rm -rf /etc/openvpn/client/*

#
# Удаляем старые файлы wireguard
rm -rf /etc/wireguard/templates/*

#
# Удалим скомпилированный патченный OpenVPN
make -C /usr/local/src/openvpn uninstall &>/dev/null
rm -rf /usr/local/src/openvpn

#
# Очищаем правила iptables
iptables -F &>/dev/null
iptables -X &>/dev/null
iptables -t nat -F &>/dev/null
iptables -t nat -X &>/dev/null
ip6tables -F &>/dev/null
ip6tables -X &>/dev/null
ip6tables -t nat -F &>/dev/null
ip6tables -t nat -X &>/dev/null

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
	exit 7
}
trap 'handle_error $LINENO "$BASH_COMMAND"' ERR

#
# Обновляем систему
apt-get update
DEBIAN_FRONTEND=noninteractive apt-get full-upgrade -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold"
DEBIAN_FRONTEND=noninteractive apt-get install --reinstall -y curl gpg procps

#
# Отключим IPv6 на время установки
if [[ -f /proc/sys/net/ipv6/conf/all/disable_ipv6 ]]; then
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
# Добавим репозиторий Debian Backports
if [[ $OS == "debian" ]]; then
	echo "deb http://deb.debian.org/debian $(lsb_release -cs)-backports main" > /etc/apt/sources.list.d/backports.list
fi

#
# Ставим необходимые пакеты
apt-get update
DEBIAN_FRONTEND=noninteractive apt-get install --reinstall -y git openvpn iptables easy-rsa gawk knot-resolver idn sipcalc python3-pip wireguard diffutils dnsutils socat lua-cqueues ipset
if [[ "$INSTALL_SSHGUARD" == "y" ]]; then
	DEBIAN_FRONTEND=noninteractive apt-get install --reinstall -y sshguard
else
	apt-get purge sshguard &>/dev/null || true
fi
apt-get autoremove -y
apt-get autoclean
PIP_BREAK_SYSTEM_PACKAGES=1 pip3 install --force-reinstall dnslib

#
# Клонируем репозиторий
rm -rf /tmp/antizapret
git clone https://github.com/GubernievS/AntiZapret-VPN.git /tmp/antizapret

#
# Сохраняем пользовательские настройки и пользовательские обработчики custom*.sh
mv -f /root/antizapret/config/* /tmp/antizapret/setup/root/antizapret/config &>/dev/null || true
mv -f /root/antizapret/custom*.sh /tmp/antizapret/setup/root/antizapret &>/dev/null || true

#
# Восстанавливаем из бэкапа пользователей vpn
tar -xzf /root/backup.tar.gz &>/dev/null || true
rm -f /root/backup.tar.gz &>/dev/null || true
mv -f /root/easyrsa3 /tmp/antizapret/setup/etc/openvpn &>/dev/null || true
mv -f /root/wireguard/antizapret.conf /tmp/antizapret/setup/etc/wireguard &>/dev/null || true
mv -f /root/wireguard/vpn.conf /tmp/antizapret/setup/etc/wireguard &>/dev/null || true
mv -f /root/wireguard/key /tmp/antizapret/setup/etc/wireguard &>/dev/null || true
rm -rf /root/wireguard

#
# Выставляем разрешения
find /tmp/antizapret -type f -exec chmod 644 {} +
find /tmp/antizapret -type d -exec chmod 755 {} +
find /tmp/antizapret -type f \( -name "*.sh" -o -name "*.py" \) -execdir chmod +x {} +

# Копируем нужное, удаляем не нужное
find /tmp/antizapret -name '.gitkeep' -delete
rm -rf /root/antizapret
cp -r /tmp/antizapret/setup/* /
rm -rf /tmp/antizapret

#
# Используем альтернативные диапазоны ip-адресов
# 10.28.0.0/14 => 172.28.0.0/14
if [[ "$ALTERNATIVE_IP" == "y" ]]; then
	sed -i 's/10\.30\./172\.30\./g' /root/antizapret/proxy.py
	sed -i 's/10\.29\./172\.29\./g' /etc/knot-resolver/kresd.conf
	sed -i 's/10\./172\./g' /root/antizapret/up.sh
	sed -i 's/10\./172\./g' /etc/openvpn/server/*.conf
	sed -i 's/10\./172\./g' /etc/wireguard/templates/*.conf
	find /etc/wireguard -name '*.conf' -exec sed -i 's/s = 10\./s = 172\./g' {} +
else
	find /etc/wireguard -name '*.conf' -exec sed -i 's/s = 172\./s = 10\./g' {} +
fi

#
# Настраиваем DNS в обычном VPN
if [[ "$VPN_DNS" == "2" ]]; then
	sed -i '/push "dhcp-option DNS 1\.1\.1\.1"/,+3c push "dhcp-option DNS 77.88.8.8"\npush "dhcp-option DNS 77.88.8.1"' /etc/openvpn/server/vpn*.conf
	sed -i "s/1.1.1.1, 1.0.0.1, 9.9.9.10, 149.112.112.10/77.88.8.8, 77.88.8.1/" /etc/wireguard/templates/vpn-client*.conf
elif [[ "$VPN_DNS" == "3" ]]; then
	sed -i '/push "dhcp-option DNS 1\.1\.1\.1"/,+3c push "dhcp-option DNS 94.140.14.14"\npush "dhcp-option DNS 94.140.15.15"\npush "dhcp-option DNS 76.76.2.44"\npush "dhcp-option DNS 76.76.10.44"' /etc/openvpn/server/vpn*.conf
	sed -i "s/1.1.1.1, 1.0.0.1, 9.9.9.10, 149.112.112.10/94.140.14.14, 94.140.15.15, 76.76.2.44, 76.76.10.44/" /etc/wireguard/templates/vpn-client*.conf
fi

#
# Настраиваем DNS в AntiZapret VPN
if [[ "$ANTIZAPRET_DNS" == "2" ]]; then
	sed -i "s/'77.88.8.8', '77.88.8.1', '77.88.8.8@1253', '77.88.8.1@1253'\|'1.1.1.1', '1.0.0.1', '9.9.9.10', '149.112.112.10'/'83.220.169.155', '212.109.195.93'/g" /etc/knot-resolver/kresd.conf
elif [[ "$ANTIZAPRET_DNS" == "3" ]]; then
	sed -i "s/'77.88.8.8', '77.88.8.1', '77.88.8.8@1253', '77.88.8.1@1253'/'1.1.1.1', '1.0.0.1', '9.9.9.10', '149.112.112.10'/g" /etc/knot-resolver/kresd.conf
fi

#
# Не блокируем рекламу, трекеры и фишинг в AntiZapret VPN
if [[ "$ANTIZAPRET_ADBLOCK" == "n" ]]; then
	sed -i '/adblock-hosts\.rpz/s/^/--/' /etc/knot-resolver/kresd.conf
fi

#
# Не используем резервные порты 80 и 443 для OpenVPN TCP
if [[ "$OPENVPN_80_443_TCP" == "n" ]]; then
	sed -i '/ \(80\|443\) tcp/s/^/#/' /etc/openvpn/client/templates/*.conf
	sed -i '/tcp.* \(80\|443\) /s/^/#/' /root/antizapret/up.sh
fi

#
# Не используем резервные порты 80 и 443 для OpenVPN UDP
if [[ "$OPENVPN_80_443_UDP" == "n" ]]; then
	sed -i '/ \(80\|443\) udp/s/^/#/' /etc/openvpn/client/templates/*.conf
	sed -i '/udp.* \(80\|443\) /s/^/#/' /root/antizapret/up.sh
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
# Отключаем защиту от сетевых атак и сканирования
if [[ "$PROTECT_SERVER" == "n" ]]; then
	sed -i '/\(antizapret-block\|antizapret-watch\|antizapret-allow\|tcp-flags\|p icmp\)/s/^/#/' /root/antizapret/up.sh
fi

#
# Создаем список исключений IP-адресов
/root/antizapret/parse.sh ip

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
systemctl enable antizapret-update.service
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
	if ! /root/antizapret/openvpn-dco.sh "y"; then
		ERRORS+="\n\e[1;31mOpenVPN DCO has not turn on!\e[0m Please run '/root/antizapret/openvpn-dco.sh' after rebooting\n"
	fi
fi

#
# Если есть ошибки, выводим их
if [[ -n "$ERRORS" ]]; then
	echo -e "$ERRORS"
fi

#
# Сохраняем настройки
echo "OPENVPN_PATCH=${OPENVPN_PATCH}
OPENVPN_DCO=${OPENVPN_DCO}
ANTIZAPRET_DNS=${ANTIZAPRET_DNS}
VPN_DNS=${VPN_DNS}
ANTIZAPRET_ADBLOCK=${ANTIZAPRET_ADBLOCK}
ALTERNATIVE_IP=${ALTERNATIVE_IP}
OPENVPN_80_443_TCP=${OPENVPN_80_443_TCP}
OPENVPN_80_443_UDP=${OPENVPN_80_443_UDP}
OPENVPN_DUPLICATE=${OPENVPN_DUPLICATE}
OPENVPN_LOG=${OPENVPN_LOG}
INSTALL_SSHGUARD=${INSTALL_SSHGUARD}
PROTECT_SERVER=${PROTECT_SERVER}
SETUP_DATE=$(date +"%d.%m.%Y %H:%M:%S %z")" > /root/antizapret/setup

#
# Создадим файл подкачки размером 512 Мб если его нет
if [[ -z "$(swapon --show)" ]]; then
	set +e
	SWAPFILE="/swapfile"
	SWAPSIZE=512
	dd if=/dev/zero of=$SWAPFILE bs=1M count=$SWAPSIZE
	chmod 600 "$SWAPFILE"
	mkswap "$SWAPFILE"
	swapon "$SWAPFILE"
	echo "$SWAPFILE none swap sw 0 0" >> /etc/fstab
fi

echo ""
echo -e "\e[1;32mAntiZapret VPN + traditional VPN successful installation!\e[0m"
echo "Rebooting..."

#
# Перезагружаем
reboot