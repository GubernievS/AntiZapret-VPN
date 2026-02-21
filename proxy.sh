#!/bin/bash

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

DEFAULT_INTERFACE="$(ip route get 1.2.3.4 2>/dev/null | awk '{print $5; exit}')"
if [[ -z "$DEFAULT_INTERFACE" ]]; then
	echo 'Default network interface not found!'
	exit 8
fi

DEFAULT_IP="$(ip route get 1.2.3.4 2>/dev/null | awk '{print $7; exit}')"
if [[ -z "$DEFAULT_IP" ]]; then
	echo 'Default IPv4 address not found!'
	exit 9
fi

echo
echo -e '\e[1;32mInstalling proxy for AntiZapret VPN server\e[0m'
echo 'Proxied ports: 80, 443, 504, 508, 540, 580, 50080, 50443, 51080, 51443, 52080, 52443'
echo 'More details: https://github.com/GubernievS/AntiZapret-VPN'
echo

MTU=$(< /sys/class/net/"$DEFAULT_INTERFACE"/mtu)
if (( MTU < 1500 )); then
	echo "Warning! Low MTU on $DEFAULT_INTERFACE: $MTU"
	echo "Change MTU in OpenVPN and WireGuard configs from 1420 to $((MTU-80)) on AntiZapret VPN server"
	echo
fi

# Спрашиваем о настройках
while read -rp 'Enter AntiZapret VPN server IPv4 address: ' -e DESTINATION_IP
do
	[[ -n $(getent ahostsv4 "$DESTINATION_IP") ]] || continue
	break
done
echo
until [[ "$SSH_PROTECTION" =~ (y|n) ]]; do
	read -rp 'Enable SSH brute-force protection? [y/n]: ' -e -i y SSH_PROTECTION
done
echo
echo 'Installation, please wait...'

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

# SSH protection включён
if [[ "$SSH_PROTECTION" == 'y' ]]; then
	apt-get purge -y fail2ban
	apt-get purge -y sshguard
fi

# Отключим IPv6
sysctl -w net.ipv6.conf.all.disable_ipv6=1
sysctl -w net.ipv6.conf.default.disable_ipv6=1
sysctl -w net.ipv6.conf.lo.disable_ipv6=1

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

# Автоматически сохраним правила iptables
echo iptables-persistent iptables-persistent/autosave_v4 boolean true | debconf-set-selections
echo iptables-persistent iptables-persistent/autosave_v6 boolean false | debconf-set-selections

# Обновляем систему и ставим необходимые пакеты
export DEBIAN_FRONTEND=noninteractive
apt-get clean
apt-get update
dpkg --configure -a
apt-get install --fix-broken -y
apt-get dist-upgrade -y
apt-get install --reinstall -y iptables iptables-persistent irqbalance unattended-upgrades
apt-get autoremove --purge -y
apt-get clean
dpkg-reconfigure -f noninteractive unattended-upgrades

# Изменим параметры для прокси
echo "# Proxy parameters modification
kernel.printk=3 4 1 3
kernel.panic=1
kernel.panic_on_oops=1
kernel.softlockup_panic=1
kernel.hardlockup_panic=1
kernel.sched_autogroup_enabled=1
net.ipv4.ip_forward=1
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr
net.ipv4.tcp_mtu_probing=1
net.core.rmem_max=4194304
net.core.wmem_max=4194304
net.ipv4.tcp_rmem=16384 131072 4194304
net.ipv4.tcp_wmem=16384 131072 4194304
net.ipv4.tcp_no_metrics_save=1
net.core.netdev_budget=600
net.ipv4.tcp_fastopen=1
net.ipv4.ip_local_port_range=10000 50000
net.netfilter.nf_conntrack_max=131072
net.core.netdev_budget_usecs=8000
net.core.dev_weight=64
net.ipv4.tcp_max_syn_backlog=1024
net.netfilter.nf_conntrack_buckets=32768
net.ipv4.conf.all.rp_filter=0
net.ipv4.conf.default.rp_filter=0
net.core.netdev_max_backlog=5000
net.core.somaxconn=4096
net.ipv4.tcp_syncookies=1
net.ipv4.udp_rmem_min=16384
net.ipv4.udp_wmem_min=16384
net.core.optmem_max=131072
net.ipv4.tcp_timestamps=1
net.ipv4.tcp_tw_reuse=0
net.ipv4.tcp_slow_start_after_idle=0
net.netfilter.nf_conntrack_tcp_timeout_established=86400
net.core.rmem_default=262144
net.core.wmem_default=262144
net.ipv4.tcp_base_mss=1024" > /etc/sysctl.d/99-proxy.conf

# Отключим IPv6
echo "# Disable IPv6
net.ipv6.conf.all.disable_ipv6=1
net.ipv6.conf.default.disable_ipv6=1
net.ipv6.conf.lo.disable_ipv6=1" > /etc/sysctl.d/99-disable-ipv6.conf

# Очистка правил iptables
iptables -w -F
iptables -w -t nat -F
iptables -w -t mangle -F
iptables -w -t raw -F
ip6tables -w -F
ip6tables -w -t nat -F
ip6tables -w -t mangle -F
ip6tables -w -t raw -F

