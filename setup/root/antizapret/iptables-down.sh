#!/bin/bash

exec 2>/dev/null

INTERFACE=$(ip route | grep '^default' | awk '{print $5}')

# filter
iptables -w -D INPUT -m conntrack --ctstate INVALID -j DROP
iptables -w -D INPUT -i "$INTERFACE" -p icmp --icmp-type echo-request -j DROP
iptables -w -D INPUT -i "$INTERFACE" -p tcp -m multiport --dports 22,80,443,50080,50443 -j ACCEPT
iptables -w -D INPUT -i "$INTERFACE" -p udp -m multiport --dports 80,443,50080,50443,51080,51443,52080,52443 -j ACCEPT
iptables -w -D INPUT -i "$INTERFACE" -m conntrack --ctstate NEW -m recent --name ANTIZAPRET-BLOCKLIST --set
iptables -w -D INPUT -i "$INTERFACE" -m conntrack --ctstate NEW -m recent --name ANTIZAPRET-BLOCKLIST --update --seconds 10 --hitcount 11 -j DROP
iptables -w -D FORWARD -m conntrack --ctstate INVALID -j DROP
iptables -w -D FORWARD -m conntrack --ctstate RELATED,ESTABLISHED,DNAT -j ACCEPT
iptables -w -D FORWARD -s 10.29.0.0/16 -m connmark --mark 0x1 -j ANTIZAPRET-ACCEPT
iptables -w -D FORWARD -s 10.29.0.0/16 -m connmark --mark 0x1 -j REJECT --reject-with icmp-port-unreachable
iptables -w -D FORWARD -s 10.28.0.0/15 -j ACCEPT
iptables -w -D FORWARD -s 172.29.0.0/16 -m connmark --mark 0x1 -j ANTIZAPRET-ACCEPT
iptables -w -D FORWARD -s 172.29.0.0/16 -m connmark --mark 0x1 -j REJECT --reject-with icmp-port-unreachable
iptables -w -D FORWARD -s 172.28.0.0/15 -j ACCEPT
iptables -w -D FORWARD -j REJECT --reject-with icmp-port-unreachable
iptables -w -D OUTPUT -m conntrack --ctstate INVALID -j DROP
iptables -w -F ANTIZAPRET-ACCEPT
iptables -w -X ANTIZAPRET-ACCEPT

# nat
iptables -w -t nat -D PREROUTING -i "$INTERFACE" -p tcp --dport 80 -j REDIRECT --to-ports 50080
iptables -w -t nat -D PREROUTING -i "$INTERFACE" -p tcp --dport 443 -j REDIRECT --to-ports 50443
iptables -w -t nat -D PREROUTING -i "$INTERFACE" -p udp --dport 80 -j REDIRECT --to-ports 50080
iptables -w -t nat -D PREROUTING -i "$INTERFACE" -p udp --dport 443 -j REDIRECT --to-ports 50443
iptables -w -t nat -D PREROUTING -i "$INTERFACE" -p udp --dport 52080 -j REDIRECT --to-ports 51080
iptables -w -t nat -D PREROUTING -i "$INTERFACE" -p udp --dport 52443 -j REDIRECT --to-ports 51443
iptables -w -t nat -D PREROUTING -s 10.29.0.0/16 ! -d 10.29.0.1/32 -p udp --dport 53 -m u32 --u32 "0x1c&0xffcf=0x100&&0x1e&0xffff=0x1" -j DNAT --to-destination 10.29.0.1
iptables -w -t nat -D PREROUTING -s 10.29.0.0/16 ! -d 10.30.0.0/15 -j CONNMARK --set-xmark 0x1/0xffffffff
iptables -w -t nat -D PREROUTING -s 10.29.0.0/16 -d 10.30.0.0/15 -j ANTIZAPRET-MAPPING
iptables -w -t nat -D POSTROUTING -s 10.28.0.0/15 -j MASQUERADE
iptables -w -t nat -D PREROUTING -s 172.29.0.0/16 ! -d 172.29.0.1/32 -p udp --dport 53 -m u32 --u32 "0x1c&0xffcf=0x100&&0x1e&0xffff=0x1" -j DNAT --to-destination 172.29.0.1
iptables -w -t nat -D PREROUTING -s 172.29.0.0/16 ! -d 172.30.0.0/15 -j CONNMARK --set-xmark 0x1/0xffffffff
iptables -w -t nat -D PREROUTING -s 172.29.0.0/16 -d 172.30.0.0/15 -j ANTIZAPRET-MAPPING
iptables -w -t nat -D POSTROUTING -s 172.28.0.0/15 -j MASQUERADE
iptables -w -t nat -F ANTIZAPRET-MAPPING
iptables -w -t nat -X ANTIZAPRET-MAPPING