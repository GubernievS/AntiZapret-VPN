#!/bin/bash
set -e

SECONDS=0

[[ -d /etc/openvpn/server/logs ]] && find /etc/openvpn/server/logs -type f -size +100M -exec truncate -s 0 {} +
cd /root/antizapret
SUM1="$(sha256sum update.sh)"
cat update.sh | bash -s "$@"
SUM2="$(sha256sum update.sh)"
if [[ "$SUM1" != "$SUM2" ]]; then
	echo 'Restarting update.sh'
	cat update.sh | bash -s "$@"
fi
./parse.sh "$@"
./custom-doall.sh "$@" || true

echo "Execution time: $SECONDS seconds"

exit 0