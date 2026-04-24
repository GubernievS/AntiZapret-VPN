# Surface escape-mode peers Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make escape-mode peers (on `az_escape` / `vpn_escape` ifaces) visible in the admin dashboard and client monitoring pages.

**Architecture:** Minimal extension of existing pattern — agent gets 2 new iface names, backend IP-map gets 2 subnet entries, admin-dashboard response gets 2 new metric keys, frontend MonitoringPage gets a strict-match badge with 4 colour palettes, AdminDashboardPage gets 2 conditionally-rendered counter rows. No dedup, no «Режим» column, no DB migration, no new endpoints.

**Tech Stack:** Python 3.13 (agent + FastAPI backend), pytest, React + TypeScript + Tailwind (frontend), Vite build.

**Spec:** `docs/superpowers/specs/2026-04-24-adj-escape-peers-surface-design.md`

**Working tree:** Already on branch `feature/frontend-batch` at `.worktrees/frontend-batch`.

---

## File Structure

| File | Purpose | Action |
|---|---|---|
| `agent/corpweb_sync_agent.py` | Agent: peer + metric collection | Modify — introduce `_IFACES` tuple, rewrite 2 iteration sites |
| `agent/tests/test_sync_agent.py` | Agent unit tests | Add 4 new tests |
| `corpweb/backend/app/services/monitoring.py` | IP → client_name map | Modify `_build_ip_map()` — 2 new subnet derivations |
| `corpweb/backend/app/api/v1/admin_dashboard.py` | Admin dashboard endpoint | Modify `get_dashboard()` — 2 new metric reads + include in totals |
| `corpweb/backend/tests/test_monitoring_new.py` | Backend monitoring tests | Add 1 new test |
| `corpweb/backend/tests/test_admin.py` | Backend admin tests | Add 1 new test under `TestAdminDashboard` |
| `corpweb/frontend/src/api/dashboard.ts` | Dashboard API types | Modify — add 2 fields to `DashboardNode` interface |
| `corpweb/frontend/src/pages/MonitoringPage.tsx` | Active connections table | Rewrite `interfaceLabel()` + add badge class helper |
| `corpweb/frontend/src/pages/AdminDashboardPage.tsx` | Node cards + load bar | Modify `NodeCard` (conditional rows) + `LoadDistributionBar` (sum 4) |

No new files. No schema migrations.

---

## Task 1: Agent — introduce `_IFACES` tuple and extend to 4 ifaces

**Files:**
- Modify: `agent/corpweb_sync_agent.py` (lines 815-820 and 839-863)
- Test: `agent/tests/test_sync_agent.py` (add new tests at end of file)

**Context:** Today the agent hard-codes iface names `"antizapret"` and `"vpn"` in two places. We introduce a module-level constant `_IFACES` used by both `collect_metrics()` and `collect_peers()`.

- [ ] **Step 1.1: Write failing test for collect_metrics with 4 escape-aware keys**

Append at end of `agent/tests/test_sync_agent.py`:

```python
class TestCollectMetricsEscapeAware:
    """collect_metrics() must report peer counts for all four ifaces
    (antizapret, vpn, az_escape, vpn_escape)."""

    def test_collect_metrics_includes_four_active_peer_keys(self):
        from unittest.mock import patch
        import agent.corpweb_sync_agent as agent

        def fake_active_peers(iface: str) -> int:
            return {
                "antizapret": 1,
                "vpn": 2,
                "az_escape": 3,
                "vpn_escape": 4,
            }[iface]

        with patch.object(agent, "_active_peers", side_effect=fake_active_peers):
            metrics = agent.collect_metrics()

        assert metrics["active_peers_antizapret"] == 1
        assert metrics["active_peers_vpn"] == 2
        assert metrics["active_peers_az_escape"] == 3
        assert metrics["active_peers_vpn_escape"] == 4
```

- [ ] **Step 1.2: Write failing test for collect_peers across 4 ifaces**

Append immediately after Step 1.1 test:

