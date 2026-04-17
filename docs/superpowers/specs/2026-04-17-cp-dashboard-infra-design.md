# CP Dashboard & Infrastructure Improvements — Design Spec

**Date:** 2026-04-17
**Status:** Approved
**Scope:** Admin Dashboard, мониторинг из метрик нод, AZ-сервис через БД, DNAT-редактор, настройка нод через агента

---

## Контекст

HA-архитектура развёрнута: CP (wgfi2.p4i.ru, 92.118.85.140) + 2 ноды (wgfi2-ssh, wgfi3). VPN-трафик балансируется через iptables DNAT. Sync-agent на нодах синхронизирует конфиги из БД.

Проблемы:
1. Мониторинг вызывает `wg show` локально на CP — не работает (WG на нодах, не на CP)
2. AZ-сервис читает/пишет файлы на диск CP — должен работать через WgBlobStore → агенты
3. DNAT-правила управляются вручную через SSH
4. Нет admin Dashboard с аналитикой нод
5. Настройка ноды (keypair, подсети) — ручная

---

## 1. Расширенные метрики агента (heartbeat v2)

### Новый формат heartbeat

```json
{
  "applied_sha": {"/etc/wireguard/antizapret.conf": "sha256...", ...},
  "health": "ok",
  "metrics": {
    "active_peers_antizapret": 78,
    "active_peers_vpn": 15,
    "rx_bytes_per_sec": 12345678,
    "tx_bytes_per_sec": 23456789
  },
  "peers": [
    {
      "public_key": "abc123...",
      "allowed_ips": "10.29.8.3/32",
      "endpoint": "92.118.85.140:40583",
      "latest_handshake": 1776359263,
      "rx_bytes": 123456,
      "tx_bytes": 654321
    }
  ]
}
```

### Изменения

- `metrics` добавляет `rx_bytes_per_sec`, `tx_bytes_per_sec` — дифференциал из `/proc/net/dev` за интервал между heartbeat-ами
- Новое поле `peers` — полный список пиров из `wg show <iface> dump`
- Хранение: `peers` в отдельном поле `nodes.peers_snapshot` (JSONB) — не раздувает основную запись `metrics`

### Определение "активный пир"

Handshake age < 30с (2 × PersistentKeepalive=15с). Единое определение в агенте и API.

### Нагрузка

- 517 пиров × 120 байт ≈ 62 КБ JSON / heartbeat
- С gzip: ~10 КБ каждые 30с на ноду
- 10 нод = 100 КБ/30с — ничтожная нагрузка

### Изменения в DB

```sql
ALTER TABLE nodes ADD COLUMN peers_snapshot JSONB;
```

---

## 2. Admin Dashboard

### Доступ

- Admin: стартовая страница `/admin/dashboard`
- Обычный пользователь: интерфейс не меняется, стартовая `/` (Мои конфиги)

### Виджеты

**Карточки нод** — горизонтальный ряд:
- Hostname, health (зелёный/жёлтый/красный индикатор)
- Active peers: `78 AZ / 15 VPN`
- Трафик: `↓ 12 Мбит/с ↑ 23 Мбит/с`
- Sync status: галочка или предупреждение (applied_sha vs wg_file_state.sha256)
- Last seen: `5с назад`

**Общая статистика** — 3 числа:
- Всего активных клиентов (сумма active peers по нодам)
- Всего конфигов (count vpn_configs)
- Всего пользователей (count users)

**Распределение нагрузки** — горизонтальная полоса:
- Каждая нода = цветной сегмент, ширина ∝ доля active peers
- Подписи: `wgfi2-ssh: 78 (92%) | wgfi3: 6 (8%)`

**Последние события** — 10-20 записей:
- Агрегируем из имеющихся данных: heartbeat transitions (нода ok→down), vpn_configs.created_at/updated_at, wg_file_state.updated_at
- Не требует отдельной таблицы event_log

### API

`GET /api/v1/admin/dashboard` — собирает из `nodes`, `vpn_configs`, `users`, `wg_file_state`. Автообновление на фронте каждые 30с.

---

## 3. Мониторинг (данные от агентов)

### Замена

Полностью переписать `monitoring.py`. Убрать:
- Локальный `wg show` парсинг
- OpenVPN мониторинг
- Фейковые показатели трафика

### Активные подключения

Таблица из `nodes.peers_snapshot`:
- Колонки: Клиент (имя), Нода, IP клиента (endpoint), AZ/VPN, Handshake age, RX/TX bytes
- Только активные (handshake < 30с)
- Фильтр по ноде
- Резолвинг имени: `allowed_ips` → `vpn_configs.config_metadata.vpn_ip` → `vpn_configs.client_name` → `users.username`
- Обновление каждые 30с

### Трафик по нодам

Текущая скорость из `nodes.metrics.rx/tx_bytes_per_sec`. Без исторического графика (нет time-series хранилища).

---

## 4. AntizapretService → WgBlobStore

### Чтение файлов

`GET /antizapret/files/{type}` — читает из `WgBlobStore.get(path)` вместо диска.

### Сохранение файлов

`PUT /antizapret/files/{type}`:
1. Пишет в `WgBlobStore.put(path, content)` → pg_notify → агенты
2. Фронт подключается к apply-status SSE
3. Показывает: "Применено на 2/2 нод" или "Применено на 1/2 — wgfi3 не отвечает"
4. Агенты при получении config-файлов запускают debounced `doall.sh` (5с) — уже реализовано

