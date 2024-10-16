#!/bin/bash
set -e

SECONDS=0

HERE="$(dirname "$(readlink -f "${0}")")"
cd "$HERE"

cat ./update.sh | bash
./parse.sh

echo "Execution time: $SECONDS seconds"