```python
class TestCollectPeersEscapeAware:
    """collect_peers() must enumerate peers from all four ifaces, tagging each
    entry with its iface. Missing iface (e.g. az_escape not up yet on a fresh
    node) must be gracefully skipped, matching existing behaviour for base
    ifaces."""

    def test_collect_peers_enumerates_all_four_ifaces(self):
        from unittest.mock import patch, MagicMock
        import subprocess
        import agent.corpweb_sync_agent as agent

        def fake_run(cmd, **kwargs):
            iface = cmd[2]  # ["wg", "show", <iface>, "dump"]
            # Header line (skipped by slicing [1:]), then one peer per iface
            # with a distinct pubkey.
            dump = (
                "HEADER\n"
                f"pub_{iface}\tpriv\t1.2.3.4:51820\t10.1.1.1/32\t1700000000\t100\t200\toff\n"
            )
            result = MagicMock()
            result.stdout = dump
            result.returncode = 0
            return result

        with patch.object(subprocess, "run", side_effect=fake_run):
            peers = agent.collect_peers()

        ifaces_seen = {p["interface"] for p in peers}
        assert ifaces_seen == {"antizapret", "vpn", "az_escape", "vpn_escape"}

    def test_collect_peers_skips_missing_escape_iface(self):
        from unittest.mock import patch, MagicMock
        import subprocess
        import agent.corpweb_sync_agent as agent

        def fake_run(cmd, **kwargs):
            iface = cmd[2]
            if iface == "az_escape":
                # Simulate iface not up — wg returns non-zero.
                raise subprocess.CalledProcessError(1, cmd)
            result = MagicMock()
            result.stdout = (
                "HEADER\n"
                f"pub_{iface}\tpriv\t1.2.3.4:51820\t10.1.1.1/32\t1700000000\t100\t200\toff\n"
            )
            result.returncode = 0
            return result

        with patch.object(subprocess, "run", side_effect=fake_run):
            peers = agent.collect_peers()

        ifaces_seen = {p["interface"] for p in peers}
        assert ifaces_seen == {"antizapret", "vpn", "vpn_escape"}
```

- [ ] **Step 1.3: Run tests to verify they fail**

```bash
cd /home/brolin/Documents/ITSS/AdminAZWG/CorpAdmin-AZ/.worktrees/frontend-batch
.venv/bin/python -m pytest agent/tests/test_sync_agent.py::TestCollectMetricsEscapeAware agent/tests/test_sync_agent.py::TestCollectPeersEscapeAware -v
```

If `.venv` is not in the worktree root, source the backend venv: `source corpweb/backend/.venv/bin/activate` and run `pytest agent/tests/…` from the worktree root.

Expected: FAIL with `KeyError: 'az_escape'` (first test) and assertion mismatches on iface sets (second/third tests).

- [ ] **Step 1.4: Implement the `_IFACES` constant and rewire call sites**

In `agent/corpweb_sync_agent.py`, just above `def _active_peers(iface: str) -> int:` (around line 785), add:

```python
# Ordered tuple of WireGuard / AmneziaWG ifaces the agent monitors for peer
# activity. The first two are the baseline; the last two host escape-mode
# (bypass) tunnels. collect_metrics() emits one active_peers_<iface> key per
# entry; collect_peers() iterates this tuple when dumping peer state.
_IFACES: tuple[str, ...] = ("antizapret", "vpn", "az_escape", "vpn_escape")
```

Rewrite `collect_metrics()` (replace the literal pair at lines 818-819):

```python
def collect_metrics() -> dict:
    global _prev_net
    metrics = {f"active_peers_{iface}": _active_peers(iface) for iface in _IFACES}
    try:
        with open("/proc/net/dev") as f:
            for line in f:
                parts = line.split()
                if len(parts) >= 10 and any(x in parts[0] for x in ("eth0", "ens")):
                    rx, tx = int(parts[1]), int(parts[9])
                    now = time.monotonic()
                    if _prev_net["ts"] > 0:
                        dt = max(now - _prev_net["ts"], 1)
                        metrics["rx_bytes_per_sec"] = int((rx - _prev_net["rx"]) / dt)
                        metrics["tx_bytes_per_sec"] = int((tx - _prev_net["tx"]) / dt)
                    _prev_net = {"rx": rx, "tx": tx, "ts": now}
                    break
    except Exception:
        pass
    return metrics
```

Rewrite `collect_peers()` (replace `for iface in ("antizapret", "vpn"):` at line 842):

```python
def collect_peers() -> list[dict]:
    """Collect full peer list from all WG interfaces via wg show dump."""
    peers = []
    for iface in _IFACES:
        try:
            result = subprocess.run(
                ["wg", "show", iface, "dump"],
                capture_output=True, text=True, check=True,
            )
        except (subprocess.CalledProcessError, FileNotFoundError):
            continue
        for line in result.stdout.splitlines()[1:]:  # skip header
            parts = line.split("\t")
            if len(parts) < 8:
                continue
            peers.append({
                "interface": iface,
                "public_key": parts[0],
                "endpoint": parts[2] if parts[2] != "(none)" else None,
                "allowed_ips": parts[3],
                "latest_handshake": int(parts[4]) if parts[4] != "0" else 0,
                "rx_bytes": int(parts[5]),
                "tx_bytes": int(parts[6]),
            })
    return peers
```

