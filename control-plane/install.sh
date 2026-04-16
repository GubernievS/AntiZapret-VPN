#!/usr/bin/env bash
# CorpAdmin-AZ Control-Plane Installer
# Supports Native (systemd) and Docker deployment modes.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BACKEND_DIR="$REPO_ROOT/corpweb/backend"
CONTROL_PLANE_DIR="$REPO_ROOT/control-plane"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

info()  { echo -e "${GREEN}[INFO]${NC}  $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }

require_root() {
    if [[ $EUID -ne 0 ]]; then
        error "This installer must be run as root (sudo $0)"
        exit 1
    fi
}

ask() {
    local prompt="$1" var="$2" default="${3:-}"
    local answer
    if [[ -n "$default" ]]; then
        read -rp "$prompt [$default]: " answer
        echo "${answer:-$default}"
    else
        read -rp "$prompt: " answer
        echo "$answer"
    fi
}

ask_secret() {
    local prompt="$1"
    local answer
    read -rsp "$prompt: " answer
    echo
    echo "$answer"
}

generate_secret() {
    python3 -c "import secrets; print(secrets.token_hex(32))"
}

# ---------------------------------------------------------------------------
# Interactive prompts
# ---------------------------------------------------------------------------
require_root

echo ""
echo "========================================"
echo "  CorpAdmin-AZ Control-Plane Installer"
echo "========================================"
echo ""
echo "Select deployment mode:"
echo "  1) Native  — PostgreSQL + nginx + systemd (production)"
echo "  2) Docker  — docker compose (development / quick start)"
echo ""

MODE=""
while [[ "$MODE" != "1" && "$MODE" != "2" ]]; do
    MODE=$(ask "Enter mode" MODE "1")
done

DOMAIN=$(ask "Panel domain (e.g. panel.example.com)" DOMAIN "")
if [[ -z "$DOMAIN" ]]; then
    error "Domain is required."
    exit 1
fi

DB_PASSWORD=$(ask_secret "PostgreSQL password for 'corpweb' user (leave blank to generate)")
if [[ -z "$DB_PASSWORD" ]]; then
    DB_PASSWORD=$(generate_secret)
    info "Generated DB password: $DB_PASSWORD"
    warn "Save this password — it will NOT be shown again."
fi

SECRET_KEY=$(generate_secret)
info "Generated Django/app SECRET_KEY."

ENV_FILE="$CONTROL_PLANE_DIR/.env"
cat > "$ENV_FILE" <<EOF
DB_PASSWORD=$DB_PASSWORD
SECRET_KEY=$SECRET_KEY
DOMAIN=$DOMAIN
EOF
chmod 600 "$ENV_FILE"
info "Credentials written to $ENV_FILE"

# ---------------------------------------------------------------------------
# Shared: run migrations + bootstrap
# ---------------------------------------------------------------------------
run_migrations_and_bootstrap() {
    local db_url="$1"
    info "Running Alembic migrations..."
    (
        cd "$BACKEND_DIR"
        DATABASE_URL="$db_url" alembic upgrade head
    )
    info "Bootstrapping vpn_manager..."
    (
        cd "$BACKEND_DIR"
        DATABASE_URL="$db_url" python3 -m app.bootstrap
    )
}

# ===========================================================================
# MODE 1: NATIVE
# ===========================================================================
if [[ "$MODE" == "1" ]]; then
    info "=== Native mode ==="

    # --- Dependencies ---
    info "Installing system packages..."
    apt-get update -qq
    apt-get install -y --no-install-recommends \
        postgresql postgresql-client \
        nginx \
        python3 python3-pip python3-venv \
        certbot python3-certbot-nginx \
        curl

    # --- PostgreSQL ---
    info "Setting up PostgreSQL database..."
    systemctl enable --now postgresql

    # Create role + database (idempotent)
    su -c "psql -tc \"SELECT 1 FROM pg_roles WHERE rolname='corpweb'\" | grep -q 1 || \
           psql -c \"CREATE ROLE corpweb WITH LOGIN PASSWORD '$DB_PASSWORD'\"" postgres
    su -c "psql -tc \"SELECT 1 FROM pg_database WHERE datname='corpweb'\" | grep -q 1 || \
           psql -c \"CREATE DATABASE corpweb OWNER corpweb\"" postgres

    DB_URL="postgresql://corpweb:${DB_PASSWORD}@localhost:5432/corpweb"

    # --- Python venv + app deps ---
    info "Installing Python dependencies..."
    VENV="/opt/corpweb/venv"
    mkdir -p /opt/corpweb
    python3 -m venv "$VENV"
    "$VENV/bin/pip" install --quiet --upgrade pip
    "$VENV/bin/pip" install --quiet -r "$BACKEND_DIR/requirements.txt"

    # --- App environment file for systemd ---
    APP_ENV="/opt/corpweb/app.env"
    cat > "$APP_ENV" <<APPENV
DATABASE_URL=$DB_URL
SECRET_KEY=$SECRET_KEY
APPENV
    chmod 600 "$APP_ENV"

    # --- systemd service ---
    info "Installing systemd service..."
    cat > /etc/systemd/system/corpweb.service <<UNIT
[Unit]
Description=CorpAdmin-AZ backend
After=network.target postgresql.service
Requires=postgresql.service

[Service]
Type=simple
WorkingDirectory=$BACKEND_DIR
EnvironmentFile=$APP_ENV
ExecStart=$VENV/bin/uvicorn app.main:app --host 127.0.0.1 --port 8000
Restart=on-failure
RestartSec=5
User=www-data
Group=www-data

[Install]
WantedBy=multi-user.target
UNIT

    systemctl daemon-reload
    systemctl enable corpweb

    # --- nginx ---
    info "Installing nginx configuration..."
    SSL_DIR="/etc/nginx/ssl"
    mkdir -p "$SSL_DIR"

    cp "$CONTROL_PLANE_DIR/nginx.conf" /etc/nginx/nginx.conf
    # Replace placeholder domain in server_name (optional; the conf uses _ wildcard)
    nginx -t
    systemctl enable --now nginx

    # --- TLS via certbot ---
    info "Obtaining TLS certificate for $DOMAIN via certbot --nginx..."
    certbot --nginx -d "$DOMAIN" --non-interactive --agree-tos \
        --register-unsafely-without-email || \
        warn "certbot failed — configure TLS manually before production use."

    # --- Migrations + bootstrap ---
    PATH="$VENV/bin:$PATH"
    run_migrations_and_bootstrap "$DB_URL"

    # --- Start backend ---
    systemctl start corpweb
    info "Native installation complete. Backend: http://127.0.0.1:8000  Panel: https://$DOMAIN"

# ===========================================================================
# MODE 2: DOCKER
# ===========================================================================
elif [[ "$MODE" == "2" ]]; then
    info "=== Docker mode ==="

    # --- Docker ---
    if ! command -v docker &>/dev/null; then
        info "Installing docker.io..."
        apt-get update -qq
        apt-get install -y --no-install-recommends docker.io docker-compose-v2 curl
        systemctl enable --now docker
    else
        info "Docker already installed: $(docker --version)"
    fi

    # --- certbot standalone for TLS ---
    if ! command -v certbot &>/dev/null; then
        apt-get install -y --no-install-recommends certbot
    fi
    info "Obtaining TLS certificate for $DOMAIN via certbot standalone..."
    certbot certonly --standalone -d "$DOMAIN" --non-interactive --agree-tos \
        --register-unsafely-without-email || \
        warn "certbot failed — configure TLS manually before production use."

    # Symlink certs where nginx.conf expects them
    SSL_DIR="/etc/nginx/ssl"
    mkdir -p "$SSL_DIR"
    CERT_PATH="/etc/letsencrypt/live/$DOMAIN"
    if [[ -d "$CERT_PATH" ]]; then
        ln -sf "$CERT_PATH/fullchain.pem" "$SSL_DIR/panel.crt"
        ln -sf "$CERT_PATH/privkey.pem"   "$SSL_DIR/panel.key"
    fi

    # --- Copy env for compose ---
    cp "$ENV_FILE" "$CONTROL_PLANE_DIR/.env"

    # --- Start containers ---
    info "Starting Docker Compose stack..."
    docker compose -f "$CONTROL_PLANE_DIR/docker-compose.yml" up -d --build

    # Wait for backend to be healthy
    info "Waiting for backend to become ready..."
    for i in $(seq 1 30); do
        if docker compose -f "$CONTROL_PLANE_DIR/docker-compose.yml" \
               exec -T backend curl -sf http://127.0.0.1:8000/health &>/dev/null; then
            break
        fi
        sleep 2
    done

    # --- Migrations + bootstrap inside container ---
    info "Running Alembic migrations inside container..."
    docker compose -f "$CONTROL_PLANE_DIR/docker-compose.yml" \
        exec -T backend alembic upgrade head
    info "Bootstrapping vpn_manager inside container..."
    docker compose -f "$CONTROL_PLANE_DIR/docker-compose.yml" \
        exec -T backend python3 -m app.bootstrap

    info "Docker installation complete. Panel: https://$DOMAIN"
fi

echo ""
echo -e "${GREEN}========================================"
echo "  Installation finished successfully!"
echo -e "========================================${NC}"
echo ""
echo "  Panel URL : https://$DOMAIN"
echo "  Env file  : $ENV_FILE"
echo ""
echo "  Next steps:"
echo "    1. Edit control-plane/nginx.conf — replace NODE_A_IP with real node IPs"
echo "    2. Run: nginx -s reload"
echo "    3. Add VPN nodes via the admin panel"
echo ""
