#!/bin/bash

./iptables-down.sh

set -e

HERE="$(dirname "$(readlink -f "${0}")")"
cd "$HERE"

INTERFACE=$(ip route | grep '^default' | awk '{print $5}')
if [[ -z "$INTERFACE" ]]; then
	echo "Default network interface not found!"
	exit 1
fi

# filter
# INPUT connection tracking
iptables -w -A INPUT -m conntrack --ctstate INVALID -j DROP
# DROP ping request
iptables -w -A INPUT -i "$INTERFACE" -p icmp --icmp-type echo-request -j DROP
# Attack and scan protection
ipset create antizapret-blocklist hash:ip timeout 600
ipset create antizapret-newlist hash:ip,port timeout 10
iptables -w -A INPUT -i "$INTERFACE" -m conntrack --ctstate NEW -m set ! --match-set antizapret-newlist src,dst -m hashlimit --hashlimit-above 1/min --hashlimit-burst 3 --hashlimit-mode srcip --hashlimit-name antizapret-port --hashlimit-htable-expire 10000 -j SET --add-set antizapret-blocklist src --exist
iptables -w -A INPUT -i "$INTERFACE" -m conntrack --ctstate NEW -m hashlimit --hashlimit-above 100/min --hashlimit-burst 1000 --hashlimit-mode srcip --hashlimit-name antizapret-connect --hashlimit-htable-expire 10000 -j SET --add-set antizapret-blocklist src --exist
iptables -w -A INPUT -i "$INTERFACE" -m conntrack --ctstate NEW -m set --match-set antizapret-blocklist src -j DROP
iptables -w -A INPUT -i "$INTERFACE" -m conntrack --ctstate NEW -j SET --add-set antizapret-newlist src,dst
# FORWARD connection tracking
iptables -w -A FORWARD -m conntrack --ctstate INVALID -j DROP
iptables -w -A FORWARD -m conntrack --ctstate RELATED,ESTABLISHED,DNAT -j ACCEPT
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