#!/bin/bash

# ═══════════════════════════════════════════════════════════════════════════════
# CorpAdmin-AZ — Control-Plane Installation Script
# ═══════════════════════════════════════════════════════════════════════════════
#
# Устанавливает Control-Plane (CP) для управления AntiZapret VPN нодами.
#
# Что делает скрипт:
#   1. Устанавливает системные зависимости (PostgreSQL, Python, Node.js, nginx, Certbot)
#   2. Создаёт базу данных PostgreSQL
#   3. Копирует backend + agent в /opt/corpweb/
#   4. Создаёт Python venv и устанавливает зависимости
#   5. Собирает React frontend
#   6. Создаёт .env конфигурацию
#   7. Применяет миграции БД и создаёт admin-пользователя
#   8. Настраивает systemd сервис для backend (uvicorn)
#   9. Настраивает nginx (reverse proxy + SSE locations)
#  10. Получает SSL сертификат через Let's Encrypt
#
# Для ручной установки — выполняйте шаги по порядку, заменяя переменные.
#
# Требования:
#   - Debian 12+ или Ubuntu 22.04+
#   - Запуск от root (sudo ./install-native.sh)
#   - DNS A-запись домена должна указывать на IP этого сервера (для SSL)
#   - Порт 80 и 443 должны быть открыты (для Certbot и nginx)
#
# После установки:
#   - Панель: https://YOUR_DOMAIN
#   - Логин: admin / admin (СМЕНИТЬ!)
#   - Ноды добавляются через панель → Ноды → Добавить
#   - Балансировка настраивается через панель → Ноды → Балансировка
#
# ═══════════════════════════════════════════════════════════════════════════════

set -e

