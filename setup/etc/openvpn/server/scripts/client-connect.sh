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

if [[ "$dev" == antizapret* && -v IV_PLAT && "$IV_PLAT" != "linux" ]]; then
	echo "push \"ifconfig-ipv6 dead::bad\"
push \"redirect-gateway ipv6 !ipv4\"
push \"block-ipv6\"" >> "$1"
fi

exit 0