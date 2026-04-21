# AWG Escape Obfuscation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Two opt-in escape AmneziaWG interfaces (`antizapret_escape`, `vpn_escape`) with strong obfuscation (S1/S2 > 0, custom H1-H4) to bypass ТСПУ protocol-level blocking. Admin-controlled via `ESCAPE_ENABLED` in AZ settings; user-controlled via per-download toggle "Обход блокировки" in LK.

**Architecture:** Pure-function layer (params generator, render funcs), service layer (VpnManager +2 ifaces, obfuscation service), API layer (bypass query + regenerate endpoint), agent layer (2 new managed files + hooks), frontend (2 toggle cards in LK + admin section + regenerate button).

**Tech Stack:** FastAPI + SQLAlchemy + Alembic (backend), amneziawg-tools on nodes, React/TypeScript + Vite (frontend), systemd + wg-quick for iface lifecycle.

**Related:** spec `docs/superpowers/specs/2026-04-21-awg-escape-obfuscation-design.md`, epic `CorpAdmin-AZ-roo`.

---

## Phase 1: Backend — Pure functions & DB schema

### Task 1: Alembic migration — `wg_obfuscation_params` table + `escape_enabled` column

**Files:**
- Create: `corpweb/backend/alembic/versions/<rev>_awg_escape_obfuscation.py`

- [ ] **Step 1: Generate empty migration file**

```bash
cd corpweb/backend && alembic revision -m "awg escape obfuscation"
```

- [ ] **Step 2: Fill in the migration**

```python
"""awg escape obfuscation

Revision ID: <auto>
Revises: <previous_head>
"""
from alembic import op
import sqlalchemy as sa


revision = "<auto>"
down_revision = "<previous_head>"
branch_labels = None
depends_on = None


def upgrade():
    op.create_table(
        "wg_obfuscation_params",
        sa.Column("iface", sa.String(64), primary_key=True),
        sa.Column("jc", sa.Integer, nullable=False),
        sa.Column("jmin", sa.Integer, nullable=False),
        sa.Column("jmax", sa.Integer, nullable=False),
        sa.Column("s1", sa.Integer, nullable=False),
        sa.Column("s2", sa.Integer, nullable=False),
        sa.Column("h1", sa.BigInteger, nullable=False),
        sa.Column("h2", sa.BigInteger, nullable=False),
        sa.Column("h3", sa.BigInteger, nullable=False),
        sa.Column("h4", sa.BigInteger, nullable=False),
        sa.Column("i1", sa.Text, nullable=False),
        sa.Column("created_at", sa.DateTime, server_default=sa.func.now(), nullable=False),
        sa.Column("updated_at", sa.DateTime, server_default=sa.func.now(), nullable=False),
    )
    op.add_column(
        "system_settings",
        sa.Column("escape_enabled", sa.Boolean, nullable=False, server_default=sa.false()),
    )


def downgrade():
    op.drop_column("system_settings", "escape_enabled")
    op.drop_table("wg_obfuscation_params")
```

- [ ] **Step 3: Apply migration locally, verify schema**

```bash
alembic upgrade head
python -c "from app.db.session import engine; from sqlalchemy import inspect; print(sorted(inspect(engine).get_columns('system_settings')[-1].keys())); print(inspect(engine).get_columns('wg_obfuscation_params'))"
```

Expected: `escape_enabled` in `system_settings`, 12 columns in `wg_obfuscation_params`.

- [ ] **Step 4: Commit**

```bash
git add corpweb/backend/alembic/versions/
git commit -m "feat(db): migration for wg_obfuscation_params + escape_enabled"
```

---

### Task 2: SQLAlchemy models — `WgObfuscationParams` + extend `SystemSettings`

**Files:**
- Modify: `corpweb/backend/app/db/models.py`
- Test: `corpweb/backend/tests/test_models.py` (add if missing)

- [ ] **Step 1: Write failing test**

```python
# tests/test_models.py
def test_wg_obfuscation_params_roundtrip(db_session):
    from app.db.models import WgObfuscationParams
    row = WgObfuscationParams(
        iface="antizapret_escape",
        jc=4, jmin=50, jmax=1000, s1=88, s2=136,
        h1=123456789, h2=987654321, h3=111222333, h4=444555666,
        i1="",
    )
    db_session.add(row); db_session.commit()
    fetched = db_session.query(WgObfuscationParams).filter_by(iface="antizapret_escape").one()
    assert fetched.s1 == 88 and fetched.h1 == 123456789

def test_system_settings_has_escape_enabled(db_session):
    from app.db.models import SystemSettings
    s = db_session.query(SystemSettings).filter_by(id=1).first()
    assert s is not None and s.escape_enabled is False
```

- [ ] **Step 2: Run — fail**

```bash
pytest tests/test_models.py -v
```

Expected: `AttributeError: module 'app.db.models' has no attribute 'WgObfuscationParams'`.

- [ ] **Step 3: Add model + column**

In `app/db/models.py`:
```python
class WgObfuscationParams(Base):
    __tablename__ = "wg_obfuscation_params"
    iface = Column(String(64), primary_key=True)
    jc = Column(Integer, nullable=False)
    jmin = Column(Integer, nullable=False)
    jmax = Column(Integer, nullable=False)
    s1 = Column(Integer, nullable=False)
    s2 = Column(Integer, nullable=False)
    h1 = Column(BigInteger, nullable=False)
    h2 = Column(BigInteger, nullable=False)
    h3 = Column(BigInteger, nullable=False)
    h4 = Column(BigInteger, nullable=False)
    i1 = Column(Text, nullable=False)
    created_at = Column(DateTime, server_default=func.now(), nullable=False)
    updated_at = Column(DateTime, server_default=func.now(), onupdate=func.now(), nullable=False)
```

Add to `SystemSettings`:
```python
escape_enabled = Column(Boolean, nullable=False, default=False, server_default="false")
```

