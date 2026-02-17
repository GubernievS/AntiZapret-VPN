#!/bin/bash

#
# Native Installation Script for CorpWeb
# Installs backend + frontend on the server with systemd, Nginx, Certbot
#

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
print_success() { echo -e "${GREEN}[OK]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[WARN]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1"; }

INSTALL_DIR="/opt/corpweb"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "========================================="
echo "  CorpWeb — Native Installation"
echo "========================================="
echo ""

# ── Check root ──
if [[ $EUID -ne 0 ]]; then
   print_error "Этот скрипт должен запускаться с правами root"
   exit 1
fi

# ── Check OS ──
print_info "Проверка операционной системы..."
if [[ -f /etc/os-release ]]; then
    . /etc/os-release
    if [[ "$ID" != "ubuntu" && "$ID" != "debian" ]]; then
        print_error "Поддерживаются только Ubuntu 22.04+ и Debian 11+"
        exit 1
    fi
    print_success "ОС: $PRETTY_NAME"
else
    print_error "Не удалось определить ОС"
    exit 1
fi

# ── Install system dependencies ──
print_info "Обновление пакетов и установка зависимостей..."
apt-get update -qq

# PostgreSQL
if ! command -v psql &> /dev/null; then
    print_info "Установка PostgreSQL..."
    apt-get install -y -qq postgresql postgresql-contrib > /dev/null
    systemctl enable postgresql
    systemctl start postgresql
    print_success "PostgreSQL установлен"
else
    print_success "PostgreSQL уже установлен"
fi

# Python 3.11+
if ! command -v python3.11 &> /dev/null && ! python3 --version 2>/dev/null | grep -qE "3\.(1[1-9]|[2-9][0-9])"; then
    print_info "Установка Python 3.11..."
    apt-get install -y -qq software-properties-common > /dev/null
    add-apt-repository -y ppa:deadsnakes/ppa > /dev/null 2>&1 || true
    apt-get update -qq
    apt-get install -y -qq python3.11 python3.11-venv python3.11-dev > /dev/null
    PYTHON_BIN="python3.11"
    print_success "Python 3.11 установлен"
else
    PYTHON_BIN="$(command -v python3.11 || command -v python3)"
    print_success "Python: $($PYTHON_BIN --version)"
fi

# Node.js 20+
if ! command -v node &> /dev/null; then
    print_info "Установка Node.js 20..."
    curl -fsSL https://deb.nodesource.com/setup_20.x | bash - > /dev/null 2>&1
    apt-get install -y -qq nodejs > /dev/null
    print_success "Node.js $(node --version) установлен"
else
    print_success "Node.js: $(node --version)"
fi

# Nginx
if ! command -v nginx &> /dev/null; then
    print_info "Установка Nginx..."
    apt-get install -y -qq nginx > /dev/null
    systemctl enable nginx
    print_success "Nginx установлен"
else
    print_success "Nginx уже установлен"
fi

# Certbot
if ! command -v certbot &> /dev/null; then
    print_info "Установка Certbot..."
    apt-get install -y -qq certbot python3-certbot-nginx > /dev/null
    print_success "Certbot установлен"
else
    print_success "Certbot уже установлен"
fi

# ── Gather configuration ──
echo ""
echo "─── Настройка ───"
echo ""

# Domain
read -p "Введите домен для панели (например: vpn-admin.company.com): " DOMAIN
if [[ -z "$DOMAIN" ]]; then
    print_error "Домен обязателен"
    exit 1
fi

# Check DNS
SERVER_IP=$(curl -s ifconfig.me || curl -s icanhazip.com)
DOMAIN_IP=$(dig +short "$DOMAIN" 2>/dev/null | head -1)
if [[ "$DOMAIN_IP" != "$SERVER_IP" ]]; then
    print_warning "DNS A-запись для $DOMAIN ($DOMAIN_IP) не совпадает с IP сервера ($SERVER_IP)"
    read -p "Продолжить? (y/N): " CONFIRM
    if [[ "$CONFIRM" != "y" && "$CONFIRM" != "Y" ]]; then
        exit 1
    fi
fi

