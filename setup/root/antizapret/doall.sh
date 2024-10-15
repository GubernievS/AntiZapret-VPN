#!/bin/bash

set -e

SECONDS=0

HERE="$(dirname "$(readlink -f "${0}")")"
cd "$HERE"

./update.sh
./parse.sh
./process.sh

echo "Execution time: $SECONDS seconds"