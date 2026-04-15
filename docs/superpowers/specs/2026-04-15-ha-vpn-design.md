# HA AntiZapret+VPN за балансером — Design Spec

**Date:** 2026-04-15  
**Status:** Approved  
**Scope:** Горизонтальное масштабирование CorpAdmin-AZ: control-plane (РФ) + data-ноды (Финляндия)

---

## Контекст и цели

Текущая нода `wgfi2` обслуживает **509 клиентов** при load average 0.07 — CPU не является узким местом. Проблема — насыщение канала в пиковые часы. Решение: горизонтальное масштабирование через добавление нод с гигабитным каналом.

Цели:
1. Горизонтальное масштабирование: добавление нод без изменения клиентских конфигов
2. Load balancing: новые подключения — на наименее нагруженную ноду
3. Automatic failover: при падении ноды клиенты переходят на живые ноды
4. Единая панель управления для всех нод
5. Чистый upstream merge: файлы GubernievS/AntiZapret-VPN не трогаем

---

## Архитектурные решения

### AWG — не отдельный сервер

Подтверждено на живой ноде: AmneziaWG реализован через **iptables REDIRECT**:
```
udp dpt:52443 → redir ports 51443
udp dpt:52080 → redir ports 51080
```
Сервер — стандартный `wg-quick` (не `awg-quick`). AWG-обфускация — только на стороне клиента. Параметры `H1=1, H2=2, H3=3, H4=4` в клиентском шаблоне совпадают со стандартными WireGuard magic headers → пакеты совместимы со стандартным WG. Значение `I1` — хардкодено в шаблоне, одинаково для всех установок.

**Следствие:** `wg_file_state` управляет ровно двумя серверными конфигами: `antizapret.conf` (51443) и `vpn.conf` (51080). Отдельных AWG-конфигов нет.

### nginx UDP proxy: least_conn

`least_conn` для UDP stream поддерживается в OSS nginx. Каждая WireGuard-сессия = nginx UDP-сессия (поддерживается PersistentKeepalive=15s до proxy_timeout). `least_conn` направляет новые сессии на ноду с наименьшим числом активных.

Отказ от `hash $remote_addr consistent`: stickiness не нужна, т.к. все ноды имеют **одинаковый server keypair** и **идентичный peer list**. Любая нода обслуживает любого клиента.

### Control-plane в России — overhead незначим

Трафик: клиент(RU) → nginx/CP(RU) +5ms → нода(FI) +70ms → интернет.  
Доминирующий хоп — трансграничный RU↔FI. Intra-Russia хоп через control-plane (~5-10ms) незначим.  
Ширина канала control-plane должна быть достаточной для суммарного VPN-трафика всех нод.

### AntiZapret-логика остаётся на нодах

DNS (knot-resolver), iptables ANTIZAPRET-MAPPING, doall.sh/parse.sh **должны работать на финских нодах**: DNS-резолвинг из РФ вернёт заблокированные адреса. Ноды нельзя упростить до "дumb exit nodes".

---

## Топология

```
┌─────────────────────────────────────────────────────┐
│  Control-plane (Россия, широкий канал)              │
│                                                     │
│  nginx (native, рекомендуется)                      │
│    stream{} UDP 51080/51443/52080/52443             │
│      └─→ least_conn + passive health checks         │
│    http{}  443 → corpweb-backend:8000               │
│      /api/v1/agent/events → proxy_buffering off     │
│                                                     │
│  corpweb-backend (FastAPI, systemd или docker)      │
│  PostgreSQL (systemd или docker)                    │
└──────────────────┬──────────────────────────────────┘
                   │ HTTPS (agent API, bearer token)
                   │ + UDP proxy (VPN трафик)
       ┌───────────┴───────────┐
       ▼                       ▼
┌─────────────┐         ┌─────────────┐
│ wgfi2 (FI)  │         │ nodeB (FI)  │  ...
│             │         │  1 Gbit/s   │
│ upstream AZ │         │ upstream AZ │
│ sync-agent  │         │ sync-agent  │
└─────────────┘         └─────────────┘
```

---

## Схема БД

Три новые таблицы добавляются через alembic-миграцию. Существующие таблицы не меняются.