### Настройки (setup файл)

- `GET /antizapret/settings` — парсит `/root/antizapret/setup` из WgBlobStore
- `PATCH /antizapret/settings` — обновляет setup в WgBlobStore → агенты получают

### Кнопка "Применить"

Убирается. Сохранение = запись в БД → агенты автоматически применяют. Фронт показывает apply-status по нодам.

### Целостность файлов

Запись и чтение через WgBlobStore побайтово идентичны (LargeBinary). Тесты должны проверять: trailing newlines, пустые строки, unicode, BOM.

---

## 5. DNAT-редактор

### Расположение

Страница "Ноды" — секция "Балансировка" под таблицей нод.

### UI

Таблица:
| Нода | IP | Health | Вес | Вкл/Выкл |
|------|-----|--------|-----|----------|
| wgfi2-ssh.p4i.ru | 89.125.39.44 | ok | `[input: 50%]` | `[toggle]` |
| wgfi3.p4i.ru | 89.125.198.77 | ok | `[input: 50%]` | `[toggle]` |

- Инпуты веса (%) — сумма всегда = 100%, фронт валидирует
- Тогл вкл/выкл — убирает ноду из балансировки (вес перераспределяется)
- Кнопка "Сохранить" — применяет iptables + persistent save
- После сохранения — показывает реальное состояние (backend парсит `iptables -t nat -L`)

### Валидация

- Веса в сумме = 100% (фронт + backend)
- Хотя бы одна нода включена
- Backend проверяет `iptables` синтаксис перед применением: генерирует правила → `iptables-restore --test` → если ОК → применяет → `netfilter-persistent save`

### API

`GET /api/v1/nodes/balancer`:
- Читает реальные iptables правила (`iptables -t nat -L PREROUTING -n`)
- Парсит probability → пересчитывает в веса
- Возвращает `{nodes: [{hostname, ip, weight, enabled}]}`

`PUT /api/v1/nodes/balancer`:
- Принимает `{nodes: [{ip, weight, enabled}]}`
- Валидация: sum(weight) = 100, min 1 enabled
- Генерирует iptables правила (для всех 4 портов: 51080, 51443, 52080, 52443)
- Применяет: flush PREROUTING → add rules → `netfilter-persistent save`
- Возвращает реальное состояние после применения

### Пересчёт весов в probability

iptables `--probability` задаёт шанс совпадения для текущего правила. Для N нод с весами w1..wN:
- Правило 1: probability = w1 / (w1+w2+...+wN)
- Правило 2: probability = w2 / (w2+w3+...+wN)
- Правило N: без probability (fallback, ловит остаток)

Пример: 3 ноды 50/30/20 → probability 0.5, 0.6, fallback.

### Абстракция

Модуль `balancer.py` — генерация/парсинг/применение iptables правил. Позже можно заменить на IPVS без изменения API/UI.

### При добавлении ноды

AddNodeModal step 3: вместо nginx-инструкций — "Добавить в балансировщик с равным весом?" → кнопка → редирект на секцию балансировки.

### Безопасность iptables

- Перед каждым применением: `iptables-restore --test` с полным набором правил
- При ошибке: не применять, вернуть ошибку в UI
- После каждого сохранения: `netfilter-persistent save` для персистентности
- GET endpoint всегда возвращает реальное состояние из `iptables`, не кэш

---

## 6. Настройка ноды через агента

### Расширенный ответ `/agent/register`

```json
{
  "node_id": 3,
  "wg_server_keys": {
    "antizapret": {"private_key": "...", "public_key": "..."},
    "vpn": {"private_key": "...", "public_key": "..."}
  },
  "wg_config": {
    "antizapret_address": "10.29.8.1/21",
    "antizapret_listen_port": 51443,
    "vpn_address": "10.28.8.1/21",
    "vpn_listen_port": 51080,
    "mtu": 1420
  }
}
```

### Агент при регистрации

1. Получает keypair → пишет `/etc/wireguard/key` и per-iface файлы
2. Получает `wg_config` → патчит `[Interface]` секцию в antizapret.conf и vpn.conf (Address, PrivateKey, ListenPort, MTU)
3. Рестартит wg-quick если что-то изменилось
4. Далее reconcile подтянет полные конфиги с пирами

### Параметры `wg_config`

Хранятся в `system_settings` или отдельной таблице `wg_network_config`. Единый источник правды для всех нод.

### Ограничения

AZ установка (setup.sh) остаётся ручным шагом. Агент настраивает только WG поверх уже установленного AZ.

---

## Порядок реализации

1. Alembic: `nodes.peers_snapshot` (JSONB)
2. Heartbeat v2 в агенте (peers + rx/tx)
3. `balancer.py` + API endpoints + iptables абстракция
4. `antizapret_service` → WgBlobStore + apply-status
5. `monitoring.py` переписать на данные из nodes
6. Admin Dashboard (backend endpoint + frontend)
7. Мониторинг frontend (новая таблица подключений)
8. DNAT-редактор frontend (секция балансировки)
9. AddNodeModal step 3 — новая инструкция
10. Расширенный `/agent/register` (wg_config)
