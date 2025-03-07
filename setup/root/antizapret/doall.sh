#!/bin/bash
set -e

SECONDS=0

HERE="$(dirname "$(readlink -f "${0}")")"
cd "$HERE"

SUM1=$(sha256sum update.sh)
cat update.sh | bash
SUM2=$(sha256sum update.sh)
if [[ "$SUM1" != "$SUM2" ]]; then
	echo "update.sh has been updated, restarting update.sh"
	cat update.sh | bash
fi
./parse.sh
find /etc/openvpn/server/logs -type f -size +10M -delete
[[ -f custom.sh ]] && mv -f custom.sh custom-doall.sh
./custom-doall.sh

###

set +e

if ! systemctl is-active --quiet kresd@2; then
    exit 0
fi

# Knot Resolver
KRESD_CONF="/etc/knot-resolver/kresd.conf"
[ -f "$KRESD_CONF" ] && {
	sed -i 's/ + MSK-IX//g' "$KRESD_CONF"
	sed -i 's/62.76.76.62/77.88.8.8@1253/g' "$KRESD_CONF"
	sed -i 's/62.76.62.76/77.88.8.1@1253/g' "$KRESD_CONF"
}

systemctl restart kresd@2

# WireGuard
for FILE in /etc/wireguard/templates/vpn-client*.conf; do
	[ -f "$FILE" ] && sed -i 's/, 62.76.76.62, 62.76.62.76//g' "$FILE"
done

# OpenVPN
for FILE in /etc/openvpn/server/vpn*.conf; do
	[ -f "$FILE" ] && {
		sed -i '/push "dhcp-option DNS 62.76.76.62"/d' "$FILE"
		sed -i '/push "dhcp-option DNS 62.76.62.76"/d' "$FILE"
	}
done

./root/antizapret/client.sh 7

###

echo "Execution time: $SECONDS seconds"