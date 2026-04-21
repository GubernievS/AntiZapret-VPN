#!/usr/bin/env bash
# install.sh — onboarding script for corpweb-sync-agent
#
# Required environment variables (set before running):
#   CORPWEB_CP_URL   — control-plane base URL, e.g. https://panel.example.com
#   CORPWEB_TOKEN    — bearer token for this node
#
# Optional:
#   CORPWEB_HOSTNAME — override reported hostname (defaults to $(hostname -f))

set -euo pipefail

AGENT_SCRIPT_SRC="$(cd "$(dirname "$0")" && pwd)/corpweb_sync_agent.py"
AGENT_PY_DEST="/usr/local/bin/corpweb-sync-agent.py"
AGENT_WRAPPER="/usr/local/bin/corpweb-sync-agent"
ENV_FILE="/etc/corpweb-sync-agent.env"
SERVICE_NAME="corpweb-sync-agent"
SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}.service"
SERVICE_SRC="$(cd "$(dirname "$0")" && pwd)/corpweb-sync-agent.service"

# ---------------------------------------------------------------------------
# Checks
# ---------------------------------------------------------------------------

if [[ $EUID -ne 0 ]]; then
  echo "ERROR: This script must be run as root (sudo install.sh)" >&2
  exit 1
fi

if [[ -z "${CORPWEB_CP_URL:-}" ]]; then
  echo "ERROR: CORPWEB_CP_URL is not set" >&2
  exit 1
fi

if [[ -z "${CORPWEB_TOKEN:-}" ]]; then
  echo "ERROR: CORPWEB_TOKEN is not set" >&2
  exit 1
fi

CORPWEB_HOSTNAME="${CORPWEB_HOSTNAME:-$(hostname -f)}"

# ---------------------------------------------------------------------------
# Helper: install amneziawg (idempotent)
# ---------------------------------------------------------------------------

install_amneziawg() {
    if command -v awg >/dev/null 2>&1; then
        echo "[agent] amneziawg already installed — skipping"
        return 0
    fi

    echo "[agent] installing amneziawg…"
    install -d /etc/apt/keyrings
    apt-get update -qq

    # Primary path: amnezia official apt repo
    if curl -fsSL --max-time 10 https://apt.amnezia.org/amnezia-archive-keyring.gpg \
          -o /etc/apt/keyrings/amnezia-archive-keyring.gpg 2>/dev/null; then
        local codename
        codename=$(lsb_release -cs 2>/dev/null || awk -F= '/^VERSION_CODENAME=/ {print $2}' /etc/os-release)
        echo "deb [signed-by=/etc/apt/keyrings/amnezia-archive-keyring.gpg] https://apt.amnezia.org/ ${codename} main" \
            > /etc/apt/sources.list.d/amnezia.list
        apt-get update -qq
        if apt-get install -y amneziawg amneziawg-tools; then
            echo "[agent] amneziawg installed via apt"
            return 0
        fi
        echo "[agent] apt install failed — falling back to GitHub releases"
    else
        echo "[agent] amnezia apt repo unreachable — using GitHub releases"
    fi

    # Fallback: download .deb artefacts from GitHub releases
    local tmpdir
    tmpdir=$(mktemp -d)
    local arch
    arch=$(dpkg --print-architecture)

    curl -fsSL "https://api.github.com/repos/amnezia-vpn/amneziawg-linux-kernel-module/releases/latest" \
        | grep -oE 'https://[^"]+amneziawg-dkms[^"]+\.deb' | head -1 \
        | xargs -r curl -fsSL -o "$tmpdir/amneziawg-dkms.deb"
    curl -fsSL "https://api.github.com/repos/amnezia-vpn/amneziawg-tools/releases/latest" \
        | grep -oE "https://[^\"]+amneziawg-tools[^\"]+${arch}\\.deb" | head -1 \
        | xargs -r curl -fsSL -o "$tmpdir/amneziawg-tools.deb"

    if [[ -s "$tmpdir/amneziawg-dkms.deb" && -s "$tmpdir/amneziawg-tools.deb" ]]; then
        apt-get install -y dkms linux-headers-"$(uname -r)" || true
        dpkg -i "$tmpdir/amneziawg-dkms.deb" "$tmpdir/amneziawg-tools.deb" || apt-get install -f -y
        rm -rf "$tmpdir"
        if command -v awg >/dev/null 2>&1; then
            echo "[agent] amneziawg installed via GitHub .deb"
            return 0
        fi
    fi

    rm -rf "$tmpdir"
    echo "[agent] ERROR: could not install amneziawg automatically." >&2
    echo "[agent] Install it manually, then re-run this script." >&2
    return 1
}

# ---------------------------------------------------------------------------
# Step 0: Install amneziawg kernel module + userspace tools
# ---------------------------------------------------------------------------

install_amneziawg

# ---------------------------------------------------------------------------
# Step 1: Install requests via pip if missing
# ---------------------------------------------------------------------------

echo "==> Checking Python requests library..."
if ! python3 -c "import requests" 2>/dev/null; then
  echo "    requests not found — installing via pip..."
  pip3 install --quiet requests
else
  echo "    requests already installed"
fi

# ---------------------------------------------------------------------------
# Step 2: Copy agent script to /usr/local/bin/
# ---------------------------------------------------------------------------

echo "==> Installing agent script to ${AGENT_PY_DEST}..."
install -m 0755 "${AGENT_SCRIPT_SRC}" "${AGENT_PY_DEST}"

# ---------------------------------------------------------------------------
# Step 3: Create wrapper script
# ---------------------------------------------------------------------------

echo "==> Creating wrapper at ${AGENT_WRAPPER}..."
cat > "${AGENT_WRAPPER}" <<'WRAPPER'
#!/usr/bin/env bash
exec python3 /usr/local/bin/corpweb-sync-agent.py "$@"
WRAPPER
chmod 0755 "${AGENT_WRAPPER}"

# ---------------------------------------------------------------------------
# Step 4: Write env file (chmod 600 — contains secret token)
# ---------------------------------------------------------------------------

echo "==> Writing ${ENV_FILE}..."
cat > "${ENV_FILE}" <<EOF
CONTROL_PLANE_URL=${CORPWEB_CP_URL}
AGENT_TOKEN=${CORPWEB_TOKEN}
AGENT_HOSTNAME=${CORPWEB_HOSTNAME}
EOF
chmod 0600 "${ENV_FILE}"
echo "    Env file written (mode 600)"

# ---------------------------------------------------------------------------
# Step 5: Install systemd service unit
# ---------------------------------------------------------------------------

echo "==> Installing systemd service ${SERVICE_FILE}..."
install -m 0644 "${SERVICE_SRC}" "${SERVICE_FILE}"
systemctl daemon-reload

# ---------------------------------------------------------------------------
# Step 6: Enable and start the service
# ---------------------------------------------------------------------------

echo "==> Enabling and starting ${SERVICE_NAME}..."
systemctl enable --now "${SERVICE_NAME}"

echo ""
echo "Installation complete."
echo "  Status:  systemctl status ${SERVICE_NAME}"
echo "  Logs:    journalctl -u ${SERVICE_NAME} -f"
echo "  Health:  $(dirname "$0")/check.sh"
