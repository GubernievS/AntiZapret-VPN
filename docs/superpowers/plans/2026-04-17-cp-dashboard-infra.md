# CP Dashboard & Infrastructure — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Admin Dashboard with node analytics, monitoring from agent metrics, AZ settings via DB, DNAT balancer editor, automatic node configuration via agent.

**Architecture:** Agent heartbeat v2 sends full peer list + rx/tx. Backend reads from `nodes.metrics`/`peers_snapshot` instead of local `wg show`. AntizapretService reads/writes via WgBlobStore. Balancer module abstracts iptables DNAT management. Frontend: admin dashboard as landing page, monitoring from node data, DNAT editor on Nodes page.

**Tech Stack:** FastAPI + SQLAlchemy + asyncpg + React/TypeScript + Tailwind. Agent: Python stdlib + requests.

---

## File Map

| Action | Path | Purpose |
|--------|------|---------|
| Create | `alembic/versions/0003_peers_snapshot.py` | Add peers_snapshot column |
| Modify | `app/db/models.py` | Add peers_snapshot to Node |
| Modify | `agent/corpweb_sync_agent.py` | Heartbeat v2: peers + rx/tx |
| Modify | `app/api/v1/agent.py` | Accept peers in heartbeat |
| Create | `app/services/balancer.py` | iptables DNAT abstraction |
| Create | `app/api/v1/balancer.py` | GET/PUT /nodes/balancer |
| Modify | `app/services/antizapret.py` | Read/write via WgBlobStore |
| Modify | `app/api/v1/antizapret.py` | Use WgBlobStore + apply-status |
| Modify | `app/services/monitoring.py` | Rewrite: read from nodes |
| Modify | `app/api/v1/monitoring.py` | Simplify endpoints |
| Create | `app/api/v1/admin_dashboard.py` | Dashboard aggregation endpoint |
| Modify | `app/main.py` | Register new routers |
| Create | `frontend/src/pages/AdminDashboardPage.tsx` | Dashboard with widgets |
| Modify | `frontend/src/pages/MonitoringPage.tsx` | Table from peers_snapshot |
| Modify | `frontend/src/pages/NodesPage.tsx` | Add balancer section |
| Modify | `frontend/src/components/AddNodeModal.tsx` | Step 3: balancer offer |
| Modify | `frontend/src/pages/AdminAntizapretPage.tsx` | Apply-status feedback |
| Create | `frontend/src/api/dashboard.ts` | Dashboard API |
| Create | `frontend/src/api/balancer.ts` | Balancer API |
| Modify | `frontend/src/App.tsx` | Admin route: /admin/dashboard |

All backend paths relative to `corpweb/backend/`. All frontend paths relative to `corpweb/frontend/src/`.

---

### Task 1: Alembic migration — peers_snapshot column

**Files:**
- Create: `corpweb/backend/alembic/versions/0003_peers_snapshot.py`
- Modify: `corpweb/backend/app/db/models.py`
- Test: `corpweb/backend/tests/test_models_ha.py`

- [ ] **Step 1: Write failing test**

```python
# Add to corpweb/backend/tests/test_models_ha.py

def test_node_peers_snapshot(db):
    from app.db.models import Node
    node = Node(
        hostname="test-snap",
        private_ip="10.0.0.1",
        enroll_token="tok-snap",
        peers_snapshot=[
            {"public_key": "abc==", "allowed_ips": "10.29.8.2/32", "endpoint": "1.2.3.4:51443",
             "latest_handshake": 1776359263, "rx_bytes": 1000, "tx_bytes": 2000}
        ],
    )
    db.add(node)
    db.commit()
    db.refresh(node)
    assert len(node.peers_snapshot) == 1
    assert node.peers_snapshot[0]["public_key"] == "abc=="
```

- [ ] **Step 2: Run to verify failure**

```bash
cd corpweb/backend && python -m pytest tests/test_models_ha.py::test_node_peers_snapshot -v
```
Expected: TypeError — `peers_snapshot` is not a valid field

- [ ] **Step 3: Add column to Node model**

In `corpweb/backend/app/db/models.py`, add to Node class:

```python
    peers_snapshot = Column(JSONB, nullable=True)
```

- [ ] **Step 4: Run test**

```bash
cd corpweb/backend && python -m pytest tests/test_models_ha.py -v
```
Expected: 4 passed

- [ ] **Step 5: Create alembic migration**

```python
# corpweb/backend/alembic/versions/0003_peers_snapshot.py
"""Add peers_snapshot to nodes

Revision ID: 0003
Revises: 0002
Create Date: 2026-04-17
"""
from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql

revision = '0003'
down_revision = '0002'

def upgrade() -> None:
    op.add_column('nodes', sa.Column('peers_snapshot', postgresql.JSONB(), nullable=True))

def downgrade() -> None:
    op.drop_column('nodes', 'peers_snapshot')
```

- [ ] **Step 6: Commit**

```bash
git add corpweb/backend/app/db/models.py corpweb/backend/alembic/versions/0003_peers_snapshot.py corpweb/backend/tests/test_models_ha.py
git commit -m "feat: add nodes.peers_snapshot column for heartbeat v2"
```

---

### Task 2: Agent heartbeat v2 — peers + rx/tx

**Files:**
- Modify: `agent/corpweb_sync_agent.py`
- Modify: `corpweb/backend/app/api/v1/agent.py`
- Test: `corpweb/backend/tests/test_agent_api.py`

- [ ] **Step 1: Write failing test**

Add to `corpweb/backend/tests/test_agent_api.py`:

```python
class TestHeartbeatV2:
    def test_heartbeat_stores_peers_snapshot(self, client, db):
        node = _make_node(db)
        resp = client.post(
            "/api/v1/agent/heartbeat",
            headers=_agent_auth(node.enroll_token),
            json={
                "applied_sha": {},
                "health": "ok",
                "metrics": {"active_peers_antizapret": 2, "active_peers_vpn": 0,
                            "rx_bytes_per_sec": 1000, "tx_bytes_per_sec": 2000},
                "peers": [
                    {"public_key": "pk1==", "allowed_ips": "10.29.8.2/32",
                     "endpoint": "1.2.3.4:51443", "latest_handshake": 1776359263,
                     "rx_bytes": 100, "tx_bytes": 200},
                ],
            },
        )
        assert resp.status_code == 200
        db.refresh(node)
        assert node.peers_snapshot is not None
        assert len(node.peers_snapshot) == 1
        assert node.peers_snapshot[0]["public_key"] == "pk1=="
```

