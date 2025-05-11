#!/bin/bash
set -e

INTERFACE="$(ip route | grep '^default' | awk '{print $5}')"
if [[ -z "$INTERFACE" ]]; then
	echo "Default network interface not found!"
	exit 1
fi

/root/antizapret/down.sh "$INTERFACE"

source /root/antizapret/setup

[[ "$ALTERNATIVE_IP" == "y" ]] && IP="172" || IP="10"

# Clear knot-resolver cache
echo "cache.clear()" | socat - /run/knot-resolver/control/1

# Network parameters modification
sysctl -w net.ipv4.ip_forward=1
sysctl -w kernel.printk="3 4 1 3"
sysctl -w net.core.default_qdisc=fq || true
sysctl -w net.ipv4.tcp_congestion_control=bbr || true

# filter
# INPUT connection tracking
iptables -w -I INPUT 1 -m conntrack --ctstate INVALID -j DROP
ip6tables -w -I INPUT 1 -m conntrack --ctstate INVALID -j DROP
# FORWARD connection tracking
iptables -w -I FORWARD 1 -m conntrack --ctstate INVALID -j DROP
ip6tables -w -I FORWARD 1 -m conntrack --ctstate INVALID -j DROP
# OUTPUT connection tracking
iptables -w -I OUTPUT 1 -m conntrack --ctstate INVALID -j DROP
ip6tables -w -I OUTPUT 1 -m conntrack --ctstate INVALID -j DROP
# FORWARD VPN traffic
iptables -w -I FORWARD 2 -d ${IP}.28.0.0/15 -j ACCEPT
iptables -w -I FORWARD 3 -s ${IP}.28.0.0/15 -j ACCEPT
# Attack and scan protection
if [[ "$ATTACK_PROTECTION" == "y" ]]; then
	ipset list antizapret-block &>/dev/null || ipset create antizapret-block hash:ip timeout 600
	ipset list antizapret-watch &>/dev/null || ipset create antizapret-watch hash:ip,port timeout 60
	ipset list antizapret-allow &>/dev/null || ipset create antizapret-allow hash:net
	iptables -w -I INPUT 2 -i "$INTERFACE" -p icmp --icmp-type echo-request -j DROP
	iptables -w -I INPUT 3 -i "$INTERFACE" -m set --match-set antizapret-allow src -j ACCEPT
	iptables -w -I INPUT 4 -i "$INTERFACE" -m conntrack --ctstate NEW -m set ! --match-set antizapret-watch src,dst -m hashlimit --hashlimit-above 10/hour --hashlimit-burst 10 --hashlimit-mode srcip --hashlimit-srcmask 24 --hashlimit-name antizapret-scan --hashlimit-htable-expire 60000 -j SET --add-set antizapret-block src --exist
	iptables -w -I INPUT 5 -i "$INTERFACE" -m conntrack --ctstate NEW -m hashlimit --hashlimit-above 10000/hour --hashlimit-burst 10000 --hashlimit-mode srcip --hashlimit-name antizapret-ddos --hashlimit-htable-expire 60000 -j SET --add-set antizapret-block src --exist
	iptables -w -I INPUT 6 -i "$INTERFACE" -m conntrack --ctstate NEW -m set --match-set antizapret-block src -j DROP
	iptables -w -I INPUT 7 -i "$INTERFACE" -m conntrack --ctstate NEW -j SET --add-set antizapret-watch src,dst
	iptables -w -I OUTPUT 2 -o "$INTERFACE" -p tcp --tcp-flags RST RST -j DROP
	iptables -w -I OUTPUT 3 -o "$INTERFACE" -p icmp --icmp-type destination-unreachable -j DROP
	ipset list antizapret-block6 &>/dev/null || ipset create antizapret-block6 hash:ip timeout 600 family inet6
	ipset list antizapret-watch6 &>/dev/null || ipset create antizapret-watch6 hash:ip,port timeout 60 family inet6
	ipset list antizapret-allow6 &>/dev/null || ipset create antizapret-allow6 hash:net family inet6
	ip6tables -w -I INPUT 2 -i "$INTERFACE" -p icmpv6 --icmpv6-type echo-request -j DROP
	ip6tables -w -I INPUT 3 -i "$INTERFACE" -m set --match-set antizapret-allow6 src -j ACCEPT
	ip6tables -w -I INPUT 4 -i "$INTERFACE" -m conntrack --ctstate NEW -m set ! --match-set antizapret-watch6 src,dst -m hashlimit --hashlimit-above 10/hour --hashlimit-burst 10 --hashlimit-mode srcip --hashlimit-srcmask 64 --hashlimit-name antizapret-scan6 --hashlimit-htable-expire 60000 -j SET --add-set antizapret-block6 src --exist
	ip6tables -w -I INPUT 5 -i "$INTERFACE" -m conntrack --ctstate NEW -m hashlimit --hashlimit-above 10000/hour --hashlimit-burst 10000 --hashlimit-mode srcip --hashlimit-name antizapret-ddos6 --hashlimit-htable-expire 60000 -j SET --add-set antizapret-block6 src --exist
	ip6tables -w -I INPUT 6 -i "$INTERFACE" -m conntrack --ctstate NEW -m set --match-set antizapret-block6 src -j DROP
	ip6tables -w -I INPUT 7 -i "$INTERFACE" -m conntrack --ctstate NEW -j SET --add-set antizapret-watch6 src,dst
	ip6tables -w -I OUTPUT 2 -o "$INTERFACE" -p tcp --tcp-flags RST RST -j DROP
	ip6tables -w -I OUTPUT 3 -o "$INTERFACE" -p icmpv6 --icmpv6-type destination-unreachable -j DROP