# Сброс счётчиков
iptables -w -Z
iptables -w -t nat -Z
iptables -w -t mangle -Z
iptables -w -t raw -Z
ip6tables -w -Z
ip6tables -w -t nat -Z
ip6tables -w -t mangle -Z
ip6tables -w -t raw -Z

# Новые правила iptables
# filter
# Default policy
iptables -w -P INPUT ACCEPT
iptables -w -P FORWARD ACCEPT
iptables -w -P OUTPUT ACCEPT
ip6tables -w -P INPUT ACCEPT
ip6tables -w -P FORWARD ACCEPT
ip6tables -w -P OUTPUT ACCEPT
# INPUT connection tracking
iptables -w -I INPUT 1 -m conntrack --ctstate INVALID -j DROP
ip6tables -w -I INPUT 1 -m conntrack --ctstate INVALID -j DROP
# FORWARD connection tracking
iptables -w -I FORWARD 1 -m conntrack --ctstate INVALID -j DROP
ip6tables -w -I FORWARD 1 -m conntrack --ctstate INVALID -j DROP
# OUTPUT connection tracking
iptables -w -I OUTPUT 1 -m conntrack --ctstate INVALID -j DROP
ip6tables -w -I OUTPUT 1 -m conntrack --ctstate INVALID -j DROP

# mangle
# Clamp TCP MSS
iptables -w -t mangle -A FORWARD -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu
ip6tables -w -t mangle -A FORWARD -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu

# nat
iptables -w -t nat -A PREROUTING -p tcp --dport 80 -j DNAT --to-destination "$DESTINATION_IP":80
iptables -w -t nat -A PREROUTING -p tcp --dport 443 -j DNAT --to-destination "$DESTINATION_IP":443
iptables -w -t nat -A PREROUTING -p tcp --dport 504 -j DNAT --to-destination "$DESTINATION_IP":504
iptables -w -t nat -A PREROUTING -p tcp --dport 508 -j DNAT --to-destination "$DESTINATION_IP":508
iptables -w -t nat -A PREROUTING -p tcp --dport 50080 -j DNAT --to-destination "$DESTINATION_IP":50080
iptables -w -t nat -A PREROUTING -p tcp --dport 50443 -j DNAT --to-destination "$DESTINATION_IP":50443

iptables -w -t nat -A PREROUTING -p udp --dport 80 -j DNAT --to-destination "$DESTINATION_IP":80
iptables -w -t nat -A PREROUTING -p udp --dport 443 -j DNAT --to-destination "$DESTINATION_IP":443
iptables -w -t nat -A PREROUTING -p udp --dport 504 -j DNAT --to-destination "$DESTINATION_IP":504
iptables -w -t nat -A PREROUTING -p udp --dport 508 -j DNAT --to-destination "$DESTINATION_IP":508
iptables -w -t nat -A PREROUTING -p udp --dport 50080 -j DNAT --to-destination "$DESTINATION_IP":50080
iptables -w -t nat -A PREROUTING -p udp --dport 50443 -j DNAT --to-destination "$DESTINATION_IP":50443

iptables -w -t nat -A PREROUTING -p udp --dport 540 -j DNAT --to-destination "$DESTINATION_IP":540
iptables -w -t nat -A PREROUTING -p udp --dport 580 -j DNAT --to-destination "$DESTINATION_IP":580
iptables -w -t nat -A PREROUTING -p udp --dport 51080 -j DNAT --to-destination "$DESTINATION_IP":51080
iptables -w -t nat -A PREROUTING -p udp --dport 51443 -j DNAT --to-destination "$DESTINATION_IP":51443
iptables -w -t nat -A PREROUTING -p udp --dport 52080 -j DNAT --to-destination "$DESTINATION_IP":52080
iptables -w -t nat -A PREROUTING -p udp --dport 52443 -j DNAT --to-destination "$DESTINATION_IP":52443

iptables -w -t nat -A POSTROUTING -d "$DESTINATION_IP" -j SNAT --to-source "$DEFAULT_IP"

# SSH protection
if [[ "$SSH_PROTECTION" == 'y' ]]; then
	iptables -w -I INPUT 2 -p tcp --dport ssh -m conntrack --ctstate NEW -m hashlimit --hashlimit-above 5/hour --hashlimit-burst 5 --hashlimit-mode srcip --hashlimit-srcmask 24 --hashlimit-name proxy-ssh --hashlimit-htable-expire 60000 -j DROP
	ip6tables -w -I INPUT 2 -p tcp --dport ssh -m conntrack --ctstate NEW -m hashlimit --hashlimit-above 5/hour --hashlimit-burst 5 --hashlimit-mode srcip --hashlimit-srcmask 64 --hashlimit-name proxy-ssh6 --hashlimit-htable-expire 60000 -j DROP
fi

# Сохранение новых правил iptables
netfilter-persistent save
systemctl enable netfilter-persistent

# Перезагружаем
echo
echo -e '\e[1;32mProxy for AntiZapret VPN server installed successfully!\e[0m'
echo 'Rebooting...'

reboot