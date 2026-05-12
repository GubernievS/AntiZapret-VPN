#!/bin/bash

if [[ ! -v duplicate_cn ]]; then
	for srv in antizapret-udp antizapret-tcp vpn-udp vpn-tcp; do
		[[ "$dev" == "$srv" ]] && continue
		lock=/dev/shm/${srv}.sock.lock
		echo "kill $common_name" | timeout -k 1 1 socat -W "$lock" - "UNIX-CONNECT:/run/openvpn-server/${srv}.sock" | sed "/^>/d; s/^/${srv} /" || true
		rm -f "$lock"
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