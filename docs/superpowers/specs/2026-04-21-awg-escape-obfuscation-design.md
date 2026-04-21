# AWG Strong-Obfuscation Escape Interface — Design

**Date:** 2026-04-21
**Bead:** CorpAdmin-AZ-roo (P1, epic)
**Related:** CorpAdmin-AZ-uy7 (WIREGUARD_BACKUP — previous escape pattern)

## Goal

Give ТСПУ-blocked clients an **opt-in bypass mode** that uses a second
pair of AmneziaWG interfaces on every node, with strong obfuscation
parameters (non-zero `S1`/`S2`, non-default `H1`–`H4`). The existing
plain AWG (with `S1=S2=0`, `H1-4=1..4`) shares the WireGuard handshake
signature and gets fingerprinted; escape-mode rewrites the handshake so
DPI cannot match it against any known protocol.

## Non-goals

- Per-client unique obfuscation (we keep per-iface params — per-client
  would require independent servers).
- Automatic rotation of obfuscation params (manual "Regenerate" button
  only, no cron).
- Backup ports for escape ifaces (YAGNI — escape is itself the backup).
- IPv6 support beyond what already exists.

## Top-level architecture

```
┌──────────── Control-Plane (CP) ────────────┐
│                                            │
│  AZ Settings UI ─── ESCAPE_ENABLED toggle  │
│                  │                         │
│                  ├─ balancer.apply_rules    │
│                  │    ↓                     │
│                  │  iptables DNAT:          │
│                  │    500   → node:500      │
│                  │    53443 → node:53443    │
│                  │                         │
│  wg_obfuscation_params (S1/S2/H1-H4) ────┐ │
│  wg_server_keys (+ 2 iface records) ─────┤ │
│  wg_file_state (+ 2 iface .conf blobs) ──┘ │
└────────────────────┬───────────────────────┘
                     │ SSE (sync-agent)
           ┌─────────┴──────────┐
           ▼                    ▼
     ┌───────────┐        ┌───────────┐
     │ Node      │        │ Node      │
     │ wg-quick@ │        │ wg-quick@ │
     │   antizapret        │   antizapret
     │   vpn               │   vpn
     │   antizapret_escape │   antizapret_escape (NEW)
     │   vpn_escape        │   vpn_escape        (NEW)
     └───────────┘        └───────────┘
```

## Decisions

### D1. Two escape interfaces, mirroring existing pair
- `antizapret_escape` — split-tunnel escape (10.27.8.0/21)
- `vpn_escape` — full-VPN escape (10.26.8.0/21)
- Preserves LK UX: user still chooses "AZ" or "full VPN" type, bypass
  is just a modifier, not a separate config type.

### D2. One client keypair → 4 peer records (eager, not lazy)
- `add_peer()` writes the peer into all 4 `.conf` blobs at creation time.
- Fresh installs and existing peers — a one-shot migration backfills
  escape-peer records for all existing clients.
- Space is fine: /21 per iface = 2046 usable IPs; we have ~500 clients.

### D3. Per-iface obfuscation params, per-installation random, never auto-rotated
- New DB table `wg_obfuscation_params(iface PK, jc, jmin, jmax, s1, s2, h1, h2, h3, h4, i1, created_at, updated_at)`.
- On first `ESCAPE_ENABLED=true` toggle (or via alembic data-migration
  at bootstrap), CP generates independent random sets for
  `antizapret_escape` and `vpn_escape`.
- "Regenerate obfuscation params" admin button → generates new values,
  invalidates all existing escape client configs (they must
  re-download). Confirmation modal required.
- Toggle off does **not** delete params. Re-enabling uses the stored
  ones — existing escape configs keep working.

### D4. Escape toggle scope = DNAT-only
- `ESCAPE_ENABLED` in AZ settings controls **two things**:
  1. Two new DNAT rules on CP (`500`, `53443` → nodes).
  2. Visibility of the "Обход блокировки" toggle in user LK.
- The escape ifaces on nodes are **always up** (wg-quick managed by
  sync-agent on every startup). Toggling off just removes balancer
  access — existing clients simply can't reach port 500/53443 on CP.
- Consequence: no node-side restart required when admin flips the toggle.

### D5. Ports: `500` for vpn_escape, `53443` for antizapret_escape
- `500/udp` — IKE mimicry, rarely blocked (breaks IPsec nationwide).
- `53443/udp` — pattern-continued (5x443), no particular mimicry.
- No backup pair — escape is itself the fallback.

### D6. Obfuscation params stored in server `.conf`
- `render_server_conf(iface, ...)` gains `awg_params: dict | None`.
  When non-None, adds `Jc/Jmin/Jmax/S1/S2/H1-4/I1` lines to
  `[Interface]` section.