- [ ] **Step 2: Run to verify failure**

```bash
cd corpweb/backend && python -m pytest tests/test_agent_api.py::TestHeartbeatV2 -v
```
Expected: FAIL — heartbeat endpoint ignores `peers` field, `peers_snapshot` stays None

- [ ] **Step 3: Update heartbeat endpoint in agent.py**

In `corpweb/backend/app/api/v1/agent.py`, update `HeartbeatRequest` model:

```python
class HeartbeatRequest(BaseModel):
    applied_sha: dict
    health: str
    metrics: dict = {}
    peers: list = []
```

Update `heartbeat` function — add after `node.metrics = req.metrics`:

```python
    if req.peers:
        node.peers_snapshot = req.peers
```

- [ ] **Step 4: Run test**

```bash
cd corpweb/backend && python -m pytest tests/test_agent_api.py -v
```
Expected: all pass

- [ ] **Step 5: Update agent collect_metrics and heartbeat**

In `agent/corpweb_sync_agent.py`, add `collect_peers()` function:

```python
def collect_peers() -> list[dict]:
    """Collect full peer list from all WG interfaces."""
    peers = []
    for iface in ("antizapret", "vpn"):
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

Update `collect_metrics()` to add rx/tx bytes per sec:

```python
_prev_rx = 0
_prev_tx = 0
_prev_ts = 0.0

def collect_metrics() -> dict:
    global _prev_rx, _prev_tx, _prev_ts
    metrics = {
        "active_peers_antizapret": _active_peers("antizapret"),
        "active_peers_vpn": _active_peers("vpn"),
    }
    # rx/tx from /proc/net/dev
    try:
        with open("/proc/net/dev") as f:
            for line in f:
                parts = line.split()
                if len(parts) >= 10 and ("eth0" in parts[0] or "ens" in parts[0]):
                    rx = int(parts[1])
                    tx = int(parts[9])
                    now = time.monotonic()
                    if _prev_ts > 0:
                        dt = max(now - _prev_ts, 1)
                        metrics["rx_bytes_per_sec"] = int((rx - _prev_rx) / dt)
                        metrics["tx_bytes_per_sec"] = int((tx - _prev_tx) / dt)
                    _prev_rx, _prev_tx, _prev_ts = rx, tx, now
                    break
    except Exception:
        pass
    return metrics
```

Update `send_heartbeat()` to include peers:

```python
def send_heartbeat() -> None:
    payload = {
        "applied_sha": _applied_shas(),
        "health": "ok",
        "metrics": collect_metrics(),
        "peers": collect_peers(),
    }
    ...
```

- [ ] **Step 6: Commit**

```bash
git add agent/corpweb_sync_agent.py corpweb/backend/app/api/v1/agent.py corpweb/backend/tests/test_agent_api.py
git commit -m "feat: heartbeat v2 — peers list + rx/tx bytes per sec"
```

---

### Task 3: Balancer module — iptables DNAT abstraction

**Files:**
- Create: `corpweb/backend/app/services/balancer.py`
- Create: `corpweb/backend/app/api/v1/balancer.py`
- Modify: `corpweb/backend/app/main.py`
- Test: `corpweb/backend/tests/test_balancer.py`

- [ ] **Step 1: Write failing tests**

```python
# corpweb/backend/tests/test_balancer.py
from app.services.balancer import generate_iptables_rules, parse_iptables_output, weights_to_probabilities

def test_weights_to_probabilities_two_nodes():
    probs = weights_to_probabilities([50, 50])
    assert probs == [0.5, None]  # last is fallback

def test_weights_to_probabilities_three_nodes():
    probs = weights_to_probabilities([50, 30, 20])
    assert abs(probs[0] - 0.5) < 0.01
    assert abs(probs[1] - 0.6) < 0.01
    assert probs[2] is None

def test_generate_rules_two_nodes():
    nodes = [
        {"ip": "89.125.39.44", "weight": 50, "enabled": True},
        {"ip": "89.125.198.77", "weight": 50, "enabled": True},
    ]
    rules = generate_iptables_rules(nodes, ports=[51443, 51080, 52443, 52080])
    # 4 ports × 2 rules each (one with probability, one fallback)
    assert len(rules) == 8
    assert any("--probability 0.5" in r and "51443" in r for r in rules)
    assert any("89.125.198.77:51443" in r for r in rules)

def test_generate_rules_disabled_node():
    nodes = [
        {"ip": "89.125.39.44", "weight": 100, "enabled": True},
        {"ip": "89.125.198.77", "weight": 0, "enabled": False},
    ]
    rules = generate_iptables_rules(nodes, ports=[51443])
    assert all("89.125.198.77" not in r for r in rules)

def test_parse_iptables_output():
    output = """Chain PREROUTING (policy ACCEPT)
target     prot opt source               destination
DNAT       17   --  0.0.0.0/0            0.0.0.0/0            udp dpt:51443 statistic mode random probability 0.50000000000 to:89.125.39.44:51443
DNAT       17   --  0.0.0.0/0            0.0.0.0/0            udp dpt:51443 to:89.125.198.77:51443"""
    nodes = parse_iptables_output(output)
    assert len(nodes) == 2
    assert nodes["89.125.39.44"]["weight"] == 50
    assert nodes["89.125.198.77"]["weight"] == 50
```

- [ ] **Step 2: Run to verify failure**

```bash
cd corpweb/backend && python -m pytest tests/test_balancer.py -v
```
Expected: ModuleNotFoundError

- [ ] **Step 3: Create balancer.py**

```python
# corpweb/backend/app/services/balancer.py
"""
iptables DNAT balancer abstraction.
Generates, parses, and applies iptables rules for UDP load balancing.
Can be replaced with IPVS in the future without changing the API.
"""
import logging
import re
import subprocess

logger = logging.getLogger(__name__)

WG_PORTS = [51443, 51080, 52443, 52080]


