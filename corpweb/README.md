# CorpWeb - Административная панель для CorpAdmin-AZ

Веб-интерфейс для управления VPN сервером AntiZapret с авторизацией, личным кабинетом пользователей и админ-панелью.

## Возможности

- **Авторизация:**
  - Логин/пароль
  - Google Workspace OAuth (автоматическое создание пользователя)

- **Для пользователей:**
  - Создание до N конфигураций (AWG-VPN или AWG-Antizapret), лимит настраивается администратором
  - Скачивание конфигурационных файлов (ZIP)
  - QR-коды для импорта в мобильное приложение AmneziaWG
  - Индикатор онлайн-подключения на карточках конфигов

- **Для администратора:**
  - Управление пользователями (создание, блокировка, удаление)
  - Серверный поиск и пагинация в списке пользователей
  - Просмотр конфигураций каждого пользователя (клик по строке → детальная страница)
  - Управление конфигами пользователей (скачивание, QR, удаление)
  - Блокировка пользователей с безопасным отключением VPN-пиров (реверс ключей — WG конфиг остаётся валидным)
  - Пагинация конфигурации в разделе «Мои конфиги»
  - Расширенный мониторинг (активные подключения, трафик, история)
  - Управление настройками AntiZapret (сервисы, маршрутизация, файлы)
  - Настройка лимитов конфигов, ссылок на клиентские приложения

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
- Установит зависимости (PostgreSQL, Python, Node.js, Nginx, Certbot)
- Создаст БД PostgreSQL
- Настроит backend (systemd сервис `corpweb-backend`)
- Соберет frontend
- Настроит Nginx с reverse proxy
- Получит SSL сертификат через Certbot
- Создаст первого админа (admin/admin)

### Расположение файлов после установки

| Что | Путь |
|-----|------|
| Backend (код + venv) | `/opt/corpweb/backend/` |
| Frontend (собранный) | `/opt/corpweb/frontend/` |
| Конфигурация | `/opt/corpweb/backend/.env` |
| Systemd сервис | `/etc/systemd/system/corpweb-backend.service` |
| Nginx конфиг | `/etc/nginx/sites-available/corpweb` |
| Логи backend | `journalctl -u corpweb-backend -f` |

## Обновление

### Прямая установка (native)

При обновлении кода **данные в БД не теряются** — обновляются только файлы backend и frontend.

```bash
# 1. Перейти в директорию с исходниками
cd /path/to/corpweb

# 2. Забрать новый код
git pull

# 3. Обновить backend: скопировать код (НЕ .env!)
sudo rsync -av --exclude='venv' --exclude='.env' --exclude='__pycache__' \
    backend/ /opt/corpweb/backend/

# 4. Установить/обновить Python-зависимости (если изменился requirements.txt)
sudo /opt/corpweb/backend/venv/bin/pip install -r /opt/corpweb/backend/requirements.txt

# 5. Собрать и обновить frontend
cd frontend
npm install
npm run build
sudo rm -rf /opt/corpweb/frontend/assets
sudo cp -r dist/* /opt/corpweb/frontend/

# 6. Перезапустить backend
sudo systemctl restart corpweb-backend

# 7. Проверить что всё работает
sudo systemctl status corpweb-backend
```

#### Что сохраняется при обновлении

- **База данных PostgreSQL** — не затрагивается, все пользователи, конфиги, настройки на месте
- **Файл `.env`** — не перезаписывается (шаг 3 явно исключает его)
- **WireGuard конфиги клиентов** — лежат в `/root/antizapret/client/`, не затрагиваются
- **SSL сертификаты** — в `/etc/letsencrypt/`, не затрагиваются
- **Nginx конфиг** — не перезаписывается

#### Если обновление содержит миграции БД

Если в обновлении добавлены новые поля в БД (это будет указано в changelog), после шага 4 выполните:

```bash
cd /opt/corpweb/backend
sudo /opt/corpweb/backend/venv/bin/python -m app.db.init_db
```

Скрипт `init_db` безопасен для повторного запуска — он создаёт только отсутствующие таблицы и колонки.

#### Откат при проблемах

Если после обновления что-то сломалось:

```bash
# Посмотреть логи
sudo journalctl -u corpweb-backend -n 50 --no-pager

# Откатить код (если git)
cd /path/to/corpweb
git checkout HEAD~1
# Повторить шаги 3-6
```

### Docker Compose

```bash
cd corpweb
git pull
docker-compose build
docker-compose up -d
```

Данные PostgreSQL хранятся в Docker volume `postgres_data` и сохраняются при пересборке.

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

## Управление сервисом

```bash
# Статус
sudo systemctl status corpweb-backend

# Перезапуск
sudo systemctl restart corpweb-backend

# Логи (последние, в реальном времени)
sudo journalctl -u corpweb-backend -f

# Логи (последние 100 строк)
sudo journalctl -u corpweb-backend -n 100 --no-pager
```

## Удаление

```bash
cd corpweb
sudo ./uninstall.sh
```

## API Документация

После установки доступна по адресу: https://vpn-admin.yourcompany.com/api/docs

## Лицензия

Наследует лицензию основного проекта CorpAdmin-AZ
