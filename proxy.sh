#!/bin/bash

# Проверка необходимости перезагрузить
if [[ -f /var/run/reboot-required ]] || pidof apt apt-get dpkg unattended-upgrades &>/dev/null; then
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
	if (( VERSION < 12 )); then
		echo "Error: Debian $VERSION is not supported! Minimal supported version is 12"
		exit 5
	fi
elif [[ "$OS" == 'ubuntu' ]]; then
	if (( VERSION < 22 )); then
		echo "Error: Ubuntu $VERSION is not supported! Minimal supported version is 22"
		exit 6
	fi
else
	echo "Error: Your Linux distribution ($OS) is not supported!"
	exit 7
fi

DEFAULT_INTERFACE="$(ip route get 1.2.3.4 2>/dev/null | grep -oP 'dev \K\S+')"
if [[ -z "$DEFAULT_INTERFACE" ]]; then
	echo 'Default network interface not found!'
	exit 8
fi

DEFAULT_IP="$(ip route get 1.2.3.4 2>/dev/null | grep -oP 'src \K\S+')"
if [[ -z "$DEFAULT_IP" ]]; then
	echo 'Default IPv4 address not found!'
	exit 9
fi

OPENVPN_SSH=20
WIREGUARD_SSH=21

echo
echo -e '\e[1;32mInstalling proxy for AntiZapret VPN server\e[0m'
echo 'Proxied ports:'
echo '    OpenVPN UDP/TCP:       80, 443, 504, 508, 50080, 50443'
echo '    WireGuard/AmneziaWG:   540, 580, 51080, 51443, 52080, 52443'
echo "    SSH OpenVPN:           $OPENVPN_SSH"
echo "    SSH WireGuard:         $WIREGUARD_SSH"
echo 'More details: https://github.com/GubernievS/AntiZapret-VPN'
echo

MTU=$(< /sys/class/net/$DEFAULT_INTERFACE/mtu)
if (( MTU < 1500 )); then
	echo "Warning! Low MTU on $DEFAULT_INTERFACE: $MTU"
	echo "Change MTU in OpenVPN and WireGuard configs from 1420 to $((MTU-80)) on AntiZapret VPN server"
	echo
fi

# Спрашиваем о настройках
until [[ "$OPENVPN_UDP" =~ (y|n) ]]; do
	read -rp 'Enable OpenVPN UDP proxying? [y/n]: ' -e -i y OPENVPN_UDP
done
echo
until [[ "$OPENVPN_TCP" =~ (y|n) ]]; do
	read -rp 'Enable OpenVPN TCP proxying? [y/n]: ' -e -i n OPENVPN_TCP
done
echo
until [[ "$WIREGUARD" =~ (y|n) ]]; do
	read -rp 'Enable WireGuard/AmneziaWG proxying? [y/n]: ' -e -i y WIREGUARD
done
echo
if [[ "$OPENVPN_UDP" == 'n' && "$OPENVPN_TCP" == 'n' && "$WIREGUARD" == 'n' ]]; then
	echo 'Error: Nothing to proxy!'
	exit 10
fi
if [[ "$OPENVPN_UDP" == 'y' || "$OPENVPN_TCP" == 'y' ]]; then
	while read -rp 'Enter OpenVPN server IPv4 address: ' -e OPENVPN_IP
	do
		[[ -n $(getent ahostsv4 "$OPENVPN_IP") ]] || continue
		break
	done
	echo
fi
if [[ "$WIREGUARD" == 'y' ]]; then
	while read -rp 'Enter WireGuard/AmneziaWG server IPv4 address: ' -e WIREGUARD_IP
	do
		[[ -n $(getent ahostsv4 "$WIREGUARD_IP") ]] || continue
		break
	done
	echo
fi
echo 'Warning! SSH protection may block your IP after 5 logins/minute!'
until [[ "$SSH_PROTECTION" =~ (y|n) ]]; do
	read -rp 'Enable SSH brute-force protection? [y/n]: ' -e -i y SSH_PROTECTION
done
echo
echo 'Warning! Scan protection blocks ping and closed-port replies!'
until [[ "$SCAN_PROTECTION" =~ (y|n) ]]; do
	read -rp 'Enable network scan protection? [y/n]: ' -e -i y SCAN_PROTECTION
done
echo
echo "Warning! SSH proxying ($OPENVPN_SSH/$WIREGUARD_SSH) works only after SSH login to this server!"
until [[ "$SSH_PROXY" =~ (y|n) ]]; do
	read -rp 'Enable SSH proxying? [y/n]: ' -e -i y SSH_PROXY