- [ ] **Step 4: Run — pass**

```bash
pytest tests/test_models.py -v
```

- [ ] **Step 5: Commit**

```bash
git add corpweb/backend/app/db/models.py corpweb/backend/tests/test_models.py
git commit -m "feat(db): WgObfuscationParams model + SystemSettings.escape_enabled"
```

---

### Task 3: Pure function — obfuscation params generator

**Files:**
- Create: `corpweb/backend/app/services/obfuscation.py`
- Test: `corpweb/backend/tests/test_obfuscation.py`

- [ ] **Step 1: Write failing tests**

```python
# tests/test_obfuscation.py
from app.services.obfuscation import generate_params


def test_generate_returns_dict_with_all_keys():
    p = generate_params()
    assert set(p) == {"jc", "jmin", "jmax", "s1", "s2", "h1", "h2", "h3", "h4", "i1"}


def test_s_values_nonzero_and_in_range():
    p = generate_params()
    assert 15 <= p["s1"] <= 150
    assert 15 <= p["s2"] <= 150


def test_h_values_above_wg_reserved_and_unique():
    p = generate_params()
    hs = [p["h1"], p["h2"], p["h3"], p["h4"]]
    assert all(h > 4 for h in hs), "H must not collide with WG magic 1..4"
    assert len(set(hs)) == 4, "H values must be unique"
    assert all(h <= 0xFFFFFFFF for h in hs), "H is uint32"


def test_jc_in_recommended_range():
    p = generate_params()
    assert 3 <= p["jc"] <= 10


def test_two_calls_produce_different_params():
    assert generate_params() != generate_params()
```

- [ ] **Step 2: Run — fail**

```bash
pytest tests/test_obfuscation.py -v
```

Expected: `ModuleNotFoundError: No module named 'app.services.obfuscation'`.

- [ ] **Step 3: Implement**

```python
# app/services/obfuscation.py
"""
Pure helpers for AmneziaWG obfuscation parameters.

Generation rules (per-iface, per-installation, manual-rotation-only):
- Jc: 3..10   (junk packets before handshake)
- Jmin/Jmax: 50..1000 (junk packet size range)
- S1/S2: 15..150 (junk prefix size in Init/Response)
- H1..H4: uint32 > 4, all distinct (custom magic bytes)
- I1: empty by default (optional initial blob)
"""
from __future__ import annotations

import secrets


def _urand_uint32_gt4(exclude: set[int]) -> int:
    while True:
        n = secrets.randbelow(0xFFFFFFFE - 4) + 5  # [5, 2^32-1]
        if n not in exclude:
            return n


def generate_params() -> dict:
    hs: list[int] = []
    for _ in range(4):
        hs.append(_urand_uint32_gt4(set(hs)))
    return {
        "jc": secrets.randbelow(8) + 3,        # 3..10
        "jmin": 50,
        "jmax": 1000,
        "s1": secrets.randbelow(136) + 15,     # 15..150
        "s2": secrets.randbelow(136) + 15,
        "h1": hs[0],
        "h2": hs[1],
        "h3": hs[2],
        "h4": hs[3],
        "i1": "",
    }
```

- [ ] **Step 4: Run — pass**

```bash
pytest tests/test_obfuscation.py -v
```

- [ ] **Step 5: Commit**

```bash
git add corpweb/backend/app/services/obfuscation.py corpweb/backend/tests/test_obfuscation.py
git commit -m "feat(obfuscation): generate_params() pure function"
```

---

### Task 4: Extend `wg_templates` — escape port maps + server awg_params

**Files:**
- Modify: `corpweb/backend/app/services/wg_templates.py`
- Test: `corpweb/backend/tests/test_wg_templates.py`

- [ ] **Step 1: Write failing tests**

```python
# tests/test_wg_templates.py (add at bottom)
def test_escape_port_map_has_two_entries():
    from app.services.wg_templates import _ESCAPE_PORT_MAP
    assert _ESCAPE_PORT_MAP["antizapret_escape"] == 53443
    assert _ESCAPE_PORT_MAP["vpn_escape"] == 500


def test_port_map_covers_all_four_ifaces():
    from app.services.wg_templates import _PORT_MAP
    assert _PORT_MAP[("antizapret_escape", "awg")] == 53443
    assert _PORT_MAP[("vpn_escape", "awg")] == 500


def test_render_server_conf_with_awg_params_adds_block():
    from app.services.wg_templates import render_server_conf
    conf = render_server_conf(
        iface="vpn_escape",
        peers=[],
        server_privkey="FAKE_PRIV",
        address="10.26.8.1/21",
        awg_params={
            "jc": 4, "jmin": 50, "jmax": 1000,
            "s1": 88, "s2": 136,
            "h1": 111, "h2": 222, "h3": 333, "h4": 444,
            "i1": "",
        },
    )
    for line in ["Jc = 4", "Jmin = 50", "Jmax = 1000", "S1 = 88", "S2 = 136",
                 "H1 = 111", "H2 = 222", "H3 = 333", "H4 = 444"]:
        assert line in conf, f"missing {line!r} in\n{conf}"
    assert "ListenPort = 500" in conf


def test_render_server_conf_without_awg_params_is_unchanged():
    """Existing antizapret/vpn configs must not get AWG params."""
    from app.services.wg_templates import render_server_conf
    conf = render_server_conf(
        iface="antizapret", peers=[], server_privkey="X", address="10.29.8.1/21",
    )
    for key in ["Jc", "S1", "H1"]:
        assert key not in conf


def test_render_client_conf_bypass_uses_escape_port_and_params():
    from app.services.wg_templates import render_client_conf, Peer
    peer = Peer(name="c1", public_key="PK", preshared_key="PSK", allowed_ips="10.26.8.10/32")
    awg = {
        "jc": 4, "jmin": 50, "jmax": 1000, "s1": 88, "s2": 136,
        "h1": 111, "h2": 222, "h3": 333, "h4": 444, "i1": "",
    }
    conf = render_client_conf(
        peer=peer,
        iface="vpn_escape",
        server_pubkey="SPK",
        endpoint_host="cp.example.com",
        flavor="awg",
        awg_params=awg,
    )
    assert "Endpoint = cp.example.com:500" in conf
    assert "H1 = 111" in conf
    assert "S1 = 88" in conf
```