```sql
CREATE TABLE wg_file_state (
    path        TEXT PRIMARY KEY,
    content     BYTEA       NOT NULL,
    sha256      TEXT        NOT NULL,
    size_bytes  INTEGER     NOT NULL,
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_by  TEXT        NOT NULL
);

CREATE TABLE wg_server_keys (
    iface       TEXT PRIMARY KEY,   -- 'antizapret' | 'vpn'
    private_key TEXT NOT NULL,
    public_key  TEXT NOT NULL,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE nodes (
    id           SERIAL PRIMARY KEY,
    hostname     TEXT UNIQUE NOT NULL,
    private_ip   TEXT NOT NULL,
    enroll_token TEXT UNIQUE NOT NULL,
    last_seen    TIMESTAMPTZ,
    health       TEXT,              -- 'ok'|'degraded'|'down'|NULL
    applied_sha  JSONB,             -- {path: sha256, ...}
    metrics      JSONB,             -- {active_peers_antizapret: N, rx_bytes_per_sec: N, ...}
    created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- NOTIFY при изменении любого файла
CREATE OR REPLACE FUNCTION notify_wg_file_changed() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
    PERFORM pg_notify('wg_file_state_changed', NEW.path);
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_wg_file_changed
AFTER INSERT OR UPDATE ON wg_file_state
FOR EACH ROW EXECUTE FUNCTION notify_wg_file_changed();
```

---

## Управляемые файлы (wg_file_state)

12 файлов. Агент применяет при каждом изменении:

| Путь | Hook на ноде |
|---|---|
| `/etc/wireguard/antizapret.conf` | `wg syncconf antizapret <(wg-quick strip antizapret)` |
| `/etc/wireguard/vpn.conf` | `wg syncconf vpn <(wg-quick strip vpn)` |
| `/root/antizapret/setup` | — |
| `/root/antizapret/config/include-hosts.txt` | `doall.sh` (debounce 5s) |
| `/root/antizapret/config/exclude-hosts.txt` | `doall.sh` (debounce 5s) |
| `/root/antizapret/config/include-ips.txt` | `doall.sh` (debounce 5s) |
| `/root/antizapret/config/exclude-ips.txt` | `doall.sh` (debounce 5s) |
| `/root/antizapret/config/allow-ips.txt` | `doall.sh` (debounce 5s) |
| `/root/antizapret/config/forward-ips.txt` | `doall.sh` (debounce 5s) |
| `/root/antizapret/config/include-adblock-hosts.txt` | `doall.sh` (debounce 5s) |
| `/root/antizapret/config/exclude-adblock-hosts.txt` | `doall.sh` (debounce 5s) |
| `/root/antizapret/config/remove-hosts.txt` | `doall.sh` (debounce 5s) |

Все 7 config-файлов изменения → debounced единственный запуск `doall.sh`. Это правильно: `doall.sh` запускается и при добавлении доменов через панель.

---

## Рефактор vpn_manager.py

### Удаляется (весь I/O и subprocess)
- `_run_script()` — вызовы `client.sh`
- `_apply_wg_config()` — `wg syncconf` локально
- `_remove_wg_peer()` — `wg set peer remove` локально
- `_find_server_configs()` — glob по `/etc/wireguard/`

### Переносится без изменений (чистые функции → wg_templates.py)
- `_reverse_key()` — base64→bytes[::-1]→base64, self-inverse
- `_reverse_peer_keys()` — находит peer-блок по маркеру `# Client = <name>`, реверсит ключи

### Новый wg_templates.py (только pure functions, no I/O)
```python
def reverse_key(key: str) -> str
def reverse_peer_keys(content: str, name: str) -> str
def parse_peers(content: str) -> list[Peer]
def render_server_conf(iface, peers, server_privkey, address) -> str
def render_client_conf(peer, iface, server_pubkey, endpoint, flavor) -> str
def next_free_ip(peers: list[Peer], subnet: str) -> str
```

### Новый WgBlobStore (единственный класс с DB I/O)
```python
async def get(path: str) -> bytes | None
async def put(path: str, content: bytes, by: str) -> None
    # вычисляет sha256/size, UPSERT → триггер шлёт NOTIFY автоматически
async def get_all_paths() -> dict[str, str]   # path → sha256
```

