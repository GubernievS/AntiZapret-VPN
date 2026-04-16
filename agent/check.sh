#!/usr/bin/env bash
# check.sh — quick health check for corpweb-sync-agent
#
# Prints:
#   1. Service status
#   2. Last 20 log lines
#   3. SHA-256 of key managed files
#   4. WireGuard active peer counts

set -euo pipefail

SERVICE="corpweb-sync-agent"

# ANSI helpers (disabled if not a terminal)
if [[ -t 1 ]]; then
  BOLD="\033[1m"
  RESET="\033[0m"
  GREEN="\033[32m"
  RED="\033[31m"
  YELLOW="\033[33m"
else
  BOLD="" RESET="" GREEN="" RED="" YELLOW=""
fi

banner() { echo -e "${BOLD}==> $*${RESET}"; }

# ---------------------------------------------------------------------------
# 1. Service status
# ---------------------------------------------------------------------------

banner "Service status: ${SERVICE}"
if systemctl is-active --quiet "${SERVICE}" 2>/dev/null; then
  echo -e "  ${GREEN}active (running)${RESET}"
else
  echo -e "  ${RED}NOT running${RESET}"
fi

systemctl status "${SERVICE}" --no-pager --lines=0 2>/dev/null || true

# ---------------------------------------------------------------------------
# 2. Last 20 log lines
# ---------------------------------------------------------------------------

echo ""
banner "Last 20 log lines"
journalctl -u "${SERVICE}" -n 20 --no-pager 2>/dev/null || \
  echo "  (journalctl not available or no logs yet)"

# ---------------------------------------------------------------------------
# 3. SHA-256 of key managed files
# ---------------------------------------------------------------------------

echo ""
banner "Managed file SHA-256 checksums"

KEY_FILES=(
  "/etc/wireguard/antizapret.conf"
  "/etc/wireguard/vpn.conf"
  "/root/antizapret/setup"
  "/root/antizapret/config/include-hosts.txt"
  "/root/antizapret/config/exclude-hosts.txt"
  "/root/antizapret/config/include-ips.txt"
  "/root/antizapret/config/exclude-ips.txt"
  "/root/antizapret/config/allow-ips.txt"
  "/root/antizapret/config/forward-ips.txt"
  "/root/antizapret/config/include-adblock-hosts.txt"
  "/root/antizapret/config/exclude-adblock-hosts.txt"
  "/root/antizapret/config/remove-hosts.txt"
)

printf "  %-60s %s\n" "FILE" "SHA-256 (first 16)"
printf "  %-60s %s\n" "----" "----------------"
for f in "${KEY_FILES[@]}"; do
  if [[ -f "$f" ]]; then
    sha=$(sha256sum "$f" | awk '{print $1}' | head -c 16)
    printf "  ${GREEN}%-60s${RESET} %s\n" "$f" "$sha"
  else
    printf "  ${YELLOW}%-60s${RESET} %s\n" "$f" "(missing)"
  fi
done

# ---------------------------------------------------------------------------
# 4. WireGuard active peer counts
# ---------------------------------------------------------------------------

echo ""
banner "WireGuard active peers (handshake < 3 minutes)"

_count_peers() {
  local iface="$1"
  if ! command -v wg &>/dev/null; then
    echo "wg not found"
    return
  fi
  if ! wg show "${iface}" &>/dev/null 2>&1; then
    echo "(interface ${iface} not up)"
    return
  fi
  local now
  now=$(date +%s)
  local count=0
  while IFS= read -r line; do
    ts=$(echo "$line" | awk '{print $2}')
    if [[ "$ts" =~ ^[0-9]+$ ]] && (( ts > 0 && now - ts < 180 )); then
      (( count++ )) || true
    fi
  done < <(wg show "${iface}" latest-handshakes 2>/dev/null)
  echo "$count"
}

az_peers=$(_count_peers antizapret)
vpn_peers=$(_count_peers vpn)

echo "  antizapret : ${az_peers} active peer(s)"
echo "  vpn        : ${vpn_peers} active peer(s)"

echo ""
echo -e "${BOLD}Health check complete.${RESET}"
