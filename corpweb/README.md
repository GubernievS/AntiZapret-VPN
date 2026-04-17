# CorpAdmin-AZ — Административная панель + HA для AntiZapret VPN

Веб-панель управления с горизонтальным масштабированием: control-plane (CP) + data-plane ноды с автоматической синхронизацией конфигов.

## Архитектура

```
┌──────────────────────────────────────────────┐
│  Control-Plane (CP) — Россия                 │
│                                              │
│  nginx (HTTPS)  ──→  corpweb-backend :8000   │
│  iptables DNAT  ──→  ноды (UDP WG/AWG)      │
│  PostgreSQL     ──→  все данные              │
└────────────────────┬─────────────────────────┘
                     │  HTTPS (Agent API + SSE)
           ┌─────────┴──────────┐
           ▼                    ▼
     ┌───────────┐        ┌───────────┐
     │ Нода 1    │        │ Нода 2    │  ...
     │ AZ + WG   │        │ AZ + WG   │
     │ sync-agent│        │ sync-agent│
     └───────────┘        └───────────┘
```

**Принцип:** Все данные в PostgreSQL. Файлы на нодах — представления данных из БД. Имея БД, можно восстановить/установить любую ноду.

## Как это работает

1. **CP** хранит все WG-конфиги, ключи, настройки AZ, списки доменов/IP в PostgreSQL (таблица `wg_file_state`)
2. При изменении данных PostgreSQL шлёт `NOTIFY` → **sync-agent** на каждой ноде получает SSE-событие
3. Агент скачивает обновлённый файл, записывает на диск, запускает хук:
   - WG конфиг → `wg syncconf`
   - AZ config файл → debounced `doall.sh` (5с)
4. Агент шлёт **heartbeat** каждые 30с: applied SHA, health, метрики, список пиров
5. **iptables DNAT** на CP балансирует UDP-трафик между нодами (настраивается через панель)

## Требования

| Компонент | Требования |
|-----------|-----------|
| **CP сервер** | Debian 12+, Python 3.11+, PostgreSQL 15+, nginx, Node.js 20+, Certbot |
| **Нода** | Debian 12+, установленный AntiZapret (setup.sh), Python 3 + requests |
| **Сеть** | CP должен иметь прямой UDP-доступ к нодам на портах 51080/51443/52080/52443 |

## Установка Control-Plane

### 1. Подготовка сервера

```bash
apt-get update && apt-get install -y \
  nginx postgresql python3-pip python3-venv git \
  certbot python3-certbot-nginx nodejs npm libnginx-mod-stream
```

### 2. Клонирование и настройка

```bash
cd /root
git clone https://github.com/AlexanderBrolin/CorpAdmin-AZ.git
cd CorpAdmin-AZ && git checkout CorpAdmin

# Создать директории
mkdir -p /opt/corpweb/{backend,frontend,agent}

# Backend
cp -r corpweb/backend/app /opt/corpweb/backend/app
cp corpweb/backend/alembic.ini /opt/corpweb/backend/
cp -r corpweb/backend/alembic /opt/corpweb/backend/alembic
cp corpweb/backend/requirements.txt /opt/corpweb/backend/
cp -r agent /opt/corpweb/agent

# Создать symlink для agent (backend ищет его по относительному пути)
ln -s /opt/corpweb/agent /opt/corpweb/backend/agent

# Python venv
cd /opt/corpweb/backend
python3 -m venv venv
source venv/bin/activate
pip install -r requirements.txt
```

### 3. PostgreSQL

```bash
sudo -u postgres psql -c "CREATE USER corpweb WITH PASSWORD 'YOUR_PASSWORD';"
sudo -u postgres psql -c "CREATE DATABASE corpweb_db OWNER corpweb;"
```

### 4. Конфигурация (.env)

