#!/bin/bash

if [[ "$IV_PLAT" != 'linux' ]]; then
	echo 'push "ifconfig-ipv6 fdea:dead::2/64 fdea:dead::1"
push "route-ipv6 ::/1"
push "route-ipv6 8000::/1"
push "route-ipv6 2000::/3"
push "block-ipv6"' >> "$1"
fi

exit 0