- [ ] **Step 1.5: Run tests to verify GREEN**

```bash
.venv/bin/python -m pytest agent/tests/test_sync_agent.py -v 2>&1 | tail -20
```

Expected: all 3 new tests PASS; existing 94 agent tests stay PASS.

- [ ] **Step 1.6: Commit**

```bash
cd /home/brolin/Documents/ITSS/AdminAZWG/CorpAdmin-AZ/.worktrees/frontend-batch
git add agent/corpweb_sync_agent.py agent/tests/test_sync_agent.py
git commit -m "feat(agent): enumerate 4 ifaces incl. escape for metrics + peers (CorpAdmin-AZ-adj)"
```

---

## Task 2: Backend — extend IP-map to escape subnets

**Files:**
- Modify: `corpweb/backend/app/services/monitoring.py:56-76` (`_build_ip_map`)
- Test: `corpweb/backend/tests/test_monitoring_new.py` (add new test)

**Context:** `_build_ip_map()` currently maps the antizapret IP (`10.29.x.x`) to `client_name` and derives the vpn IP (`10.28.x.x`) from the same host part. Escape peers get IPs on `10.27.x.x` (az_escape) and `10.26.x.x` (vpn_escape) with the same host part — we extend the derivation.

- [ ] **Step 2.1: Write failing test for escape IP resolution**

Append in `corpweb/backend/tests/test_monitoring_new.py` (bottom of file):

```python
def test_ip_map_resolves_escape_subnets(db):
    """_build_ip_map must resolve 10.27.x.x → az_escape and 10.26.x.x →
    vpn_escape to the same client_name as the baseline 10.29.x.x / 10.28.x.x
    pair, using the same host part."""
    from app.db.models import User, VPNConfig, Node
    from app.services.monitoring import MonitoringService
    import time

    user = User(email="esc@test", password_hash="x", role="user", is_active=True)
    db.add(user)
    db.flush()
    cfg = VPNConfig(
        user_id=user.id,
        client_name="testuser-escape",
        config_type="awg_vpn",
        is_active=True,
        config_metadata={"vpn_ip": "10.29.8.5"},
    )
    db.add(cfg)
    now = int(time.time())
    node = Node(
        hostname="kvn-test", health="ok", last_seen=None,
        peers_snapshot=[
            {
                "interface": "az_escape",
                "public_key": "pk_az_esc",
                "endpoint": "1.2.3.4:53443",
                "allowed_ips": "10.27.8.5/32",
                "latest_handshake": now - 10,
                "rx_bytes": 100, "tx_bytes": 200,
            },
            {
                "interface": "vpn_escape",
                "public_key": "pk_vpn_esc",
                "endpoint": "1.2.3.4:500",
                "allowed_ips": "10.26.8.5/32",
                "latest_handshake": now - 15,
                "rx_bytes": 300, "tx_bytes": 400,
            },
        ],
        metrics={},
    )
    db.add(node)
    db.commit()

    svc = MonitoringService(db)
    conns = svc.get_active_connections()

    by_iface = {c["interface"]: c for c in conns}
    assert by_iface["az_escape"]["client_name"] == "testuser-escape"
    assert by_iface["vpn_escape"]["client_name"] == "testuser-escape"
```

- [ ] **Step 2.2: Run test to verify FAIL**

```bash
cd /home/brolin/Documents/ITSS/AdminAZWG/CorpAdmin-AZ/.worktrees/frontend-batch/corpweb/backend
.venv/bin/python -m pytest tests/test_monitoring_new.py::test_ip_map_resolves_escape_subnets -v
```

Expected: FAIL — `client_name` will be `None` for escape ifaces because IP-map does not yet know about 10.26 / 10.27.

- [ ] **Step 2.3: Extend `_build_ip_map` to derive escape IPs**

Replace `_build_ip_map` in `corpweb/backend/app/services/monitoring.py` (lines 56-76) with:

```python
    def _build_ip_map(self) -> dict[str, str]:
        """
        Map VPN IP → client_name.
        Each client has up to four IPs sharing the same host part:
          10.29.x.x  (antizapret, baseline)
          10.28.x.x  (vpn, baseline)
          10.27.x.x  (az_escape, bypass)
          10.26.x.x  (vpn_escape, bypass)
        config_metadata stores only the antizapret IP, so we derive the other
        three by replacing the subnet prefix.
        """
        configs = self._db.query(VPNConfig).filter(VPNConfig.is_active == True).all()
        result = {}
        for cfg in configs:
            az_ip = (cfg.config_metadata or {}).get("vpn_ip", "")
            if not az_ip:
                continue
            parts = az_ip.split(".")
            if len(parts) == 4 and parts[0] == "10" and parts[1] == "29":
                host = f"{parts[2]}.{parts[3]}"
                result[az_ip] = cfg.client_name
                result[f"10.28.{host}"] = cfg.client_name
                result[f"10.27.{host}"] = cfg.client_name
                result[f"10.26.{host}"] = cfg.client_name
            else:
                # Legacy entry — preserve at its raw IP.
                result[az_ip] = cfg.client_name
        return result
```

- [ ] **Step 2.4: Run full monitoring test file**

```bash
.venv/bin/python -m pytest tests/test_monitoring_new.py -v 2>&1 | tail -15
```

Expected: the new test PASSES + all pre-existing `test_monitoring_new` tests stay PASS.

- [ ] **Step 2.5: Commit**

```bash
cd /home/brolin/Documents/ITSS/AdminAZWG/CorpAdmin-AZ/.worktrees/frontend-batch
git add corpweb/backend/app/services/monitoring.py corpweb/backend/tests/test_monitoring_new.py
git commit -m "feat(monitoring): map 10.27/10.26 subnets to client_name for escape peers (CorpAdmin-AZ-adj)"
```

---

## Task 3: Backend — admin dashboard exposes escape peer counts

**Files:**
- Modify: `corpweb/backend/app/api/v1/admin_dashboard.py`
- Test: `corpweb/backend/tests/test_admin.py` under class `TestAdminDashboard`

**Context:** `get_dashboard()` reads `active_peers_antizapret` and `active_peers_vpn` from `node.metrics`, puts them in each node's entry, and sums them into `totals.active_clients`. We add the two escape keys symmetrically.

- [ ] **Step 3.1: Read existing `TestAdminDashboard` for fixture style**

```bash
sed -n '127,200p' /home/brolin/Documents/ITSS/AdminAZWG/CorpAdmin-AZ/.worktrees/frontend-batch/corpweb/backend/tests/test_admin.py
```

Identify how nodes are seeded with `metrics=...` and how the admin client is authenticated.

- [ ] **Step 3.2: Write failing test for escape counters in dashboard response**

Fixture signature of the existing class (verified 2026-04-24): `test_*(self, client, admin_user, admin_token, system_settings, db_session)`. Calls use `auth_header(admin_token)` (import already in file) and use `client.get(...)`. Append inside `class TestAdminDashboard` in `corpweb/backend/tests/test_admin.py`:

```python
    def test_dashboard_exposes_escape_peer_counts(
        self, client, admin_user, admin_token, system_settings, db_session
    ):
        from app.db.models import Node
        node = Node(
            hostname="kvn-esc",
            health="ok",
            last_seen=None,
            metrics={
                "active_peers_antizapret": 1,
                "active_peers_vpn": 2,
                "active_peers_az_escape": 3,
                "active_peers_vpn_escape": 4,
            },
            applied_sha={},
            peers_snapshot=[],
        )
        db_session.add(node)
        db_session.commit()

        response = client.get("/api/v1/admin/dashboard", headers=auth_header(admin_token))
        assert response.status_code == 200
        body = response.json()
        entry = next(n for n in body["nodes"] if n["hostname"] == "kvn-esc")
        assert entry["active_peers_antizapret"] == 1
        assert entry["active_peers_vpn"] == 2
        assert entry["active_peers_az_escape"] == 3
        assert entry["active_peers_vpn_escape"] == 4
        # All four counted in the grand total.
        assert body["totals"]["active_clients"] >= 1 + 2 + 3 + 4
```

If `db_session` does not exist in `conftest.py`, substitute with whichever SA-session fixture the test suite uses (grep `@pytest.fixture` on `*session*` in `corpweb/backend/tests/conftest.py`).

- [ ] **Step 3.3: Run test to verify FAIL**

```bash
cd /home/brolin/Documents/ITSS/AdminAZWG/CorpAdmin-AZ/.worktrees/frontend-batch/corpweb/backend
.venv/bin/python -m pytest tests/test_admin.py::TestAdminDashboard::test_dashboard_exposes_escape_peer_counts -v
```