- [ ] **Step 2: Run — fail**

```bash
pytest tests/test_wg_templates.py -v
```

- [ ] **Step 3: Implement**

In `app/services/wg_templates.py`:
```python
_ESCAPE_PORT_MAP = {
    "antizapret_escape": 53443,
    "vpn_escape": 500,
}

_PORT_MAP = {
    ("antizapret", "wg"):  51443,
    ("antizapret", "awg"): 52443,
    ("vpn", "wg"):         51080,
    ("vpn", "awg"):        52080,
    ("antizapret_escape", "awg"): 53443,
    ("vpn_escape", "awg"):        500,
}
```

Extend `render_server_conf` signature:
```python
def render_server_conf(
    iface, peers, server_privkey, address,
    *,
    awg_params: dict | None = None,
) -> str:
    ...
    if awg_params:
        lines.append(f"Jc = {awg_params['jc']}")
        lines.append(f"Jmin = {awg_params['jmin']}")
        lines.append(f"Jmax = {awg_params['jmax']}")
        lines.append(f"S1 = {awg_params['s1']}")
        lines.append(f"S2 = {awg_params['s2']}")
        lines.append(f"H1 = {awg_params['h1']}")
        lines.append(f"H2 = {awg_params['h2']}")
        lines.append(f"H3 = {awg_params['h3']}")
        lines.append(f"H4 = {awg_params['h4']}")
        if awg_params.get("i1"):
            lines.append(f"I1 = {awg_params['i1']}")
```

Extend `render_client_conf` signature with `awg_params: dict | None = None`. If `awg_params` provided — replace the hardcoded `_AWG_OBFUSCATION`/`_AWG_I1` with formatted params.

- [ ] **Step 4: Run — pass**

```bash
pytest tests/test_wg_templates.py -v
```

- [ ] **Step 5: Commit**

```bash
git add corpweb/backend/app/services/wg_templates.py corpweb/backend/tests/test_wg_templates.py
git commit -m "feat(wg_templates): escape port map + render_server/client_conf awg_params"
```

---

## Phase 2: Backend — Services

### Task 5: `obfuscation_service` — get/regenerate/ensure_initialized

**Files:**
- Create: `corpweb/backend/app/services/obfuscation_service.py`
- Test: `corpweb/backend/tests/test_obfuscation_service.py`

- [ ] **Step 1: Write failing tests**

```python
# tests/test_obfuscation_service.py
def test_ensure_initialized_creates_missing_rows(db_session):
    from app.services.obfuscation_service import ensure_initialized, get_params
    ensure_initialized(db_session, ifaces=["antizapret_escape", "vpn_escape"])
    a = get_params(db_session, "antizapret_escape")
    v = get_params(db_session, "vpn_escape")
    assert a is not None and v is not None
    assert a["h1"] != v["h1"]  # independent random


def test_ensure_initialized_idempotent(db_session):
    from app.services.obfuscation_service import ensure_initialized, get_params
    ensure_initialized(db_session, ifaces=["vpn_escape"])
    before = get_params(db_session, "vpn_escape")
    ensure_initialized(db_session, ifaces=["vpn_escape"])
    after = get_params(db_session, "vpn_escape")
    assert before == after


def test_regenerate_overwrites_existing(db_session):
    from app.services.obfuscation_service import ensure_initialized, regenerate, get_params
    ensure_initialized(db_session, ifaces=["vpn_escape"])
    before = get_params(db_session, "vpn_escape")
    regenerate(db_session, ifaces=["vpn_escape"])
    after = get_params(db_session, "vpn_escape")
    assert before != after
```

- [ ] **Step 2: Run — fail**

- [ ] **Step 3: Implement**

```python
# app/services/obfuscation_service.py
from sqlalchemy.orm import Session
from app.db.models import WgObfuscationParams
from app.services.obfuscation import generate_params


def _row_to_dict(row: WgObfuscationParams) -> dict:
    return {
        "jc": row.jc, "jmin": row.jmin, "jmax": row.jmax,
        "s1": row.s1, "s2": row.s2,
        "h1": row.h1, "h2": row.h2, "h3": row.h3, "h4": row.h4,
        "i1": row.i1,
    }


def get_params(db: Session, iface: str) -> dict | None:
    row = db.get(WgObfuscationParams, iface)
    return _row_to_dict(row) if row else None


def ensure_initialized(db: Session, ifaces: list[str]) -> None:
    """Generate + store params for any iface missing a row."""
    for iface in ifaces:
        if db.get(WgObfuscationParams, iface) is None:
            p = generate_params()
            db.add(WgObfuscationParams(iface=iface, **p))
    db.commit()


def regenerate(db: Session, ifaces: list[str]) -> None:
    """Overwrite params (admin-triggered rotation)."""
    for iface in ifaces:
        row = db.get(WgObfuscationParams, iface)
        p = generate_params()
        if row is None:
            db.add(WgObfuscationParams(iface=iface, **p))
        else:
            for k, v in p.items():
                setattr(row, k, v)
    db.commit()
```

- [ ] **Step 4: Run — pass**

- [ ] **Step 5: Commit**

```bash
git commit -m "feat(obfuscation_service): ensure_initialized + regenerate"
```

---

### Task 6: Extend `VpnManager._IFACE_CONFIG` to 4 ifaces

**Files:**
- Modify: `corpweb/backend/app/services/vpn_manager_new.py`
- Test: `corpweb/backend/tests/test_vpn_manager_new.py`