def weights_to_probabilities(weights: list[int]) -> list[float | None]:
    """
    Convert weights to iptables --probability values.
    Last enabled node has no probability (fallback).

    Example: [50, 30, 20] → [0.5, 0.6, None]
    Formula: prob[i] = weight[i] / sum(weight[i:])
    """
    result = []
    remaining = sum(weights)
    for i, w in enumerate(weights):
        if remaining <= 0:
            result.append(None)
            continue
        if i == len(weights) - 1:
            result.append(None)  # last = fallback
        else:
            result.append(round(w / remaining, 5))
        remaining -= w
    return result


def generate_iptables_rules(
    nodes: list[dict],
    ports: list[int] | None = None,
) -> list[str]:
    """
    Generate iptables -t nat -A PREROUTING rules for DNAT balancing.
    nodes: [{"ip": "x.x.x.x", "weight": 50, "enabled": True}, ...]
    Returns list of iptables rule strings (without 'iptables -t nat' prefix).
    """
    if ports is None:
        ports = WG_PORTS

    enabled = [n for n in nodes if n.get("enabled")]
    if not enabled:
        return []

    weights = [n["weight"] for n in enabled]
    probs = weights_to_probabilities(weights)
    rules = []

    for port in ports:
        for i, node in enumerate(enabled):
            rule = f"-A PREROUTING -p udp --dport {port}"
            if probs[i] is not None:
                rule += f" -m statistic --mode random --probability {probs[i]}"
            rule += f" -j DNAT --to-destination {node['ip']}:{port}"
            rules.append(rule)

    return rules


def generate_postrouting_rules(nodes: list[dict]) -> list[str]:
    """Generate SNAT rules for return traffic from all nodes."""
    seen = set()
    rules = []
    for n in nodes:
        if n.get("enabled") and n["ip"] not in seen:
            seen.add(n["ip"])
            rules.append(f"-A POSTROUTING -d {n['ip']} -j SNAT --to-source {{CP_IP}}")
    return rules


def parse_iptables_output(output: str) -> dict[str, dict]:
    """
    Parse `iptables -t nat -L PREROUTING -n` output into node weights.
    Returns {ip: {"weight": N, "enabled": True}} — weights are approximate (from probability).
    """
    # Find all DNAT rules with their probabilities
    ip_prob: dict[str, list[float]] = {}
    for line in output.splitlines():
        if "DNAT" not in line or "udp" not in line:
            continue
        # Extract destination IP
        dest_match = re.search(r'to:(\d+\.\d+\.\d+\.\d+):\d+', line)
        if not dest_match:
            continue
        ip = dest_match.group(1)
        # Extract probability (if present)
        prob_match = re.search(r'probability\s+([\d.]+)', line)
        prob = float(prob_match.group(1)) if prob_match else None

        if ip not in ip_prob:
            ip_prob[ip] = []
        ip_prob[ip].append(prob)

    if not ip_prob:
        return {}

    # Reconstruct weights from probabilities
    # Each IP may appear multiple times (once per port). Use the first probability found.
    ips = list(ip_prob.keys())
    raw_probs = []
    for ip in ips:
        probs = [p for p in ip_prob[ip] if p is not None]
        raw_probs.append(probs[0] if probs else None)

    # Reverse the probability calculation to get weights
    weights = _probabilities_to_weights(raw_probs)

    result = {}
    for i, ip in enumerate(ips):
        result[ip] = {"weight": weights[i], "enabled": True}
    return result


def _probabilities_to_weights(probs: list[float | None]) -> list[int]:
    """
    Reverse probability → weights.
    With N nodes, prob[0] = w0 / total, prob[1] = w1 / (total - w0), etc.
    """
    n = len(probs)
    if n == 0:
        return []
    if n == 1:
        return [100]

    weights = []
    remaining = 100.0
    for i, p in enumerate(probs):
        if p is None:
            weights.append(round(remaining))
        else:
            w = round(p * remaining)
            weights.append(w)
            remaining -= w

    # Normalize to sum=100
    total = sum(weights)
    if total > 0 and total != 100:
        weights = [round(w * 100 / total) for w in weights]
        # Fix rounding
        diff = 100 - sum(weights)
        weights[-1] += diff

    return weights


def apply_rules(nodes: list[dict], cp_ip: str) -> dict:
    """
    Apply DNAT + SNAT rules via iptables. Returns the actual state after apply.
    Raises RuntimeError on iptables error.
    """
    pre_rules = generate_iptables_rules(nodes)
    post_rules = generate_postrouting_rules(nodes)

    # Build full iptables-restore input for nat table
    lines = ["*nat", ":PREROUTING ACCEPT [0:0]", ":INPUT ACCEPT [0:0]",
             ":OUTPUT ACCEPT [0:0]", ":POSTROUTING ACCEPT [0:0]"]
    lines.extend(pre_rules)
    for r in post_rules:
        lines.append(r.replace("{CP_IP}", cp_ip))
    lines.append("COMMIT\n")
    restore_input = "\n".join(lines)

    # Test first
    test = subprocess.run(
        ["iptables-restore", "--test"],
        input=restore_input, capture_output=True, text=True,
    )
    if test.returncode != 0:
        raise RuntimeError(f"iptables-restore --test failed: {test.stderr}")

    # Apply
    result = subprocess.run(
        ["iptables-restore"],
        input=restore_input, capture_output=True, text=True,
    )
    if result.returncode != 0:
        raise RuntimeError(f"iptables-restore failed: {result.stderr}")

    # Save
    subprocess.run(["netfilter-persistent", "save"], capture_output=True)

    # Return actual state
    return read_current_state()


def read_current_state() -> dict:
    """Read current iptables PREROUTING rules and return parsed state."""
    try:
        result = subprocess.run(
            ["iptables", "-t", "nat", "-L", "PREROUTING", "-n"],
            capture_output=True, text=True, timeout=5,
        )
        return parse_iptables_output(result.stdout)
    except Exception:
        return {}
```

- [ ] **Step 4: Run tests**

```bash
cd corpweb/backend && python -m pytest tests/test_balancer.py -v
```
Expected: 5 passed

- [ ] **Step 5: Create balancer API endpoint**

```python
# corpweb/backend/app/api/v1/balancer.py
"""Balancer API — manage iptables DNAT load balancing."""
import subprocess
from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel
from sqlalchemy.orm import Session