- On nodes, `amneziawg-tools` already handles these at `wg-quick up` time.
- Same params baked into client configs via `render_client_conf()`.

### D7. Client-config rendering: new `bypass: bool` param
- `get_client_conf(db, name, flavor, endpoint_host, iface, *, bypass=False, ...)`.
- If `bypass=True`:
  - Effective iface = `{iface}_escape`
  - Endpoint port = escape port (500 or 53443)
  - AWG params loaded from `wg_obfuscation_params` for that iface
  - AllowedIPs for antizapret_escape = same split-tunnel list
- `bypass=True` **forbidden** together with `use_backup_port=True`
  (HTTP 400 on API, disabled state on UI). Escape already has its own
  dedicated port.

### D8. Frontend LK: replace amber-background checkbox with two Toggle cards
- Above the config grid, new block "Опции скачивания":
  ```
  grid grid-cols-1 sm:grid-cols-2 gap-3
    Toggle-card "Резервный порт" (when clientLinks.wireguard_backup_enabled)
    Toggle-card "Обход блокировки" (when clientLinks.escape_enabled)
  ```
- Cards use same style as config cards (`bg-white border border-gray-200 rounded-xl`).
- Each card: header + toggle + `text-xs text-gray-500` description.
- Mutual exclusion: enabling one disables the other toggle (visually
  greyed, with tooltip "Недоступно вместе с X").
- If neither flag is enabled globally — the whole block is not rendered.
- No per-config persistence — toggles reset on page reload (α from 5b).

### D9. Admin UI: new section "Обход блокировки" in AdminAntizapretPage
- Mirrors "Резервные порты" section pattern.
- Contains:
  - Toggle: `ESCAPE_ENABLED` — wires to same save+apply flow.
  - Danger button: "Перегенерировать параметры обфускации" — red,
    confirm-dialog "Это отключит всех текущих bypass-клиентов.
    Подтвердить?". Triggers POST `/api/v1/antizapret/obfuscation/regenerate`.

### D10. Agent: minimal refactor, no architecture change
- `MANAGED_FILES` grows by 2 entries:
  - `/etc/wireguard/antizapret_escape.conf` → hook `wg_antizapret_escape`
  - `/etc/wireguard/vpn_escape.conf` → hook `wg_vpn_escape`
- Hook dispatcher: new branches call `apply_wg_syncconf("antizapret_escape")`
  and `apply_wg_syncconf("vpn_escape")`.
- `register_if_needed()`: when CP returns keys for the new ifaces,
  agent writes them and runs `wg-quick@*_escape` start/restart. Code
  already loops over `keys.items()` — zero structural change, just
  new iface names appearing in the response.
- `_apply_wg_config()` gains 2 mapping entries for the escape ifaces.
- Total diff: ~40 lines.

## Data model

### New table: `wg_obfuscation_params`
```sql
CREATE TABLE wg_obfuscation_params (
    iface VARCHAR(64) PRIMARY KEY,
    jc INTEGER NOT NULL,
    jmin INTEGER NOT NULL,
    jmax INTEGER NOT NULL,
    s1 INTEGER NOT NULL,
    s2 INTEGER NOT NULL,
    h1 BIGINT NOT NULL,   -- uint32 > 4
    h2 BIGINT NOT NULL,
    h3 BIGINT NOT NULL,
    h4 BIGINT NOT NULL,
    i1 TEXT NOT NULL,
    created_at TIMESTAMP NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMP NOT NULL DEFAULT NOW()
);
```
Alembic migration also ensures rows for `antizapret_escape`/`vpn_escape`
are generated if missing at backend startup.

### Extended: `system_settings`
```sql
ALTER TABLE system_settings ADD COLUMN escape_enabled BOOLEAN NOT NULL DEFAULT FALSE;
```

### `wg_server_keys` and `wg_file_state`
No schema change — just new rows (2 keypairs + 2 `.conf` blobs)
created by `VpnManager.bootstrap()`.

## Backend changes (in order)

1. **`balancer.py`** — escape ports **not** in `DEFAULT_PORTS` by
   default. Instead `get_active_ports(db)` reads `system_settings.escape_enabled`
   and appends `500, 53443` only when True. `ensure_ports_reconciled` and
   `apply_rules` call this.
2. **`wg_templates.py`** — extend `_PORT_MAP`, add `_ESCAPE_PORT_MAP`,
   extend `render_server_conf` with `awg_params`, extend
   `render_client_conf` with `bypass=False`.
3. **`vpn_manager_new.py`** — extend `_IFACE_CONFIG` to 4 ifaces,
   `bootstrap()` handles new ones, `add_peer`/`delete_peer`/`_toggle_peer`
   already loop — no changes. `get_client_conf` gains `bypass` kwarg.