done
echo
echo 'Installation, please wait...'

# Удалим ненужные службы
dpkg -s ufw &>/dev/null && apt-get purge -y ufw
dpkg -s firewalld &>/dev/null && apt-get purge -y firewalld
dpkg -s apparmor &>/dev/null && apt-get purge -y apparmor
dpkg -s apport &>/dev/null && apt-get purge -y apport
dpkg -s modemmanager &>/dev/null && apt-get purge -y modemmanager
dpkg -s snapd &>/dev/null && apt-get purge -y snapd
dpkg -s upower &>/dev/null && apt-get purge -y upower
dpkg -s multipath-tools &>/dev/null && apt-get purge -y multipath-tools
dpkg -s rsyslog &>/dev/null && apt-get purge -y rsyslog
dpkg -s udisks2 &>/dev/null && apt-get purge -y udisks2
dpkg -s qemu-guest-agent &>/dev/null && apt-get purge -y qemu-guest-agent
dpkg -s tuned &>/dev/null && apt-get purge -y tuned
dpkg -s sysstat &>/dev/null && apt-get purge -y sysstat
dpkg -s acpid &>/dev/null && apt-get purge -y acpid
dpkg -s fwupd &>/dev/null && apt-get purge -y fwupd
dpkg -s watchdog &>/dev/null && apt-get purge -y watchdog
dpkg -s pcscd &>/dev/null && apt-get purge -y pcscd
dpkg -s packagekit &>/dev/null && apt-get purge -y packagekit
dpkg -s thermald &>/dev/null && apt-get purge -y thermald
dpkg -s open-iscsi &>/dev/null && apt-get purge -y open-iscsi
dpkg -s ubuntu-drivers-common &>/dev/null && apt-get purge -y ubuntu-drivers-common
dpkg -s avahi-daemon &>/dev/null && apt-get purge -y avahi-daemon
dpkg -s accountsservice &>/dev/null && apt-get purge -y accountsservice
dpkg -s bolt &>/dev/null && apt-get purge -y bolt
dpkg -s plymouth &>/dev/null && apt-get purge -y plymouth
dpkg -s popularity-contest &>/dev/null && apt-get purge -y popularity-contest
dpkg -s whoopsie &>/dev/null && apt-get purge -y whoopsie
dpkg -s landscape-common &>/dev/null && apt-get purge -y landscape-common
dpkg -s canonical-livepatch &>/dev/null && apt-get purge -y canonical-livepatch
dpkg -s ppp &>/dev/null && apt-get purge -y ppp
dpkg -s speech-dispatcher &>/dev/null && apt-get purge -y speech-dispatcher
dpkg -s brltty &>/dev/null && apt-get purge -y brltty
dpkg -s bluez &>/dev/null && apt-get purge -y bluez
dpkg -s bluetooth &>/dev/null && apt-get purge -y bluetooth
dpkg -s wpasupplicant &>/dev/null && apt-get purge -y wpasupplicant
dpkg -s cups &>/dev/null && apt-get purge -y cups
dpkg -s cups-browsed &>/dev/null && apt-get purge -y cups-browsed
dpkg -s cups-client &>/dev/null && apt-get purge -y cups-client
dpkg -s cups-daemon &>/dev/null && apt-get purge -y cups-daemon
dpkg -s cups-common &>/dev/null && apt-get purge -y cups-common
dpkg -s nfs-common &>/dev/null && apt-get purge -y nfs-common
dpkg -s rpcbind &>/dev/null && apt-get purge -y rpcbind
dpkg -s cifs-utils &>/dev/null && apt-get purge -y cifs-utils
dpkg -s ntfs-3g &>/dev/null && apt-get purge -y ntfs-3g
dpkg -s os-prober &>/dev/null && apt-get purge -y os-prober
dpkg -s laptop-detect &>/dev/null && apt-get purge -y laptop-detect
dpkg -s powermgmt-base &>/dev/null && apt-get purge -y powermgmt-base
dpkg -s xdg-user-dirs &>/dev/null && apt-get purge -y xdg-user-dirs
dpkg -s update-notifier-common &>/dev/null && apt-get purge -y update-notifier-common
dpkg -s at &>/dev/null && apt-get purge -y at
dpkg -s spice-vdagent &>/dev/null && apt-get purge -y spice-vdagent
dpkg -s libnss-mdns &>/dev/null && apt-get purge -y libnss-mdns
dpkg -s byobu &>/dev/null && apt-get purge -y byobu
dpkg -s ubuntu-advantage-tools &>/dev/null && apt-get purge -y ubuntu-advantage-tools
dpkg -s ubuntu-pro-client &>/dev/null && apt-get purge -y ubuntu-pro-client
dpkg -s pollinate &>/dev/null && apt-get purge -y pollinate
dpkg -s secureboot-db &>/dev/null && apt-get purge -y secureboot-db
#dpkg -s pastebinit &>/dev/null && apt-get purge -y pastebinit