Expected: FAIL — `KeyError: 'active_peers_az_escape'` when indexing the response entry.

- [ ] **Step 3.4: Extend `get_dashboard()` with escape keys**

Replace the node-loop body in `corpweb/backend/app/api/v1/admin_dashboard.py:22-47` with:

```python
    total_active = 0
    node_data = []
    for n in nodes:
        m = n.metrics or {}
        az = m.get("active_peers_antizapret", 0)
        vpn = m.get("active_peers_vpn", 0)
        az_esc = m.get("active_peers_az_escape", 0)
        vpn_esc = m.get("active_peers_vpn_escape", 0)
        total_active += az + vpn + az_esc + vpn_esc

        applied = n.applied_sha or {}
        synced = all(
            applied.get(p) == all_paths.get(p)
            for p in all_paths
            if p.startswith("/")
        )

        node_data.append({
            "id": n.id,
            "hostname": n.hostname,
            "health": n.health,
            "active_peers_antizapret": az,
            "active_peers_vpn": vpn,
            "active_peers_az_escape": az_esc,
            "active_peers_vpn_escape": vpn_esc,
            "rx_bytes_per_sec": m.get("rx_bytes_per_sec", 0),
            "tx_bytes_per_sec": m.get("tx_bytes_per_sec", 0),
            "synced": synced,
            "last_seen": n.last_seen.isoformat() if n.last_seen else None,
        })
```

- [ ] **Step 3.5: Run test suite for admin and dashboard**

```bash
.venv/bin/python -m pytest tests/test_admin.py -v 2>&1 | tail -15
```

Expected: new test PASSES, existing `TestAdminDashboard` tests stay PASS.

Also run full backend suite to catch unexpected regressions:

```bash
.venv/bin/python -m pytest -q 2>&1 | tail -5
```

Expected: 325+ passing (324 prior + 2 new).

- [ ] **Step 3.6: Commit**

```bash
cd /home/brolin/Documents/ITSS/AdminAZWG/CorpAdmin-AZ/.worktrees/frontend-batch
git add corpweb/backend/app/api/v1/admin_dashboard.py corpweb/backend/tests/test_admin.py
git commit -m "feat(admin-dashboard): expose escape peer counts per node + in totals (CorpAdmin-AZ-adj)"
```

---

## Task 4: Frontend types — extend `DashboardNode`

**Files:**
- Modify: `corpweb/frontend/src/api/dashboard.ts`

**Context:** The TypeScript interface must gain two required fields matching the backend response. Since backend is updated in Task 3 before any deploy, these fields will always be present at runtime.

- [ ] **Step 4.1: Add escape counter fields to `DashboardNode`**

Replace the interface in `corpweb/frontend/src/api/dashboard.ts`:

```typescript
export interface DashboardNode {
  id: number
  hostname: string
  health: string | null
  active_peers_antizapret: number
  active_peers_vpn: number
  active_peers_az_escape: number
  active_peers_vpn_escape: number
  rx_bytes_per_sec: number
  tx_bytes_per_sec: number
  synced: boolean
  last_seen: string | null
}
```

- [ ] **Step 4.2: Run TS build from frontend dir**

```bash
cd /home/brolin/Documents/ITSS/AdminAZWG/CorpAdmin-AZ/.worktrees/frontend-batch/corpweb/frontend
npm run build 2>&1 | tail -10
```

Expected: build succeeds; may emit no new errors yet (fields are just added, not yet consumed in Task 5/6).

- [ ] **Step 4.3: Commit**

```bash
cd /home/brolin/Documents/ITSS/AdminAZWG/CorpAdmin-AZ/.worktrees/frontend-batch
git add corpweb/frontend/src/api/dashboard.ts
git commit -m "feat(api): add escape peer counters to DashboardNode type (CorpAdmin-AZ-adj)"
```

---

## Task 5: Frontend MonitoringPage — strict iface badge + colours

**Files:**
- Modify: `corpweb/frontend/src/pages/MonitoringPage.tsx` (lines 27-31 for label helper, line 218-220 for badge render)

**Context:** Today `interfaceLabel()` returns `'AZ'` for any iface containing `"az"` — so `az_escape` is rendered as `'AZ'` and visually indistinguishable from `antizapret`. Same for `vpn_escape` → `'VPN'`. Also badge colour is a fixed blue. Replace both with strict 4-way mapping.

- [ ] **Step 5.1: Rewrite label + add class helper**

