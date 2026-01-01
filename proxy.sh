#!/bin/bash

set -e

handle_error() {
	echo "$(lsb_release -ds) $(uname -r) $(date --iso-8601=seconds)"
	echo -e "\e[1;31mError at line $1: $2\e[0m"
	exit 1
}
trap 'handle_error $LINENO "$BASH_COMMAND"' ERR

echo
echo -e '\e[1;32mInstalling proxy for AntiZapret VPN + full VPN\e[0m'
echo 'Proxied ports: 80, 443, 50080, 50443, 51080, 51443, 52080, 52443'
echo 'More details: https://github.com/GubernievS/AntiZapret-VPN'
echo

while read -rp 'Enter AntiZapret VPN server IPv4 address: ' -e DESTINATION_IP
do
	[[ -n $(getent ahostsv4 "$DESTINATION_IP") ]] || continue
	break
done

if [[ -z "$DESTINATION_IP" ]]; then
	echo 'Destination AntiZapret VPN server IPv4 address not set!'
	exit 2
fi

INTERFACE="$(ip route | grep '^default' | awk '{print $5}')"
if [[ -z "$INTERFACE" ]]; then
	echo 'Default network interface not found!'
	exit 3
fi

EXTERNAL_IP="$(ip -4 addr show dev "$INTERFACE" | grep -oP '(?<=inet\s)\d+(\.\d+){3}')"
if [[ -z "$EXTERNAL_IP" ]]; then
	echo 'External IPv4 address not found on default network interface!'
	exit 4
fi

echo
echo 'Preparing for installation, please wait...'

# Remove unnecessary services
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

# Set autosave
echo iptables-persistent iptables-persistent/autosave_v4 boolean true | debconf-set-selections
echo iptables-persistent iptables-persistent/autosave_v6 boolean false | debconf-set-selections

# Install pkg
export DEBIAN_FRONTEND=noninteractive
apt-get clean
apt-get update
dpkg --configure -a
apt-get install --fix-broken -y
apt-get dist-upgrade -y
apt-get install --reinstall -y iptables iptables-persistent irqbalance
apt-get autoremove --purge -y
apt-get clean

# Proxy parameters modification
cat <<'EOF' > /etc/sysctl.d/99-proxy.conf
# Proxy parameters modification
net.ipv4.ip_forward=1
kernel.printk=3 4 1 3
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr
net.ipv4.tcp_mtu_probing=1
net.core.rmem_max=16777216
net.core.wmem_max=16777216
net.ipv4.tcp_rmem=4096 131072 16777216
net.ipv4.tcp_wmem=4096 16384 16777216
net.ipv4.tcp_no_metrics_save=1
net.core.netdev_budget=600
net.ipv4.tcp_fastopen=3
net.ipv4.ip_local_port_range=1024 65535
net.netfilter.nf_conntrack_max=262144
net.core.netdev_budget_usecs=4000
net.core.dev_weight=64
net.ipv4.tcp_max_syn_backlog=1024
net.netfilter.nf_conntrack_buckets=65536
net.ipv4.conf.all.rp_filter=0
net.ipv4.conf.default.rp_filter=0
net.core.netdev_max_backlog=2000
net.core.somaxconn=4096
net.ipv4.tcp_syncookies=1
net.ipv4.udp_rmem_min=16384
net.ipv4.udp_wmem_min=16384
EOF

# Disable IPv6
cat <<'EOF' > /etc/sysctl.d/99-disable-ipv6.conf
# Disable IPv6
net.ipv6.conf.all.disable_ipv6=1
net.ipv6.conf.default.disable_ipv6=1
net.ipv6.conf.lo.disable_ipv6=1
EOF

# Forced loading nf_conntrack module
echo "nf_conntrack" > /etc/modules-load.d/nf_conntrack.conf

# Clear iptables
iptables -F && iptables -t nat -F && iptables -t mangle -F

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

# nat
# OpenVPN TCP
iptables -t nat -A PREROUTING -p tcp --dport 80 -j DNAT --to-destination "$DESTINATION_IP":80
iptables -t nat -A PREROUTING -p tcp --dport 50080 -j DNAT --to-destination "$DESTINATION_IP":50080
iptables -t nat -A PREROUTING -p tcp --dport 443 -j DNAT --to-destination "$DESTINATION_IP":443
iptables -t nat -A PREROUTING -p tcp --dport 50443 -j DNAT --to-destination "$DESTINATION_IP":50443

iptables -t nat -A POSTROUTING -p tcp -d "$DESTINATION_IP" --dport 80 -j SNAT --to-source "$EXTERNAL_IP"
iptables -t nat -A POSTROUTING -p tcp -d "$DESTINATION_IP" --dport 50080 -j SNAT --to-source "$EXTERNAL_IP"
iptables -t nat -A POSTROUTING -p tcp -d "$DESTINATION_IP" --dport 443 -j SNAT --to-source "$EXTERNAL_IP"
iptables -t nat -A POSTROUTING -p tcp -d "$DESTINATION_IP" --dport 50443 -j SNAT --to-source "$EXTERNAL_IP"

# OpenVPN UDP
iptables -t nat -A PREROUTING -p udp --dport 80 -j DNAT --to-destination "$DESTINATION_IP":80
iptables -t nat -A PREROUTING -p udp --dport 50080 -j DNAT --to-destination "$DESTINATION_IP":50080
iptables -t nat -A PREROUTING -p udp --dport 443 -j DNAT --to-destination "$DESTINATION_IP":443
iptables -t nat -A PREROUTING -p udp --dport 50443 -j DNAT --to-destination "$DESTINATION_IP":50443

iptables -t nat -A POSTROUTING -p udp -d "$DESTINATION_IP" --dport 80 -j SNAT --to-source "$EXTERNAL_IP"
iptables -t nat -A POSTROUTING -p udp -d "$DESTINATION_IP" --dport 50080 -j SNAT --to-source "$EXTERNAL_IP"
iptables -t nat -A POSTROUTING -p udp -d "$DESTINATION_IP" --dport 443 -j SNAT --to-source "$EXTERNAL_IP"
iptables -t nat -A POSTROUTING -p udp -d "$DESTINATION_IP" --dport 50443 -j SNAT --to-source "$EXTERNAL_IP"

# WireGuard/AmneziaWG 
iptables -t nat -A PREROUTING -p udp --dport 51080 -j DNAT --to-destination "$DESTINATION_IP":51080
iptables -t nat -A PREROUTING -p udp --dport 51443 -j DNAT --to-destination "$DESTINATION_IP":51443
iptables -t nat -A PREROUTING -p udp --dport 52080 -j DNAT --to-destination "$DESTINATION_IP":52080
iptables -t nat -A PREROUTING -p udp --dport 52443 -j DNAT --to-destination "$DESTINATION_IP":52443

iptables -t nat -A POSTROUTING -p udp -d "$DESTINATION_IP" --dport 51080 -j SNAT --to-source "$EXTERNAL_IP"
iptables -t nat -A POSTROUTING -p udp -d "$DESTINATION_IP" --dport 51443 -j SNAT --to-source "$EXTERNAL_IP"
iptables -t nat -A POSTROUTING -p udp -d "$DESTINATION_IP" --dport 52080 -j SNAT --to-source "$EXTERNAL_IP"
iptables -t nat -A POSTROUTING -p udp -d "$DESTINATION_IP" --dport 52443 -j SNAT --to-source "$EXTERNAL_IP"

netfilter-persistent save

# Rebooting
echo
echo -e '\e[1;32mProxy for AntiZapret VPN + full VPN installed successfully!\e[0m'
echo 'Rebooting...'

reboot