# SSH protection включён
if [[ "$SSH_PROTECTION" == 'y' ]]; then
	dpkg -s fail2ban &>/dev/null && apt-get purge -y fail2ban
	dpkg -s sshguard &>/dev/null && apt-get purge -y sshguard
fi

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

# Автоматически сохраним правила iptables
echo iptables-persistent iptables-persistent/autosave_v4 boolean true | debconf-set-selections
echo iptables-persistent iptables-persistent/autosave_v6 boolean false | debconf-set-selections

# Обновляем систему и ставим необходимые пакеты
export DEBIAN_FRONTEND=noninteractive
apt-get clean
apt-get update
dpkg --configure -a
apt-get install --fix-broken -y
apt-get dist-upgrade -y --fix-missing
apt-get install -y iptables iptables-persistent irqbalance unattended-upgrades
apt-get autoremove --purge -y
apt-get clean
dpkg-reconfigure -f noninteractive unattended-upgrades

# Изменим параметры для прокси
echo "# Proxy parameters modification
kernel.printk=3 4 1 3
kernel.panic=1
kernel.panic_on_oops=1
kernel.softlockup_panic=0
kernel.hardlockup_panic=0
kernel.sched_autogroup_enabled=0
kernel.nmi_watchdog=0
net.ipv4.ip_forward=1
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr
net.ipv4.tcp_mtu_probing=1
net.core.rmem_max=33554432
net.core.wmem_max=33554432
net.ipv4.tcp_rmem=4096 262144 16777216
net.ipv4.tcp_wmem=4096 262144 16777216
net.ipv4.tcp_no_metrics_save=1
net.core.netdev_budget=600
net.ipv4.tcp_fastopen=3
net.ipv4.ip_local_port_range=10000 65535
net.netfilter.nf_conntrack_max=131072
net.core.netdev_budget_usecs=8000
net.core.dev_weight=64
net.ipv4.tcp_max_syn_backlog=4096
net.netfilter.nf_conntrack_buckets=32768
net.ipv4.conf.all.rp_filter=0
net.ipv4.conf.default.rp_filter=0
net.core.netdev_max_backlog=10000
net.core.somaxconn=4096
net.ipv4.tcp_syncookies=1
net.ipv4.udp_rmem_min=4096
net.ipv4.udp_wmem_min=4096
net.core.optmem_max=20480
net.ipv4.tcp_timestamps=1
net.ipv4.tcp_tw_reuse=1
net.ipv4.tcp_slow_start_after_idle=0
net.netfilter.nf_conntrack_tcp_timeout_established=3600
net.core.rmem_default=262144
net.core.wmem_default=262144
net.ipv4.tcp_base_mss=1024
net.ipv4.conf.all.accept_redirects=0
net.ipv4.conf.default.accept_redirects=0
net.ipv4.conf.all.send_redirects=0
net.ipv4.conf.default.send_redirects=0
net.ipv4.conf.all.secure_redirects=0
net.ipv4.conf.default.secure_redirects=0
net.ipv4.conf.all.accept_source_route=0
net.ipv4.conf.default.accept_source_route=0
net.ipv4.ip_local_reserved_ports=50080,50443,51080,51443,52080,52443
net.ipv4.tcp_keepalive_time=600
net.ipv4.tcp_keepalive_intvl=30
net.ipv4.tcp_keepalive_probes=3
net.netfilter.nf_conntrack_udp_timeout=30
net.netfilter.nf_conntrack_udp_timeout_stream=120
net.netfilter.nf_conntrack_tcp_be_liberal=1
net.ipv4.tcp_notsent_lowat=131072
net.ipv4.tcp_fin_timeout=15
net.ipv4.tcp_orphan_retries=3
net.ipv4.tcp_retries2=8
net.ipv4.tcp_syn_retries=4
net.ipv4.tcp_synack_retries=3
net.netfilter.nf_conntrack_tcp_loose=1
net.netfilter.nf_conntrack_tcp_timeout_syn_sent=120
net.netfilter.nf_conntrack_tcp_timeout_syn_recv=60
net.netfilter.nf_conntrack_tcp_timeout_fin_wait=120
net.netfilter.nf_conntrack_tcp_timeout_time_wait=120
net.netfilter.nf_conntrack_tcp_timeout_close_wait=60
net.netfilter.nf_conntrack_icmp_timeout=30
net.ipv4.ip_no_pmtu_disc=0
net.ipv4.ip_forward_use_pmtu=1
" > /etc/sysctl.d/99-proxy.conf

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
# OUTPUT connection tracking
iptables -w -I OUTPUT 1 -m conntrack --ctstate INVALID -j DROP
ip6tables -w -I OUTPUT 1 -m conntrack --ctstate INVALID -j DROP
# SSH protection
if [[ "$SSH_PROTECTION" == 'y' ]]; then
	iptables -w -I INPUT 2 -p tcp --dport ssh -m conntrack --ctstate NEW -m hashlimit --hashlimit-above 5/hour --hashlimit-burst 5 --hashlimit-mode srcip --hashlimit-srcmask 24 --hashlimit-name proxy-ssh --hashlimit-htable-expire 60000 -j DROP
	ip6tables -w -I INPUT 2 -p tcp --dport ssh -m conntrack --ctstate NEW -m hashlimit --hashlimit-above 5/hour --hashlimit-burst 5 --hashlimit-mode srcip --hashlimit-srcmask 64 --hashlimit-name proxy-ssh6 --hashlimit-htable-expire 60000 -j DROP
	if [[ "$SSH_PROXY" == 'y' ]]; then
		if [[ "$OPENVPN_UDP" == 'y' || "$OPENVPN_TCP" == 'y' ]]; then
			iptables -w -t mangle -A PREROUTING -p tcp --dport $OPENVPN_SSH -m conntrack --ctstate NEW -m hashlimit --hashlimit-above 5/hour --hashlimit-burst 5 --hashlimit-mode srcip --hashlimit-srcmask 24 --hashlimit-name proxy-ssh-openvpn --hashlimit-htable-expire 60000 -j DROP
		fi
		if [[ "$WIREGUARD" == 'y' ]]; then
			iptables -w -t mangle -A PREROUTING -p tcp --dport $WIREGUARD_SSH -m conntrack --ctstate NEW -m hashlimit --hashlimit-above 5/hour --hashlimit-burst 5 --hashlimit-mode srcip --hashlimit-srcmask 24 --hashlimit-name proxy-ssh-wireguard --hashlimit-htable-expire 60000 -j DROP
		fi
	fi
