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

echo "Execution time: $SECONDS seconds"