from app.db.session import get_db
from app.db.models import Node
from app.api.deps import require_admin
from app.services.balancer import read_current_state, apply_rules

router = APIRouter()


class BalancerNode(BaseModel):
    ip: str
    weight: int
    enabled: bool


class BalancerUpdate(BaseModel):
    nodes: list[BalancerNode]


@router.get("")
def get_balancer(
    db: Session = Depends(get_db),
    _=Depends(require_admin),
):
    """Read actual iptables state and merge with known nodes."""
    iptables_state = read_current_state()
    db_nodes = db.query(Node).order_by(Node.id).all()

    result = []
    for n in db_nodes:
        ipt = iptables_state.get(n.private_ip, {})
        result.append({
            "id": n.id,
            "hostname": n.hostname,
            "ip": n.private_ip,
            "health": n.health,
            "weight": ipt.get("weight", 0),
            "enabled": ipt.get("enabled", False),
        })
    return {"nodes": result}


@router.put("")
def update_balancer(
    data: BalancerUpdate,
    db: Session = Depends(get_db),
    _=Depends(require_admin),
):
    """Apply new balancer weights. Validates sum=100, applies iptables, returns actual state."""
    enabled = [n for n in data.nodes if n.enabled]
    if not enabled:
        raise HTTPException(400, "At least one node must be enabled")

    total_weight = sum(n.weight for n in enabled)
    if total_weight != 100:
        raise HTTPException(400, f"Weights must sum to 100, got {total_weight}")

    # Detect CP IP
    try:
        cp_ip = subprocess.run(
            ["hostname", "-I"], capture_output=True, text=True
        ).stdout.strip().split()[0]
    except Exception:
        cp_ip = "92.118.85.140"

    nodes = [{"ip": n.ip, "weight": n.weight, "enabled": n.enabled} for n in data.nodes]

    try:
        actual = apply_rules(nodes, cp_ip)
    except RuntimeError as e:
        raise HTTPException(500, f"Failed to apply iptables: {e}")

    # Return fresh state
    db_nodes = db.query(Node).order_by(Node.id).all()
    result = []
    for n in db_nodes:
        ipt = actual.get(n.private_ip, {})
        result.append({
            "id": n.id,
            "hostname": n.hostname,
            "ip": n.private_ip,
            "health": n.health,
            "weight": ipt.get("weight", 0),
            "enabled": ipt.get("enabled", False),
        })
    return {"nodes": result, "applied": True}
```

- [ ] **Step 6: Register router in main.py**

```python
from app.api.v1 import balancer
app.include_router(balancer.router, prefix="/api/v1/nodes/balancer", tags=["balancer"])
```

- [ ] **Step 7: Commit**

```bash
git add corpweb/backend/app/services/balancer.py corpweb/backend/app/api/v1/balancer.py \
        corpweb/backend/app/main.py corpweb/backend/tests/test_balancer.py
git commit -m "feat: iptables DNAT balancer module + API endpoints"
```

---

### Task 4: AntizapretService → WgBlobStore

**Files:**
- Modify: `corpweb/backend/app/services/antizapret.py`
- Modify: `corpweb/backend/app/api/v1/antizapret.py`
- Test: `corpweb/backend/tests/test_antizapret_blob.py`

- [ ] **Step 1: Write failing test**

```python
# corpweb/backend/tests/test_antizapret_blob.py
from app.services.antizapret import AntizapretService, EDITABLE_FILES
from app.services.wg_blob_store import WgBlobStore


def test_get_file_from_blobstore(db):
    store = WgBlobStore(db)
    store.put("/root/antizapret/config/include-hosts.txt", b"example.com\n", by="test")

    svc = AntizapretService(db)
    content = svc.get_file_content("include_hosts")
    assert content == "example.com\n"


def test_save_file_to_blobstore(db):
    svc = AntizapretService(db)
    svc.save_file_content("include_hosts", "new.example.com\n")

    store = WgBlobStore(db)
    blob = store.get("/root/antizapret/config/include-hosts.txt")
    assert blob == b"new.example.com\n"


def test_get_settings_from_blobstore(db):
    store = WgBlobStore(db)
    store.put("/root/antizapret/setup", b"DISCORD_INCLUDE=y\nROUTE_ALL=n\n", by="test")

    svc = AntizapretService(db)
    settings = svc.get_settings()
    assert settings["DISCORD_INCLUDE"] == "y"
    assert settings["ROUTE_ALL"] == "n"


def test_update_settings_in_blobstore(db):
    store = WgBlobStore(db)
    store.put("/root/antizapret/setup", b"DISCORD_INCLUDE=y\nROUTE_ALL=n\n", by="test")

    svc = AntizapretService(db)
    changed = svc.update_settings({"ROUTE_ALL": "y"})
    assert changed == 1

    blob = store.get("/root/antizapret/setup")
    assert b"ROUTE_ALL=y" in blob


def test_file_content_roundtrip_preserves_bytes(db):
    """Ensure trailing newlines, empty lines, unicode are preserved."""
    original = "# Comment\nexample.com\n\ntest.org\n"
    svc = AntizapretService(db)
    svc.save_file_content("include_hosts", original)
    result = svc.get_file_content("include_hosts")
    assert result == original
```

- [ ] **Step 2: Run to verify failure**

```bash
cd corpweb/backend && python -m pytest tests/test_antizapret_blob.py -v
```
Expected: TypeError — AntizapretService() takes no db argument

- [ ] **Step 3: Rewrite AntizapretService to use WgBlobStore**

Replace `corpweb/backend/app/services/antizapret.py`:

```python
"""
Antizapret configuration service.
Reads/writes via WgBlobStore (DB) instead of local filesystem.
Changes propagate to nodes via pg_notify → sync-agent.
"""
import re
import logging
from typing import Dict, Optional

from sqlalchemy.orm import Session

from app.services.wg_blob_store import WgBlobStore

logger = logging.getLogger(__name__)

ANTIZAPRET_SETUP_PATH = "/root/antizapret/setup"