# Database
DB_NAME="corpweb_db"
DB_USER="corpweb"
DB_PASSWORD="$(openssl rand -hex 16)"

# Secret key
SECRET_KEY="$(openssl rand -hex 32)"

# Google OAuth
echo ""
read -p "Google OAuth Client ID (пусто — пропустить): " GOOGLE_CLIENT_ID
GOOGLE_CLIENT_SECRET=""
GOOGLE_OAUTH_DOMAIN=""
if [[ -n "$GOOGLE_CLIENT_ID" ]]; then
    read -p "Google OAuth Client Secret: " GOOGLE_CLIENT_SECRET
    read -p "Google Workspace домен (например: company.com): " GOOGLE_OAUTH_DOMAIN
fi

# ── Create PostgreSQL database ──
print_info "Создание базы данных..."
su - postgres -c "psql -tc \"SELECT 1 FROM pg_roles WHERE rolname='$DB_USER'\" | grep -q 1 || psql -c \"CREATE USER $DB_USER WITH PASSWORD '$DB_PASSWORD';\"" 2>/dev/null
su - postgres -c "psql -tc \"SELECT 1 FROM pg_database WHERE datname='$DB_NAME'\" | grep -q 1 || psql -c \"CREATE DATABASE $DB_NAME OWNER $DB_USER;\"" 2>/dev/null
print_success "БД: $DB_NAME, пользователь: $DB_USER"

# ── Copy backend ──
print_info "Копирование backend в $INSTALL_DIR/backend..."
mkdir -p "$INSTALL_DIR"
cp -r "$SCRIPT_DIR/backend" "$INSTALL_DIR/backend"

# Create venv and install deps
print_info "Установка Python зависимостей..."
$PYTHON_BIN -m venv "$INSTALL_DIR/backend/venv"
"$INSTALL_DIR/backend/venv/bin/pip" install --quiet --upgrade pip
"$INSTALL_DIR/backend/venv/bin/pip" install --quiet -r "$INSTALL_DIR/backend/requirements.txt"
print_success "Python зависимости установлены"

