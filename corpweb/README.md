# CorpWeb - Административная панель для CorpAdmin-AZ

Веб-интерфейс для управления VPN сервером AntiZapret с авторизацией, личным кабинетом пользователей и админ-панелью.

## Возможности

- **Авторизация:**
  - Логин/пароль
  - Google Workspace OAuth (автоматическое создание пользователя)

- **Для пользователей:**
  - Создание до 2 конфигураций (AWG-VPN или AWG-Antizapret)
  - Скачивание конфигурационных файлов
  - Мониторинг активных подключений

- **Для администратора:**
  - Управление пользователями (создание, блокировка, удаление)
  - Просмотр всех конфигураций
  - Расширенный мониторинг

## Требования

- Ubuntu 22.04+ или Debian 11+
- Python 3.11+
- PostgreSQL 15+
- Node.js 20+ (для сборки фронтенда)
- Nginx
- Docker и Docker Compose (опционально)

## Установка

### Вариант 1: Docker Compose (быстрое развертывание)

```bash
cd corpweb
./install-docker.sh
```

### Вариант 2: Прямая установка (production)

```bash
cd corpweb
sudo ./install-native.sh
```

Скрипт автоматически:
- Установит зависимости
- Создаст БД PostgreSQL
- Настроит backend (systemd сервис)
- Соберет frontend
- Настроит Nginx с reverse proxy
- Получит SSL сертификат через Certbot
- Создаст первого админа (admin/admin)

## Настройка Google OAuth

1. Перейти в [Google Cloud Console](https://console.cloud.google.com/)
2. Создать новый проект или выбрать существующий
3. Включить Google+ API
4. Создать OAuth 2.0 Client ID:
   - Application type: Web application
   - Authorized redirect URIs: `https://vpn-admin.yourcompany.com/api/v1/auth/google/callback`
5. Скопировать Client ID и Client Secret
6. Указать их при установке или в файле `.env`

## Первый вход

1. Открыть https://vpn-admin.yourcompany.com
2. Войти как `admin` / `admin`
3. **Сменить пароль admin!**

## Обновление

```bash
cd corpweb
git pull
./install.sh  # Повторно запустит установку
```

## Удаление

```bash
cd corpweb
sudo ./uninstall.sh
```

## Поддержка

- Основной репозиторий: [CorpAdmin-AZ](https://github.com/your-repo/CorpAdmin-AZ)
- Issues: [GitHub Issues](https://github.com/your-repo/CorpAdmin-AZ/issues)

## API Документация

После установки доступна по адресу: https://vpn-admin.yourcompany.com/api/docs

## Лицензия

Наследует лицензию основного проекта CorpAdmin-AZ
