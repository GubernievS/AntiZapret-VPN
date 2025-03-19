#!/bin/bash

INTERFACE=$(ip route | grep '^default' | awk '{print $5}')
if [[ -z "$INTERFACE" ]]; then
	echo "Default network interface not found!"
	exit 1
fi

./down.sh "$INTERFACE"

set -e

HERE="$(dirname "$(readlink -f "${0}")")"
cd "$HERE"

# Clear knot-resolver cache
echo "cache.clear()" | socat - /run/knot-resolver/control/1

# Network parameters modification
sysctl -w net.ipv4.ip_forward=1
sysctl -w kernel.printk="3 4 1 3"
sysctl -w net.core.default_qdisc=fq
sysctl -w net.ipv4.tcp_congestion_control=bbr

# filter
# INPUT connection tracking
iptables -w -A INPUT -m conntrack --ctstate INVALID -j DROP
ip6tables -w -A INPUT -m conntrack --ctstate INVALID -j DROP
# Attack and scan protection
ipset create antizapret-block hash:ip timeout 600
ipset create antizapret-watch hash:ip,port timeout 60
ipset list antizapret-allow &>/dev/null || ipset create antizapret-allow hash:net
iptables -w -A INPUT -i "$INTERFACE" -p icmp --icmp-type echo-request -j DROP
iptables -w -A INPUT -i "$INTERFACE" -m conntrack --ctstate NEW -m set ! --match-set antizapret-watch src,dst -m hashlimit --hashlimit-above 10/hour --hashlimit-burst 10 --hashlimit-mode srcip --hashlimit-srcmask 24 --hashlimit-name antizapret-scan --hashlimit-htable-expire 60000 -j SET --add-set antizapret-block src --exist
iptables -w -A INPUT -i "$INTERFACE" -m conntrack --ctstate NEW -m hashlimit --hashlimit-above 10000/hour --hashlimit-burst 10000 --hashlimit-mode srcip --hashlimit-name antizapret-ddos --hashlimit-htable-expire 60000 -j SET --add-set antizapret-block src --exist
iptables -w -A INPUT -i "$INTERFACE" -m conntrack --ctstate NEW -m set --match-set antizapret-block src -m set ! --match-set antizapret-allow src -j DROP
iptables -w -A INPUT -i "$INTERFACE" -m conntrack --ctstate NEW -j SET --add-set antizapret-watch src,dst
iptables -w -A OUTPUT -o "$INTERFACE" -p tcp --tcp-flags RST RST -j DROP
iptables -w -A OUTPUT -o "$INTERFACE" -p icmp --icmp-type destination-unreachable -j DROP
ipset create antizapret-block6 hash:ip timeout 600 family inet6
ipset create antizapret-watch6 hash:ip,port timeout 60 family inet6
ipset list antizapret-allow6 &>/dev/null || ipset create antizapret-allow6 hash:net family inet6
ip6tables -w -A INPUT -i "$INTERFACE" -p icmpv6 --icmpv6-type echo-request -j DROP
ip6tables -w -A INPUT -i "$INTERFACE" -m conntrack --ctstate NEW -m set ! --match-set antizapret-watch6 src,dst -m hashlimit --hashlimit-above 10/hour --hashlimit-burst 10 --hashlimit-mode srcip --hashlimit-srcmask 24 --hashlimit-name antizapret-scan6 --hashlimit-htable-expire 60000 -j SET --add-set antizapret-block6 src --exist
ip6tables -w -A INPUT -i "$INTERFACE" -m conntrack --ctstate NEW -m hashlimit --hashlimit-above 10000/hour --hashlimit-burst 10000 --hashlimit-mode srcip --hashlimit-name antizapret-ddos6 --hashlimit-htable-expire 60000 -j SET --add-set antizapret-block6 src --exist
ip6tables -w -A INPUT -i "$INTERFACE" -m conntrack --ctstate NEW -m set --match-set antizapret-block6 src -m set ! --match-set antizapret-allow6 src -j DROP
ip6tables -w -A INPUT -i "$INTERFACE" -m conntrack --ctstate NEW -j SET --add-set antizapret-watch6 src,dst
ip6tables -w -A OUTPUT -o "$INTERFACE" -p tcp --tcp-flags RST RST -j DROP
ip6tables -w -A OUTPUT -o "$INTERFACE" -p icmpv6 --icmpv6-type destination-unreachable -j DROP
# FORWARD connection tracking
iptables -w -A FORWARD -m conntrack --ctstate INVALID -j DROP
iptables -w -A FORWARD -m conntrack --ctstate RELATED,ESTABLISHED,DNAT -j ACCEPT
ip6tables -w -A FORWARD -m conntrack --ctstate INVALID -j DROP
ip6tables -w -A FORWARD -m conntrack --ctstate RELATED,ESTABLISHED,DNAT -j ACCEPT
# ANTIZAPRET-ACCEPT
iptables -w -N ANTIZAPRET-ACCEPT
iptables -w -A FORWARD -s 10.29.0.0/16 -m connmark --mark 0x1 -j ANTIZAPRET-ACCEPT
iptables -w -A FORWARD -s 10.29.0.0/16 -m connmark --mark 0x1 -j REJECT --reject-with icmp-port-unreachable
while read -r line
do
	iptables -w -A ANTIZAPRET-ACCEPT -d "$line" -j ACCEPT
