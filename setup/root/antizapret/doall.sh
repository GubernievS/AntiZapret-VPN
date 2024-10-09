#!/bin/bash

set -e

HERE="$(dirname "$(readlink -f "${0}")")"
cd "$HERE"

./update.sh
./parse.sh
./process.sh