### Новый интерфейс vpn_manager (async, DB-backed)
```python
async def bootstrap(db) -> None           # идемпотентно: keypair + пустые блобы
async def add_peer(db, name: str) -> PeerInfo
    # advisory lock → читает blob → parse → next_free_ip → render → put
async def delete_peer(db, name: str) -> None
async def disable_peer(db, name: str) -> None   # reverse_peer_keys → put
async def enable_peer(db, name: str) -> None    # reverse_peer_keys → put
async def list_peers(db) -> list[PeerInfo]
async def get_client_conf(db, name, flavor) -> str   # render in-memory
```

**Существующие API-endpoints панели не меняются.** Фронт для клиентов переделывать не нужно.

---

## Agent API

Все endpoints (кроме `install.sh`) требуют `Authorization: Bearer <enroll_token>`.

| Method | Path | Описание |
|---|---|---|
| `GET` | `/api/v1/agent/install.sh?token=T` | Рендерит bash-скрипт с вшитым токеном. Одноразовый. |
| `POST` | `/api/v1/agent/register` | `{hostname, private_ip}` → `{node_id, wg_server_keys}`. 409 если повторно. |
| `GET` | `/api/v1/agent/file?path=P` | `{content: base64, sha256, updated_at}` |
| `GET` | `/api/v1/agent/events` | SSE. `data: {"path": "..."}` на NOTIFY. Keepalive-comment каждые 15s. |
| `POST` | `/api/v1/agent/heartbeat` | `{applied_sha, health, metrics}` → UPDATE nodes |
| `POST` | `/api/v1/agent/drain` | Пауза apply на ноде, TTL 10 мин. |

SSE реализован через asyncpg `add_listener` + `asyncio.Queue` + FastAPI `StreamingResponse`.

---

## sync-agent

Файл: `agent/corpweb_sync_agent.py`, ~200 строк. Зависимости: stdlib + `requests`.

Конфиг `/etc/corpweb-sync-agent.env`:
```
CONTROL_PLANE_URL=https://panel.example.com
AGENT_TOKEN=<bearer>
AGENT_HOSTNAME=<hostname>
```

Главный цикл:
```
register_if_needed()
  → POST /register → получает wg_server_keys
  → пишет /etc/wireguard/key и key.pub
  → systemctl restart wg-quick@antizapret wg-quick@vpn

while True:
    startup_reconcile()     # все 12 файлов, sha256-сравнение перед записью
    stream_events()         # SSE loop + heartbeat каждые 30s
  except ConnectionError:
    sleep(1) → reconnect
```

`apply_path(path)`:
1. GET `/api/v1/agent/file?path=...`
2. Если sha256 совпадает → no-op
3. `write_atomic(path, content)` — через tmpfile + `os.replace()`
4. Запустить hook или поставить в debounce-очередь для `doall.sh`

Heartbeat body:
```json
{
  "applied_sha": {"/etc/wireguard/antizapret.conf": "abc123..."},
  "health": "ok",
  "metrics": {
    "active_peers_antizapret": 12,
    "active_peers_vpn": 8,
    "rx_bytes_per_sec": 1048576,
    "tx_bytes_per_sec": 2097152
  }
}
```

Метрики: `active_peers` читаются из `wg show <iface> latest-handshakes` (пиры с handshake < 3 мин). `rx/tx_bytes_per_sec` — дифференциал из `/proc/net/dev`.

---

## Новый раздел фронта: Nodes

Новая вкладка в навигации. Существующие разделы не трогаются.

**Страница `/nodes`:** таблица нод с hostname, health (цветовой индикатор), active peers, last seen. Кнопки: Details, Drain.

**Modal "Add Node":** трёхшаговый:
1. Ввод hostname + node IP (IP для nginx upstream)
2. Инструкция: команды step1 (setup.sh) и step2 (one-liner curl) с Copy-кнопками, поллинг статуса ноды каждые 3s
3. После `health=ok`: подтверждение + напоминание добавить IP в nginx.conf

**Страница `/nodes/{id}`:** детали по 12 файлам (в sync / отстаёт), метрики, кнопка Drain с таймером.

**Новые компоненты:** `NodesList`, `AddNodeModal`, `NodeDetail`, новые функции в `src/api/`.

---

## nginx.conf (control-plane)

