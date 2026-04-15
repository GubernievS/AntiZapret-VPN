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

if [[ "$IV_PLAT" != 'linux' ]]; then
	echo 'push "ifconfig-ipv6 fdea:dead::2/64 fdea:dead::1"
push "route-ipv6 ::/1"
push "route-ipv6 8000::/1"
push "route-ipv6 2000::/3"
push "block-ipv6"' >> "$1"
fi

exit 0