# ── Build frontend ──
print_info "Сборка frontend..."
cd "$SCRIPT_DIR/frontend"
npm install --silent 2>/dev/null
npm run build 2>/dev/null
mkdir -p "$INSTALL_DIR/frontend"
cp -r dist/* "$INSTALL_DIR/frontend/"
print_success "Frontend собран и скопирован в $INSTALL_DIR/frontend"

# ── Create .env file ──
print_info "Создание .env файла..."
cat > "$INSTALL_DIR/backend/.env" <<EOF
# Database
DATABASE_URL=postgresql://$DB_USER:$DB_PASSWORD@localhost:5432/$DB_NAME

# Security
SECRET_KEY=$SECRET_KEY
JWT_ALGORITHM=HS256
ACCESS_TOKEN_EXPIRE_MINUTES=60
REFRESH_TOKEN_EXPIRE_DAYS=30

# Google OAuth
GOOGLE_CLIENT_ID=${GOOGLE_CLIENT_ID:-disabled}
GOOGLE_CLIENT_SECRET=${GOOGLE_CLIENT_SECRET:-disabled}
GOOGLE_OAUTH_DOMAIN=${GOOGLE_OAUTH_DOMAIN:-disabled}

# URLs
FRONTEND_URL=https://$DOMAIN
BACKEND_URL=https://$DOMAIN/api
CORS_ORIGINS=https://$DOMAIN

# VPN
VPN_CLIENT_SCRIPT=/root/antizapret/client.sh
VPN_CLIENT_DIR=/root/antizapret/client
OPENVPN_STATUS_LOG_DIR=/etc/openvpn/server/logs

# Monitoring
MONITORING_UPDATE_INTERVAL=30

# Logging
LOG_LEVEL=INFO
EOF
print_success ".env создан"

# ── Run Alembic migrations ──
print_info "Применение миграций БД..."
cd "$INSTALL_DIR/backend"
"$INSTALL_DIR/backend/venv/bin/alembic" upgrade head
print_success "Миграции применены"

# ── Create branding directory ──
mkdir -p "$INSTALL_DIR/frontend/branding"

# ── Create systemd service ──
print_info "Создание systemd сервиса..."
cat > /etc/systemd/system/corpweb-backend.service <<EOF
[Unit]
Description=CorpWeb Backend (FastAPI)
After=network.target postgresql.service
Requires=postgresql.service

[Service]
Type=simple
User=root
WorkingDirectory=$INSTALL_DIR/backend
EnvironmentFile=$INSTALL_DIR/backend/.env
ExecStart=$INSTALL_DIR/backend/venv/bin/uvicorn app.main:app --host 127.0.0.1 --port 8000
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable corpweb-backend
systemctl start corpweb-backend
print_success "Сервис corpweb-backend запущен"

# ── Configure Nginx ──
print_info "Настройка Nginx..."
cat > /etc/nginx/sites-available/corpweb <<EOF
server {
    listen 80;
    server_name $DOMAIN;

    # Redirect to HTTPS (certbot will update this)
    location / {
        return 301 https://\$host\$request_uri;
    }
}

server {
    listen 443 ssl http2;
    server_name $DOMAIN;

    # SSL certificates will be added by certbot
    # ssl_certificate /etc/letsencrypt/live/$DOMAIN/fullchain.pem;
    # ssl_certificate_key /etc/letsencrypt/live/$DOMAIN/privkey.pem;

    root $INSTALL_DIR/frontend;
    index index.html;

    # Security headers
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header Referrer-Policy "strict-origin-when-cross-origin" always;

    # Gzip
    gzip on;
    gzip_vary on;
    gzip_min_length 1024;
    gzip_types text/plain text/css application/json application/javascript text/xml application/xml text/javascript image/svg+xml;

    # API proxy
    location /api/ {
        proxy_pass http://127.0.0.1:8000;
        proxy_http_version 1.1;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_read_timeout 300;
    }

    # Branding assets
    location /branding/ {
        alias $INSTALL_DIR/frontend/branding/;
        expires 1d;
        access_log off;
    }

    # Static files
    location /assets/ {
        expires 30d;
        access_log off;
        add_header Cache-Control "public, immutable";
    }

    # SPA fallback
    location / {
        try_files \$uri \$uri/ /index.html;
    }
}
EOF

ln -sf /etc/nginx/sites-available/corpweb /etc/nginx/sites-enabled/corpweb
rm -f /etc/nginx/sites-enabled/default

nginx -t && systemctl reload nginx
print_success "Nginx настроен"

# ── SSL certificate ──
print_info "Получение SSL сертификата..."
certbot --nginx -d "$DOMAIN" --non-interactive --agree-tos --register-unsafely-without-email 2>/dev/null && \
    print_success "SSL сертификат получен" || \
    print_warning "Не удалось получить SSL. Настройте вручную: certbot --nginx -d $DOMAIN"

systemctl reload nginx

# ── Summary ──
echo ""
echo "========================================="
echo -e "  ${GREEN}Установка завершена!${NC}"
echo "========================================="
echo ""
echo "  Панель:     https://$DOMAIN"
echo "  API Docs:   https://$DOMAIN/api/docs"
echo ""
echo "  Первый вход:"
echo "    Логин:    admin"
echo "    Пароль:   admin"
echo ""
echo "  Файлы:"
echo "    Backend:  $INSTALL_DIR/backend/"
echo "    Frontend: $INSTALL_DIR/frontend/"
echo "    .env:     $INSTALL_DIR/backend/.env"
echo "    Логи:     journalctl -u corpweb-backend -f"
echo ""
echo "  Управление:"
echo "    systemctl restart corpweb-backend"
echo "    systemctl status corpweb-backend"
echo ""
if [[ -z "$GOOGLE_CLIENT_ID" || "$GOOGLE_CLIENT_ID" == "disabled" ]]; then
    echo -e "  ${YELLOW}Google OAuth не настроен.${NC}"
    echo "  Для настройки отредактируйте $INSTALL_DIR/backend/.env"
    echo "  и перезапустите: systemctl restart corpweb-backend"
    echo ""
fi
echo "  БД: postgresql://$DB_USER:****@localhost:5432/$DB_NAME"
echo ""
print_warning "Смените пароль admin после первого входа!"