- [ ] **Step 1: Write failing tests**

```python
def test_iface_config_has_escape_entries():
    from app.services.vpn_manager_new import _IFACE_CONFIG
    assert "antizapret_escape" in _IFACE_CONFIG
    assert "vpn_escape" in _IFACE_CONFIG
    assert _IFACE_CONFIG["antizapret_escape"]["subnet"] == "10.27.8.0/21"
    assert _IFACE_CONFIG["vpn_escape"]["subnet"] == "10.26.8.0/21"


def test_bootstrap_creates_four_keypairs_and_conf_blobs(db_session):
    from app.services.vpn_manager_new import vpn_manager
    from app.db.models import WgServerKeys
    from app.services.wg_blob_store import WgBlobStore
    vpn_manager.bootstrap(db_session)
    keys = {r.iface for r in db_session.query(WgServerKeys).all()}
    assert keys == {"antizapret", "vpn", "antizapret_escape", "vpn_escape"}
    store = WgBlobStore(db_session)
    for iface in ["antizapret", "vpn", "antizapret_escape", "vpn_escape"]:
        assert store.get(f"/etc/wireguard/{iface}.conf") is not None
```

- [ ] **Step 2: Run — fail**

- [ ] **Step 3: Implement** — extend `_IFACE_CONFIG`:

```python
_IFACE_CONFIG = {
    "antizapret": {
        "address": "10.29.8.1/21", "subnet": "10.29.8.0/21",
        "conf_path": "/etc/wireguard/antizapret.conf",
    },
    "vpn": {
        "address": "10.28.8.1/21", "subnet": "10.28.8.0/21",
        "conf_path": "/etc/wireguard/vpn.conf",
    },
    "antizapret_escape": {
        "address": "10.27.8.1/21", "subnet": "10.27.8.0/21",
        "conf_path": "/etc/wireguard/antizapret_escape.conf",
    },
    "vpn_escape": {
        "address": "10.26.8.1/21", "subnet": "10.26.8.0/21",
        "conf_path": "/etc/wireguard/vpn_escape.conf",
    },
}
```

`bootstrap()` already loops — just one guard to pass `awg_params` for escape ifaces:

```python
from app.services.obfuscation_service import ensure_initialized, get_params

def bootstrap(self, db):
    ensure_initialized(db, ifaces=["antizapret_escape", "vpn_escape"])
    store = WgBlobStore(db)
    for iface, cfg in _IFACE_CONFIG.items():
        ...
        awg = get_params(db, iface) if iface.endswith("_escape") else None
        if store.get(cfg["conf_path"]) is None:
            conf = render_server_conf(
                iface=iface, peers=[],
                server_privkey=priv, address=cfg["address"],
                awg_params=awg,
            )
            store.put(cfg["conf_path"], conf.encode(), by="bootstrap")
```

- [ ] **Step 4: Run — pass**

- [ ] **Step 5: Commit**

```bash
git commit -m "feat(vpn_manager): extend _IFACE_CONFIG with escape ifaces"
```

---

### Task 7: Extend `add_peer` / `delete_peer` — peer in 4 ifaces

**Files:**
- Modify: `corpweb/backend/app/services/vpn_manager_new.py`
- Test: existing `test_vpn_manager_new.py`

- [ ] **Step 1: Failing test**

```python
def test_add_peer_writes_to_all_four_ifaces(db_session):
    from app.services.vpn_manager_new import vpn_manager
    from app.services.wg_blob_store import WgBlobStore
    from app.services.wg_templates import parse_peers
    vpn_manager.bootstrap(db_session)
    vpn_manager.add_peer(db_session, "alice")
    store = WgBlobStore(db_session)
    for iface in ["antizapret", "vpn", "antizapret_escape", "vpn_escape"]:
        blob = store.get(f"/etc/wireguard/{iface}.conf")
        peers = parse_peers(blob.decode())
        names = [p.name for p in peers]
        assert "alice" in names, f"alice missing in {iface}"


def test_add_peer_uses_parallel_host_parts(db_session):
    from app.services.vpn_manager_new import vpn_manager
    from app.services.wg_blob_store import WgBlobStore
    from app.services.wg_templates import parse_peers
    vpn_manager.bootstrap(db_session)
    vpn_manager.add_peer(db_session, "bob")
    store = WgBlobStore(db_session)
    ips = {}
    for iface in ["antizapret", "vpn", "antizapret_escape", "vpn_escape"]:
        peers = parse_peers(store.get(f"/etc/wireguard/{iface}.conf").decode())
        ips[iface] = [p for p in peers if p.name == "bob"][0].allowed_ips
    # All share host part (e.g. ".8.2/32")
    host_parts = {ip.split(".", 2)[-1] for ip in ips.values()}
    assert len(host_parts) == 1
```

- [ ] **Step 2: Run — fail**

- [ ] **Step 3: Implement** — in `_add_peer_impl`, extend `iface_ip` dict:

```python
host_parts = free_ip.split(".")[2:]
iface_ip = {
    "antizapret":        free_ip,                                   # 10.29.x.x
    "vpn":               f"10.28.{host_parts[0]}.{host_parts[1]}",
    "antizapret_escape": f"10.27.{host_parts[0]}.{host_parts[1]}",
    "vpn_escape":        f"10.26.{host_parts[0]}.{host_parts[1]}",
}
```

Loop over `_IFACE_CONFIG.items()` already handles all 4 — but `render_server_conf` call must pass `awg_params` for escape ifaces:

```python
awg = get_params(db, iface) if iface.endswith("_escape") else None
new_conf = render_server_conf(iface=iface, peers=all_peers,
                              server_privkey=server_keys.private_key,
                              address=cfg["address"], awg_params=awg)
```

- [ ] **Step 4: Run — pass**

- [ ] **Step 5: Commit**

