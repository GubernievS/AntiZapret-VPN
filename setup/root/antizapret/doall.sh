#!/bin/bash
set -e

handle_error() {
	echo ""
	echo -e "\e[1;31mError occurred at line $1 while executing: $2\e[0m"
	echo ""
	echo "$(lsb_release -d | awk -F'\t' '{print $2}') $(uname -r) $(date)"
	exit 1
}
trap 'handle_error $LINENO "$BASH_COMMAND"' ERR

SECONDS=0

HERE="$(dirname "$(readlink -f "${0}")")"
cd "$HERE"

cat update.sh | bash
./parse.sh
[[ -f "custom.sh" ]] && chmod +x custom.sh && ./custom.sh

echo "Execution time: $SECONDS seconds"