EDITABLE_FILES: Dict[str, str] = {
    "include_hosts": "/root/antizapret/config/include-hosts.txt",
    "exclude_hosts": "/root/antizapret/config/exclude-hosts.txt",
    "include_ips": "/root/antizapret/config/include-ips.txt",
}

BOOLEAN_SETTINGS = [
    "ROUTE_ALL", "DISCORD_INCLUDE", "CLOUDFLARE_INCLUDE", "AMAZON_INCLUDE",
    "GOOGLE_INCLUDE", "WHATSAPP_INCLUDE", "TELEGRAM_INCLUDE", "HETZNER_INCLUDE",
    "DIGITALOCEAN_INCLUDE", "OVH_INCLUDE", "AKAMAI_INCLUDE", "ROBLOX_INCLUDE",
    "BLOCK_ADS", "CLEAR_HOSTS", "OPENVPN_80_443_TCP", "OPENVPN_80_443_UDP",
    "SSH_PROTECTION", "ATTACK_PROTECTION", "TORRENT_GUARD", "RESTRICT_FORWARD",
]

STRING_SETTINGS = ["OPENVPN_HOST", "WIREGUARD_HOST"]
ALL_KNOWN_SETTINGS = BOOLEAN_SETTINGS + STRING_SETTINGS


class AntizapretServiceError(Exception):
    pass


class AntizapretService:

    def __init__(self, db: Session):
        self._store = WgBlobStore(db)

    def get_file_content(self, file_type: str) -> str:
        if file_type not in EDITABLE_FILES:
            raise AntizapretServiceError(f"Unknown file type: {file_type}")
        blob = self._store.get(EDITABLE_FILES[file_type])
        if blob is None:
            return ""
        return blob.decode("utf-8")

    def save_file_content(self, file_type: str, content: str) -> None:
        if file_type not in EDITABLE_FILES:
            raise AntizapretServiceError(f"Unknown file type: {file_type}")
        self._store.put(EDITABLE_FILES[file_type], content.encode("utf-8"), by="admin")
        logger.info("Saved %s to WgBlobStore", EDITABLE_FILES[file_type])

    def get_settings(self) -> Dict[str, Optional[str]]:
        result: Dict[str, Optional[str]] = {k: None for k in ALL_KNOWN_SETTINGS}
        blob = self._store.get(ANTIZAPRET_SETUP_PATH)
        if blob is None:
            return result
        content = blob.decode("utf-8")
        pattern = re.compile(r'^([A-Z0-9_]+)=["\']?([^"\'#\n]*)["\']?\s*(?:#.*)?$', re.MULTILINE)
        for match in pattern.finditer(content):
            key, value = match.group(1), match.group(2).strip()
            if key in result:
                result[key] = value
        return result

    def update_settings(self, new_settings: Dict[str, str]) -> int:
        blob = self._store.get(ANTIZAPRET_SETUP_PATH)
        if blob is None:
            raise AntizapretServiceError("Setup file not found in DB")
        content = blob.decode("utf-8")
        changed = 0
        for key, value in new_settings.items():
            if key not in ALL_KNOWN_SETTINGS:
                continue
            if key in BOOLEAN_SETTINGS:
                value = "y" if value.lower() in ("y", "yes", "true", "1") else "n"
            line_pattern = re.compile(rf'^{re.escape(key)}=.*$', re.MULTILINE)
            new_line = f"{key}={value}"
            if line_pattern.search(content):
                content = line_pattern.sub(new_line, content)
            else:
                content = content.rstrip("\n") + f"\n{new_line}\n"
            changed += 1
        self._store.put(ANTIZAPRET_SETUP_PATH, content.encode("utf-8"), by="admin")
        logger.info("Updated %d antizapret settings", changed)
        return changed
```

Note: the singleton `antizapret_service = AntizapretService()` is removed. Each call creates instance with `db`.

- [ ] **Step 4: Update antizapret API endpoints**

In `corpweb/backend/app/api/v1/antizapret.py`, replace singleton with `db`-backed instantiation:

```python
# Remove: from app.services.antizapret import antizapret_service
# Add:
from app.services.antizapret import AntizapretService, AntizapretServiceError, EDITABLE_FILES

# In each endpoint, instantiate:
#   svc = AntizapretService(db)
# Replace antizapret_service.xxx(args) with svc.xxx(args)
# Add db: Session = Depends(get_db) to each endpoint signature
# Remove run_doall endpoint (no longer needed — agents auto-apply)
```

Update `get_file`:
```python
@router.get("/files/{file_type}", response_model=FileContentResponse)
async def get_file(
    file_type: str,
    db: Session = Depends(get_db),
    _admin: User = Depends(require_admin),
):
    if file_type not in EDITABLE_FILES:
        raise HTTPException(status_code=404, detail=f"Unknown file type '{file_type}'")
    svc = AntizapretService(db)
    try:
        content = svc.get_file_content(file_type)
    except AntizapretServiceError as e:
        raise HTTPException(status_code=500, detail=str(e))
    return FileContentResponse(file_type=file_type, content=content)
```

Same pattern for `save_file`, `get_settings`, `update_settings`. Remove `run_doall` endpoint.

- [ ] **Step 5: Run tests**

```bash
cd corpweb/backend && python -m pytest tests/test_antizapret_blob.py -v
```
Expected: 5 passed

- [ ] **Step 6: Commit**

```bash
git add corpweb/backend/app/services/antizapret.py corpweb/backend/app/api/v1/antizapret.py \
        corpweb/backend/tests/test_antizapret_blob.py
git commit -m "feat: AntizapretService reads/writes via WgBlobStore instead of filesystem"
```

---

### Task 5: Monitoring rewrite — data from nodes

**Files:**
- Modify: `corpweb/backend/app/services/monitoring.py`
- Modify: `corpweb/backend/app/api/v1/monitoring.py`
- Test: `corpweb/backend/tests/test_monitoring_new.py`

- [ ] **Step 1: Write failing test**

```python
# corpweb/backend/tests/test_monitoring_new.py
from app.services.monitoring import MonitoringService
from app.db.models import Node, VPNConfig
import uuid
from datetime import datetime


