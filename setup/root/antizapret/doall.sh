#!/bin/bash
set -e

SECONDS=0

HERE="$(dirname "$(readlink -f "${0}")")"
cd "$HERE"

bash < ./update.sh
./parse.sh

echo "Execution time: $SECONDS seconds"