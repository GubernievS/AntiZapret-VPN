#!/bin/bash
set -e

SECONDS=0

HERE="$(dirname "$(readlink -f "${0}")")"
cd "$HERE"

cat update.sh | bash
./parse.sh
[[ -f "custom.sh" ]] && chmod +x custom.sh && ./custom.sh
find /etc/openvpn/server/logs -type f -size +10M -delete

echo "Execution time: $SECONDS seconds"