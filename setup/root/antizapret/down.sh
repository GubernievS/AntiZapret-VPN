#!/bin/bash

exec 2>/dev/null

if [[ -z "$1" ]]; then
	INTERFACE=$(ip route | grep '^default' | awk '{print $5}')
else
	INTERFACE=$1
fi

# filter
# INPUT connection tracking
iptables -w -D INPUT -m conntrack --ctstate INVALID -j DROP
ip6tables -w -D INPUT -m conntrack --ctstate INVALID -j DROP
# FORWARD connection tracking
iptables -w -D FORWARD -m conntrack --ctstate INVALID -j DROP
ip6tables -w -D FORWARD -m conntrack --ctstate INVALID -j DROP
# OUTPUT connection tracking
iptables -w -D OUTPUT -m conntrack --ctstate INVALID -j DROP
ip6tables -w -D OUTPUT -m conntrack --ctstate INVALID -j DROP
# FORWARD VPN traffic
iptables -w -D FORWARD -d 10.28.0.0/15 -j ACCEPT
iptables -w -D FORWARD -d 172.28.0.0/15 -j ACCEPT
iptables -w -D FORWARD -s 10.28.0.0/15 -j ACCEPT
iptables -w -D FORWARD -s 172.28.0.0/15 -j ACCEPT
# Attack and scan protection
iptables -w -D INPUT -i "$INTERFACE" -p icmp --icmp-type echo-request -j DROP
iptables -w -D INPUT -i "$INTERFACE" -m conntrack --ctstate NEW -m set ! --match-set antizapret-watch src,dst -m hashlimit --hashlimit-above 10/hour --hashlimit-burst 10 --hashlimit-mode srcip --hashlimit-srcmask 24 --hashlimit-name antizapret-scan --hashlimit-htable-expire 60000 -j SET --add-set antizapret-block src --exist
iptables -w -D INPUT -i "$INTERFACE" -m conntrack --ctstate NEW -m hashlimit --hashlimit-above 10000/hour --hashlimit-burst 10000 --hashlimit-mode srcip --hashlimit-name antizapret-ddos --hashlimit-htable-expire 60000 -j SET --add-set antizapret-block src --exist
iptables -w -D INPUT -i "$INTERFACE" -m conntrack --ctstate NEW -m set --match-set antizapret-block src -m set ! --match-set antizapret-allow src -j DROP
iptables -w -D INPUT -i "$INTERFACE" -m conntrack --ctstate NEW -j SET --add-set antizapret-watch src,dst
iptables -w -D OUTPUT -o "$INTERFACE" -p tcp --tcp-flags RST RST -j DROP
iptables -w -D OUTPUT -o "$INTERFACE" -p icmp --icmp-type destination-unreachable -j DROP
ipset destroy antizapret-block
ipset destroy antizapret-watch
ip6tables -w -D INPUT -i "$INTERFACE" -p icmpv6 --icmpv6-type echo-request -j DROP
ip6tables -w -D INPUT -i "$INTERFACE" -m conntrack --ctstate NEW -m set ! --match-set antizapret-watch6 src,dst -m hashlimit --hashlimit-above 10/hour --hashlimit-burst 10 --hashlimit-mode srcip --hashlimit-srcmask 24 --hashlimit-name antizapret-scan6 --hashlimit-htable-expire 60000 -j SET --add-set antizapret-block6 src --exist
ip6tables -w -D INPUT -i "$INTERFACE" -m conntrack --ctstate NEW -m hashlimit --hashlimit-above 10000/hour --hashlimit-burst 10000 --hashlimit-mode srcip --hashlimit-name antizapret-ddos6 --hashlimit-htable-expire 60000 -j SET --add-set antizapret-block6 src --exist
ip6tables -w -D INPUT -i "$INTERFACE" -m conntrack --ctstate NEW -m set --match-set antizapret-block6 src -m set ! --match-set antizapret-allow6 src -j DROP
ip6tables -w -D INPUT -i "$INTERFACE" -m conntrack --ctstate NEW -j SET --add-set antizapret-watch6 src,dst
ip6tables -w -D OUTPUT -o "$INTERFACE" -p tcp --tcp-flags RST RST -j DROP
ip6tables -w -D OUTPUT -o "$INTERFACE" -p icmpv6 --icmpv6-type destination-unreachable -j DROP
ipset destroy antizapret-block6
ipset destroy antizapret-watch6

# nat
# OpenVPN TCP port redirection for backup connections
iptables -w -t nat -D PREROUTING -i "$INTERFACE" -p tcp --dport 80 -j REDIRECT --to-ports 50080
iptables -w -t nat -D PREROUTING -i "$INTERFACE" -p tcp --dport 443 -j REDIRECT --to-ports 50443
# OpenVPN UDP port redirection for backup connections
iptables -w -t nat -D PREROUTING -i "$INTERFACE" -p udp --dport 80 -j REDIRECT --to-ports 50080
iptables -w -t nat -D PREROUTING -i "$INTERFACE" -p udp --dport 443 -j REDIRECT --to-ports 50443
# AmneziaWG redirection ports to WireGuard
iptables -w -t nat -D PREROUTING -i "$INTERFACE" -p udp --dport 52080 -j REDIRECT --to-ports 51080
iptables -w -t nat -D PREROUTING -i "$INTERFACE" -p udp --dport 52443 -j REDIRECT --to-ports 51443
# DNS redirection to Knot Resolver
iptables -w -t nat -D PREROUTING -s 10.29.0.0/16 ! -d 10.29.0.1/32 -p udp --dport 53 -m u32 --u32 "0x1c&0xffcf=0x100&&0x1e&0xffff=0x1" -j DNAT --to-destination 10.29.0.1
iptables -w -t nat -D PREROUTING -s 172.29.0.0/16 ! -d 172.29.0.1/32 -p udp --dport 53 -m u32 --u32 "0x1c&0xffcf=0x100&&0x1e&0xffff=0x1" -j DNAT --to-destination 172.29.0.1
# ANTIZAPRET-MAPPING
iptables -w -t nat -D PREROUTING -s 10.29.0.0/16 -d 10.30.0.0/15 -j ANTIZAPRET-MAPPING
iptables -w -t nat -D PREROUTING -s 172.29.0.0/16 -d 172.30.0.0/15 -j ANTIZAPRET-MAPPING
iptables -w -t nat -F ANTIZAPRET-MAPPING
iptables -w -t nat -X ANTIZAPRET-MAPPING
# MASQUERADE
iptables -w -t nat -D POSTROUTING -s 10.28.0.0/15 -j MASQUERADE
iptables -w -t nat -D POSTROUTING -s 172.28.0.0/15 -j MASQUERADE

./custom-down.sh