# ── Цвета и утилиты ──────────────────────────────────────────────────────────

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
print_success() { echo -e "${GREEN}[OK]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[WARN]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Куда устанавливается CP
INSTALL_DIR="/opt/corpweb"

# Директория с исходниками (откуда запущен скрипт)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"

echo "========================================="
echo "  CorpAdmin-AZ — Установка Control-Plane"
echo "========================================="
echo ""

# ── Шаг 0: Проверка прав и ОС ────────────────────────────────────────────────
# Ручная установка: убедитесь что вы root (sudo su -)

if [[ $EUID -ne 0 ]]; then
   print_error "Скрипт должен запускаться от root"
   print_info "Выполните: sudo su - или sudo ./install-native.sh"
   exit 1
fi

print_info "Проверка ОС..."
if [[ -f /etc/os-release ]]; then
    . /etc/os-release
    if [[ "$ID" != "ubuntu" && "$ID" != "debian" ]]; then
        print_error "Поддерживаются только Ubuntu 22.04+ и Debian 12+"
        exit 1
    fi
    print_success "ОС: $PRETTY_NAME"
else
    print_error "Не удалось определить ОС"
    exit 1
fi

# ── Шаг 1: Системные зависимости ─────────────────────────────────────────────
# Ручная установка:
#   apt-get update
#   apt-get install -y postgresql python3-pip python3-venv nginx certbot python3-certbot-nginx
#   curl -fsSL https://deb.nodesource.com/setup_20.x | bash - && apt-get install -y nodejs

print_info "Установка системных зависимостей..."
apt-get update -qq

# PostgreSQL — хранилище всех данных CP (конфиги, ключи, пользователи)
if ! command -v psql &> /dev/null; then
    print_info "Установка PostgreSQL..."
    apt-get install -y -qq postgresql postgresql-contrib > /dev/null
    systemctl enable postgresql
    systemctl start postgresql
    print_success "PostgreSQL установлен"
else
    print_success "PostgreSQL уже установлен"
fi

# Python 3.11+ — для FastAPI backend
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

# Node.js 20+ — для сборки React frontend
if ! command -v node &> /dev/null; then
    print_info "Установка Node.js 20..."
    curl -fsSL https://deb.nodesource.com/setup_20.x | bash - > /dev/null 2>&1
    apt-get install -y -qq nodejs > /dev/null
    print_success "Node.js $(node --version) установлен"
else
    print_success "Node.js: $(node --version)"
fi

# Nginx — reverse proxy для API + SPA frontend + SSE
if ! command -v nginx &> /dev/null; then
    print_info "Установка Nginx..."
    apt-get install -y -qq nginx > /dev/null
    systemctl enable nginx
    print_success "Nginx установлен"
else
    print_success "Nginx уже установлен"
fi

# Certbot — автоматический SSL от Let's Encrypt
if ! command -v certbot &> /dev/null; then
    print_info "Установка Certbot..."
    apt-get install -y -qq certbot python3-certbot-nginx > /dev/null
    print_success "Certbot установлен"
else
    print_success "Certbot уже установлен"
fi

# ── Шаг 2: Ввод параметров ───────────────────────────────────────────────────
# Ручная установка: задайте переменные вручную
#   DOMAIN="vpn.yourcompany.com"
#   DB_PASSWORD="$(openssl rand -hex 16)"
#   SECRET_KEY="$(openssl rand -hex 32)"

echo ""
echo "─── Настройка ───"
echo ""

read -p "Введите домен для панели (например: vpn.company.com): " DOMAIN
if [[ -z "$DOMAIN" ]]; then
    print_error "Домен обязателен"
    exit 1
fi

# Проверка DNS — домен должен указывать на IP этого сервера для получения SSL
SERVER_IP=$(curl -s -m5 ifconfig.me || curl -s -m5 icanhazip.com || echo "unknown")
DOMAIN_IP=$(dig +short "$DOMAIN" 2>/dev/null | head -1 || echo "")

SSL_POSSIBLE=true
if [[ -z "$DOMAIN_IP" ]]; then
    print_warning "Не удалось определить DNS для $DOMAIN"
    print_warning "SSL сертификат не будет получен автоматически"
    SSL_POSSIBLE=false
    read -p "Продолжить без SSL? (y/N): " CONFIRM
    [[ "$CONFIRM" != "y" && "$CONFIRM" != "Y" ]] && exit 1
elif [[ "$DOMAIN_IP" != "$SERVER_IP" ]]; then
    print_warning "DNS A-запись: $DOMAIN → $DOMAIN_IP"
    print_warning "IP сервера:   $SERVER_IP"
    print_warning "DNS не совпадает — SSL сертификат не будет получен автоматически"
    SSL_POSSIBLE=false
    read -p "Продолжить? (y/N): " CONFIRM
    [[ "$CONFIRM" != "y" && "$CONFIRM" != "Y" ]] && exit 1
else
    print_success "DNS: $DOMAIN → $SERVER_IP (совпадает)"
fi

# Генерация паролей
DB_NAME="corpweb_db"
DB_USER="corpweb"
DB_PASSWORD="$(openssl rand -hex 16)"
SECRET_KEY="$(openssl rand -hex 32)"

# Google OAuth (опционально)
echo ""
read -p "Google OAuth Client ID (пусто — пропустить): " GOOGLE_CLIENT_ID
GOOGLE_CLIENT_SECRET=""
GOOGLE_OAUTH_DOMAIN=""
if [[ -n "$GOOGLE_CLIENT_ID" ]]; then
    read -p "Google OAuth Client Secret: " GOOGLE_CLIENT_SECRET
    read -p "Google Workspace домен (например: company.com): " GOOGLE_OAUTH_DOMAIN
fi

# ── Шаг 3: Создание БД ──────────────────────────────────────────────────────
# Ручная установка:
#   sudo -u postgres psql -c "CREATE USER corpweb WITH PASSWORD 'YOUR_PASSWORD';"
#   sudo -u postgres psql -c "CREATE DATABASE corpweb_db OWNER corpweb;"

print_info "Создание базы данных..."
su - postgres -c "psql -tc \"SELECT 1 FROM pg_roles WHERE rolname='$DB_USER'\" | grep -q 1 || psql -c \"CREATE USER $DB_USER WITH PASSWORD '$DB_PASSWORD';\"" 2>/dev/null
su - postgres -c "psql -tc \"SELECT 1 FROM pg_database WHERE datname='$DB_NAME'\" | grep -q 1 || psql -c \"CREATE DATABASE $DB_NAME OWNER $DB_USER;\"" 2>/dev/null
print_success "БД: $DB_NAME, пользователь: $DB_USER"

# ── Шаг 4: Копирование кода ─────────────────────────────────────────────────
# Ручная установка:
#   mkdir -p /opt/corpweb
#   cp -r corpweb/backend /opt/corpweb/backend
#   cp -r agent /opt/corpweb/agent

print_info "Копирование backend и agent в $INSTALL_DIR..."
mkdir -p "$INSTALL_DIR"
cp -r "$SCRIPT_DIR/backend" "$INSTALL_DIR/backend"

# Agent — исходники sync-agent для раздачи нодам через API
if [[ -d "$REPO_ROOT/agent" ]]; then
    cp -r "$REPO_ROOT/agent" "$INSTALL_DIR/agent"
    print_success "Agent скопирован в $INSTALL_DIR/agent"
else
    print_warning "Каталог agent/ не найден в $REPO_ROOT"
fi

# ── Шаг 5: Python venv + зависимости ────────────────────────────────────────
# Ручная установка:
#   cd /opt/corpweb/backend
#   python3 -m venv venv
#   source venv/bin/activate
#   pip install -r requirements.txt

print_info "Установка Python зависимостей..."
$PYTHON_BIN -m venv "$INSTALL_DIR/backend/venv"
"$INSTALL_DIR/backend/venv/bin/pip" install --quiet --upgrade pip
"$INSTALL_DIR/backend/venv/bin/pip" install --quiet -r "$INSTALL_DIR/backend/requirements.txt"
print_success "Python зависимости установлены"

# ── Шаг 6: Сборка frontend ──────────────────────────────────────────────────
# Ручная установка:
#   cd corpweb/frontend && npm install && npm run build
#   cp -r dist/* /opt/corpweb/frontend/

print_info "Сборка frontend..."
cd "$SCRIPT_DIR/frontend"
npm install --silent 2>/dev/null
npm run build 2>/dev/null
mkdir -p "$INSTALL_DIR/frontend"
cp -r dist/* "$INSTALL_DIR/frontend/"
mkdir -p "$INSTALL_DIR/frontend/branding"
print_success "Frontend собран"

# ── Шаг 7: Конфигурация .env ────────────────────────────────────────────────
# Ручная установка: создайте /opt/corpweb/backend/.env со следующим содержимым
# и замените значения на свои

print_info "Создание .env файла..."
cat > "$INSTALL_DIR/backend/.env" <<EOF
# ── Database ──
DATABASE_URL=postgresql://$DB_USER:$DB_PASSWORD@localhost:5432/$DB_NAME

# ── Security ──
SECRET_KEY=$SECRET_KEY
JWT_ALGORITHM=HS256
ACCESS_TOKEN_EXPIRE_MINUTES=60
REFRESH_TOKEN_EXPIRE_DAYS=30

# ── Google OAuth (опционально) ──
GOOGLE_CLIENT_ID=${GOOGLE_CLIENT_ID:-disabled}
GOOGLE_CLIENT_SECRET=${GOOGLE_CLIENT_SECRET:-disabled}
GOOGLE_OAUTH_DOMAIN=${GOOGLE_OAUTH_DOMAIN:-disabled}

# ── URLs ──
FRONTEND_URL=https://$DOMAIN
BACKEND_URL=https://$DOMAIN/api
CORS_ORIGINS=https://$DOMAIN

# ── HA (hostname для клиентских конфигов) ──
LB_ENDPOINT_HOST=$DOMAIN

# ── Legacy (не используется в HA-режиме) ──
VPN_CLIENT_SCRIPT=/dev/null
VPN_CLIENT_DIR=/tmp
OPENVPN_STATUS_LOG_DIR=/tmp

# ── Мониторинг ──
MONITORING_UPDATE_INTERVAL=30

# ── Логирование ──
LOG_LEVEL=INFO
EOF
chmod 600 "$INSTALL_DIR/backend/.env"
print_success ".env создан: $INSTALL_DIR/backend/.env"

# ── Шаг 8: Миграции БД + инициализация ──────────────────────────────────────
# Ручная установка:
#   cd /opt/corpweb/backend && source venv/bin/activate
#   alembic upgrade head
#   python3 -c "from app.db.init_db import init_db; init_db()"

print_info "Применение миграций БД..."
cd "$INSTALL_DIR/backend"
"$INSTALL_DIR/backend/venv/bin/alembic" upgrade head 2>/dev/null || \
    print_warning "Alembic: часть миграций уже применена"
print_success "Миграции применены"

print_info "Инициализация БД (admin, системные настройки)..."
"$INSTALL_DIR/backend/venv/bin/python" -c "from app.db.init_db import init_db; init_db()"

# ── Шаг 9: Systemd сервис ───────────────────────────────────────────────────
# Ручная установка: создайте /etc/systemd/system/corpweb-backend.service

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

# ── Шаг 10: Nginx ────────────────────────────────────────────────────────────
# Ручная установка: создайте /etc/nginx/sites-available/corpweb
# Важно: SSE location'ы для /api/v1/agent/events и /api/v1/apply-status/stream
# должны иметь proxy_buffering off, иначе SSE не работает

print_info "Настройка Nginx..."

# Временный self-signed сертификат чтобы nginx стартовал с listen 443
# Certbot заменит его на настоящий
SSL_DIR="/etc/nginx/ssl"
mkdir -p "$SSL_DIR"
if [[ ! -f "$SSL_DIR/selfsigned.crt" ]]; then
    openssl req -x509 -newkey rsa:2048 \
        -keyout "$SSL_DIR/selfsigned.key" -out "$SSL_DIR/selfsigned.crt" \
        -days 1 -nodes -subj "/CN=$DOMAIN" 2>/dev/null
fi

cat > /etc/nginx/sites-available/corpweb <<NGINX_EOF
server {
    listen 80;
    server_name $DOMAIN;

    # ACME challenge для Certbot (нужен для получения SSL)
    location /.well-known/acme-challenge/ {
        root /var/www/html;
    }

    # Всё остальное → HTTPS
    location / {
        return 301 https://\$host\$request_uri;
    }
}

server {
    listen 443 ssl http2;
    server_name $DOMAIN;

    # SSL сертификаты (certbot заменит self-signed на Let's Encrypt)
    ssl_certificate $SSL_DIR/selfsigned.crt;
    ssl_certificate_key $SSL_DIR/selfsigned.key;
    ssl_protocols TLSv1.2 TLSv1.3;

    root $INSTALL_DIR/frontend;
    index index.html;

    # ── Безопасность ──
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header Referrer-Policy "strict-origin-when-cross-origin" always;

    # ── Сжатие ──
    gzip on;
    gzip_vary on;
    gzip_min_length 1024;
    gzip_types text/plain text/css application/json application/javascript text/xml application/xml text/javascript image/svg+xml;

    # ── API proxy (все /api/ запросы → FastAPI backend на :8000) ──
    location /api/ {
        proxy_pass http://127.0.0.1:8000;
        proxy_http_version 1.1;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_read_timeout 300;
    }

    # ── SSE: события для sync-agent'ов на нодах (долгоживущее соединение) ──
    # Без proxy_buffering off SSE не будет доставлять события в реальном времени
    location /api/v1/agent/events {
        proxy_pass http://127.0.0.1:8000;
        proxy_http_version 1.1;
        proxy_read_timeout 24h;
        proxy_buffering off;
        proxy_cache off;
        proxy_set_header Connection '';
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        chunked_transfer_encoding on;
    }

    # ── SSE: статус применения изменений (фронт ждёт подтверждения от нод) ──
    location /api/v1/apply-status/stream {
        proxy_pass http://127.0.0.1:8000;
        proxy_http_version 1.1;
        proxy_read_timeout 60s;
        proxy_buffering off;
        proxy_cache off;
        proxy_set_header Connection '';
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        chunked_transfer_encoding on;
    }

    # ── Статика ──
    location /branding/ {
        alias $INSTALL_DIR/frontend/branding/;
        expires 1d;
        access_log off;
    }

    location /assets/ {
        expires 30d;
        access_log off;
        add_header Cache-Control "public, immutable";
    }

    # ── SPA fallback (все неизвестные URL → index.html) ──
    location / {
        try_files \$uri \$uri/ /index.html;
    }
}
NGINX_EOF

ln -sf /etc/nginx/sites-available/corpweb /etc/nginx/sites-enabled/corpweb
rm -f /etc/nginx/sites-enabled/default

nginx -t && systemctl reload nginx
print_success "Nginx настроен (self-signed SSL)"

# ── Шаг 11: SSL сертификат Let's Encrypt ────────────────────────────────────
# Ручная установка:
#   certbot --nginx -d YOUR_DOMAIN
#
# Требования для успешного получения:
#   1. DNS A-запись YOUR_DOMAIN → IP этого сервера
#   2. Порт 80 открыт и доступен из интернета (Certbot использует HTTP challenge)
#   3. Nginx запущен и слушает порт 80

if [[ "$SSL_POSSIBLE" == "true" ]]; then
    print_info "Получение SSL сертификата Let's Encrypt..."
    if certbot --nginx -d "$DOMAIN" --non-interactive --agree-tos \
        --register-unsafely-without-email 2>/dev/null; then
        print_success "SSL сертификат получен и установлен"
        systemctl reload nginx
    else
        print_error "Не удалось получить SSL сертификат"
        echo ""
        echo "  Возможные причины:"
        echo "    1. DNS A-запись $DOMAIN не указывает на IP этого сервера ($SERVER_IP)"
        echo "    2. Порт 80 закрыт файрволом или занят другим сервисом"
        echo "    3. Let's Encrypt rate limit (макс. 5 сертификатов в неделю на домен)"
        echo ""
        echo "  Что сделать:"
        echo "    1. Проверьте DNS: dig $DOMAIN"
        echo "    2. Проверьте порт 80: curl -v http://$DOMAIN/.well-known/acme-challenge/test"
        echo "    3. Повторите вручную: certbot --nginx -d $DOMAIN"
        echo ""
        echo "  Панель работает на https://$DOMAIN с self-signed сертификатом."
        echo "  Браузер покажет предупреждение — это нормально до получения SSL."
        echo ""
    fi
else
    echo ""
    print_warning "SSL сертификат не запрошен (DNS не настроен)"
    echo ""
    echo "  Когда DNS A-запись $DOMAIN будет указывать на $SERVER_IP,"
    echo "  выполните:"
    echo "    certbot --nginx -d $DOMAIN"
    echo ""
    echo "  Панель пока работает с self-signed сертификатом."
    echo ""
fi

# ── Итог ─────────────────────────────────────────────────────────────────────

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
echo "    Agent:    $INSTALL_DIR/agent/"
echo "    .env:     $INSTALL_DIR/backend/.env"
echo "    Логи:     journalctl -u corpweb-backend -f"
echo ""
echo "  Управление:"
echo "    systemctl restart corpweb-backend"
echo "    systemctl status corpweb-backend"
echo ""

if [[ -z "$GOOGLE_CLIENT_ID" || "$GOOGLE_CLIENT_ID" == "disabled" ]]; then
    echo -e "  ${YELLOW}Google OAuth не настроен.${NC}"
    echo "  Отредактируйте $INSTALL_DIR/backend/.env и перезапустите backend"
    echo ""
fi

echo "  Следующие шаги:"
echo "    1. Сменить пароль admin"
echo "    2. Настроить DNAT балансировку (Ноды → Балансировка) или вручную через iptables"
echo "    3. Установить AntiZapret на нодах и добавить их через панель"
echo ""
echo "  БД: postgresql://$DB_USER:****@localhost:5432/$DB_NAME"
echo ""
print_warning "Смените пароль admin после первого входа!"