```bash
cat > /opt/corpweb/backend/.env << 'EOF'
DATABASE_URL=postgresql://corpweb:YOUR_PASSWORD@localhost:5432/corpweb_db
SECRET_KEY=YOUR_SECRET_KEY
JWT_ALGORITHM=HS256
ACCESS_TOKEN_EXPIRE_MINUTES=60
REFRESH_TOKEN_EXPIRE_DAYS=30

GOOGLE_CLIENT_ID=YOUR_GOOGLE_CLIENT_ID
GOOGLE_CLIENT_SECRET=YOUR_GOOGLE_CLIENT_SECRET
GOOGLE_OAUTH_DOMAIN=yourcompany.com

FRONTEND_URL=https://vpn.yourcompany.com
BACKEND_URL=https://vpn.yourcompany.com/api
CORS_ORIGINS=https://vpn.yourcompany.com

LB_ENDPOINT_HOST=vpn.yourcompany.com

VPN_CLIENT_SCRIPT=/dev/null
VPN_CLIENT_DIR=/tmp
MONITORING_UPDATE_INTERVAL=30
OPENVPN_STATUS_LOG_DIR=/tmp
LOG_LEVEL=INFO
EOF
chmod 600 /opt/corpweb/backend/.env
```

### 5. База данных

```bash
cd /opt/corpweb/backend && source venv/bin/activate

# Миграции
alembic upgrade head

# Начальные данные (admin/admin + системные настройки)
python3 -c "from app.db.init_db import init_db; init_db()"
```

### 6. Frontend

```bash
cd /root/CorpAdmin-AZ/corpweb/frontend
npm install && npm run build
cp -r dist/* /opt/corpweb/frontend/
```

### 7. Systemd сервис

```bash
cat > /etc/systemd/system/corpweb-backend.service << 'EOF'
[Unit]
Description=CorpWeb Backend (FastAPI)
After=network.target postgresql.service
Requires=postgresql.service

[Service]
Type=simple
User=root
WorkingDirectory=/opt/corpweb/backend
EnvironmentFile=/opt/corpweb/backend/.env
ExecStart=/opt/corpweb/backend/venv/bin/uvicorn app.main:app --host 127.0.0.1 --port 8000
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now corpweb-backend
```

### 8. Nginx

Конфигурация nginx для CP включает:
- HTTP → HTTPS редирект
- Reverse proxy для API (`/api/` → backend)
- SSE proxy без буферизации (`/api/v1/agent/events`, `/api/v1/apply-status/stream`)
- SPA fallback для фронтенда
- Опционально: `stream {}` блок для UDP (если используется nginx вместо iptables DNAT)

```bash
# SSL сертификат
certbot --nginx -d vpn.yourcompany.com --non-interactive --agree-tos -m admin@yourcompany.com
```

### 9. DNAT балансировка

Балансировка UDP-трафика настраивается через панель (Ноды → Балансировка) или вручную:

```bash
# Пример для 2 нод 50/50
iptables -t nat -A PREROUTING -p udp --dport 51443 -m statistic --mode random --probability 0.5 -j DNAT --to-destination NODE1_IP:51443
iptables -t nat -A PREROUTING -p udp --dport 51443 -j DNAT --to-destination NODE2_IP:51443
# ... аналогично для 51080, 52443, 52080

# SNAT для обратного трафика (ОБЯЗАТЕЛЬНО с -d фильтром!)
iptables -t nat -A POSTROUTING -d NODE1_IP -j SNAT --to-source CP_IP
iptables -t nat -A POSTROUTING -d NODE2_IP -j SNAT --to-source CP_IP

# ip_forward
echo 1 > /proc/sys/net/ipv4/ip_forward

# Сохранить
netfilter-persistent save
```

### 10. Bootstrap VPN manager

При первой установке или миграции с single-node:

```bash
cd /opt/corpweb/backend && source venv/bin/activate
python3 -m app.migrate  # миграция файлов с диска в БД (для существующих нод)
```

## Подготовка ноды

### 1. Установка AntiZapret

```bash
# Если su (не root), добавить PATH:
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

# Установка из нашего форка (поддержка Debian 12)
bash <(curl -fsSL https://raw.githubusercontent.com/AlexanderBrolin/CorpAdmin-AZ/CorpAdmin/setup.sh)
```

### 2. Добавление ноды в CP

1. В панели: **Ноды → Добавить ноду** → ввести hostname и IP
2. Скопировать команду установки агента из Step 2:
   ```bash
   curl -fsSL "https://vpn.yourcompany.com/api/v1/agent/install.sh?token=TOKEN" | bash
   ```
3. Дождаться статуса `ok` в панели

### 3. Что делает агент при установке

