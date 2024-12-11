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
ip6tables -w -A INPUT -m conntrack --ctstate INVALID -j DROP
# DROP all ICMP-packets except ICMP Fragmentation Needed and ICMPv6 Packet Too Big
iptables -w -A INPUT -i "$INTERFACE" -p icmp --icmp-type fragmentation-needed -j ACCEPT
iptables -w -A INPUT -i "$INTERFACE" -p icmp -j DROP
ip6tables -w -A INPUT -i "$INTERFACE" -p icmpv6 --icmpv6-type packet-too-big -j ACCEPT
ip6tables -w -A INPUT -i "$INTERFACE" -p icmpv6 -j DROP
# Attack and scan protection
ipset create antizapret-blocklist hash:ip timeout 600
ipset create antizapret-watchlist hash:ip,port timeout 20
iptables -w -A INPUT -i "$INTERFACE" -m conntrack --ctstate NEW -m set ! --match-set antizapret-watchlist src,dst -m hashlimit --hashlimit-above 1/min --hashlimit-burst 3 --hashlimit-mode srcip --hashlimit-name antizapret-port --hashlimit-htable-expire 20000 -j SET --add-set antizapret-blocklist src --exist
iptables -w -A INPUT -i "$INTERFACE" -m conntrack --ctstate NEW -m hashlimit --hashlimit-above 100/min --hashlimit-burst 1000 --hashlimit-mode srcip --hashlimit-name antizapret-conn --hashlimit-htable-expire 20000 -j SET --add-set antizapret-blocklist src --exist
iptables -w -A INPUT -i "$INTERFACE" -m conntrack --ctstate NEW -m set --match-set antizapret-blocklist src -j DROP
iptables -w -A INPUT -i "$INTERFACE" -m conntrack --ctstate NEW -j SET --add-set antizapret-watchlist src,dst --exist
ipset create antizapret-blocklist6 hash:ip timeout 600 family inet6
ipset create antizapret-watchlist6 hash:ip,port timeout 20 family inet6
ip6tables -w -A INPUT -i "$INTERFACE" -m conntrack --ctstate NEW -m set ! --match-set antizapret-watchlist6 src,dst -m hashlimit --hashlimit-above 1/min --hashlimit-burst 3 --hashlimit-mode srcip --hashlimit-name antizapret-port --hashlimit-htable-expire 20000 -j SET --add-set antizapret-blocklist6 src --exist
ip6tables -w -A INPUT -i "$INTERFACE" -m conntrack --ctstate NEW -m hashlimit --hashlimit-above 100/min --hashlimit-burst 1000 --hashlimit-mode srcip --hashlimit-name antizapret-conn --hashlimit-htable-expire 20000 -j SET --add-set antizapret-blocklist6 src --exist
ip6tables -w -A INPUT -i "$INTERFACE" -m conntrack --ctstate NEW -m set --match-set antizapret-blocklist6 src -j DROP
ip6tables -w -A INPUT -i "$INTERFACE" -m conntrack --ctstate NEW -j SET --add-set antizapret-watchlist6 src,dst --exist
# OpenVPN TCP ports attack and scan protection
iptables -w -A INPUT -i "$INTERFACE" -m conntrack --ctstate NEW -m bpf --bytecode "23,48 0 0 0,84 0 0 240,21 19 0 96,48 0 0 0,84 0 0 240,21 0 16 64,48 0 0 9,21 0 14 17,40 0 0 6,69 12 0 8191,177 0 0 0,72 0 0 2,21 0 9 50080,80 0 0 8,21 0 7 56,64 0 0 37,21 0 5 1,80 0 0 45,21 0 3 0,64 0 0 46,21 0 1 0,6 0 0 65535,6 0 0 0" -j ACCEPT
iptables -w -A INPUT -i "$INTERFACE" -m conntrack --ctstate NEW -m bpf --bytecode "23,48 0 0 0,84 0 0 240,21 19 0 96,48 0 0 0,84 0 0 240,21 0 16 64,48 0 0 9,21 0 14 17,40 0 0 6,69 12 0 8191,177 0 0 0,72 0 0 2,21 0 9 50443,80 0 0 8,21 0 7 56,64 0 0 37,21 0 5 1,80 0 0 45,21 0 3 0,64 0 0 46,21 0 1 0,6 0 0 65535,6 0 0 0" -j ACCEPT
iptables -w -A INPUT -i "$INTERFACE" -p tcp -m conntrack --ctstate NEW -m multiport --dports 50080,50443 -j DROP
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