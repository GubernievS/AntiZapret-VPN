# Surface escape-mode peers in dashboard / monitoring — Design

**Date:** 2026-04-24
**Bead:** `CorpAdmin-AZ-adj` (P2, feature), under epic `CorpAdmin-AZ-te3`
**Depends on:** `CorpAdmin-AZ-6za` (closed) — escape tunnels are functional end-to-end.

## Goal

Make escape-mode peers (clients connected via `az_escape` / `vpn_escape` ifaces) visible in two operator UIs:

1. **Admin dashboard** (`AdminDashboardPage.tsx`) — per-node card currently shows peer counts for two base ifaces only. Add escape counts so operators can see bypass-mode load.
2. **Client monitoring** (`MonitoringPage.tsx`) — active-connections table shows one badge per iface and treats `az_escape` + `vpn_escape` as their base counterparts due to a loose `includes()` match. Fix the badge to distinguish all four ifaces unambiguously.

## Non-goals

- **No dedup by public_key.** A client connected simultaneously on base and escape iface is rendered as two rows (same as today two clients with identical public_key on separate base ifaces would be two rows). Real-world collisions are rare (3-min handshake timeout clears stale ifaces) and dedup solves a problem that doesn't need solving here.
- **No «Режим» column.** Mode is 1:1 derivable from `interface` and conveyed visually by badge colour. A second column would duplicate information.
- **No backup-port visibility.** Backup-port clients (UDP 540/580) live on the same base iface as regular clients; the server cannot distinguish them via `wg show`. Out of scope.
- **No database migration.** `node.peers_snapshot` and `node.metrics` are `JSONB` and already accept arbitrary keys.
- **No new API endpoints.** Existing `/api/v1/monitoring/connections`, `/api/v1/monitoring/traffic`, `/api/v1/admin/dashboard` are reused as-is; response shapes gain fields.

## Top-level architecture

Strict extension of the existing pattern, not a new mechanism:

```
┌──────────────── node (data-plane) ─────────────────┐
│ sync-agent._IFACES                                 │
│   was:  ("antizapret", "vpn")                      │
│   now:  ("antizapret", "vpn", "az_escape", "vpn_escape")│
│                                                    │
│ collect_peers()   — loop over _IFACES              │
│ _active_peers()   — loop over _IFACES              │
│ heartbeat payload:                                 │
│   metrics.active_peers_antizapret   (unchanged)    │
│   metrics.active_peers_vpn          (unchanged)    │
│   metrics.active_peers_az_escape    (NEW)          │
│   metrics.active_peers_vpn_escape   (NEW)          │
│   peers[]  — flat list, .interface already tags each entry│
└────────────────────────────────────────────────────┘
                    │ HTTPS heartbeat
                    ▼
┌──────────────── CP (backend) ──────────────────────┐
│ MonitoringService._IP_MAP                          │
│   + 10.27.x.x → az_escape-antizapret-<num>         │
│   + 10.26.x.x → vpn_escape-vpn-<num>               │
│                                                    │
│ AdminDashboardResponse (schema)                    │
│   + active_peers_az_escape: int                    │
│   + active_peers_vpn_escape: int                   │
└────────────────────────────────────────────────────┘
                    │ JSON
                    ▼
┌──────────────── CP (frontend) ─────────────────────┐
│ MonitoringPage.tsx                                 │
│   interfaceLabel()  — strict switch on 4 values    │
│   badge colours:    4 distinct palettes            │
│                                                    │
│ AdminDashboardPage.tsx                             │
│   node card: render escape counters conditionally  │
│              (show only if count > 0)              │
│   LoadDistributionBar: sum all 4 counters          │
└────────────────────────────────────────────────────┘
```

## Decisions

### D1. Minimal extension, not aggregation

Agent stays dumb — adds two iface names to the iteration list, that's it. Backend stays dumb — extends IP-map with two subnet entries. No deduplication, no "current active iface" picker, no mode-resolver. If a peer is live on both base and escape, they appear twice. This is the same semantics as today's base-only view, just applied to four ifaces.

### D2. Conditional display > feature flag

Escape counters on the admin dashboard are rendered only when `count > 0`. Driver: if the node's escape ifaces are currently unused (escape globally disabled, or simply no bypass clients), the UI shows no extra rows — clean default appearance. When the first bypass peer connects, the row appears automatically. No need to read `ESCAPE_ENABLED` on the frontend.

### D3. Badge — strict iface match, colour = mode

`interfaceLabel()` is rewritten from `includes()` to strict equality. Each iface gets its own badge palette:

| iface         | label     | badge classes                        |
|---------------|-----------|--------------------------------------|
| `antizapret`  | `AZ`      | `bg-blue-100 text-blue-700`          |
| `vpn`         | `VPN`     | `bg-green-100 text-green-700`        |
| `az_escape`   | `AZ-esc`  | `bg-orange-100 text-orange-700`      |
| `vpn_escape`  | `VPN-esc` | `bg-amber-100 text-amber-700`        |

Palette chosen for colour-distance: blue vs green for base (cool tones), orange vs amber for escape (warm tones, subtle sibling pair). Default fallback for unknown iface returns the iface name verbatim with neutral gray (`bg-gray-100 text-gray-600`) — defensive against future iface rename.

### D4. Agent iface-list is the single source of truth