In `corpweb/frontend/src/pages/MonitoringPage.tsx`, replace the `interfaceLabel` function (lines 27-31) with:

```typescript
function interfaceLabel(iface: string): string {
  switch (iface) {
    case 'antizapret': return 'AZ'
    case 'vpn':        return 'VPN'
    case 'az_escape':  return 'AZ-esc'
    case 'vpn_escape': return 'VPN-esc'
    default:           return iface
  }
}

function interfaceBadgeClasses(iface: string): string {
  switch (iface) {
    case 'antizapret': return 'bg-blue-100 text-blue-700'
    case 'vpn':        return 'bg-green-100 text-green-700'
    case 'az_escape':  return 'bg-orange-100 text-orange-700'
    case 'vpn_escape': return 'bg-amber-100 text-amber-700'
    default:           return 'bg-gray-100 text-gray-600'
  }
}
```

- [ ] **Step 5.2: Update badge render to use class helper**

In the same file at lines 217-221, replace the `<span>` that renders the interface cell with:

```tsx
                    <td className="px-4 py-3">
                      <span className={`inline-flex px-2 py-0.5 rounded-full text-xs font-medium ${interfaceBadgeClasses(conn.interface)}`}>
                        {interfaceLabel(conn.interface)}
                      </span>
                    </td>
```

- [ ] **Step 5.3: Verify TS build + rebuild dist**

```bash
cd /home/brolin/Documents/ITSS/AdminAZWG/CorpAdmin-AZ/.worktrees/frontend-batch/corpweb/frontend
npm run build 2>&1 | tail -10
```

Expected: build succeeds; `dist/assets/index-*.js` + `.css` regenerated.

- [ ] **Step 5.4: Commit**

```bash
cd /home/brolin/Documents/ITSS/AdminAZWG/CorpAdmin-AZ/.worktrees/frontend-batch
git add corpweb/frontend/src/pages/MonitoringPage.tsx
git commit -m "feat(monitoring): distinguish escape ifaces with AZ-esc / VPN-esc coloured badges (CorpAdmin-AZ-adj)"
```

---

## Task 6: Frontend AdminDashboardPage — conditional rows + LoadDistributionBar sum 4

**Files:**
- Modify: `corpweb/frontend/src/pages/AdminDashboardPage.tsx`

**Context:** The `LoadDistributionBar` component currently sums only `active_peers_antizapret + active_peers_vpn`. The `NodeCard` component shows one row «Пиры AZ / VPN». We update the bar to sum all 4, and add two conditionally-rendered rows for escape counters (shown only when `count > 0` — zero rows are collapsed).

- [ ] **Step 6.1: Update `LoadDistributionBar` to sum four counters**

Replace the `LoadDistributionBar` body in `corpweb/frontend/src/pages/AdminDashboardPage.tsx` (lines 55-93). Add a helper and use it everywhere inside:

```tsx
function totalPeers(node: DashboardNode): number {
  return (
    node.active_peers_antizapret +
    node.active_peers_vpn +
    node.active_peers_az_escape +
    node.active_peers_vpn_escape
  )
}

function LoadDistributionBar({ nodes }: { nodes: DashboardNode[] }) {
  const total = nodes.reduce((sum, n) => sum + totalPeers(n), 0)
  if (total === 0) {
    return <p className="text-sm text-gray-400 py-2">Нет активных клиентов</p>
  }

  return (
    <div className="space-y-3">
      <div className="flex h-4 rounded-full overflow-hidden gap-px">
        {nodes.map((node, i) => {
          const peers = totalPeers(node)
          const pct = (peers / total) * 100
          if (pct === 0) return null
          return (
            <div
              key={node.id}
              className={`${SEGMENT_COLORS[i % SEGMENT_COLORS.length]} transition-all`}
              style={{ width: `${pct}%` }}
              title={`${node.hostname}: ${peers} клиентов (${pct.toFixed(1)}%)`}
            />
          )
        })}
      </div>
      <div className="flex flex-wrap gap-x-4 gap-y-1">
        {nodes.map((node, i) => {
          const peers = totalPeers(node)
          const pct = ((peers / total) * 100).toFixed(1)
          return (
            <div key={node.id} className="flex items-center gap-1.5 text-xs text-gray-600">
              <div className={`w-2.5 h-2.5 rounded-sm ${SEGMENT_COLORS[i % SEGMENT_COLORS.length]}`} />
              <span className="font-mono">{node.hostname}</span>
              <span className="text-gray-400">{peers} ({pct}%)</span>
            </div>
          )
        })}
      </div>
    </div>
  )
}
```

