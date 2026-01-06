#!/bin/bash

if [[ ! -v duplicate_cn ]]; then
	for srv in antizapret-udp antizapret-tcp vpn-udp vpn-tcp; do
		[[ "$dev" == "$srv" ]] && continue
		echo "kill $common_name" \
		| socat - "UNIX-CONNECT:/run/openvpn-server/${srv}.sock" \
		| tail -n +2 \
		| sed "s/^/$srv kill /" &
	done
fi

if [[ "$IV_PLAT" == "android" ]]; then
	[[ "$dev" == vpn* ]] && ipv4_flag="" || ipv4_flag=" !ipv4"
	echo "push \"ifconfig-ipv6 2001::dead\"
push \"redirect-gateway ipv6$ipv4_flag\"
push \"block-ipv6\"" >> "$1"
fi

exit 0