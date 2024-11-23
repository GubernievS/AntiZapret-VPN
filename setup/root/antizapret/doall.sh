#!/bin/bash
set -e

SECONDS=0

HERE="$(dirname "$(readlink -f "${0}")")"
cd "$HERE"

cat update.sh | bash
./parse.sh
[[ -f "custom.sh" ]] && chmod +x custom.sh && ./custom.sh

echo "Execution time: $SECONDS seconds"