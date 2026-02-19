#!/bin/bash
set -e

cd /root/antizapret

./down.sh

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
if [[ "$WARP_OUTBOUND" == 'y' ]]; then
	set +e
	echo "Starting $WARP_INTERFACE..."
	PRIVATE_KEY=$(wg genkey)
	KEY=$(echo "$PRIVATE_KEY" | wg pubkey)

	REG=$(curl -sfL --connect-timeout 10 -X POST "https://api.cloudflareclient.com/v0i1909051800/reg" \
		-H 'Content-Type: application/json' \
		-d "{\"key\":\"$KEY\",\"warp_enabled\":true}")

	PUBLIC_KEY=$(echo "$REG" | jq -r '.result.config.peers[0].public_key')
	ENDPOINT=$(echo "$REG" | jq -r '.result.config.peers[0].endpoint.host')
	ADDRESS=$(echo "$REG" | jq -r '.result.config.interface.addresses.v4')

	echo "[Interface]
PrivateKey = $PRIVATE_KEY
Address = $ADDRESS
MTU = 1420
Table = 13335
PostUp = ip rule add from $IP.28.0.0/15 to $IP.28.0.0/15 lookup main priority 5000 || true
PostUp = ip rule add from $IP.28.0.0/15 to $FAKE_IP.0.0/15 lookup main priority 5000 || true
PostUp = ip rule add from $IP.28.0.0/15 lookup 13335 priority 10000 || true
PostDown = ip rule del from $IP.28.0.0/15 to $IP.28.0.0/15 priority 5000
PostDown = ip rule del from $IP.28.0.0/15 to $FAKE_IP.0.0/15 priority 5000
PostDown = ip rule del from $IP.28.0.0/15 lookup 13335 priority 10000

[Peer]
PublicKey = $PUBLIC_KEY
AllowedIPs = 0.0.0.0/0
Endpoint = $ENDPOINT" > $WARP_PATH

	wg-quick up $WARP_PATH

	if [[ $? -eq 0 ]]; then
		echo "Started $WARP_INTERFACE: $ENDPOINT connected"
		OUT_INTERFACE="$WARP_INTERFACE"
		OUT_IP="$ADDRESS"	
	else
		echo "Starting $WARP_INTERFACE failed! Use $OUT_INTERFACE"
	fi
	set -e
else
	rm -f $WARP_PATH
fi

# SoftIRQ CPU balance
printf '%x' $(( (1 << $(nproc)) - 1 )) | tee /sys/class/net/$DEFAULT_INTERFACE/queues/rx-*/rps_cpus >/dev/null

# Clear knot-resolver cache
count="$(echo 'cache.clear()' | socat - /run/knot-resolver/control/1 | grep -oE '[0-9]+' || echo 0)"
echo "DNS cache cleared: $count entries"

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
# Torrent guard
if [[ "$TORRENT_GUARD" == 'y' ]]; then
	ipset create antizapret-torrent hash:ip timeout 60 -exist
	iptables -w -I FORWARD 2 -s $IP.28.0.0/16 -p tcp -m string --string 'GET ' --algo kmp --to 100 -m string --string 'info_hash=' --algo bm -m string --string 'peer_id=' --algo bm -m string --string 'port=' --algo bm -j SET --add-set antizapret-torrent src --exist
	iptables -w -I FORWARD 3 -s $IP.28.0.0/16 -p udp -m string --string 'BitTorrent protocol' --algo kmp --to 100 -j SET --add-set antizapret-torrent src --exist
	iptables -w -I FORWARD 4 -s $IP.28.0.0/16 -p udp -m string --string 'd1:ad2:id20:' --algo kmp --to 100 -j SET --add-set antizapret-torrent src --exist
	iptables -w -I FORWARD 5 -s $IP.28.0.0/16 -m set --match-set antizapret-torrent src -j DROP
fi
# Restrict forwarding
if [[ "$RESTRICT_FORWARD" == 'y' ]]; then
	{
		echo 'create antizapret-forward hash:net -exist'
		echo 'flush antizapret-forward'
		if [[ -f result/forward-ips.txt ]]; then
			while read -r line; do
				echo "add antizapret-forward $line"
			done < result/forward-ips.txt
		fi
	} | ipset restore
	iptables -w -I FORWARD 2 -s $IP.29.0.0/16 -m connmark --mark 0x1 -m set ! --match-set antizapret-forward dst -j DROP
fi
# Client isolation
if [[ "$CLIENT_ISOLATION" == 'y' ]]; then
	iptables -w -I FORWARD 2 ! -i $OUT_INTERFACE -d $IP.28.0.0/15 -j DROP
else
	iptables -w -I FORWARD 2 -d $IP.28.0.0/15 -j ACCEPT
