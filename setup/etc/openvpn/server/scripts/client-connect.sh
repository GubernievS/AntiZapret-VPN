#!/bin/bash

if [[ "$IV_PLAT" != 'linux' ]]; then
	echo 'push "ifconfig-ipv6 fdea:dead::2/64 fdea:dead::1"
push "redirect-gateway ipv6 !ipv4"
push "block-ipv6"' >> "$1"
fi

exit 0