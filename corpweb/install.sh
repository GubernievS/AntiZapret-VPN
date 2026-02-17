#!/bin/bash

#
# CorpWeb Installation Script
# Административная панель для CorpAdmin-AZ
#

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Print functions
print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Header
echo "========================================="
echo "  CorpWeb Installation Script"
echo "  Административная панель для CorpAdmin-AZ"
echo "========================================="
echo ""

# Check if running as root
if [[ $EUID -eq 0 ]] && [[ "$1" != "native" ]]; then
   print_warning "Этот скрипт не должен запускаться с правами root для Docker установки"
   print_info "Для прямой установки используйте: sudo ./install.sh native"
fi

# Ask installation type
if [[ -z "$1" ]]; then
    echo "Выберите способ установки:"
    echo ""
    echo "1) Docker Compose (рекомендуется для тестирования)"
    echo "   - Быстрое развертывание"
    echo "   - Изолированное окружение"
    echo "   - Простое обновление"
    echo ""
    echo "2) Прямая установка (рекомендуется для production)"
    echo "   - Меньше overhead"
    echo "   - Проще диагностика"
    echo "   - Интеграция с systemd"
    echo ""
    read -p "Ваш выбор (1/2): " INSTALL_TYPE
else
    if [[ "$1" == "docker" ]]; then
        INSTALL_TYPE=1
    elif [[ "$1" == "native" ]]; then
        INSTALL_TYPE=2
    else
        print_error "Неизвестный тип установки: $1"
        print_info "Используйте: ./install.sh [docker|native]"
        exit 1
    fi
fi

case $INSTALL_TYPE in
    1)
        print_info "Запуск Docker Compose установки..."
        ./install-docker.sh
        ;;
    2)
        print_info "Запуск прямой установки..."
        if [[ $EUID -ne 0 ]]; then
            print_error "Прямая установка требует прав root"
            print_info "Запустите: sudo ./install.sh native"
            exit 1
        fi
        ./install-native.sh
        ;;
    *)
        print_error "Неверный выбор. Используйте 1 или 2."
        exit 1
        ;;
esac
