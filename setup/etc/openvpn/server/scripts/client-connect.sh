#!/bin/bash

if [[ ! -v duplicate_cn ]]; then
	for srv in antizapret-udp antizapret-tcp vpn-udp vpn-tcp; do
		[[ "$dev" == "$srv" ]] && continue
		lock="/dev/shm/${srv}.sock.lock"
		(
			flock -w 3 1000 || exit 0
			echo "kill $common_name" | timeout 3 socat - "UNIX-CONNECT:/run/openvpn-server/${srv}.sock" | sed "/^>/d; s/^/${srv} /" || true
		) 1000>>"$lock" &
	done
	wait
fi

if [[ "$IV_PLAT" != 'linux' ]]; then
	echo 'push "ifconfig-ipv6 fdea:dead::2/64 fdea:dead::1"
push "route-ipv6 ::/1"
push "route-ipv6 8000::/1"
push "route-ipv6 2000::/3"
push "block-ipv6"' >> "$1"
fi

exit 0