- [ ] **Step 6.2: Update `NodeCard` — add two conditional escape rows**

In the same file, inside `NodeCard` at line 105-111 (`<div className="space-y-1.5 text-xs text-gray-600">` block), after the existing «Пиры AZ / VPN» row, insert:

```tsx
        {node.active_peers_az_escape > 0 && (
          <div className="flex items-center justify-between">
            <span className="text-gray-400">Пиры AZ-esc</span>
            <span className="font-medium text-orange-700">
              {node.active_peers_az_escape}
            </span>
          </div>
        )}
        {node.active_peers_vpn_escape > 0 && (
          <div className="flex items-center justify-between">
            <span className="text-gray-400">Пиры VPN-esc</span>
            <span className="font-medium text-amber-700">
              {node.active_peers_vpn_escape}
            </span>
          </div>
        )}
```

The full `NodeCard` section after edit (for reference — the existing AZ / VPN row stays exactly as-is, these two are additions right below it):

```tsx
      <div className="space-y-1.5 text-xs text-gray-600">
        <div className="flex items-center justify-between">
          <span className="text-gray-400">Пиры AZ / VPN</span>
          <span className="font-medium text-gray-900">
            {node.active_peers_antizapret} / {node.active_peers_vpn}
          </span>
        </div>
        {node.active_peers_az_escape > 0 && (
          <div className="flex items-center justify-between">
            <span className="text-gray-400">Пиры AZ-esc</span>
            <span className="font-medium text-orange-700">
              {node.active_peers_az_escape}
            </span>
          </div>
        )}
        {node.active_peers_vpn_escape > 0 && (
          <div className="flex items-center justify-between">
            <span className="text-gray-400">Пиры VPN-esc</span>
            <span className="font-medium text-amber-700">
              {node.active_peers_vpn_escape}
            </span>
          </div>
        )}
        <!-- existing rx/tx/synced rows continue unchanged -->
```

- [ ] **Step 6.3: Verify TS build**

```bash
cd /home/brolin/Documents/ITSS/AdminAZWG/CorpAdmin-AZ/.worktrees/frontend-batch/corpweb/frontend
npm run build 2>&1 | tail -10
```

Expected: build succeeds, dist regenerated.

- [ ] **Step 6.4: Commit**

```bash
cd /home/brolin/Documents/ITSS/AdminAZWG/CorpAdmin-AZ/.worktrees/frontend-batch
git add corpweb/frontend/src/pages/AdminDashboardPage.tsx
git commit -m "feat(dashboard): show escape peer counters on node card when > 0; load-bar sums 4 ifaces (CorpAdmin-AZ-adj)"
```

---

## Task 7: Deploy & manual verification

**Context:** At this point all code is on `feature/frontend-batch` with tests green. Deploy to production (one CP + two nodes) and visually verify end-to-end.

- [ ] **Step 7.1: Push branch**

```bash
cd /home/brolin/Documents/ITSS/AdminAZWG/CorpAdmin-AZ/.worktrees/frontend-batch
git push origin feature/frontend-batch
```

- [ ] **Step 7.2: Deploy agent to wgfi2**

```bash
scp -P 2201 agent/corpweb_sync_agent.py brolin@wgfi2.p4i.ru:/tmp/
ssh -p 2201 brolin@wgfi2.p4i.ru 'echo "\"rcnhfl1w2z" | su -c "install -m 0755 -o root -g root /tmp/corpweb_sync_agent.py /usr/local/bin/corpweb-sync-agent.py && systemctl restart corpweb-sync-agent && sleep 3 && systemctl status corpweb-sync-agent --no-pager | head -10"'
```

Expected: service restarts cleanly; status shows `active (running)`.

- [ ] **Step 7.3: Deploy agent to wgfi3**

```bash
scp -P 2201 agent/corpweb_sync_agent.py brolin@wgfi3.p4i.ru:/tmp/
ssh -p 2201 brolin@wgfi3.p4i.ru 'echo "\"rcnhfl1w2z" | su -c "install -m 0755 -o root -g root /tmp/corpweb_sync_agent.py /usr/local/bin/corpweb-sync-agent.py && systemctl restart corpweb-sync-agent && sleep 3 && systemctl status corpweb-sync-agent --no-pager | head -10"'
```

Expected: same as 7.2.

- [ ] **Step 7.4: Deploy backend on CP**

