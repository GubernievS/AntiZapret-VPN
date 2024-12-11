#!/bin/bash
#
# Скрипт создаёт файл подкачки размером 512 МБ
# Или активирует его если файл подкачки существует но не активен
#
# chmod +x create-swap.sh && ./create-swap.sh
#
set -e

handle_error() {
	echo ""
	echo "Error occurred at line $1 while executing: $2"
	echo ""
	echo "$(lsb_release -d | awk -F'\t' '{print $2}') $(uname -r) $(date)"
	exit 1
}
trap 'handle_error $LINENO "$BASH_COMMAND"' ERR

# Путь к файлу подкачки
SWAPFILE="/swapfile"
# Размер файла подкачки (в мегабайтах)
SWAPSIZE=512

# Проверка, существует ли активный файл подкачки
if swapon --show | grep -q "$SWAPFILE"; then
    echo "Файл подкачки уже существует и активен."
    exit 0
fi

# Проверка, существует ли файл, но не активирован
if [ -f "$SWAPFILE" ]; then
    echo "Файл подкачки существует, но не активен. Активируем его..."
    sudo swapon "$SWAPFILE"
    if [ $? -eq 0 ]; then
        echo "Файл подкачки успешно активирован."
        exit 0
    else
        echo "Ошибка при активации файла подкачки."
        exit 1
    fi
fi

# Создание нового файла подкачки
echo "Файл подкачки не найден. Создаём новый файл размером ${SWAPSIZE}МБ..."
sudo fallocate -l ${SWAPSIZE}M "$SWAPFILE" || {
    echo "Ошибка: не удалось выделить место для файла подкачки.";
    exit 1;
}

# Установка правильных прав доступа
sudo chmod 600 "$SWAPFILE"

# Инициализация файла подкачки
sudo mkswap "$SWAPFILE" || {
    echo "Ошибка: не удалось инициализировать файл подкачки.";
    exit 1;
}

# Активация файла подкачки
sudo swapon "$SWAPFILE" || {
    echo "Ошибка: не удалось активировать файл подкачки.";
    exit 1;
}

# Обновление fstab для автоматического монтирования при загрузке
if ! grep -q "$SWAPFILE" /etc/fstab; then
    echo "$SWAPFILE none swap sw 0 0" | sudo tee -a /etc/fstab
    echo "Файл подкачки добавлен в /etc/fstab."
fi

echo "Файл подкачки успешно создан и активирован."