fi
# SSH proxy
if [[ "$SSH_PROXY" == 'y' ]]; then
	iptables -w -A INPUT -p tcp --dport ssh -m conntrack --ctstate ESTABLISHED -m recent --set --name proxy-ssh -j ACCEPT
	if [[ "$OPENVPN_UDP" == 'y' || "$OPENVPN_TCP" == 'y' ]]; then
		iptables -w -A INPUT -p tcp --dport $OPENVPN_SSH -m conntrack --ctstate NEW -m recent ! --rcheck --seconds 60 --name proxy-ssh -j DROP
	fi
	if [[ "$WIREGUARD" == 'y' ]]; then
		iptables -w -A INPUT -p tcp --dport $WIREGUARD_SSH -m conntrack --ctstate NEW -m recent ! --rcheck --seconds 60 --name proxy-ssh -j DROP
	fi
fi
# Scan protection
if [[ "$SCAN_PROTECTION" == 'y' ]]; then
	iptables -w -I INPUT 2 -i $DEFAULT_INTERFACE -p icmp --icmp-type echo-request -j DROP
	iptables -w -I OUTPUT 2 -o $DEFAULT_INTERFACE -p tcp --tcp-flags RST RST -j DROP
	iptables -w -I OUTPUT 3 -o $DEFAULT_INTERFACE -p icmp --icmp-type port-unreachable -j DROP
	ip6tables -w -I INPUT 2 -i $DEFAULT_INTERFACE -p icmpv6 --icmpv6-type echo-request -j DROP
	ip6tables -w -I OUTPUT 2 -o $DEFAULT_INTERFACE -p tcp --tcp-flags RST RST -j DROP
	ip6tables -w -I OUTPUT 3 -o $DEFAULT_INTERFACE -p icmpv6 --icmpv6-type port-unreachable -j DROP
fi