done < result/ips.txt
# ACCEPT all packets from VPN
iptables -w -A FORWARD -s 10.28.0.0/15 -j ACCEPT
# REJECT other packets
iptables -w -A FORWARD -j REJECT --reject-with icmp-port-unreachable
# OUTPUT connection tracking
iptables -w -A OUTPUT -m conntrack --ctstate INVALID -j DROP
ip6tables -w -A OUTPUT -m conntrack --ctstate INVALID -j DROP

# nat
# OpenVPN TCP port redirection for backup connections
iptables -w -t nat -A PREROUTING -i "$INTERFACE" -p tcp --dport 80 -j REDIRECT --to-ports 50080
iptables -w -t nat -A PREROUTING -i "$INTERFACE" -p tcp --dport 443 -j REDIRECT --to-ports 50443
# OpenVPN UDP port redirection for backup connections
iptables -w -t nat -A PREROUTING -i "$INTERFACE" -p udp --dport 80 -j REDIRECT --to-ports 50080
iptables -w -t nat -A PREROUTING -i "$INTERFACE" -p udp --dport 443 -j REDIRECT --to-ports 50443
# AmneziaWG redirection ports to WireGuard
iptables -w -t nat -A PREROUTING -i "$INTERFACE" -p udp --dport 52080 -j REDIRECT --to-ports 51080
iptables -w -t nat -A PREROUTING -i "$INTERFACE" -p udp --dport 52443 -j REDIRECT --to-ports 51443
# DNS redirection to Knot Resolver
iptables -w -t nat -A PREROUTING -s 10.29.0.0/16 ! -d 10.29.0.1/32 -p udp --dport 53 -m u32 --u32 "0x1c&0xffcf=0x100&&0x1e&0xffff=0x1" -j DNAT --to-destination 10.29.0.1
# ANTIZAPRET-ACCEPT
iptables -w -t nat -A PREROUTING -s 10.29.0.0/16 ! -d 10.30.0.0/15 -j CONNMARK --set-xmark 0x1/0xffffffff
# ANTIZAPRET-MAPPING
iptables -w -t nat -N ANTIZAPRET-MAPPING
iptables -w -t nat -A PREROUTING -s 10.29.0.0/16 -d 10.30.0.0/15 -j ANTIZAPRET-MAPPING
# MASQUERADE
iptables -w -t nat -A POSTROUTING -s 10.28.0.0/15 -j MASQUERADE

./custom-up.sh