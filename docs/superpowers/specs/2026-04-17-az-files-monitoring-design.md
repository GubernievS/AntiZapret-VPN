# AZ Files Expansion + Monitoring Sort — Design Spec

**Date:** 2026-04-17
**Status:** Approved
**Scope:** Расширение редактируемых файлов AZ с 3 до 9, добавление 6 настроек в Настройки AZ, сортировка в мониторинге, верификация сохранения

---

## 1. Расширение EDITABLE_FILES (с 3 до 9)

### Новые файлы

| Ключ | Путь | Описание в UI |
|------|------|---------------|
| `exclude_ips` | `/root/antizapret/config/exclude-ips.txt` | Исключить IP из VPN — IP-адреса и подсети которые НЕ будут маршрутизироваться через VPN |
| `allow_ips` | `/root/antizapret/config/allow-ips.txt` | Разрешить прямой доступ — IP-адреса исключённые из защиты от атак (allowlist) |
| `forward_ips` | `/root/antizapret/config/forward-ips.txt` | Прямая маршрутизация IP — IP-адреса для прямой маршрутизации без проксирования |
| `include_adblock_hosts` | `/root/antizapret/config/include-adblock-hosts.txt` | Добавить в блокировку рекламы — домены для дополнительной блокировки |
| `exclude_adblock_hosts` | `/root/antizapret/config/exclude-adblock-hosts.txt` | Исключить из блокировки рекламы — домены исключённые из блокировки |
| `remove_hosts` | `/root/antizapret/config/remove-hosts.txt` | Исключить домены из обработки — домены полностью исключённые из обработки AntiZapret |

### Существующие (без изменений)

| Ключ | Путь | Описание |
|------|------|----------|
| `include_hosts` | `/root/antizapret/config/include-hosts.txt` | Добавить домены для маршрутизации через AntiZapret VPN |
| `exclude_hosts` | `/root/antizapret/config/exclude-hosts.txt` | Исключить домены из маршрутизации через AntiZapret VPN |
| `include_ips` | `/root/antizapret/config/include-ips.txt` | Добавить IP-адреса для маршрутизации через AntiZapret VPN |

### Изменения

- `antizapret.py`: добавить 6 записей в `EDITABLE_FILES`
- `AdminFilesPage.tsx`: добавить 6 табов с описаниями
- Механизм сохранения тот же: WgBlobStore → pg_notify → sync-agent → debounced doall.sh

---

## 2. Настройки AZ — 6 новых параметров

### Новые boolean settings

| Ключ | Описание | По умолчанию |
|------|----------|-------------|
| `ANTIZAPRET_DNS` | DNS-сервер для AntiZapret-режима. Включён = knot-resolver на ноде (резолвит заблокированные домены). Выключен = системный DNS | 1 (вкл) |
| `VPN_DNS` | DNS-сервер для VPN-режима (весь трафик). Включён = knot-resolver. Выключен = системный DNS | 1 (вкл) |
| `ALTERNATIVE_CLIENT_IP` | Альтернативные подсети для клиентов. Для случаев конфликта с локальной сетью клиента | n |
| `ALTERNATIVE_FAKE_IP` | Альтернативные фейковые IP для DNS-резолвинга заблокированных доменов | n |
| `CLIENT_ISOLATION` | Изоляция клиентов друг от друга. Вкл = клиенты VPN не видят друг друга. Выкл = могут общаться через VPN | y |

### Новый string setting

| Ключ | Описание |
|------|----------|
| `WARP_OUTBOUND` | Маршрутизация исходящего трафика ноды через Cloudflare WARP. Пусто = выключен. Значение = имя интерфейса WARP |

### Примечание по ANTIZAPRET_DNS / VPN_DNS

В setup-файле они хранятся как `1`/`0`, не `y`/`n`. В UI показываем как toggle. При сохранении: toggle on → `1`, toggle off → `0`. Добавить в отдельный список `NUMERIC_BOOLEAN_SETTINGS` чтобы не путать с обычными `y`/`n`.

### Изменения

- `antizapret.py`: добавить в `BOOLEAN_SETTINGS` + `NUMERIC_BOOLEAN_SETTINGS` + `STRING_SETTINGS`
- `AdminAntizapretPage.tsx`: добавить 6 новых полей с описаниями

---

## 3. Мониторинг — сортировка таблицы

### Требования

- По умолчанию: сортировка по RX (скачанные данные) по убыванию
- Клик на заголовок колонки → toggle asc/desc
- Индикатор направления сортировки (стрелка ↑/↓)
- Сортируемые колонки: Клиент, Нода, Интерфейс, Хендшейк, RX, TX

### Изменения

- `MonitoringPage.tsx`: state `sortField` + `sortDir`, onClick на заголовках, `useMemo` для сортированного списка

---

## 4. Верификация сохранения

### Тесты (backend)

- `test_antizapret_blob.py`: добавить тесты для ВСЕХ 9 файлов — записать через AntizapretService, прочитать через WgBlobStore, проверить побайтовое совпадение
- Тест roundtrip: сохранить файл с trailing newlines, пустыми строками, unicode → прочитать → сравнить
- Тест новых настроек: ANTIZAPRET_DNS=1 → update → read → verify `1` (не `y`)
- Тест WARP_OUTBOUND: string setting → save → read → verify

### E2E проверка при деплое

- После деплоя: изменить файл через панель → проверить в БД → проверить на ноде (ssh) → проверить что doall отработал
