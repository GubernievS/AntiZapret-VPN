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

if [[ -v IV_PLAT && "$IV_PLAT" != "linux" ]]; then
	echo 'push "ifconfig-ipv6 fd00:dead::2 fd00:dead::1"' >> "$1"
	echo 'push "route-ipv6 2000::/3 fd00:dead::1"' >> "$1"
	echo 'push "block-ipv6"' >> "$1"
fi

exit 0