fi
# Attack and scan protection
if [[ "$ATTACK_PROTECTION" == 'y' ]]; then
	{
		echo 'create antizapret-allow hash:net -exist'
		echo 'flush antizapret-allow'
		if [[ -f result/allow-ips.txt ]]; then
			while read -r line; do
				echo "add antizapret-allow $line"
			done < result/allow-ips.txt
		fi
	} | ipset restore
	ipset create antizapret-block hash:ip timeout 600 -exist
	ipset create antizapret-watch hash:ip,port timeout 600 -exist
	iptables -w -I INPUT 2 -i $DEFAULT_INTERFACE -p icmp --icmp-type echo-request -j DROP
	iptables -w -I INPUT 3 -i $DEFAULT_INTERFACE -m set --match-set antizapret-allow src -j ACCEPT
	iptables -w -I INPUT 4 -i $DEFAULT_INTERFACE -m conntrack --ctstate NEW -m set ! --match-set antizapret-watch src,dst -m hashlimit --hashlimit-above 10/hour --hashlimit-burst 10 --hashlimit-mode srcip --hashlimit-name antizapret-scan --hashlimit-htable-expire 600000 -j SET --add-set antizapret-block src --exist
	iptables -w -I INPUT 5 -i $DEFAULT_INTERFACE -m conntrack --ctstate NEW -m hashlimit --hashlimit-above 100000/hour --hashlimit-burst 100000 --hashlimit-mode srcip --hashlimit-name antizapret-ddos --hashlimit-htable-expire 600000 -j SET --add-set antizapret-block src --exist
	iptables -w -I INPUT 6 -i $DEFAULT_INTERFACE -m conntrack --ctstate NEW -m set --match-set antizapret-block src -j DROP
	iptables -w -I INPUT 7 -i $DEFAULT_INTERFACE -m conntrack --ctstate NEW -j SET --add-set antizapret-watch src,dst --exist
	iptables -w -I OUTPUT 2 -o $DEFAULT_INTERFACE -p tcp --tcp-flags RST RST -j DROP
	iptables -w -I OUTPUT 3 -o $DEFAULT_INTERFACE -p icmp --icmp-type port-unreachable -j DROP
	ipset create antizapret-allow6 hash:net family inet6 -exist
	ipset create antizapret-block6 hash:ip timeout 600 family inet6 -exist
	ipset create antizapret-watch6 hash:ip,port timeout 600 family inet6 -exist
	ip6tables -w -I INPUT 2 -i $DEFAULT_INTERFACE -p icmpv6 --icmpv6-type echo-request -j DROP
	ip6tables -w -I INPUT 3 -i $DEFAULT_INTERFACE -m set --match-set antizapret-allow6 src -j ACCEPT
	ip6tables -w -I INPUT 4 -i $DEFAULT_INTERFACE -m conntrack --ctstate NEW -m set ! --match-set antizapret-watch6 src,dst -m hashlimit --hashlimit-above 10/hour --hashlimit-burst 10 --hashlimit-mode srcip --hashlimit-name antizapret-scan6 --hashlimit-htable-expire 600000 -j SET --add-set antizapret-block6 src --exist
	ip6tables -w -I INPUT 5 -i $DEFAULT_INTERFACE -m conntrack --ctstate NEW -m hashlimit --hashlimit-above 100000/hour --hashlimit-burst 100000 --hashlimit-mode srcip --hashlimit-name antizapret-ddos6 --hashlimit-htable-expire 600000 -j SET --add-set antizapret-block6 src --exist
	ip6tables -w -I INPUT 6 -i $DEFAULT_INTERFACE -m conntrack --ctstate NEW -m set --match-set antizapret-block6 src -j DROP
	ip6tables -w -I INPUT 7 -i $DEFAULT_INTERFACE -m conntrack --ctstate NEW -j SET --add-set antizapret-watch6 src,dst --exist
	ip6tables -w -I OUTPUT 2 -o $DEFAULT_INTERFACE -p tcp --tcp-flags RST RST -j DROP
	ip6tables -w -I OUTPUT 3 -o $DEFAULT_INTERFACE -p icmpv6 --icmpv6-type port-unreachable -j DROP
fi
# SSH protection
if [[ "$SSH_PROTECTION" == 'y' ]]; then
	iptables -w -I INPUT 2 -p tcp --dport ssh -m conntrack --ctstate NEW -m hashlimit --hashlimit-above 5/hour --hashlimit-burst 5 --hashlimit-mode srcip --hashlimit-srcmask 24 --hashlimit-name antizapret-ssh --hashlimit-htable-expire 60000 -j DROP
	ip6tables -w -I INPUT 2 -p tcp --dport ssh -m conntrack --ctstate NEW -m hashlimit --hashlimit-above 5/hour --hashlimit-burst 5 --hashlimit-mode srcip --hashlimit-srcmask 64 --hashlimit-name antizapret-ssh6 --hashlimit-htable-expire 60000 -j DROP