```bash
git commit -m "feat(vpn_manager): add_peer writes to all four ifaces"
```

---

### Task 8: `get_client_conf` gains `bypass=False`

**Files:**
- Modify: `corpweb/backend/app/services/vpn_manager_new.py`

- [ ] **Step 1: Failing test**

```python
def test_get_client_conf_bypass_uses_escape_iface_and_params(db_session):
    from app.services.vpn_manager_new import vpn_manager
    vpn_manager.bootstrap(db_session)
    vpn_manager.add_peer(db_session, "carol")
    conf = vpn_manager.get_client_conf(
        db_session, "carol", flavor="awg",
        endpoint_host="cp", iface="vpn", bypass=True,
        client_private_key="PRV",
    )
    assert "Endpoint = cp:500" in conf
    assert "S1 = " in conf  # obfuscation param injected
    assert "H1 = " in conf


def test_get_client_conf_bypass_forbidden_with_backup(db_session):
    from app.services.vpn_manager_new import vpn_manager
    vpn_manager.bootstrap(db_session)
    vpn_manager.add_peer(db_session, "dave")
    import pytest
    with pytest.raises(ValueError, match="bypass.*backup"):
        vpn_manager.get_client_conf(
            db_session, "dave", flavor="awg",
            endpoint_host="cp", iface="vpn",
            bypass=True, use_backup_port=True,
            client_private_key="PRV",
        )
```

- [ ] **Step 2: Run — fail**

- [ ] **Step 3: Implement**

```python
def get_client_conf(self, db, name, flavor, endpoint_host,
                   iface="antizapret", *,
                   client_private_key=None, allowed_ips=None,
                   use_backup_port=False, bypass=False) -> str:
    if bypass and use_backup_port:
        raise ValueError("bypass and backup_port are mutually exclusive")

    effective_iface = f"{iface}_escape" if bypass else iface
    cfg = _IFACE_CONFIG[effective_iface]
    blob = WgBlobStore(db).get(cfg["conf_path"])
    ...
    awg = get_params(db, effective_iface) if bypass else None
    return render_client_conf(
        peer=target, iface=effective_iface,
        server_pubkey=server_keys.public_key,
        endpoint_host=endpoint_host, flavor=flavor,
        client_private_key=client_private_key,
        allowed_ips=allowed_ips,
        use_backup_port=use_backup_port,
        awg_params=awg,
    )
```

- [ ] **Step 4: Run — pass**

- [ ] **Step 5: Commit**

```bash
git commit -m "feat(vpn_manager): get_client_conf bypass param"
```

---

### Task 9: `balancer.get_active_ports` — reads `escape_enabled`

**Files:**
- Modify: `corpweb/backend/app/services/balancer.py`
- Test: `corpweb/backend/tests/test_balancer.py`

- [ ] **Step 1: Failing tests**

```python
class TestActivePorts:
    def test_escape_disabled_returns_base_ports(self):
        from app.services.balancer import get_active_ports
        assert get_active_ports(escape_enabled=False) == [51443, 51080, 52443, 52080, 540, 580]

    def test_escape_enabled_appends_escape_ports(self):
        from app.services.balancer import get_active_ports
        got = get_active_ports(escape_enabled=True)
        assert 500 in got and 53443 in got
        assert len(got) == 8
```

- [ ] **Step 2: Run — fail**

- [ ] **Step 3: Implement**

```python
BASE_PORTS = [51443, 51080, 52443, 52080, 540, 580]
ESCAPE_PORTS = [500, 53443]

def get_active_ports(escape_enabled: bool) -> list[int]:
    return BASE_PORTS + (ESCAPE_PORTS if escape_enabled else [])

# DEFAULT_PORTS kept as alias for base (legacy tests)
DEFAULT_PORTS = BASE_PORTS
```

Update `apply_rules` to take `escape_enabled: bool` and pass `get_active_ports(escape_enabled)` into `generate_iptables_rules`. Update `ensure_ports_reconciled` to read `SystemSettings.escape_enabled` and pass through.

- [ ] **Step 4: Run — pass**

- [ ] **Step 5: Commit**

```bash
git commit -m "feat(balancer): active-ports driven by escape_enabled"
```

---

## Phase 3: Backend — API

### Task 10: `/api/v1/antizapret/obfuscation/regenerate` endpoint

**Files:**
- Modify: `corpweb/backend/app/api/v1/antizapret.py`
- Test: `corpweb/backend/tests/test_api_antizapret.py`

- [ ] **Step 1: Failing test**

```python
def test_regenerate_obfuscation_admin_only(client, admin_token, user_token):
    r = client.post("/api/v1/antizapret/obfuscation/regenerate",
                    headers={"Authorization": f"Bearer {user_token}"})
    assert r.status_code == 403

    r = client.post("/api/v1/antizapret/obfuscation/regenerate",
                    headers={"Authorization": f"Bearer {admin_token}"})
    assert r.status_code == 200
    assert r.json()["status"] == "ok"
```

- [ ] **Step 2: Run — fail**

- [ ] **Step 3: Implement**

```python
@router.post("/obfuscation/regenerate")
async def regenerate_obfuscation(
    db: Session = Depends(get_db),
    current_user: User = Depends(require_admin),
):
    from app.services.obfuscation_service import regenerate
    from app.services.vpn_manager_new import vpn_manager
    regenerate(db, ifaces=["antizapret_escape", "vpn_escape"])
    # Re-render server configs with new params
    vpn_manager.rerender_escape_server_confs(db)
    return {"status": "ok"}
```

Add thin helper in `VpnManager`:
```python
def rerender_escape_server_confs(self, db):
    store = WgBlobStore(db)
    for iface in ("antizapret_escape", "vpn_escape"):
        cfg = _IFACE_CONFIG[iface]
        blob = store.get(cfg["conf_path"])
        peers = parse_peers(blob.decode()) if blob else []
        keys = db.get(WgServerKeys, iface)
        awg = get_params(db, iface)
        new_conf = render_server_conf(iface=iface, peers=peers,
                                      server_privkey=keys.private_key,
                                      address=cfg["address"], awg_params=awg)
        store.put(cfg["conf_path"], new_conf.encode(), by="regenerate")
```