```bash
rsync -avz -e "ssh -p 2201" corpweb/backend/app/ brolin@wgfi2.p4i.ru:/tmp/corpweb-backend-app/
ssh -p 2201 brolin@wgfi2.p4i.ru 'echo "\"rcnhfl1w2z" | su -c "rm -rf /opt/corpweb/backend/app && cp -r /tmp/corpweb-backend-app /opt/corpweb/backend/app && systemctl restart corpweb-backend && sleep 2 && systemctl status corpweb-backend --no-pager | head -8"'
```

Expected: backend restarts, status `active (running)`. No `alembic upgrade` needed (no new migrations).

- [ ] **Step 7.5: Deploy frontend on CP**

```bash
rsync -avz -e "ssh -p 2201" corpweb/frontend/dist/ brolin@wgfi2.p4i.ru:/tmp/corpweb-dist-frontend-batch/
ssh -p 2201 brolin@wgfi2.p4i.ru 'echo "\"rcnhfl1w2z" | su -c "rm -rf /opt/corpweb/frontend/assets /opt/corpweb/frontend/index.html && cp -r /tmp/corpweb-dist-frontend-batch/* /opt/corpweb/frontend/ && ls /opt/corpweb/frontend/assets/"'
```

Expected: fresh `index-*.js` + `index-*.css` in `/opt/corpweb/frontend/assets/`.

- [ ] **Step 7.6: Manual visual verification**

In the admin browser session (Ctrl+F5 to flush):

1. **AdminDashboardPage** — when at least one escape peer is active on any node, that node's card shows a «Пиры AZ-esc: N» row in orange and/or «Пиры VPN-esc: N» row in amber. Nodes with zero escape peers show no extra rows (only the existing «Пиры AZ / VPN» line).
2. **MonitoringPage** — table rows for peers on `az_escape` show orange «AZ-esc» badge; rows for `vpn_escape` show amber «VPN-esc» badge. Rows for baseline `antizapret` remain blue «AZ»; `vpn` become green «VPN» (was blue before).
3. **LoadDistributionBar** on dashboard — total count in the bar's segment titles reflects all 4 iface counters, not just AZ + VPN.

If no escape peers are currently connected, either ask the operator to enable `Обход блокировки` on a test client and reconnect, or accept the UI-only verification (empty state shows no escape rows — that's the correct behaviour per D2).

- [ ] **Step 7.7: Update beads description on adj**

Bd task `CorpAdmin-AZ-adj` description mentions «aggregate, dedup by public_key, add режим column» — which we explicitly rejected in favour of D. Update to reflect shipped scope:

```bash
bd update CorpAdmin-AZ-adj --description="Surface escape-mode peers (az_escape + vpn_escape) in admin dashboard and monitoring via minimal extension — agent enumerates 4 ifaces, backend IP-map covers 10.26/10.27, frontend badge uses strict iface match with per-iface colour. No dedup, no separate Режим column — iface colour carries the mode signal. See docs/superpowers/specs/2026-04-24-adj-escape-peers-surface-design.md."
```

- [ ] **Step 7.8: Close the bead**

```bash
bd close CorpAdmin-AZ-adj --reason "Shipped via feature/frontend-batch — 4-iface agent, IP-map 10.26/10.27, dashboard counters, MonitoringPage per-iface badge colours. Deployed to wgfi2 + wgfi3 + CP on 2026-04-24."
```

After `adj` closes, epic `CorpAdmin-AZ-te3` has only `t2r` (P3, parked) left — invoke `superpowers:finishing-a-development-branch` next to decide merge strategy for `feature/frontend-batch → CorpAdmin`.

---

## Self-review checklist (already applied)

- **Spec coverage:** D1 (minimal extension) → Tasks 1-6; D2 (conditional display) → Task 6.2; D3 (badge palette) → Task 5.1; D4 (single iface source of truth) → Task 1.4 constant; D5 (graceful missing iface) → Task 1.2 third test; D6 (metric keys additive) → Task 1.4 dict-comprehension + Task 3.4 separate keys; D7 (LoadDistributionBar sums 4) → Task 6.1.
- **Placeholder scan:** no TBD/TODO; every step has concrete code blocks or exact commands.
- **Type consistency:** `DashboardNode` fields `active_peers_az_escape` / `active_peers_vpn_escape` are used with identical names in Tasks 3 (backend), 4 (type), 6 (consumption). `_IFACES` constant name consistent in Tasks 1.1-1.5.
- **Test coverage:** 3 new agent tests + 1 monitoring service test + 1 admin dashboard test = 5 new tests total. TDD RED-verified in Steps 1.3, 2.2, 3.3.
