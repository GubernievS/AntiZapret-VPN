# WireGuard Backup Ports — Design Spec

**Date:** 2026-04-17
**Status:** Approved
**Scope:** Добавление backup-портов 540/580 для обхода блокировок провайдера

---

## Контекст

`WIREGUARD_BACKUP` — фича upstream AntiZapret-VPN. При включении на ноде `up.sh` добавляет iptables REDIRECT:
- `udp/540` → `51443` (WG antizapret)
- `udp/580` → `51080` (WG vpn)

Клиенты могут использовать порты 540/580 вместо 52443/52080 когда провайдер блокирует основные.

**Ключевой факт:** серверный конфиг НЕ содержит информации о портах клиентов. Клиент выбирает порт через `Endpoint` в своём конфиге. Сервер отвечает на source IP:port, не на конкретный listen port.

---

## Дизайн

### 1. Backend: `balancer.py`

Всегда 6 портов DNAT на нодах:
```python
DEFAULT_PORTS = [51443, 51080, 52443, 52080, 540, 580]
```

Если `WIREGUARD_BACKUP=n` на нодах — пакеты на 540/580 доходят до ноды и дропаются (нет iptables REDIRECT). Вреда нет, overhead ничтожный.

### 2. Backend: `antizapret.py`

Добавить `WIREGUARD_BACKUP` в `BOOLEAN_SETTINGS` (стандартный boolean y/n). Синхронизация на ноды идёт через уже существующий механизм:

```
Админ тогл → Save в wg_file_state.setup
  → pg_notify → SSE → агенты
  → агент пишет /root/antizapret/setup → debounced doall.sh
  → up.sh читает WIREGUARD_BACKUP=y → iptables REDIRECT
```

### 3. Backend: `wg_templates.py`

Расширить `render_client_conf`:
```python
_BACKUP_PORT_MAP = {
    "antizapret": 540,
    "vpn": 580,
}

def render_client_conf(
    peer, iface, server_pubkey, endpoint_host, flavor,
    *, allowed_ips=None, client_private_key=None,
    use_backup_port: bool = False,
):
    if use_backup_port:
        port = _BACKUP_PORT_MAP[iface]
    else:
        port = _PORT_MAP[(iface, flavor)]
    # ... остальное без изменений
```

### 4. Backend: `vpn_manager_new.py`

`get_client_conf` принимает `use_backup_port` и передаёт в `render_client_conf`.

### 5. Backend: `configs.py`

Добавить query параметр `?backup=true` в:
- `GET /configs/{id}/download?backup=true`
- `GET /configs/{id}/qr?backup=true`

При `backup=true` → `get_client_conf(..., use_backup_port=True)`.

Validation: если `WIREGUARD_BACKUP` глобально выключен, игнорировать параметр (возвращать основной порт) — чтобы не было "битых" конфигов когда админ отключил фичу.

### 6. Backend: `client-links` endpoint

Добавить в response:
```json
{
  "google_play_url": "...",
  ...
  "wireguard_backup_enabled": true
}
```

Читается из `setup` файла (`AntizapretService.get_settings()["WIREGUARD_BACKUP"] == "y"`).

### 7. Frontend: AdminAntizapretPage

Новая секция "Резервные порты":
- Тогл **"WireGuard Backup (порты 540/580)"**
- Описание: *"Включает iptables REDIRECT на нодах: 540→51443, 580→51080. Пользователи смогут выбрать резервный порт при скачивании конфига."*

### 8. Frontend: NodesPage — секция Балансировка

Информационный блок:
```
Порты DNAT: 51443, 51080, 52443, 52080, 540, 580
```

### 9. Frontend: User Dashboard (ЛК)

Чекбокс **"Использовать резервный порт"** возле кнопок "Скачать" и "QR-код":
- Активен только если `wireguard_backup_enabled=true` (из client-links)
- Если выключен — disabled + tooltip "Включите WIREGUARD_BACKUP в настройках AZ"
- При чекбокс=true → `?backup=true` в query
- Не сохраняется — это ephemeral UI state (один и тот же конфиг рендерится по-разному)

### 10. Pydantic schema

Добавить `WIREGUARD_BACKUP: Optional[str]` в `AntizapretSettingsResponse`.
Добавить `wireguard_backup_enabled: bool` в client-links response schema.

### 11. Frontend type

Добавить `WIREGUARD_BACKUP: string | null` в `AntizapretSettings`.

---

## Тесты

### Backend (pytest)

- `test_render_client_conf_backup_port_antizapret` — Endpoint содержит `:540`
- `test_render_client_conf_backup_port_vpn` — Endpoint содержит `:580`
- `test_render_client_conf_default_port` — без флага основной порт
- `test_get_client_conf_backup_passthrough` — vpn_manager передаёт флаг
- `test_download_with_backup_query` — endpoint `?backup=true` возвращает конфиг с 540
- `test_download_backup_disabled_globally` — если WIREGUARD_BACKUP=n, backup=true игнорируется
- `test_balancer_always_6_ports` — `generate_iptables_rules` генерирует 6 портов (4*2=8 rules для 2 нод)
- `test_client_links_includes_backup_flag` — endpoint возвращает флаг
- `test_wireguard_backup_in_settings` — setting сохраняется как y/n

### Frontend (tsc + build)

- Тогл рендерится в AdminAntizapretPage
- Чекбокс backup порта в ЛК disabled при выключенной фиче
- Порты в инфо-блоке NodesPage — 6 штук

---

## Нагрузка / риски

- **Производительность:** 2 лишних iptables правила на CP — незаметно
- **Трафик на 540/580 когда выключено на нодах:** пакеты доходят до ноды и дропаются — один wasted round trip, не проблема
- **Совместимость:** не ломает существующие конфиги (по умолчанию используется основной порт)
- **Безопасность:** backup порты = те же ключи, та же WG аутентификация. Атаки = аналогично основным портам

---

## Миграция / деплой

Порядок:
1. Задеплоить backend + frontend на CP
2. Через панель: админ включает `WIREGUARD_BACKUP=y`
3. Автоматически через агента применяется на нодах (iptables REDIRECT)
4. Пользователи могут использовать новый чекбокс в ЛК

**Откат:** админ выключает тогл → агенты удаляют iptables REDIRECT на нодах при следующем doall.sh → backup порты перестают работать. DNAT на CP остаётся (не мешает).
