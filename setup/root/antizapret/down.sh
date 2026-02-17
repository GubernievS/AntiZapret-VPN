#!/bin/bash
exec 2>/dev/null

cd /root/antizapret

source setup

if [[ -z "$DEFAULT_INTERFACE" ]]; then
	DEFAULT_INTERFACE="$(ip route get 1.2.3.4 2>/dev/null | awk '{print $5; exit}')"
fi
if [[ -z "$DEFAULT_INTERFACE" ]]; then
	echo 'Default network interface not found!'
	exit 1
fi

DEFAULT_IP="$(ip route get 1.2.3.4 2>/dev/null | awk '{print $7; exit}')"
if [[ -z "$DEFAULT_IP" ]]; then
	echo 'Default IPv4 address not found!'
	exit 2
fi

if [[ -z "$OUT_INTERFACE" ]]; then
	OUT_INTERFACE="$DEFAULT_INTERFACE"
	if [[ -z "$OUT_IP" ]]; then
		OUT_IP="$DEFAULT_IP"
	fi
fi

[[ "$ALTERNATIVE_IP" == 'y' ]] && IP="${IP:-172}" || IP=10
[[ "$ALTERNATIVE_FAKE_IP" == 'y' ]] && FAKE_IP="${FAKE_IP:-198.18}" || FAKE_IP="$IP.30"

# WARP
WARP_INTERFACE=warp
WARP_PATH="/etc/wireguard/$WARP_INTERFACE.conf"
wg-quick down $WARP_PATH
ip link delete dev $WARP_INTERFACE

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
# Torrent guard
iptables -w -D FORWARD -s $IP.28.0.0/16 -p tcp -m string --string 'GET ' --algo kmp --to 100 -m string --string 'info_hash=' --algo bm -m string --string 'peer_id=' --algo bm -m string --string 'port=' --algo bm -j SET --add-set antizapret-torrent src --exist
iptables -w -D FORWARD -s $IP.28.0.0/16 -p udp -m string --string 'BitTorrent protocol' --algo kmp --to 100 -j SET --add-set antizapret-torrent src --exist
iptables -w -D FORWARD -s $IP.28.0.0/16 -p udp -m string --string 'd1:ad2:id20:' --algo kmp --to 100 -j SET --add-set antizapret-torrent src --exist
iptables -w -D FORWARD -s $IP.28.0.0/16 -m set --match-set antizapret-torrent src -j DROP
# Restrict forwarding
iptables -w -D FORWARD -s $IP.29.0.0/16 -m connmark --mark 0x1 -m set ! --match-set antizapret-forward dst -j DROP
# Client isolation
iptables -w -D FORWARD ! -i $OUT_INTERFACE -d $IP.28.0.0/15 -j DROP
iptables -w -D FORWARD -d $IP.28.0.0/15 -j ACCEPT
# Attack and scan protection
iptables -w -D INPUT -i $DEFAULT_INTERFACE -p icmp --icmp-type echo-request -j DROP
iptables -w -D INPUT -i $DEFAULT_INTERFACE -m set --match-set antizapret-allow src -j ACCEPT
iptables -w -D INPUT -i $DEFAULT_INTERFACE -m conntrack --ctstate NEW -m set ! --match-set antizapret-watch src,dst -m hashlimit --hashlimit-above 10/hour --hashlimit-burst 10 --hashlimit-mode srcip --hashlimit-name antizapret-scan --hashlimit-htable-expire 600000 -j SET --add-set antizapret-block src --exist
iptables -w -D INPUT -i $DEFAULT_INTERFACE -m conntrack --ctstate NEW -m hashlimit --hashlimit-above 100000/hour --hashlimit-burst 100000 --hashlimit-mode srcip --hashlimit-name antizapret-ddos --hashlimit-htable-expire 600000 -j SET --add-set antizapret-block src --exist
iptables -w -D INPUT -i $DEFAULT_INTERFACE -m conntrack --ctstate NEW -m set --match-set antizapret-block src -j DROP
iptables -w -D INPUT -i $DEFAULT_INTERFACE -m conntrack --ctstate NEW -j SET --add-set antizapret-watch src,dst --exist
iptables -w -D OUTPUT -o $DEFAULT_INTERFACE -p tcp --tcp-flags RST RST -j DROP
iptables -w -D OUTPUT -o $DEFAULT_INTERFACE -p icmp --icmp-type port-unreachable -j DROP
ip6tables -w -D INPUT -i $DEFAULT_INTERFACE -p icmpv6 --icmpv6-type echo-request -j DROP
ip6tables -w -D INPUT -i $DEFAULT_INTERFACE -m set --match-set antizapret-allow6 src -j ACCEPT
ip6tables -w -D INPUT -i $DEFAULT_INTERFACE -m conntrack --ctstate NEW -m set ! --match-set antizapret-watch6 src,dst -m hashlimit --hashlimit-above 10/hour --hashlimit-burst 10 --hashlimit-mode srcip --hashlimit-name antizapret-scan6 --hashlimit-htable-expire 600000 -j SET --add-set antizapret-block6 src --exist
ip6tables -w -D INPUT -i $DEFAULT_INTERFACE -m conntrack --ctstate NEW -m hashlimit --hashlimit-above 100000/hour --hashlimit-burst 100000 --hashlimit-mode srcip --hashlimit-name antizapret-ddos6 --hashlimit-htable-expire 600000 -j SET --add-set antizapret-block6 src --exist
ip6tables -w -D INPUT -i $DEFAULT_INTERFACE -m conntrack --ctstate NEW -m set --match-set antizapret-block6 src -j DROP
ip6tables -w -D INPUT -i $DEFAULT_INTERFACE -m conntrack --ctstate NEW -j SET --add-set antizapret-watch6 src,dst --exist
ip6tables -w -D OUTPUT -o $DEFAULT_INTERFACE -p tcp --tcp-flags RST RST -j DROP
ip6tables -w -D OUTPUT -o $DEFAULT_INTERFACE -p icmpv6 --icmpv6-type port-unreachable -j DROP
# SSH protection
iptables -w -D INPUT -p tcp --dport ssh -m conntrack --ctstate NEW -m hashlimit --hashlimit-above 3/hour --hashlimit-burst 3 --hashlimit-mode srcip --hashlimit-srcmask 24 --hashlimit-name antizapret-ssh --hashlimit-htable-expire 60000 -j DROP
ip6tables -w -D INPUT -p tcp --dport ssh -m conntrack --ctstate NEW -m hashlimit --hashlimit-above 3/hour --hashlimit-burst 3 --hashlimit-mode srcip --hashlimit-srcmask 64 --hashlimit-name antizapret-ssh6 --hashlimit-htable-expire 60000 -j DROP