fi

# mangle
# Clamp TCP MSS
iptables -w -t mangle -A FORWARD -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu
ip6tables -w -t mangle -A FORWARD -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu

# raw
# NOTRACK loopback
iptables -w -t raw -A PREROUTING -i lo -j NOTRACK
iptables -w -t raw -A OUTPUT -o lo -j NOTRACK
ip6tables -w -t raw -A PREROUTING -i lo -j NOTRACK
ip6tables -w -t raw -A OUTPUT -o lo -j NOTRACK

# nat
# OpenVPN TCP port redirection for backup connections
if [[ "$OPENVPN_BACKUP_TCP" == 'y' ]]; then
	iptables -w -t nat -A PREROUTING -i $DEFAULT_INTERFACE -p tcp --dport 80 -j REDIRECT --to-ports 50080
	iptables -w -t nat -A PREROUTING -i $DEFAULT_INTERFACE -p tcp --dport 443 -j REDIRECT --to-ports 50443
	iptables -w -t nat -A PREROUTING -i $DEFAULT_INTERFACE -p tcp --dport 504 -j REDIRECT --to-ports 50443
	iptables -w -t nat -A PREROUTING -i $DEFAULT_INTERFACE -p tcp --dport 508 -j REDIRECT --to-ports 50080
fi
# OpenVPN UDP port redirection for backup connections
if [[ "$OPENVPN_BACKUP_UDP" == 'y' ]]; then
	iptables -w -t nat -A PREROUTING -i $DEFAULT_INTERFACE -p udp --dport 80 -j REDIRECT --to-ports 50080
	iptables -w -t nat -A PREROUTING -i $DEFAULT_INTERFACE -p udp --dport 443 -j REDIRECT --to-ports 50443
	iptables -w -t nat -A PREROUTING -i $DEFAULT_INTERFACE -p udp --dport 504 -j REDIRECT --to-ports 50443
	iptables -w -t nat -A PREROUTING -i $DEFAULT_INTERFACE -p udp --dport 508 -j REDIRECT --to-ports 50080
fi
# WireGuard/AmneziaWG port redirection for backup connections
if [[ "$WIREGUARD_BACKUP" == 'y' ]]; then
	iptables -w -t nat -A PREROUTING -i $DEFAULT_INTERFACE -p udp --dport 540 -j REDIRECT --to-ports 51443
	iptables -w -t nat -A PREROUTING -i $DEFAULT_INTERFACE -p udp --dport 580 -j REDIRECT --to-ports 51080
fi
# AmneziaWG redirection ports to WireGuard
iptables -w -t nat -A PREROUTING -i $DEFAULT_INTERFACE -p udp --dport 52080 -j REDIRECT --to-ports 51080
iptables -w -t nat -A PREROUTING -i $DEFAULT_INTERFACE -p udp --dport 52443 -j REDIRECT --to-ports 51443
# AntiZapret DNS redirection to Knot Resolver
iptables -w -t nat -A PREROUTING -s $IP.29.0.0/16 -p udp --dport 53 -j DNAT --to-destination 127.0.0.1
iptables -w -t nat -A PREROUTING -s $IP.29.0.0/16 -p tcp --dport 53 -j DNAT --to-destination 127.0.0.1
# VPN DNS redirection to Knot Resolver
if [[ "$VPN_DNS" == '1' ]]; then
	iptables -w -t nat -A PREROUTING -s $IP.28.0.0/16 -p udp --dport 53 -j DNAT --to-destination 127.0.0.2
	iptables -w -t nat -A PREROUTING -s $IP.28.0.0/16 -p tcp --dport 53 -j DNAT --to-destination 127.0.0.2
fi
# Restrict forwarding
if [[ "$RESTRICT_FORWARD" == 'y' ]]; then
	iptables -w -t nat -A PREROUTING -s $IP.29.0.0/16 ! -d $FAKE_IP.0.0/15 -j CONNMARK --set-mark 0x1
fi
# Mapping fake IP to real IP
iptables -w -t nat -S ANTIZAPRET-MAPPING &>/dev/null || iptables -w -t nat -N ANTIZAPRET-MAPPING
iptables -w -t nat -A PREROUTING -s $IP.29.0.0/16 -d $FAKE_IP.0.0/15 -j ANTIZAPRET-MAPPING
# SNAT/MASQUERADE VPN
if [[ -z "$OUT_IP" ]]; then
	iptables -w -t nat -A POSTROUTING -s $IP.28.0.0/15 -o $OUT_INTERFACE -j MASQUERADE
else
	iptables -w -t nat -A POSTROUTING -s $IP.28.0.0/15 -o $OUT_INTERFACE -j SNAT --to-source $OUT_IP
fi

./custom-up.sh
exit 0