- [ ] **Step 4: Run — pass**

- [ ] **Step 5: Commit**

```bash
git commit -m "feat(api): POST /antizapret/obfuscation/regenerate"
```

---

### Task 11: `/configs/{id}/download` + `/qr` — `bypass` query param

**Files:**
- Modify: `corpweb/backend/app/api/v1/configs.py`
- Test: `corpweb/backend/tests/test_api_configs.py`

- [ ] **Step 1: Failing tests**

```python
def test_download_bypass_requires_escape_enabled(client, user_token, config_id, set_escape):
    set_escape(False)
    r = client.get(f"/api/v1/configs/{config_id}/download?bypass=true",
                   headers={"Authorization": f"Bearer {user_token}"})
    assert r.status_code == 403

    set_escape(True)
    r = client.get(f"/api/v1/configs/{config_id}/download?bypass=true",
                   headers={"Authorization": f"Bearer {user_token}"})
    assert r.status_code == 200


def test_download_bypass_and_backup_rejected(client, user_token, config_id, set_escape):
    set_escape(True)
    r = client.get(f"/api/v1/configs/{config_id}/download?bypass=true&backup=true",
                   headers={"Authorization": f"Bearer {user_token}"})
    assert r.status_code == 400
```

- [ ] **Step 2: Run — fail**

- [ ] **Step 3: Implement** — in both download and QR handlers:

```python
async def download_config(
    config_id: uuid.UUID,
    backup: bool = Query(False),
    bypass: bool = Query(False),
    ...
):
    if bypass and backup:
        raise HTTPException(400, "bypass and backup are mutually exclusive")

    if bypass:
        s = db.query(SystemSettings).filter_by(id=1).first()
        if not (s and s.escape_enabled):
            raise HTTPException(403, "escape mode is disabled")

    ...
    content = vpn_manager.get_client_conf(
        db, config.client_name, flavor, endpoint_host, iface,
        client_private_key=private_key, allowed_ips=allowed_ips,
        use_backup_port=backup, bypass=bypass,
    )
```

- [ ] **Step 4: Run — pass**

- [ ] **Step 5: Commit**

```bash
git commit -m "feat(api): bypass query param on config download/qr"
```

---

### Task 12: `/configs/client-links` — `escape_enabled` flag

**Files:**
- Modify: `corpweb/backend/app/api/v1/configs.py`

- [ ] **Step 1: Failing test**

```python
def test_client_links_exposes_escape_enabled(client, user_token, set_escape):
    set_escape(True)
    r = client.get("/api/v1/configs/client-links",
                   headers={"Authorization": f"Bearer {user_token}"})
    assert r.json()["escape_enabled"] is True

    set_escape(False)
    r = client.get("/api/v1/configs/client-links",
                   headers={"Authorization": f"Bearer {user_token}"})
    assert r.json()["escape_enabled"] is False
```

- [ ] **Step 2: Implement**

```python
async def get_client_links(..., db: Session = Depends(get_db)):
    s = db.query(SystemSettings).filter(SystemSettings.id == 1).first()
    from app.services.antizapret import AntizapretService
    svc = AntizapretService(db)
    return {
        "google_play_url": s.google_play_url if s else None,
        ...
        "wireguard_backup_enabled": svc.get_settings().get("WIREGUARD_BACKUP") == "y",
        "escape_enabled": bool(s and s.escape_enabled),
    }
```

- [ ] **Step 3: Commit**

```bash
git commit -m "feat(api): client-links returns escape_enabled"
```

---

### Task 13: System-settings API — expose and patch `escape_enabled` + rebalance on change

**Files:**
- Modify: existing `corpweb/backend/app/api/v1/admin.py` (or wherever system-settings endpoint lives)
- Modify: `corpweb/backend/app/schemas/system_settings.py` (or similar)

- [ ] **Step 1: Failing test**

```python
def test_patch_escape_enabled_triggers_rebalance(client, admin_token, mocker):
    spy = mocker.patch("app.services.balancer.apply_rules", return_value={})
    r = client.patch(
        "/api/v1/admin/system-settings",
        json={"escape_enabled": True},
        headers={"Authorization": f"Bearer {admin_token}"},
    )
    assert r.status_code == 200
    spy.assert_called_once()
    # assert ports arg included 500 and 53443
```

- [ ] **Step 2: Add `escape_enabled` to Pydantic schema + endpoint.** On PATCH where `escape_enabled` changes, call `balancer.apply_rules(nodes, cp_ip, escape_enabled=...)`.

- [ ] **Step 3: Commit**

```bash
git commit -m "feat(api): PATCH escape_enabled triggers balancer rebalance"
```

---

### Task 14: Lifespan — ensure obfuscation params + bootstrap escape ifaces

**Files:**
- Modify: `corpweb/backend/app/main.py`

- [ ] **Step 1: Test** — call to `ensure_initialized` at startup (mock and verify).

- [ ] **Step 2: Implement**

```python
@asynccontextmanager
async def lifespan(app):
    from app.db.init_db import init_db
    from app.services.scheduler import start_scheduler, stop_scheduler
    from app.services.balancer import ensure_ports_reconciled
    from app.services.obfuscation_service import ensure_initialized
    from app.services.vpn_manager_new import vpn_manager
    from app.db.session import SessionLocal

    init_db()
    start_scheduler()
    db = SessionLocal()
    try:
        ensure_initialized(db, ifaces=["antizapret_escape", "vpn_escape"])
        vpn_manager.bootstrap(db)
        ensure_ports_reconciled(db)
    except Exception as exc:
        logging.getLogger(__name__).warning("startup init failed: %s", exc)
    finally:
        db.close()
    yield
    stop_scheduler()
```