# mangle
# Clamp TCP MSS
iptables -w -t mangle -D FORWARD -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu
ip6tables -w -t mangle -D FORWARD -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu

# raw
# NOTRACK loopback
iptables -w -t raw -D PREROUTING -i lo -j NOTRACK
iptables -w -t raw -D OUTPUT -o lo -j NOTRACK
ip6tables -w -t raw -D PREROUTING -i lo -j NOTRACK
ip6tables -w -t raw -D OUTPUT -o lo -j NOTRACK
# NOTRACK DNS
iptables -w -t raw -D PREROUTING ! -s $IP.28.0.0/15 -p udp --dport 53 -j NOTRACK
iptables -w -t raw -D PREROUTING ! -s $IP.28.0.0/15 -p tcp --dport 53 -j NOTRACK
iptables -w -t raw -D OUTPUT ! -d $IP.28.0.0/15 -p udp --sport 53 -j NOTRACK
iptables -w -t raw -D OUTPUT ! -d $IP.28.0.0/15 -p tcp --sport 53 -j NOTRACK

# nat
# OpenVPN TCP port redirection for backup connections
iptables -w -t nat -D PREROUTING -i $DEFAULT_INTERFACE -p tcp --dport 80 -j REDIRECT --to-ports 50080
iptables -w -t nat -D PREROUTING -i $DEFAULT_INTERFACE -p tcp --dport 443 -j REDIRECT --to-ports 50443
iptables -w -t nat -D PREROUTING -i $DEFAULT_INTERFACE -p tcp --dport 504 -j REDIRECT --to-ports 50443
iptables -w -t nat -D PREROUTING -i $DEFAULT_INTERFACE -p tcp --dport 508 -j REDIRECT --to-ports 50080
# OpenVPN UDP port redirection for backup connections
iptables -w -t nat -D PREROUTING -i $DEFAULT_INTERFACE -p udp --dport 80 -j REDIRECT --to-ports 50080
iptables -w -t nat -D PREROUTING -i $DEFAULT_INTERFACE -p udp --dport 443 -j REDIRECT --to-ports 50443
iptables -w -t nat -D PREROUTING -i $DEFAULT_INTERFACE -p udp --dport 504 -j REDIRECT --to-ports 50443
iptables -w -t nat -D PREROUTING -i $DEFAULT_INTERFACE -p udp --dport 508 -j REDIRECT --to-ports 50080
# AmneziaWG redirection ports to WireGuard
iptables -w -t nat -D PREROUTING -i $DEFAULT_INTERFACE -p udp --dport 52080 -j REDIRECT --to-ports 51080
iptables -w -t nat -D PREROUTING -i $DEFAULT_INTERFACE -p udp --dport 52443 -j REDIRECT --to-ports 51443
# VPN DNS redirection to Knot Resolver
iptables -w -t nat -D PREROUTING -s $IP.28.0.0/22 ! -d $IP.28.0.1/32 -p udp --dport 53 -j DNAT --to-destination $IP.28.0.1
iptables -w -t nat -D PREROUTING -s $IP.28.4.0/22 ! -d $IP.28.4.1/32 -p udp --dport 53 -j DNAT --to-destination $IP.28.4.1
iptables -w -t nat -D PREROUTING -s $IP.28.8.0/24 ! -d $IP.28.8.1/32 -p udp --dport 53 -j DNAT --to-destination $IP.28.8.1
iptables -w -t nat -D PREROUTING -s $IP.28.0.0/22 ! -d $IP.28.0.1/32 -p tcp --dport 53 -j DNAT --to-destination $IP.28.0.1
iptables -w -t nat -D PREROUTING -s $IP.28.4.0/22 ! -d $IP.28.4.1/32 -p tcp --dport 53 -j DNAT --to-destination $IP.28.4.1
iptables -w -t nat -D PREROUTING -s $IP.28.8.0/24 ! -d $IP.28.8.1/32 -p tcp --dport 53 -j DNAT --to-destination $IP.28.8.1
# AntiZapret DNS redirection to Knot Resolver
iptables -w -t nat -D PREROUTING -s $IP.29.0.0/22 ! -d $IP.29.0.1/32 -p udp --dport 53 -j DNAT --to-destination $IP.29.0.1
iptables -w -t nat -D PREROUTING -s $IP.29.4.0/22 ! -d $IP.29.4.1/32 -p udp --dport 53 -j DNAT --to-destination $IP.29.4.1
iptables -w -t nat -D PREROUTING -s $IP.29.8.0/24 ! -d $IP.29.8.1/32 -p udp --dport 53 -j DNAT --to-destination $IP.29.8.1
iptables -w -t nat -D PREROUTING -s $IP.29.0.0/22 ! -d $IP.29.0.1/32 -p tcp --dport 53 -j DNAT --to-destination $IP.29.0.1
iptables -w -t nat -D PREROUTING -s $IP.29.4.0/22 ! -d $IP.29.4.1/32 -p tcp --dport 53 -j DNAT --to-destination $IP.29.4.1
iptables -w -t nat -D PREROUTING -s $IP.29.8.0/24 ! -d $IP.29.8.1/32 -p tcp --dport 53 -j DNAT --to-destination $IP.29.8.1
# Restrict forwarding
iptables -w -t nat -D PREROUTING -s $IP.29.0.0/16 ! -d $FAKE_IP.0.0/15 -j CONNMARK --set-mark 0x1
# Mapping fake IP to real IP
iptables -w -t nat -D PREROUTING -s $IP.29.0.0/16 -d $FAKE_IP.0.0/15 -j ANTIZAPRET-MAPPING
# SNAT/MASQUERADE VPN
iptables -w -t nat -D POSTROUTING -s $IP.28.0.0/15 -o $OUT_INTERFACE -j MASQUERADE
iptables -w -t nat -D POSTROUTING -s $IP.28.0.0/15 -o $OUT_INTERFACE -j SNAT --to-source $OUT_IP

./custom-down.sh
exit 0