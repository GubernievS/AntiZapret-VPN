#!/bin/bash
set -e

SECONDS=0

cd /root/antizapret

SUM1="$(sha256sum update.sh)"
cat update.sh | bash -s "$1"
SUM2="$(sha256sum update.sh)"
if [[ "$SUM1" != "$SUM2" ]]; then
	echo 'update.sh has been updated, restarting update.sh'
	cat update.sh | bash -s "$1"
fi
./parse.sh "$1"
find /etc/openvpn/server/logs -type f -size +10M -delete
./custom-doall.sh "$1"

echo "Execution time: $SECONDS seconds"
exit 0