def _make_node_with_peers(db, hostname="node1", peers=None):
    node = Node(
        hostname=hostname, private_ip="10.0.0.1", enroll_token=f"tok-{hostname}",
        health="ok",
        metrics={"active_peers_antizapret": 2, "active_peers_vpn": 0,
                 "rx_bytes_per_sec": 1000, "tx_bytes_per_sec": 2000},
        peers_snapshot=peers or [],
    )
    db.add(node)
    db.commit()
    return node


def test_get_active_connections(db):
    import time
    now = int(time.time())
    _make_node_with_peers(db, "n1", [
        {"public_key": "pk1", "allowed_ips": "10.29.8.2/32", "endpoint": "1.2.3.4:51443",
         "latest_handshake": now - 10, "rx_bytes": 100, "tx_bytes": 200, "interface": "antizapret"},
        {"public_key": "pk2", "allowed_ips": "10.29.8.3/32", "endpoint": "5.6.7.8:51443",
         "latest_handshake": now - 300, "rx_bytes": 100, "tx_bytes": 200, "interface": "antizapret"},
    ])
    svc = MonitoringService(db)
    conns = svc.get_active_connections()
    assert len(conns) == 1  # only pk1, pk2 handshake too old
    assert conns[0]["public_key"] == "pk1"
    assert conns[0]["node"] == "n1"


def test_get_traffic_stats(db):
    _make_node_with_peers(db, "n1")
    _make_node_with_peers(db, "n2")
    svc = MonitoringService(db)
    stats = svc.get_traffic_stats()
    assert stats["total_rx_bytes_per_sec"] == 2000
    assert stats["total_tx_bytes_per_sec"] == 4000
    assert len(stats["per_node"]) == 2
```

- [ ] **Step 2: Run to verify failure**

```bash
cd corpweb/backend && python -m pytest tests/test_monitoring_new.py -v
```

- [ ] **Step 3: Rewrite monitoring.py**

Replace `corpweb/backend/app/services/monitoring.py` entirely:

```python
"""
Monitoring service — reads peer data from nodes.peers_snapshot (agent heartbeats).
No local wg show or OpenVPN parsing.
"""
import time
from sqlalchemy.orm import Session
from app.db.models import Node, VPNConfig

ACTIVE_HANDSHAKE_MAX_AGE = 30  # seconds (2 × PersistentKeepalive)


class MonitoringService:

    def __init__(self, db: Session):
        self._db = db

    def get_active_connections(self, node_filter: str | None = None) -> list[dict]:
        """
        Return active peers from all live nodes.
        Active = handshake < 30s ago.
        Resolves client names from vpn_configs.
        """
        query = self._db.query(Node).filter(Node.health.in_(["ok", "degraded"]))
        if node_filter:
            query = query.filter(Node.hostname == node_filter)
        nodes = query.all()

        ip_to_name = self._build_ip_map()
        now = int(time.time())
        result = []

        for node in nodes:
            for peer in (node.peers_snapshot or []):
                hs = peer.get("latest_handshake", 0)
                if hs == 0 or (now - hs) > ACTIVE_HANDSHAKE_MAX_AGE:
                    continue
                ip = (peer.get("allowed_ips") or "").split("/")[0]
                result.append({
                    "node": node.hostname,
                    "interface": peer.get("interface", ""),
                    "public_key": peer.get("public_key", ""),
                    "client_name": ip_to_name.get(ip),
                    "endpoint": peer.get("endpoint"),
                    "allowed_ips": peer.get("allowed_ips"),
                    "handshake_age": now - hs,
                    "rx_bytes": peer.get("rx_bytes", 0),
                    "tx_bytes": peer.get("tx_bytes", 0),
                })
        return result

    def get_traffic_stats(self) -> dict:
        """Aggregate rx/tx bytes per sec across all live nodes."""
        nodes = self._db.query(Node).filter(Node.health.in_(["ok", "degraded"])).all()
        total_rx = 0
        total_tx = 0
        per_node = []
        for n in nodes:
            m = n.metrics or {}
            rx = m.get("rx_bytes_per_sec", 0)
            tx = m.get("tx_bytes_per_sec", 0)
            total_rx += rx
            total_tx += tx
            per_node.append({
                "hostname": n.hostname,
                "rx_bytes_per_sec": rx,
                "tx_bytes_per_sec": tx,
            })
        return {
            "total_rx_bytes_per_sec": total_rx,
            "total_tx_bytes_per_sec": total_tx,
            "per_node": per_node,
        }

    def get_overview(self) -> dict:
        """Combined stats for monitoring page."""
        return {
            "connections": self.get_active_connections(),
            "traffic": self.get_traffic_stats(),
        }

    def _build_ip_map(self) -> dict[str, str]:
        """Map VPN IP → client_name from vpn_configs."""
        configs = self._db.query(VPNConfig).filter(VPNConfig.is_active == True).all()
        result = {}
        for cfg in configs:
            meta = cfg.config_metadata or {}
            ip = meta.get("vpn_ip")
            if ip:
                result[ip] = cfg.client_name
        return result
```

- [ ] **Step 4: Update monitoring API endpoints**

Simplify `corpweb/backend/app/api/v1/monitoring.py`:

```python
"""Monitoring API — reads from node agent heartbeats."""
from fastapi import APIRouter, Depends, Query
from sqlalchemy.orm import Session

from app.api.deps import require_admin
from app.db.session import get_db
from app.services.monitoring import MonitoringService

router = APIRouter()


@router.get("/connections")
def get_connections(
    node: str = Query(None),
    db: Session = Depends(get_db),
    _=Depends(require_admin),
):
    svc = MonitoringService(db)
    return svc.get_active_connections(node_filter=node)


@router.get("/traffic")
def get_traffic(
    db: Session = Depends(get_db),
    _=Depends(require_admin),
):
    svc = MonitoringService(db)
    return svc.get_traffic_stats()


@router.get("/overview")
def get_overview(
    db: Session = Depends(get_db),
    _=Depends(require_admin),
):
    svc = MonitoringService(db)
    return svc.get_overview()
```

- [ ] **Step 5: Run tests**

```bash
cd corpweb/backend && python -m pytest tests/test_monitoring_new.py -v
```
Expected: 2 passed

- [ ] **Step 6: Commit**

```bash
git add corpweb/backend/app/services/monitoring.py corpweb/backend/app/api/v1/monitoring.py \
        corpweb/backend/tests/test_monitoring_new.py