New ifaces are added to one constant (`_IFACES` or equivalent in `corpweb_sync_agent.py`). Both `collect_peers()` and `_active_peers()` read it. Adding a fifth iface in the future touches one line.

### D5. Graceful absence of escape iface on node

If `az_escape` or `vpn_escape` is not yet brought up on a node (e.g. fresh install before first `/register`), `wg show <iface> dump` returns non-zero exit. Existing agent code already tolerates this for base ifaces — `_active_peers()` returns 0 and `collect_peers()` returns []. No new handling needed; we verify it still holds in tests.

### D6. No change to existing metrics keys

`active_peers_antizapret` and `active_peers_vpn` keep their current semantics (peer count on the base iface, no inclusion of escape). This preserves any existing alerting / Grafana rules the operator may have built. Escape counts are strictly additive new keys.

### D7. LoadDistributionBar aggregates all four

On the admin dashboard, the distribution bar sums `active_peers_antizapret + active_peers_vpn + active_peers_az_escape + active_peers_vpn_escape` for each node. Rationale: the bar shows total connected peers per node — escape peers are "connected peers", so they count. If we ever want a "base-vs-escape" split view, that's a separate design.

## Testing strategy (TDD)

### Agent (Python, pytest — `agent/tests/test_sync_agent.py`)

- `test_active_peers_enumerates_all_four_ifaces` — mock `wg show <iface> latest-handshakes` for all 4, assert returns sum across all.
- `test_collect_peers_enumerates_all_four_ifaces` — mock `wg show <iface> dump` with distinct peers per iface, assert result list contains entries with `interface` field set to each of the 4 values.
- `test_heartbeat_payload_includes_escape_metric_keys` — assert `metrics.active_peers_az_escape` and `metrics.active_peers_vpn_escape` are present and integer-valued.
- `test_collect_peers_tolerates_missing_escape_iface` — mock `wg show az_escape` → non-zero exit, assert behaviour matches today's base-iface-missing path (entry absent from result, no exception).

### Backend (Python, pytest — `corpweb/backend/tests/`)

- `test_monitoring_ip_map_resolves_escape_subnets` — peer with `allowed_ips=10.27.8.5/32` → expected client-name pattern; same for `10.26.8.5/32`.
- `test_admin_dashboard_response_exposes_escape_peer_counts` — seed `node.metrics` with all 4 keys, call endpoint, assert all 4 fields are in response JSON.
- Regression: existing monitoring / admin-dashboard tests stay green (confirms no break in base iface handling).

### Frontend (TypeScript)

- `npm run build` — TS-check must stay green; in particular `interfaceLabel()` strict switch must be exhaustive (or provide a fallback).
- Manual visual verification after CP deploy: connect via real escape config on wgfi2 or wgfi3, observe row in MonitoringPage with correct badge and counter appearing in AdminDashboardPage.

## Scope of code changes

| File | Change |
|---|---|
| `agent/corpweb_sync_agent.py` | Extend `_IFACES` (or equivalent tuple) with 2 new names. |
| `agent/tests/test_sync_agent.py` | 4 new tests (see Testing). |
| `corpweb/backend/app/services/monitoring.py` | Extend `_IP_MAP` with 2 entries for 10.26 / 10.27. |
| Admin dashboard response schema (location under `corpweb/backend/app/schemas/` — verified at implementation time via `grep active_peers_antizapret`) | Add 2 optional int fields. |
| `corpweb/backend/app/api/v1/admin_dashboard.py` | Populate 2 new fields from `node.metrics`. |
| `corpweb/backend/tests/…` | 2 new tests (see Testing). |
| `corpweb/frontend/src/pages/MonitoringPage.tsx` | Rewrite `interfaceLabel()`, add badge-colour lookup keyed by iface. |
| `corpweb/frontend/src/pages/AdminDashboardPage.tsx` | 2 new conditional rows in the node card; update `LoadDistributionBar` sum. |
| `corpweb/frontend/src/api/dashboard.ts` (type) | Add 2 optional fields to `NodeInfo` type. |

No new files, no migration, no new endpoints.

## Deploy plan

Part of the frontend-batch series, applied at the end:

1. **Agent** — `scp corpweb_sync_agent.py` to each node; `install -m 0755` to `/usr/local/bin/`; `systemctl restart corpweb-sync-agent`. Do both `wgfi2` and `wgfi3`.
2. **Backend** — on CP: `cp -r corpweb/backend/app /opt/corpweb/backend/app` + `systemctl restart corpweb-backend`. No `alembic upgrade` (no migrations).
3. **Frontend** — on CP: `rsync` built `dist/` from worktree, apply to `/opt/corpweb/frontend/` (same procedure as `ttq`/`f82`/`96f` deploys earlier today).
4. **Verify** — navigate an escape-mode client; check MonitoringPage shows `AZ-esc` or `VPN-esc` badge for that row; admin dashboard node card shows corresponding counter incrementing.

## Out-of-scope discoveries (file separately if they bite)

- **`CorpAdmin-AZ-6u8`** (already filed, P1) — user reported `ANTIZAPRET_DNS=1` clients connect but fail to resolve. Related to escape DNS semantics established 2026-04-24. Not part of `adj`.
- **`CorpAdmin-AZ-t2r`** (P3, parked) — CP dashboard drift-counter per node from heartbeat `escape_drift_applied_count`. Orthogonal to this design.