4. **`antizapret.py` service** — no change (escape not stored in
   /root/antizapret/setup); `SystemSettings.escape_enabled` handled via
   existing `system_settings` endpoints.
5. **New: `obfuscation.py` service** — generates/loads/regenerates
   obfuscation params.
6. **API routers:**
   - `POST /api/v1/antizapret/obfuscation/regenerate` (admin only)
   - `GET /api/v1/configs/client-links` → add `escape_enabled` flag
   - `GET /api/v1/configs/{id}/download` / `/qr` → add `bypass=true` query;
     403 if `escape_enabled=False`, 400 if `bypass+backup` both true.
   - `GET/PATCH /api/v1/admin/system-settings` → expose `escape_enabled`.
7. **Lifespan startup** — ensure `wg_obfuscation_params` rows exist
   (bootstrap-style init, after `init_db`).

## Frontend changes

1. **`api/configs.ts`** — `ClientLinks` gains `escape_enabled?: boolean`.
   `download(id, { backup, bypass })`, `getQR(id, { backup, bypass })`.
2. **`api/antizapret.ts`** — `AntizapretSettings` gains `ESCAPE_ENABLED`.
3. **`api/admin.ts`** or similar — new `obfuscation.regenerate()` call.
4. **`components/Toggle.tsx`** — extract existing AdminAntizapret toggle
   into a shared component.
5. **`pages/DashboardPage.tsx`** — remove amber checkbox, add new card
   grid "Опции скачивания". Pass `{ backup, bypass }` to downloads.
6. **`pages/AdminAntizapretPage.tsx`** — new "Обход блокировки" section
   with toggle + regenerate button + confirm dialog.

## Agent changes

1. **`MANAGED_FILES`** — +2 entries with hooks `wg_antizapret_escape`, `wg_vpn_escape`.
2. **`apply_path` dispatch** — +2 branches.
3. **`_apply_wg_config`** — +2 iface entries.
4. **`register_if_needed`** — no change (already loops).

## Node-side setup

- `wg-quick@antizapret_escape.service` and `wg-quick@vpn_escape.service`
  — standard systemd template; activated by agent after first key write.
- `up.sh` upstream script is **not modified**. No REDIRECT needed —
  escape ifaces listen directly on 500/53443.
- `amneziawg-tools` is already installed on nodes (required for
  existing AWG ifaces).

## CP install-script changes

- `install-native.sh` — no change. Bootstrap in lifespan handles the
  new tables on first startup.

## Migration / rollout

1. Deploy backend with new migrations (creates `wg_obfuscation_params`,
   adds `escape_enabled` column, triggers bootstrap: generates 2
   additional keypairs, 2 empty `.conf` blobs, 2 obfuscation param sets).
2. Deploy new agent to all nodes — agent receives new iface keys in
   next registration cycle, brings up `wg-quick@*_escape.service`
   (empty of peers initially).
3. Backfill migration: iterate over existing `vpn_configs` rows, call
   `add_peer`-like flow to add them to escape ifaces. Idempotent
   (sha-diff check in WgBlobStore handles no-op case).
4. Admin flips `ESCAPE_ENABLED=true` in UI → DNAT rules applied on CP.
5. Users see "Обход блокировки" toggle in LK; opt-in per download.

## Testing strategy (TDD)

- **Pure functions** (unit): `render_server_conf` with awg_params,
  `render_client_conf` with bypass flag, escape-port maps,
  `generate_obfuscation_params()` determinism/range checks,
  `get_active_ports(escape_enabled)`.
- **Service-level**: `obfuscation.regenerate()` bumps `updated_at` and
  writes new values; `VpnManager.bootstrap` idempotency with 4 ifaces;
  `add_peer` writes to 4 blobs.
- **API**: `?bypass=true` blocked when `escape_enabled=False`;
  `bypass+backup` returns 400; `/obfuscation/regenerate` admin-only;
  `client-links` exposes flag.
- **Agent**: `MANAGED_FILES` wiring; dispatch of new hooks;
  `wg syncconf {antizapret,vpn}_escape` invocation (mocked subprocess).
- **Integration (smoke)**: end-to-end via existing test harness —
  `add_peer` followed by `get_client_conf(bypass=True)` returns a
  conf with the escape port and obfuscation params present.

## Out of scope / future work

- IPv6 escape routes (match current state: not supported).
- Per-client obfuscation params.
- Auto-regeneration schedule.
- XRay/Reality / OpenVPN-over-WebSocket side channels (discussed in
  brainstorm; explicitly deferred).
- Escape backup ports (add if 500/53443 also get blocked).