fi
# SSH protection
if [[ "$SSH_PROTECTION" == "y" ]]; then
	iptables -w -I INPUT 2 -p tcp --dport ssh -m conntrack --ctstate NEW -m hashlimit --hashlimit-above 3/hour --hashlimit-burst 3 --hashlimit-mode srcip --hashlimit-srcmask 24 --hashlimit-name antizapret-ssh --hashlimit-htable-expire 60000 -j DROP
	ip6tables -w -I INPUT 2 -p tcp --dport ssh -m conntrack --ctstate NEW -m hashlimit --hashlimit-above 3/hour --hashlimit-burst 3 --hashlimit-mode srcip --hashlimit-srcmask 64 --hashlimit-name antizapret-ssh6 --hashlimit-htable-expire 60000 -j DROP
fi

# nat
# OpenVPN TCP port redirection for backup connections
if [[ "$OPENVPN_80_443_TCP" == "y" ]]; then
	iptables -w -t nat -A PREROUTING -i "$INTERFACE" -p tcp --dport 80 -j REDIRECT --to-ports 50080
	iptables -w -t nat -A PREROUTING -i "$INTERFACE" -p tcp --dport 443 -j REDIRECT --to-ports 50443
fi
# OpenVPN UDP port redirection for backup connections
if [[ "$OPENVPN_80_443_UDP" == "y" ]]; then
	iptables -w -t nat -A PREROUTING -i "$INTERFACE" -p udp --dport 80 -j REDIRECT --to-ports 50080
	iptables -w -t nat -A PREROUTING -i "$INTERFACE" -p udp --dport 443 -j REDIRECT --to-ports 50443
fi
# AmneziaWG redirection ports to WireGuard
iptables -w -t nat -A PREROUTING -i "$INTERFACE" -p udp --dport 52080 -j REDIRECT --to-ports 51080
iptables -w -t nat -A PREROUTING -i "$INTERFACE" -p udp --dport 52443 -j REDIRECT --to-ports 51443
# DNS redirection to Knot Resolver
iptables -w -t nat -A PREROUTING -s ${IP}.29.0.0/22 ! -d ${IP}.29.0.1/32 -p udp --dport 53 -j DNAT --to-destination ${IP}.29.0.1
iptables -w -t nat -A PREROUTING -s ${IP}.29.4.0/22 ! -d ${IP}.29.4.1/32 -p udp --dport 53 -j DNAT --to-destination ${IP}.29.4.1
iptables -w -t nat -A PREROUTING -s ${IP}.29.8.0/24 ! -d ${IP}.29.8.1/32 -p udp --dport 53 -j DNAT --to-destination ${IP}.29.8.1
iptables -w -t nat -A PREROUTING -s ${IP}.29.0.0/22 ! -d ${IP}.29.0.1/32 -p tcp --dport 53 -j DNAT --to-destination ${IP}.29.0.1
iptables -w -t nat -A PREROUTING -s ${IP}.29.4.0/22 ! -d ${IP}.29.4.1/32 -p tcp --dport 53 -j DNAT --to-destination ${IP}.29.4.1
iptables -w -t nat -A PREROUTING -s ${IP}.29.8.0/24 ! -d ${IP}.29.8.1/32 -p tcp --dport 53 -j DNAT --to-destination ${IP}.29.8.1
# ANTIZAPRET-MAPPING
iptables -w -t nat -nL ANTIZAPRET-MAPPING &>/dev/null || iptables -w -t nat -N ANTIZAPRET-MAPPING
iptables -w -t nat -A PREROUTING -s ${IP}.29.0.0/16 -d ${IP}.30.0.0/15 -j ANTIZAPRET-MAPPING
# MASQUERADE VPN traffic
iptables -w -t nat -A POSTROUTING -s ${IP}.28.0.0/15 -j MASQUERADE

/root/antizapret/custom-up.sh