```nginx
stream {
    upstream wg_antizapret {
        least_conn;
        server NODE_A_IP:51443 max_fails=3 fail_timeout=10s;
        server NODE_B_IP:51443 max_fails=3 fail_timeout=10s;
    }
    upstream wg_vpn {
        least_conn;
        server NODE_A_IP:51080 max_fails=3 fail_timeout=10s;
        server NODE_B_IP:51080 max_fails=3 fail_timeout=10s;
    }
    upstream awg_antizapret {
        least_conn;
        server NODE_A_IP:52443 max_fails=3 fail_timeout=10s;
        server NODE_B_IP:52443 max_fails=3 fail_timeout=10s;
    }
    upstream awg_vpn {
        least_conn;
        server NODE_A_IP:52080 max_fails=3 fail_timeout=10s;
        server NODE_B_IP:52080 max_fails=3 fail_timeout=10s;
    }

    server { listen 51443 udp reuseport; proxy_pass wg_antizapret;   proxy_timeout 10m; proxy_responses 0; }
    server { listen 51080 udp reuseport; proxy_pass wg_vpn;          proxy_timeout 10m; proxy_responses 0; }
    server { listen 52443 udp reuseport; proxy_pass awg_antizapret;  proxy_timeout 10m; proxy_responses 0; }
    server { listen 52080 udp reuseport; proxy_pass awg_vpn;         proxy_timeout 10m; proxy_responses 0; }
}

http {
    upstream corpweb_backend { server 127.0.0.1:8000; keepalive 16; }

    server {
        listen 443 ssl http2;
        server_name panel.example.com;
        ssl_certificate     /etc/nginx/ssl/panel.crt;
        ssl_certificate_key /etc/nginx/ssl/panel.key;

        location / {
            proxy_pass http://corpweb_backend;
            proxy_http_version 1.1;
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
        }

        # SSE для agent events: без буферизации, долгий таймаут
        location /api/v1/agent/events {
            proxy_pass http://corpweb_backend;
            proxy_http_version 1.1;
            proxy_read_timeout 24h;
            proxy_buffering off;
            proxy_cache off;
            proxy_set_header Connection '';
            chunked_transfer_encoding on;
        }
    }
    server { listen 80; return 301 https://$host$request_uri; }
}
```

В v1 nginx.conf правится вручную при добавлении ноды + `nginx -s reload`. Автогенерация из таблицы `nodes` — v2.

---

## Установка control-plane (два режима)

`control-plane/install.sh` спрашивает в начале: `[1] Native  [2] Docker`

**Native (рекомендуется для production):**
- `apt install postgresql nginx python3 certbot`
- Создаёт БД и пользователя PostgreSQL
- Копирует `corpweb-backend` как systemd-сервис (uvicorn)
- `certbot --nginx -d panel.example.com`
- Устанавливает nginx.conf в `/etc/nginx/`
- `systemctl enable --now nginx corpweb-backend postgresql`

**Docker:**
- `apt install docker.io docker-compose-plugin`
- `certbot standalone` (до старта nginx в docker)
- `docker compose up -d`

**Общее для обоих режимов:**
```bash
alembic upgrade head
python3 -m app.bootstrap   # vpn_manager.bootstrap()
```

`vpn_manager.bootstrap()` (идемпотентно):
- Если `wg_server_keys` пуста → генерит WG keypair для `antizapret` и `vpn`
- Если `wg_file_state` пуста → создаёт пустые `antizapret.conf`/`vpn.conf` + дефолтные config-файлы

---

## Миграция wgfi2 (сценарий A+C)

```
1. Поднять control-plane (install.sh)
2. POST /api/v1/admin/import-wgfiles  (multipart upload)
     Админ вручную копирует с wgfi2:
       scp root@wgfi2:/etc/wireguard/antizapret.conf .
       scp root@wgfi2:/etc/wireguard/vpn.conf .
       scp root@wgfi2:/etc/wireguard/key .
       scp -r root@wgfi2:/root/antizapret/config .
     Загружает эти файлы через форму в панели.
     Backend: кладёт конфиги в wg_file_state, keypair в wg_server_keys.
   Все 509 клиентов теперь в БД.
3. Зарегистрировать wgfi2 через панель "Add Node"
     → one-liner на wgfi2 → register → получает тот же keypair → no-op
     → startup_reconcile: sha256 совпадают → ничего не пишется
4. Добавить nodeB (чистая, гигабит)
     → setup.sh интерактивно → install.sh one-liner
     → получает keypair + все 509 клиентов
5. Переключить DNS vpn.example.com → control-plane IP
6. Добавить обе ноды в nginx.conf → nginx -s reload

Rollback: DNS обратно на wgfi2 → клиенты работают напрямую как раньше
```

