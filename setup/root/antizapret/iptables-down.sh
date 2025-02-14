#!/bin/bash

exec 2>/dev/null

INTERFACE=$(ip route | grep '^default' | awk '{print $5}')

# filter
# INPUT connection tracking
iptables -w -D INPUT -m conntrack --ctstate INVALID -j DROP
ip6tables -w -D INPUT -m conntrack --ctstate INVALID -j DROP
# Attack and scan protection
iptables -w -D INPUT -i "$INTERFACE" -p icmp --icmp-type echo-request -j DROP
iptables -w -D INPUT -i "$INTERFACE" -m conntrack --ctstate NEW -m set ! --match-set antizapret-watch src,dst -m hashlimit --hashlimit-above 10/hour --hashlimit-burst 10 --hashlimit-mode srcip --hashlimit-srcmask 24 --hashlimit-name antizapret-port --hashlimit-htable-expire 60000 -j SET --add-set antizapret-block src --exist
iptables -w -D INPUT -i "$INTERFACE" -m conntrack --ctstate NEW -p udp -m set ! --match-set antizapret-watch src,dst -m hashlimit --hashlimit-above 5/hour --hashlimit-burst 5 --hashlimit-mode srcip --hashlimit-name antizapret-port-udp --hashlimit-htable-expire 60000 -j SET --add-set antizapret-block src --exist
iptables -w -D INPUT -i "$INTERFACE" -m conntrack --ctstate NEW -p tcp -m set ! --match-set antizapret-watch src,dst -m hashlimit --hashlimit-above 5/hour --hashlimit-burst 5 --hashlimit-mode srcip --hashlimit-name antizapret-port-tcp --hashlimit-htable-expire 60000 -j SET --add-set antizapret-block src --exist
iptables -w -D INPUT -i "$INTERFACE" -m conntrack --ctstate NEW -p udp -m hashlimit --hashlimit-above 1500/hour --hashlimit-burst 1500 --hashlimit-mode srcip --hashlimit-name antizapret-conn-udp --hashlimit-htable-expire 60000 -j SET --add-set antizapret-block src --exist
iptables -w -D INPUT -i "$INTERFACE" -m conntrack --ctstate NEW -p tcp -m hashlimit --hashlimit-above 500/hour --hashlimit-burst 500 --hashlimit-mode srcip --hashlimit-name antizapret-conn-tcp --hashlimit-htable-expire 60000 -j SET --add-set antizapret-block src --exist
iptables -w -D INPUT -i "$INTERFACE" -m conntrack --ctstate NEW -m set --match-set antizapret-block src -m set ! --match-set antizapret-allow src -j DROP
iptables -w -D INPUT -i "$INTERFACE" -m conntrack --ctstate NEW -j SET --add-set antizapret-watch src,dst
iptables -w -D OUTPUT -o "$INTERFACE" -p tcp --tcp-flags RST RST -j DROP
iptables -w -D OUTPUT -o "$INTERFACE" -p icmp --icmp-type destination-unreachable -j DROP
ipset destroy antizapret-block
ipset destroy antizapret-watch
ip6tables -w -D INPUT -i "$INTERFACE" -p icmpv6 --icmpv6-type echo-request -j DROP
ip6tables -w -D INPUT -i "$INTERFACE" -m conntrack --ctstate NEW -m set ! --match-set antizapret-watch6 src,dst -m hashlimit --hashlimit-above 10/hour --hashlimit-burst 10 --hashlimit-mode srcip --hashlimit-srcmask 24 --hashlimit-name antizapret-port6 --hashlimit-htable-expire 60000 -j SET --add-set antizapret-block6 src --exist
ip6tables -w -D INPUT -i "$INTERFACE" -m conntrack --ctstate NEW -p udp -m set ! --match-set antizapret-watch6 src,dst -m hashlimit --hashlimit-above 5/hour --hashlimit-burst 5 --hashlimit-mode srcip --hashlimit-name antizapret-port-udp6 --hashlimit-htable-expire 60000 -j SET --add-set antizapret-block6 src --exist
ip6tables -w -D INPUT -i "$INTERFACE" -m conntrack --ctstate NEW -p tcp -m set ! --match-set antizapret-watch6 src,dst -m hashlimit --hashlimit-above 5/hour --hashlimit-burst 5 --hashlimit-mode srcip --hashlimit-name antizapret-port-tcp6 --hashlimit-htable-expire 60000 -j SET --add-set antizapret-block6 src --exist
ip6tables -w -D INPUT -i "$INTERFACE" -m conntrack --ctstate NEW -p udp -m hashlimit --hashlimit-above 1500/hour --hashlimit-burst 1500 --hashlimit-mode srcip --hashlimit-name antizapret-conn-udp6 --hashlimit-htable-expire 60000 -j SET --add-set antizapret-block6 src --exist
ip6tables -w -D INPUT -i "$INTERFACE" -m conntrack --ctstate NEW -p tcp -m hashlimit --hashlimit-above 500/hour --hashlimit-burst 500 --hashlimit-mode srcip --hashlimit-name antizapret-conn-tcp6 --hashlimit-htable-expire 60000 -j SET --add-set antizapret-block6 src --exist
ip6tables -w -D INPUT -i "$INTERFACE" -m conntrack --ctstate NEW -m set --match-set antizapret-block6 src -m set ! --match-set antizapret-allow6 src -j DROP
ip6tables -w -D INPUT -i "$INTERFACE" -m conntrack --ctstate NEW -j SET --add-set antizapret-watch6 src,dst
ip6tables -w -D OUTPUT -o "$INTERFACE" -p tcp --tcp-flags RST RST -j DROP
ip6tables -w -D OUTPUT -o "$INTERFACE" -p icmpv6 --icmpv6-type destination-unreachable -j DROP
ipset destroy antizapret-block6
ipset destroy antizapret-watch6
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