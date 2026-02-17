#!/bin/bash

#
# Docker Compose Installation Script
#

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
print_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1"; }

echo "========================================="
echo "  Docker Compose Installation"
echo "========================================="
echo ""

# Check Docker
print_info "Проверка Docker..."
if ! command -v docker &> /dev/null; then
    print_error "Docker не установлен"
    print_info "Установите Docker: https://docs.docker.com/engine/install/"
    exit 1
fi

if ! command -v docker-compose &> /dev/null && ! docker compose version &> /dev/null; then
    print_error "Docker Compose не установлен"
    print_info "Установите Docker Compose: https://docs.docker.com/compose/install/"
    exit 1
fi

print_success "Docker и Docker Compose установлены"

# Check .env file
if [[ ! -f .env ]]; then
    print_info "Создание .env файла из .env.example..."
    cp .env.example .env

    # Generate SECRET_KEY
    SECRET_KEY=$(openssl rand -hex 32)
    sed -i "s/change_me_to_random_string_64_chars_minimum/$SECRET_KEY/g" .env

    # Generate DB password
    DB_PASSWORD=$(openssl rand -base64 24 | tr -d "=+/" | cut -c1-24)
    sed -i "s/change_me_in_production/$DB_PASSWORD/g" .env

    print_info "Файл .env создан. Отредактируйте его перед продолжением:"
    print_info "- GOOGLE_CLIENT_ID"
    print_info "- GOOGLE_CLIENT_SECRET"
    print_info "- GOOGLE_OAUTH_DOMAIN"
    print_info "- FRONTEND_URL / BACKEND_URL"
    echo ""
    read -p "Нажмите Enter после редактирования .env файла..."
fi

# Build and start
print_info "Сборка и запуск контейнеров..."
docker-compose up -d --build

print_success "CorpWeb запущен!"
echo ""
print_info "Проверьте статус: docker-compose ps"
print_info "Логи: docker-compose logs -f"
print_info "Откройте: http://localhost (или ваш домен)"
echo ""
print_info "Первый вход: admin / admin"
print_info "ВАЖНО: Смените пароль admin после первого входа!"
