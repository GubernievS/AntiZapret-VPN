#!/bin/bash

if [[ "$IV_PLAT" != 'linux' ]]; then
	echo 'push "ifconfig-ipv6 fdea:dead::2/64 fdea:dead::1"
push "route-ipv6 ::/3"
push "route-ipv6 2000::/4"
push "route-ipv6 3000::/4"
push "route-ipv6 fc00::/7"
push "block-ipv6"' >> "$1"
fi

exit 0