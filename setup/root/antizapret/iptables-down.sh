#!/bin/bash

exec 2>/dev/null

INTERFACE=$(ip route | grep '^default' | awk '{print $5}')

# filter
# INPUT connection tracking
iptables -w -D INPUT -m conntrack --ctstate INVALID -j DROP
ip6tables -w -D INPUT -m conntrack --ctstate INVALID -j DROP
# DROP all ICMP-packets except ICMP Fragmentation Needed and ICMPv6 Packet Too Big
iptables -w -D INPUT -i "$INTERFACE" -p icmp --icmp-type fragmentation-needed -j ACCEPT
iptables -w -D INPUT -i "$INTERFACE" -p icmp -j DROP
ip6tables -w -D INPUT -i "$INTERFACE" -p icmpv6 --icmpv6-type packet-too-big -j ACCEPT
ip6tables -w -D INPUT -i "$INTERFACE" -p icmpv6 -j DROP
# Attack and scan protection
iptables -w -D INPUT -i "$INTERFACE" -m conntrack --ctstate NEW -m set ! --match-set antizapret-watchlist src,dst -m hashlimit --hashlimit-above 1/min --hashlimit-burst 3 --hashlimit-mode srcip --hashlimit-name antizapret-port --hashlimit-htable-expire 20000 -j SET --add-set antizapret-blocklist src --exist
iptables -w -D INPUT -i "$INTERFACE" -m conntrack --ctstate NEW -m hashlimit --hashlimit-above 100/min --hashlimit-burst 1000 --hashlimit-mode srcip --hashlimit-name antizapret-conn --hashlimit-htable-expire 20000 -j SET --add-set antizapret-blocklist src --exist
iptables -w -D INPUT -i "$INTERFACE" -m conntrack --ctstate NEW -m set --match-set antizapret-blocklist src -j DROP
iptables -w -D INPUT -i "$INTERFACE" -m conntrack --ctstate NEW -j SET --add-set antizapret-watchlist src,dst --exist
ipset destroy antizapret-blocklist
ipset destroy antizapret-watchlist
ip6tables -w -D INPUT -i "$INTERFACE" -m conntrack --ctstate NEW -m set ! --match-set antizapret-watchlist6 src,dst -m hashlimit --hashlimit-above 1/min --hashlimit-burst 3 --hashlimit-mode srcip --hashlimit-name antizapret-port --hashlimit-htable-expire 20000 -j SET --add-set antizapret-blocklist6 src --exist
ip6tables -w -D INPUT -i "$INTERFACE" -m conntrack --ctstate NEW -m hashlimit --hashlimit-above 100/min --hashlimit-burst 1000 --hashlimit-mode srcip --hashlimit-name antizapret-conn --hashlimit-htable-expire 20000 -j SET --add-set antizapret-blocklist6 src --exist
ip6tables -w -D INPUT -i "$INTERFACE" -m conntrack --ctstate NEW -m set --match-set antizapret-blocklist6 src -j DROP
ip6tables -w -D INPUT -i "$INTERFACE" -m conntrack --ctstate NEW -j SET --add-set antizapret-watchlist6 src,dst --exist
ipset destroy antizapret-blocklist6
ipset destroy antizapret-watchlist6
# OpenVPN TCP ports attack and scan protection
iptables -w -D INPUT -i "$INTERFACE" -m conntrack --ctstate NEW -m bpf --bytecode "23,48 0 0 0,84 0 0 240,21 19 0 96,48 0 0 0,84 0 0 240,21 0 16 64,48 0 0 9,21 0 14 17,40 0 0 6,69 12 0 8191,177 0 0 0,72 0 0 2,21 0 9 50080,80 0 0 8,21 0 7 56,64 0 0 37,21 0 5 1,80 0 0 45,21 0 3 0,64 0 0 46,21 0 1 0,6 0 0 65535,6 0 0 0" -j ACCEPT
iptables -w -D INPUT -i "$INTERFACE" -m conntrack --ctstate NEW -m bpf --bytecode "23,48 0 0 0,84 0 0 240,21 19 0 96,48 0 0 0,84 0 0 240,21 0 16 64,48 0 0 9,21 0 14 17,40 0 0 6,69 12 0 8191,177 0 0 0,72 0 0 2,21 0 9 50443,80 0 0 8,21 0 7 56,64 0 0 37,21 0 5 1,80 0 0 45,21 0 3 0,64 0 0 46,21 0 1 0,6 0 0 65535,6 0 0 0" -j ACCEPT
iptables -w -D INPUT -i "$INTERFACE" -p tcp -m conntrack --ctstate NEW -m multiport --dports 50080,50443 -j DROP
# FORWARD connection tracking
iptables -w -D FORWARD -m conntrack --ctstate INVALID -j DROP
iptables -w -D FORWARD -m conntrack --ctstate RELATED,ESTABLISHED,DNAT -j ACCEPT
ip6tables -w -D FORWARD -m conntrack --ctstate INVALID -j DROP
ip6tables -w -D FORWARD -m conntrack --ctstate RELATED,ESTABLISHED,DNAT -j ACCEPT
# ANTIZAPRET-ACCEPT
iptables -w -D FORWARD -s 10.29.0.0/16 -m connmark --mark 0x1 -j ANTIZAPRET-ACCEPT
iptables -w -D FORWARD -s 10.29.0.0/16 -m connmark --mark 0x1 -j REJECT --reject-with icmp-port-unreachable
iptables -w -D FORWARD -s 172.29.0.0/16 -m connmark --mark 0x1 -j ANTIZAPRET-ACCEPT
iptables -w -D FORWARD -s 172.29.0.0/16 -m connmark --mark 0x1 -j REJECT --reject-with icmp-port-unreachable
iptables -w -F ANTIZAPRET-ACCEPT
iptables -w -X ANTIZAPRET-ACCEPT
# ACCEPT all packets from VPN
iptables -w -D FORWARD -s 10.28.0.0/15 -j ACCEPT
iptables -w -D FORWARD -s 172.28.0.0/15 -j ACCEPT
# REJECT other packets
iptables -w -D FORWARD -j REJECT --reject-with icmp-port-unreachable
# OUTPUT connection tracking
iptables -w -D OUTPUT -m conntrack --ctstate INVALID -j DROP
ip6tables -w -D OUTPUT -m conntrack --ctstate INVALID -j DROP

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
# ANTIZAPRET-ACCEPT
iptables -w -t nat -D PREROUTING -s 10.29.0.0/16 ! -d 10.30.0.0/15 -j CONNMARK --set-xmark 0x1/0xffffffff
iptables -w -t nat -D PREROUTING -s 172.29.0.0/16 ! -d 172.30.0.0/15 -j CONNMARK --set-xmark 0x1/0xffffffff
# ANTIZAPRET-MAPPING
iptables -w -t nat -D PREROUTING -s 10.29.0.0/16 -d 10.30.0.0/15 -j ANTIZAPRET-MAPPING
iptables -w -t nat -D PREROUTING -s 172.29.0.0/16 -d 172.30.0.0/15 -j ANTIZAPRET-MAPPING
iptables -w -t nat -F ANTIZAPRET-MAPPING
iptables -w -t nat -X ANTIZAPRET-MAPPING
# MASQUERADE
iptables -w -t nat -D POSTROUTING -s 10.28.0.0/15 -j MASQUERADE
iptables -w -t nat -D POSTROUTING -s 172.28.0.0/15 -j MASQUERADE