git commit -m "feat: monitoring reads from nodes.peers_snapshot instead of local wg show"
```

---

### Task 6: Admin Dashboard backend

**Files:**
- Create: `corpweb/backend/app/api/v1/admin_dashboard.py`
- Modify: `corpweb/backend/app/main.py`
- Test: `corpweb/backend/tests/test_admin_dashboard.py`

- [ ] **Step 1: Write failing test**

```python
# corpweb/backend/tests/test_admin_dashboard.py
from tests.conftest import auth_header
from app.db.models import Node


def test_dashboard_returns_data(client, db, admin_user, admin_token):
    node = Node(hostname="n1", private_ip="10.0.0.1", enroll_token="tok-n1",
                health="ok", metrics={"active_peers_antizapret": 5, "active_peers_vpn": 2,
                                      "rx_bytes_per_sec": 1000, "tx_bytes_per_sec": 2000})
    db.add(node)
    db.commit()

    resp = client.get("/api/v1/admin/dashboard", headers=auth_header(admin_token))
    assert resp.status_code == 200
    data = resp.json()
    assert "nodes" in data
    assert "totals" in data
    assert data["totals"]["active_clients"] == 7
    assert len(data["nodes"]) == 1
    assert data["nodes"][0]["hostname"] == "n1"


def test_dashboard_requires_admin(client, db, regular_user, user_token):
    resp = client.get("/api/v1/admin/dashboard", headers=auth_header(user_token))
    assert resp.status_code == 403
```

- [ ] **Step 2: Create endpoint**

```python
# corpweb/backend/app/api/v1/admin_dashboard.py
"""Admin Dashboard — aggregate data from nodes, configs, users."""
from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session

from app.db.session import get_db
from app.db.models import Node, VPNConfig, User
from app.api.deps import require_admin
from app.services.wg_blob_store import WgBlobStore

router = APIRouter()


@router.get("")
def get_dashboard(
    db: Session = Depends(get_db),
    _=Depends(require_admin),
):
    nodes = db.query(Node).order_by(Node.id).all()
    store = WgBlobStore(db)
    all_paths = store.get_all_paths()

    total_active = 0
    node_data = []
    for n in nodes:
        m = n.metrics or {}
        az = m.get("active_peers_antizapret", 0)
        vpn = m.get("active_peers_vpn", 0)
        total_active += az + vpn

        # Check sync status
        applied = n.applied_sha or {}
        synced = all(applied.get(p) == all_paths.get(p) for p in all_paths if p.startswith("/"))

        node_data.append({
            "id": n.id,
            "hostname": n.hostname,
            "health": n.health,
            "active_peers_antizapret": az,
            "active_peers_vpn": vpn,
            "rx_bytes_per_sec": m.get("rx_bytes_per_sec", 0),
            "tx_bytes_per_sec": m.get("tx_bytes_per_sec", 0),
            "synced": synced,
            "last_seen": n.last_seen.isoformat() if n.last_seen else None,
        })

    total_configs = db.query(VPNConfig).count()
    total_users = db.query(User).count()

    return {
        "nodes": node_data,
        "totals": {
            "active_clients": total_active,
            "total_configs": total_configs,
            "total_users": total_users,
        },
    }
```

Register in main.py:
```python
from app.api.v1 import admin_dashboard
app.include_router(admin_dashboard.router, prefix="/api/v1/admin/dashboard", tags=["admin-dashboard"])
```

- [ ] **Step 3: Run tests**

```bash
cd corpweb/backend && python -m pytest tests/test_admin_dashboard.py -v
```
Expected: 2 passed

- [ ] **Step 4: Commit**

```bash
git add corpweb/backend/app/api/v1/admin_dashboard.py corpweb/backend/app/main.py \
        corpweb/backend/tests/test_admin_dashboard.py
git commit -m "feat: admin dashboard endpoint — nodes, totals, sync status"
```

---

### Task 7: Frontend — Admin Dashboard page

**Files:**
- Create: `corpweb/frontend/src/pages/AdminDashboardPage.tsx`
- Create: `corpweb/frontend/src/api/dashboard.ts`
- Modify: `corpweb/frontend/src/App.tsx`

- [ ] **Step 1: Create API module**

```typescript
// corpweb/frontend/src/api/dashboard.ts
import api from './client'

export interface DashboardNode {
  id: number
  hostname: string
  health: string | null
  active_peers_antizapret: number
  active_peers_vpn: number
  rx_bytes_per_sec: number
  tx_bytes_per_sec: number
  synced: boolean
  last_seen: string | null
}

export interface DashboardData {
  nodes: DashboardNode[]
  totals: {
    active_clients: number
    total_configs: number
    total_users: number
  }
}

export const getDashboard = () =>
  api.get<DashboardData>('/admin/dashboard').then(r => r.data)
```

- [ ] **Step 2: Create AdminDashboardPage**

Create `corpweb/frontend/src/pages/AdminDashboardPage.tsx` with:
- Node cards row: hostname, health badge, peers (AZ/VPN), traffic (rx/tx formatted), sync icon, last seen
- Totals row: active clients, total configs, total users
- Load distribution bar: colored segments per node
- Auto-refresh every 30s
- Use Tailwind, lucide-react icons, follow existing patterns

- [ ] **Step 3: Update App.tsx routing**

Add admin dashboard route:
```tsx
import AdminDashboardPage from './pages/AdminDashboardPage'
// Inside admin routes:
<Route path="/admin/dashboard" element={<ProtectedRoute requireAdmin><AdminDashboardPage /></ProtectedRoute>} />
```

Make `/admin/dashboard` the default redirect for admin users.

- [ ] **Step 4: Verify**

```bash
cd corpweb/frontend && npx tsc --noEmit && npm run build
```

- [ ] **Step 5: Commit**

```bash
git add corpweb/frontend/src/
git commit -m "feat: admin dashboard page — node cards, totals, load distribution"
```

---

### Task 8: Frontend — Monitoring page rewrite

**Files:**
- Modify: `corpweb/frontend/src/pages/MonitoringPage.tsx`
- Modify: `corpweb/frontend/src/api/monitoring.ts`

- [ ] **Step 1: Update monitoring API**

```typescript
// corpweb/frontend/src/api/monitoring.ts — replace content
import api from './client'