- [ ] **Step 3: Commit**

```bash
git commit -m "feat(lifespan): initialize escape obfuscation params + bootstrap"
```

---

### Task 15: Data migration — backfill existing peers into escape ifaces

**Files:**
- Create: `corpweb/backend/alembic/versions/<rev>_backfill_escape_peers.py`

- [ ] **Step 1: Write migration**

```python
"""backfill escape peers from vpn_configs

Revision ID: <auto>
Revises: <awg_escape_obfuscation>
"""
from alembic import op


revision = "<auto>"
down_revision = "<awg_escape_obfuscation>"


def upgrade():
    conn = op.get_bind()
    from app.services.vpn_manager_new import vpn_manager
    from app.db.session import SessionLocal
    db = SessionLocal(bind=conn)
    try:
        vpn_manager.bootstrap(db)  # creates escape keypairs + blobs if missing
        names = [r[0] for r in conn.execute(
            "SELECT client_name FROM vpn_configs ORDER BY created_at"
        )]
        # Re-derive peer entries by calling a backfill helper
        vpn_manager.backfill_escape_peers(db, names)
    finally:
        db.close()


def downgrade():
    pass  # idempotent; do not delete peers
```

Add `VpnManager.backfill_escape_peers(db, names: list[str])` — for each existing peer, write a peer entry into `*_escape.conf` with same public_key, preshared_key, and parallel host-part IP in the escape subnet.

- [ ] **Step 2: Apply locally, verify all peers present in both escape ifaces.**

- [ ] **Step 3: Commit**

```bash
git commit -m "feat(db): data migration — backfill existing peers into escape ifaces"
```

---

## Phase 4: Agent

### Task 16: Agent — MANAGED_FILES + hook dispatch

**Files:**
- Modify: `agent/corpweb_sync_agent.py`
- Test: `agent/tests/test_sync_agent.py`

- [ ] **Step 1: Failing tests**

```python
def test_managed_files_includes_escape_ifaces():
    mapping = dict(agent.MANAGED_FILES)
    assert mapping["/etc/wireguard/antizapret_escape.conf"] == "wg_antizapret_escape"
    assert mapping["/etc/wireguard/vpn_escape.conf"] == "wg_vpn_escape"


def test_apply_path_dispatches_wg_antizapret_escape(tmp_path):
    target = tmp_path / "antizapret_escape.conf"
    with patch("corpweb_sync_agent.apply_wg_syncconf") as m:
        agent.apply_path(str(target), b"[Interface]\n", "wg_antizapret_escape")
    m.assert_called_once_with("antizapret_escape")


def test_apply_path_dispatches_wg_vpn_escape(tmp_path):
    target = tmp_path / "vpn_escape.conf"
    with patch("corpweb_sync_agent.apply_wg_syncconf") as m:
        agent.apply_path(str(target), b"[Interface]\n", "wg_vpn_escape")
    m.assert_called_once_with("vpn_escape")
```

- [ ] **Step 2: Run — fail**

- [ ] **Step 3: Implement**

```python
MANAGED_FILES = [
    ...,
    ("/etc/wireguard/antizapret_escape.conf", "wg_antizapret_escape"),
    ("/etc/wireguard/vpn_escape.conf",        "wg_vpn_escape"),
]

# in apply_path:
if hook == "wg_antizapret": apply_wg_syncconf("antizapret")
elif hook == "wg_vpn": apply_wg_syncconf("vpn")
elif hook == "wg_antizapret_escape": apply_wg_syncconf("antizapret_escape")
elif hook == "wg_vpn_escape": apply_wg_syncconf("vpn_escape")
```

- [ ] **Step 4: Pass**

- [ ] **Step 5: Commit**

```bash
git commit -m "feat(agent): manage escape iface confs + dispatch hooks"
```

---

### Task 17: Agent — `_apply_wg_config` for escape ifaces

**Files:**
- Modify: `agent/corpweb_sync_agent.py`

- [ ] **Step 1: Failing test** — given CP response with `antizapret_escape_address`/`antizapret_escape_listen_port` + same for `vpn_escape`, agent patches respective conf files.

- [ ] **Step 2: Implement** — extend `iface_map`:

```python
iface_map = {
    "antizapret": {..., "address": cfg.get("antizapret_address"), "port": cfg.get("antizapret_listen_port")},
    "vpn": {..., "address": cfg.get("vpn_address"), "port": cfg.get("vpn_listen_port")},
    "antizapret_escape": {
        "conf": "/etc/wireguard/antizapret_escape.conf",
        "address": cfg.get("antizapret_escape_address"),
        "port": cfg.get("antizapret_escape_listen_port"),
    },
    "vpn_escape": {
        "conf": "/etc/wireguard/vpn_escape.conf",
        "address": cfg.get("vpn_escape_address"),
        "port": cfg.get("vpn_escape_listen_port"),
    },
}
```

And extend backend `/api/v1/agent/register` response to include those keys.

- [ ] **Step 3: Commit**

```bash
git commit -m "feat(agent): patch [Interface] for escape ifaces"
```

---

## Phase 5: Frontend

### Task 18: Extract shared `<Toggle>` component

**Files:**
- Create: `corpweb/frontend/src/components/Toggle.tsx`
- Modify: `corpweb/frontend/src/pages/AdminAntizapretPage.tsx` — import from shared

- [ ] **Step 1: Move the Toggle from AdminAntizapretPage into its own file (same styling).**

- [ ] **Step 2: Verify `npm run build` passes.**

- [ ] **Step 3: Commit**

```bash
git commit -m "refactor(ui): extract shared Toggle component"
```

---

### Task 19: API types + methods — escape flag and bypass query

**Files:**
- Modify: `corpweb/frontend/src/api/configs.ts`
- Modify: `corpweb/frontend/src/api/antizapret.ts`

