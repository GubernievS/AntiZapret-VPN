#!/bin/bash

#
# Uninstall CorpWeb
#

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
print_success() { echo -e "${GREEN}[OK]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[WARN]${NC} $1"; }

INSTALL_DIR="/opt/corpweb"

echo "========================================="
echo "  CorpWeb — Удаление"
echo "========================================="
echo ""

if [[ $EUID -ne 0 ]]; then
   echo -e "${RED}[ERROR]${NC} Запустите с правами root"
   exit 1
fi

read -p "Вы уверены, что хотите удалить CorpWeb? (y/N): " CONFIRM
if [[ "$CONFIRM" != "y" && "$CONFIRM" != "Y" ]]; then
    echo "Отменено."
    exit 0
fi

# Stop and disable service
if systemctl is-active --quiet corpweb-backend 2>/dev/null; then
    print_info "Остановка сервиса..."
    systemctl stop corpweb-backend
fi
if systemctl is-enabled --quiet corpweb-backend 2>/dev/null; then
    systemctl disable corpweb-backend
fi
rm -f /etc/systemd/system/corpweb-backend.service
systemctl daemon-reload
print_success "Сервис удалён"

# Stop Docker if running
if command -v docker &> /dev/null; then
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    if [[ -f "$SCRIPT_DIR/docker-compose.yml" ]]; then
        print_info "Остановка Docker контейнеров..."
        cd "$SCRIPT_DIR"
        docker compose down -v 2>/dev/null || docker-compose down -v 2>/dev/null || true
        print_success "Docker контейнеры остановлены"
    fi
fi

# Remove Nginx config
if [[ -f /etc/nginx/sites-enabled/corpweb ]]; then
    rm -f /etc/nginx/sites-enabled/corpweb
    rm -f /etc/nginx/sites-available/corpweb
    nginx -t 2>/dev/null && systemctl reload nginx 2>/dev/null || true
    print_success "Nginx конфигурация удалена"
fi

# Remove files
if [[ -d "$INSTALL_DIR" ]]; then
    rm -rf "$INSTALL_DIR"
    print_success "Файлы удалены: $INSTALL_DIR"
fi

# Database
read -p "Удалить базу данных corpweb_db? (y/N): " DEL_DB
if [[ "$DEL_DB" == "y" || "$DEL_DB" == "Y" ]]; then
    su - postgres -c "psql -c 'DROP DATABASE IF EXISTS corpweb_db;'" 2>/dev/null || true
    su - postgres -c "psql -c 'DROP USER IF EXISTS corpweb;'" 2>/dev/null || true
    print_success "База данных удалена"
fi

echo ""
print_success "CorpWeb удалён"