1. Регистрируется на CP → получает server keypair + wg_config
2. Записывает ключи в `/etc/wireguard/`
3. Патчит `[Interface]` секции WG конфигов (Address, ListenPort, MTU)
4. Запускает startup reconcile — скачивает все 12 управляемых файлов, применяет при различии SHA
5. Подключается к SSE — слушает изменения в реальном времени
6. Каждые 30с шлёт heartbeat с метриками и списком пиров

### 4. Если нода использует тот же keypair что CP

При HA все ноды используют один server keypair. Агент получит его при регистрации. Если на ноде уже были другие ключи — агент перезапишет и рестартит WG.

## Добавление / удаление нод

### Добавление

1. Установить AntiZapret на новом сервере
2. В панели: Ноды → Добавить → установить агент
3. Ноды → Балансировка → включить ноду, выставить вес → Сохранить

### Удаление

1. Ноды → Балансировка → выключить ноду → Сохранить
2. Подождать пока conntrack-сессии клиентов истекут (~3 мин)
3. На ноде: `systemctl stop corpweb-sync-agent`
4. В панели: удалить ноду

## Управляемые файлы

12 файлов синхронизируются между CP и нодами:

| Файл | Хук после изменения |
|------|-------------------|
| `/etc/wireguard/antizapret.conf` | `wg syncconf antizapret` |
| `/etc/wireguard/vpn.conf` | `wg syncconf vpn` |
| `/root/antizapret/setup` | — |
| `/root/antizapret/config/include-hosts.txt` | `doall.sh` (debounce 5с) |
| `/root/antizapret/config/exclude-hosts.txt` | `doall.sh` |
| `/root/antizapret/config/include-ips.txt` | `doall.sh` |
| `/root/antizapret/config/exclude-ips.txt` | `doall.sh` |
| `/root/antizapret/config/allow-ips.txt` | `doall.sh` |
| `/root/antizapret/config/forward-ips.txt` | `doall.sh` |
| `/root/antizapret/config/include-adblock-hosts.txt` | `doall.sh` |
| `/root/antizapret/config/exclude-adblock-hosts.txt` | `doall.sh` |
| `/root/antizapret/config/remove-hosts.txt` | `doall.sh` |

## Панель управления

### Для пользователей
- Создание VPN-конфигов (AWG-Antizapret / AWG-VPN)
- Скачивание конфигов (ZIP) и QR-коды
- Лимит конфигов на пользователя (настраивается админом)

### Для администратора
- **Дашборд** — статус нод, активные клиенты, распределение нагрузки
- **Мониторинг** — активные подключения с сортировкой, трафик по нодам
- **Ноды** — добавление/удаление, балансировка (DNAT), IP балансировщика
- **Настройки AZ** — 25 параметров: маршрутизация, CDN-сервисы, DNS, безопасность, WARP
- **Файлы AZ** — 9 конфигурационных файлов: домены, IP, adblock, исключения
- **Пользователи** — управление, блокировка (реверс ключей), удаление
- **Системные настройки** — лимиты, ссылки на клиентские приложения

## Обновление

```bash
cd /root/CorpAdmin-AZ && git pull origin CorpAdmin

# Backend
rm -rf /opt/corpweb/backend/app
cp -r corpweb/backend/app /opt/corpweb/backend/app
cd /opt/corpweb/backend && source venv/bin/activate
pip install -r requirements.txt
alembic upgrade head

# Frontend
cd /root/CorpAdmin-AZ/corpweb/frontend
npm install && npm run build
rm -rf /opt/corpweb/frontend/assets /opt/corpweb/frontend/index.html
cp -r dist/* /opt/corpweb/frontend/

# Перезапуск
systemctl restart corpweb-backend

# Обновить агентов на нодах (если изменился agent код)
# На каждой ноде:
curl -fsSL "https://vpn.yourcompany.com/api/v1/agent/sync-agent.py?token=TOKEN" \
  -o /usr/local/bin/corpweb-sync-agent.py
systemctl restart corpweb-sync-agent
```

## Первый вход

1. Открыть https://vpn.yourcompany.com
2. Войти как `admin` / `admin`
3. **Сменить пароль!**

## API Документация

Swagger UI: https://vpn.yourcompany.com/api/docs

## Лицензия

Наследует лицензию AntiZapret-VPN (GubernievS/AntiZapret-VPN).