- [ ] **Step 1:** extend `ClientLinks` with `escape_enabled?: boolean`, extend `download(id, { backup, bypass })` and `getQR` similarly, extend `AntizapretSettings` with `ESCAPE_ENABLED`.

- [ ] **Step 2:** new API call for obfuscation regenerate.

```typescript
regenerateObfuscation: () => api.post('/antizapret/obfuscation/regenerate')
```

- [ ] **Step 3: Commit**

```bash
git commit -m "feat(api-client): escape_enabled + bypass query + regenerate"
```

---

### Task 20: Admin — "Обход блокировки" section with toggle + regenerate

**Files:**
- Modify: `corpweb/frontend/src/pages/AdminAntizapretPage.tsx`

- [ ] **Step 1:** new `<Section title="Обход блокировки">` placed after "Резервные порты":
  - `<Toggle label="Включить режим обхода блокировки (ESCAPE_ENABLED)" .../>`
  - `<button>` red (bg-red-600) "Перегенерировать параметры обфускации"
  - onClick → confirm dialog ("Это отключит всех текущих bypass-клиентов. Подтвердить?") → `antizapretApi.regenerateObfuscation()` → toast.

- [ ] **Step 2: Verify build passes, visual check in browser.**

- [ ] **Step 3: Commit**

```bash
git commit -m "feat(ui): admin section for escape toggle + regenerate"
```

---

### Task 21: LK — replace amber checkbox with grid of Toggle cards

**Files:**
- Modify: `corpweb/frontend/src/pages/DashboardPage.tsx`

- [ ] **Step 1:** remove amber checkbox block. Add new section above config grid:

```tsx
{(clientLinks?.wireguard_backup_enabled || clientLinks?.escape_enabled) && configs.length > 0 && (
  <div className="mb-6">
    <h2 className="text-sm font-semibold text-gray-700 mb-3">Опции скачивания</h2>
    <div className="grid grid-cols-1 sm:grid-cols-2 gap-3">
      {clientLinks.wireguard_backup_enabled && (
        <ToggleCard
          title="Резервный порт"
          description="Использовать UDP 540/580 вместо стандартных 5144x/5208x. Помогает при блокировке провайдером стандартных портов."
          enabled={useBackupPort}
          disabled={useEscape}
          onChange={setUseBackupPort}
        />
      )}
      {clientLinks.escape_enabled && (
        <ToggleCard
          title="Обход блокировки"
          description="Усиленная обфускация + отдельный канал на порту 500/53443. Включайте только если обычный режим не коннектится."
          enabled={useEscape}
          disabled={useBackupPort}
          onChange={setUseEscape}
        />
      )}
    </div>
  </div>
)}
```

Pass `{ backup: useBackupPort, bypass: useEscape }` to `configsApi.download` and `getQR`.

- [ ] **Step 2: Build + browser smoke check (both toggles, mutual exclusion, hidden when flags off).**

- [ ] **Step 3: Commit**

```bash
git commit -m "feat(lk): two toggle cards for backup and escape modes"
```

---

## Phase 6: Deployment

### Task 22: Deploy backend + frontend to CP

- [ ] `git push origin CorpAdmin` (user)
- [ ] On CP: `git pull`; `cp -r backend/app /opt/corpweb/backend/app`; `alembic upgrade head` (runs schema + backfill migrations); `systemctl restart corpweb-backend`
- [ ] Check logs for `ensure_initialized` + `bootstrap` success.

### Task 23: Deploy new agent to both nodes

- [ ] scp `agent/corpweb_sync_agent.py` to each node; `install` under root; `systemctl restart corpweb-sync-agent`
- [ ] On each node: `systemctl status wg-quick@antizapret_escape wg-quick@vpn_escape` — both active.
- [ ] Check iptables on each node: `iptables -t nat -L PREROUTING -n | grep -E "(500|53443)"` — REDIRECT rules if any? (Not needed — direct listen.)
- [ ] CP iptables: DNAT for 500/53443 only after admin flips `ESCAPE_ENABLED=true`.

### Task 24: End-to-end smoke test

- [ ] Flip `ESCAPE_ENABLED=true` in UI → DNAT on CP gets 500/53443 entries (verify via `iptables -t nat -L PREROUTING -n`).
- [ ] In LK with existing user: "Обход блокировки" toggle appears.
- [ ] Toggle on → download → conf contains `Endpoint = <host>:500` (or `:53443` for AZ-type) + `S1`/`H1` lines.
- [ ] Install in AmneziaWG client, connect → handshake completes, traffic flows.
- [ ] Toggle off in admin → DNAT removed → old conf stops working.
- [ ] Regenerate button → new params stored → existing conf stops working → re-download → works again.

### Task 25: Close epic

- [ ] `bd close CorpAdmin-AZ-roo --reason "Deployed. Smoke passed: end-to-end escape handshake, regen invalidation, toggle on/off cycling. N tests passing."`

---

## Self-review checklist

Before handing over:
- [ ] No TBD / TODO / "implement later" anywhere in plan ✓
- [ ] Each step has either code, command, or specific file+line reference ✓
- [ ] Spec-coverage: every D1-D10 decision maps to at least one Task ✓ (D1→T6, D2→T7, D3→T3/T5/T10, D4→T9/T13, D5→T4, D6→T4, D7→T8/T11, D8→T21, D9→T20, D10→T16/T17)
- [ ] Type consistency: `bypass` kwarg name consistent across wg_templates, vpn_manager, API, frontend ✓
- [ ] TDD enforced: every functional task starts with failing test ✓
- [ ] Commits frequent (1 per task) ✓

## Execution handoff

Plan complete. Two options for execution:

1. **Subagent-Driven (recommended)** — fresh subagent per task, review between tasks, fast iteration.
2. **Inline Execution** — execute in current session with checkpoints.

Which approach?
