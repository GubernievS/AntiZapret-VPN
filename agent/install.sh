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