export interface ActiveConnection {
  node: string
  interface: string
  client_name: string | null
  endpoint: string | null
  allowed_ips: string
  handshake_age: number
  rx_bytes: number
  tx_bytes: number
}

export interface TrafficStats {
  total_rx_bytes_per_sec: number
  total_tx_bytes_per_sec: number
  per_node: { hostname: string; rx_bytes_per_sec: number; tx_bytes_per_sec: number }[]
}

export const getConnections = (node?: string) =>
  api.get<ActiveConnection[]>('/monitoring/connections', { params: node ? { node } : {} }).then(r => r.data)

export const getTraffic = () =>
  api.get<TrafficStats>('/monitoring/traffic').then(r => r.data)
```

- [ ] **Step 2: Rewrite MonitoringPage**

New MonitoringPage.tsx:
- Active connections table: Client, Node, Interface (AZ/VPN), Endpoint, Handshake age, RX/TX
- Node filter dropdown
- Traffic per node: hostname + rx/tx formatted
- Auto-refresh 30s
- Remove old chart, remove OpenVPN, remove fake traffic data

- [ ] **Step 3: Verify**

```bash
cd corpweb/frontend && npx tsc --noEmit && npm run build
```

- [ ] **Step 4: Commit**

```bash
git add corpweb/frontend/src/
git commit -m "feat: monitoring page — active connections from agent heartbeats"
```

---

### Task 9: Frontend — DNAT balancer editor + AddNodeModal fix

**Files:**
- Create: `corpweb/frontend/src/api/balancer.ts`
- Modify: `corpweb/frontend/src/pages/NodesPage.tsx`
- Modify: `corpweb/frontend/src/components/AddNodeModal.tsx`

- [ ] **Step 1: Create balancer API**

```typescript
// corpweb/frontend/src/api/balancer.ts
import api from './client'

export interface BalancerNode {
  id: number
  hostname: string
  ip: string
  health: string | null
  weight: number
  enabled: boolean
}

export const getBalancer = () =>
  api.get<{ nodes: BalancerNode[] }>('/nodes/balancer').then(r => r.data)

export const updateBalancer = (nodes: { ip: string; weight: number; enabled: boolean }[]) =>
  api.put<{ nodes: BalancerNode[]; applied: boolean }>('/nodes/balancer', { nodes }).then(r => r.data)
```

- [ ] **Step 2: Add balancer section to NodesPage**

Below the nodes table, add "Балансировка" section:
- Table: Hostname, IP, Health, Weight input (%), Enable toggle
- Validation: weights sum to 100
- "Сохранить" button
- After save: show actual state from response
- Follow Tailwind patterns from existing code

- [ ] **Step 3: Fix AddNodeModal step 3**

Replace nginx upstream instructions with:
```tsx
<p>Нода добавлена. Перейдите в раздел «Балансировка» чтобы включить её в распределение трафика.</p>
<button onClick={() => { onClose(); /* navigate to balancer section */ }}>
  Перейти к балансировке
</button>
```

- [ ] **Step 4: Verify**

```bash
cd corpweb/frontend && npx tsc --noEmit && npm run build
```

- [ ] **Step 5: Commit**

```bash
git add corpweb/frontend/src/
git commit -m "feat: DNAT balancer editor + AddNodeModal references balancer"
```

---

### Task 10: Extended /agent/register — wg_config

**Files:**
- Modify: `corpweb/backend/app/api/v1/agent.py`
- Modify: `agent/corpweb_sync_agent.py`
- Test: `corpweb/backend/tests/test_agent_api.py`

- [ ] **Step 1: Write failing test**

Add to `corpweb/backend/tests/test_agent_api.py`:

```python
class TestRegisterV2:
    def test_register_returns_wg_config(self, client, db):
        node = _make_node(db)
        resp = client.post(
            "/api/v1/agent/register",
            headers=_agent_auth(node.enroll_token),
            json={"hostname": "wgfi2", "private_ip": "10.0.0.1"},
        )
        assert resp.status_code == 200
        data = resp.json()
        assert "wg_config" in data
        assert data["wg_config"]["antizapret_address"] == "10.29.8.1/21"
        assert data["wg_config"]["vpn_address"] == "10.28.8.1/21"
```

- [ ] **Step 2: Update register endpoint**

In `corpweb/backend/app/api/v1/agent.py`, update `register` function to include `wg_config`:

```python
    return {
        "node_id": node.id,
        "wg_server_keys": keys,
        "wg_config": {
            "antizapret_address": "10.29.8.1/21",
            "antizapret_listen_port": 51443,
            "vpn_address": "10.28.8.1/21",
            "vpn_listen_port": 51080,
            "mtu": 1420,
        },
    }
```

- [ ] **Step 3: Update agent to apply wg_config**

In `agent/corpweb_sync_agent.py`, update `register_if_needed()` to read `wg_config` from response and patch the `[Interface]` section of WG confs if needed (Address, PrivateKey, ListenPort, MTU).

- [ ] **Step 4: Run tests**

```bash
cd corpweb/backend && python -m pytest tests/test_agent_api.py -v
```

- [ ] **Step 5: Commit**

```bash
git add corpweb/backend/app/api/v1/agent.py agent/corpweb_sync_agent.py \
        corpweb/backend/tests/test_agent_api.py
git commit -m "feat: /agent/register returns wg_config for automatic node setup"
```

---

### Task 11: Frontend — AZ settings apply-status feedback

**Files:**
- Modify: `corpweb/frontend/src/pages/AdminAntizapretPage.tsx`

- [ ] **Step 1: Update AZ page**

After saving file/settings:
1. Call `waitForApply(path)` from `src/api/applyStatus.ts`
2. Show spinner "Применяю на нодах..."
3. On ready: "Применено на 2/2 нод" or "Применено на 1/2 — wgfi3 не отвечает"
4. Remove "Сохранить и Применить" button — "Сохранить" does both

- [ ] **Step 2: Verify**

```bash
cd corpweb/frontend && npx tsc --noEmit && npm run build
```

- [ ] **Step 3: Commit**

```bash
git add corpweb/frontend/src/
git commit -m "feat: AZ settings — apply-status feedback after save"
```