# mangle
# Clamp TCP MSS
iptables -w -t mangle -A FORWARD -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu
ip6tables -w -t mangle -A FORWARD -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu

# nat
# OpenVPN TCP
if [[ "$OPENVPN_TCP" == 'y' ]]; then
	iptables -w -t nat -A PREROUTING -p tcp --dport 80 -j DNAT --to-destination $OPENVPN_IP:50080
	iptables -w -t nat -A PREROUTING -p tcp --dport 443 -j DNAT --to-destination $OPENVPN_IP:50443
	iptables -w -t nat -A PREROUTING -p tcp --dport 504 -j DNAT --to-destination $OPENVPN_IP:50443
	iptables -w -t nat -A PREROUTING -p tcp --dport 508 -j DNAT --to-destination $OPENVPN_IP:50080
	iptables -w -t nat -A PREROUTING -p tcp --dport 50080 -j DNAT --to-destination $OPENVPN_IP:50080
	iptables -w -t nat -A PREROUTING -p tcp --dport 50443 -j DNAT --to-destination $OPENVPN_IP:50443
fi
# OpenVPN UDP
if [[ "$OPENVPN_UDP" == 'y' ]]; then
	iptables -w -t nat -A PREROUTING -p udp --dport 80 -j DNAT --to-destination $OPENVPN_IP:50080
	iptables -w -t nat -A PREROUTING -p udp --dport 443 -j DNAT --to-destination $OPENVPN_IP:50443
	iptables -w -t nat -A PREROUTING -p udp --dport 504 -j DNAT --to-destination $OPENVPN_IP:50443
	iptables -w -t nat -A PREROUTING -p udp --dport 508 -j DNAT --to-destination $OPENVPN_IP:50080
	iptables -w -t nat -A PREROUTING -p udp --dport 50080 -j DNAT --to-destination $OPENVPN_IP:50080
	iptables -w -t nat -A PREROUTING -p udp --dport 50443 -j DNAT --to-destination $OPENVPN_IP:50443
fi
# WireGuard/AmneziaWG
if [[ "$WIREGUARD" == 'y' ]]; then
	iptables -w -t nat -A PREROUTING -p udp --dport 540 -j DNAT --to-destination $WIREGUARD_IP:51443
	iptables -w -t nat -A PREROUTING -p udp --dport 580 -j DNAT --to-destination $WIREGUARD_IP:51080
	iptables -w -t nat -A PREROUTING -p udp --dport 51080 -j DNAT --to-destination $WIREGUARD_IP:51080
	iptables -w -t nat -A PREROUTING -p udp --dport 51443 -j DNAT --to-destination $WIREGUARD_IP:51443
	iptables -w -t nat -A PREROUTING -p udp --dport 52080 -j DNAT --to-destination $WIREGUARD_IP:51080
	iptables -w -t nat -A PREROUTING -p udp --dport 52443 -j DNAT --to-destination $WIREGUARD_IP:51443
fi
# SSH proxy
if [[ "$SSH_PROXY" == 'y' ]]; then
	if [[ "$OPENVPN_UDP" == 'y' || "$OPENVPN_TCP" == 'y' ]]; then
		iptables -w -t nat -A PREROUTING -p tcp --dport $OPENVPN_SSH -m recent --rcheck --seconds 60 --name proxy-ssh -j DNAT --to-destination $OPENVPN_IP:22
	fi
	if [[ "$WIREGUARD" == 'y' ]]; then
		iptables -w -t nat -A PREROUTING -p tcp --dport $WIREGUARD_SSH -m recent --rcheck --seconds 60 --name proxy-ssh -j DNAT --to-destination $WIREGUARD_IP:22
	fi
fi
# SNAT
if [[ -n "$OPENVPN_IP" ]]; then
	iptables -w -t nat -A POSTROUTING -d $OPENVPN_IP -j SNAT --to-source $DEFAULT_IP
fi
if [[ -n "$WIREGUARD_IP" && "$WIREGUARD_IP" != "$OPENVPN_IP" ]]; then
	iptables -w -t nat -A POSTROUTING -d $WIREGUARD_IP -j SNAT --to-source $DEFAULT_IP
fi

# Сохранение новых правил iptables
netfilter-persistent save
systemctl enable netfilter-persistent

# Обнуление счётчиков в сохранённых правилах
sed -E -i 's/\[[0-9]+:[0-9]+\]/[0:0]/g' /etc/iptables/rules.*

# Перезагружаем
echo
echo -e '\e[1;32mProxy for AntiZapret VPN server installed successfully!\e[0m'
reboot