---

## Структура репозитория

```
CorpAdmin-AZ/
├── setup.sh, setup/, proxy.sh      ← upstream, НЕ ТРОГАЕМ
│
├── corpweb/backend/app/
│   ├── services/
│   │   ├── vpn_manager.py          ← рефактор (file I/O → DB blob)
│   │   └── wg_templates.py         ← НОВОЕ: pure functions
│   ├── api/v1/
│   │   ├── agent.py                ← НОВОЕ: agent API endpoints
│   │   └── nodes.py                ← НОВОЕ: nodes CRUD + install.sh
│   └── db/
│       ├── models/wg_file_state.py ← НОВОЕ
│       ├── models/wg_server_keys.py← НОВОЕ
│       └── models/node.py          ← НОВОЕ
│
├── corpweb/backend/alembic/versions/
│   └── xxxx_ha_tables.py           ← НОВОЕ: миграция
│
├── corpweb/frontend/src/
│   ├── pages/Nodes.tsx             ← НОВОЕ
│   ├── components/AddNodeModal.tsx ← НОВОЕ
│   ├── components/NodeDetail.tsx   ← НОВОЕ
│   └── api/nodes.ts                ← НОВОЕ
│
├── agent/
│   ├── corpweb_sync_agent.py       ← НОВОЕ (~200 строк)
│   ├── corpweb-sync-agent.service  ← НОВОЕ
│   ├── install.sh                  ← НОВОЕ
│   ├── check.sh                    ← НОВОЕ
│   └── README.md                   ← НОВОЕ
│
├── control-plane/
│   ├── nginx.conf                  ← НОВОЕ
│   ├── docker-compose.yml          ← НОВОЕ
│   ├── install.sh                  ← НОВОЕ (native + docker)
│   └── README.md                   ← НОВОЕ
│
└── docs/
    ├── HA-SETUP.md                 ← НОВОЕ
    ├── UPSTREAM-SYNC.md            ← НОВОЕ
    └── ADD-NODE.md                 ← НОВОЕ
```

---

## Ограничения v1

- **Control-plane — SPOF** для панели и LB. Существующие VPN-сессии продолжают работать на нодах при падении CP. HA control-plane — v2.
- **nginx.conf — статический**: ноды добавляются вручную + `nginx -s reload`. Автогенерация из `nodes` — v2.
- **Серверные keypair'ы в plain-text** в `wg_server_keys`. Encryption at rest — v2.
- **Onboarding — два шага**: `setup.sh` интерактивно + one-liner. Полная автоматизация — v2.
- **OpenVPN не балансируется**: остаётся на каждой ноде независимо.
- **Import-wgfiles**: миграция через ручной `scp` + upload в панель, не через SSH из бэкенда. Безопаснее (backend не держит SSH credentials к нодам).
- **`WIREGUARD_HOST` в файле `setup`**: при импорте с wgfi2 значение `WIREGUARD_HOST=wgfi2.p4i.ru` сохраняется as-is. Клиентские конфиги генерируются бэкендом in-memory с правильным LB-hostname — `setup`-файл не используется для этого. Если после перехода запустить `client.sh` вручную на ноде, он создаст конфиги с устаревшим hostname. Это acceptable: ручные операции на ноде помечаются как debug/fallback.

---

## Порядок реализации

1. Alembic-миграция + SQLAlchemy-модели (3 таблицы + trigger)
2. `wg_templates.py` — pure functions + unit tests (TDD)
3. `WgBlobStore` — DB layer + unit tests
4. Рефактор `vpn_manager.py` — существующие endpoint-тесты должны пройти
5. Agent API (`agent.py`, `nodes.py`) + integration tests
6. `agent/corpweb_sync_agent.py` + `install.sh` + `check.sh`
7. Frontend: компоненты Nodes + AddNodeModal + NodeDetail
8. `control-plane/install.sh` (native + docker) + `nginx.conf`
9. Import-wgfiles endpoint + форма в панели для миграции wgfi2
10. `docs/` (HA-SETUP, UPSTREAM-SYNC, ADD-NODE)
