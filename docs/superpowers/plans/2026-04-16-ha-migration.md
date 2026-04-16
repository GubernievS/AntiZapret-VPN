# HA Migration Plan v2 — DB-backed VPN manager + apply confirmation + cutover

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Switch wgfi2 from file/subprocess VPN management to DB-backed with confirmed apply on all live nodes, so that a DB backup/restore on a new CP server gives a fully working multi-node system.

**Architecture:** Alembic adds 3 tables + 2 NOTIFY triggers. Migration script reads 12 files + keypair + client private keys from disk into DB. API endpoints switch to `vpn_manager_new`. Two SSE channels: `wg_file_state_changed` (agents listen), `node_applied` (frontend listens). Frontend waits for all live nodes to confirm apply before showing download.

**Tech Stack:** FastAPI + SQLAlchemy + PostgreSQL + asyncpg (SSE) + alembic.

---

## Key Design Decisions

### 1. Apply Confirmation (SSE → frontend)

```
User clicks "Create config"
  → POST /configs → add_peer writes to wg_file_state → returns {config_id, status: "applying"}
  → pg_notify('wg_file_state_changed', path) → agents apply
  → agents send heartbeat with updated applied_sha
  → UPDATE nodes SET applied_sha → pg_notify('node_applied', node_id)
  → Frontend SSE /api/v1/events/apply-status?paths=P listens for node_applied
  → Backend compares all live nodes' applied_sha vs wg_file_state.sha256
  → All match → SSE sends {status: "ready"} → frontend unlocks download
  → 30s timeout → SSE sends {status: "ready", warning: "node X not synced"} → unlock anyway
```

Two NOTIFY channels, two SSE endpoints, clean separation:
- `wg_file_state_changed` → agents (already implemented)
- `node_applied` → frontend (new trigger on `UPDATE nodes SET applied_sha`)

### 2. Client Config Downloads

- Client private keys stored in `vpn_configs.config_metadata.private_key`
- AllowedIPs template stored in `wg_file_state` at path `antizapret:allowed_ips`
- `render_client_conf` generates configs on-the-fly from stored data
- Endpoint hostname from `settings.LB_ENDPOINT_HOST` (defaults to FRONTEND_URL hostname)

### 3. Live Nodes Definition

A node is "live" when `health IN ('ok', 'degraded')`. Nodes with `health = 'down'`, `'draining'`, or `NULL` are not waited on.

---

## File Map

| Action | Path | Purpose |
|--------|------|---------|
| Create | `corpweb/backend/alembic/versions/0002_ha_tables.py` | 3 tables + 2 triggers |
| Create | `corpweb/backend/app/migrate.py` | One-time file→DB migration |
| Create | `corpweb/backend/app/api/v1/apply_status.py` | Frontend SSE: apply status |
| Modify | `corpweb/backend/app/services/wg_templates.py` | `render_client_conf` + allowed_ips/private_key params |
| Modify | `corpweb/backend/app/services/vpn_manager_new.py` | `get_client_conf` passes private_key; `check_applied` method |
| Modify | `corpweb/backend/app/api/v1/configs.py` | Switch to vpn_manager_new; async create flow |
| Modify | `corpweb/backend/app/api/v1/admin.py` | Switch to vpn_manager_new |
| Modify | `corpweb/backend/app/api/v1/public.py` | Switch to vpn_manager_new |
| Modify | `corpweb/backend/app/main.py` | Register apply_status router |
| Modify | `corpweb/backend/app/config.py` | Add `LB_ENDPOINT_HOST` |
| Modify | `corpweb/frontend/src/api/configs.ts` | Add `waitForApply` SSE helper |
| Modify | `corpweb/frontend/src/pages/` (config create flow) | Spinner during apply |
| Create | `corpweb/backend/tests/test_migration.py` | Migration tests |
| Create | `corpweb/backend/tests/test_apply_status.py` | Apply status tests |
| Modify | `corpweb/backend/tests/test_wg_templates.py` | New param tests |
| Modify | `corpweb/backend/tests/test_vpn_manager_new.py` | New method tests |

---

### Task A: Alembic Migration + node_applied trigger

**Files:**
- Create: `corpweb/backend/alembic/versions/0002_ha_tables.py`

- [ ] **Step 1: Create the migration file**

```python
# corpweb/backend/alembic/versions/0002_ha_tables.py
"""Add HA tables + NOTIFY triggers

Revision ID: 0002
Revises:
Create Date: 2026-04-16
"""
from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql

revision = '0002'
down_revision = None
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        'wg_file_state',
        sa.Column('path', sa.String(500), primary_key=True),
        sa.Column('content', sa.LargeBinary(), nullable=False),
        sa.Column('sha256', sa.String(64), nullable=False),
        sa.Column('size_bytes', sa.Integer(), nullable=False),
        sa.Column('updated_at', sa.DateTime(), nullable=False, server_default=sa.func.now()),
        sa.Column('updated_by', sa.String(100), nullable=False),
    )

    op.create_table(
        'wg_server_keys',
        sa.Column('iface', sa.String(50), primary_key=True),
        sa.Column('private_key', sa.Text(), nullable=False),
        sa.Column('public_key', sa.Text(), nullable=False),
        sa.Column('created_at', sa.DateTime(), nullable=False, server_default=sa.func.now()),
    )

    op.create_table(
        'nodes',
        sa.Column('id', sa.Integer(), primary_key=True, autoincrement=True),
        sa.Column('hostname', sa.String(255), unique=True, nullable=False),
        sa.Column('private_ip', sa.String(50), nullable=False),
        sa.Column('enroll_token', sa.String(255), unique=True, nullable=False),
        sa.Column('last_seen', sa.DateTime(), nullable=True),
        sa.Column('health', sa.String(20), nullable=True),
        sa.Column('applied_sha', postgresql.JSONB(), nullable=True),
        sa.Column('metrics', postgresql.JSONB(), nullable=True),
        sa.Column('created_at', sa.DateTime(), nullable=False, server_default=sa.func.now()),
    )

    # Trigger 1: notify agents when file content changes
    op.execute("""
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
    """)

    # Trigger 2: notify frontend when node applies new config
    op.execute("""
        CREATE OR REPLACE FUNCTION notify_node_applied() RETURNS trigger
        LANGUAGE plpgsql AS $$
        BEGIN
            IF OLD.applied_sha IS DISTINCT FROM NEW.applied_sha THEN
                PERFORM pg_notify('node_applied', NEW.id::text);
            END IF;
            RETURN NEW;
        END;
        $$;

        CREATE TRIGGER trg_node_applied
        AFTER UPDATE ON nodes
        FOR EACH ROW EXECUTE FUNCTION notify_node_applied();
    """)


def downgrade() -> None:
    op.execute("DROP TRIGGER IF EXISTS trg_node_applied ON nodes")
    op.execute("DROP FUNCTION IF EXISTS notify_node_applied")
    op.execute("DROP TRIGGER IF EXISTS trg_wg_file_changed ON wg_file_state")
    op.execute("DROP FUNCTION IF EXISTS notify_wg_file_changed")
    op.drop_table('nodes')
    op.drop_table('wg_server_keys')
    op.drop_table('wg_file_state')
```

- [ ] **Step 2: Test locally**

```bash
cd corpweb/backend && python -m pytest tests/test_models_ha.py -v
```
Expected: 3 passed

- [ ] **Step 3: Commit**

```bash
git add corpweb/backend/alembic/versions/0002_ha_tables.py
git commit -m "feat: alembic migration — 3 HA tables + wg_file_state_changed + node_applied triggers"
```

---

### Task B: render_client_conf + vpn_manager_new updates

**Files:**
- Modify: `corpweb/backend/app/services/wg_templates.py`
- Modify: `corpweb/backend/app/services/vpn_manager_new.py`
- Modify: `corpweb/backend/app/config.py`
- Test: `corpweb/backend/tests/test_wg_templates.py`
- Test: `corpweb/backend/tests/test_vpn_manager_new.py`

- [ ] **Step 1: Write failing tests for new render_client_conf params**

Add to `corpweb/backend/tests/test_wg_templates.py`:

```python
def test_render_client_conf_custom_allowed_ips():
    peer = Peer(name="a-1", public_key="pub==", preshared_key="psk==", allowed_ips="10.29.8.2/32")
    out = render_client_conf(peer, "antizapret", "spub==", "lb.example.com", "awg",
                             allowed_ips="10.29.8.0/24, 1.2.3.0/24, 5.6.7.0/24")
    assert "1.2.3.0/24" in out
    assert "5.6.7.0/24" in out

def test_render_client_conf_with_private_key():
    peer = Peer(name="a-1", public_key="pub==", preshared_key="psk==", allowed_ips="10.29.8.2/32")
    out = render_client_conf(peer, "vpn", "spub==", "lb.example.com", "wg",
                             client_private_key="REAL_PRIV_KEY==")
    assert "PrivateKey = REAL_PRIV_KEY==" in out
    assert "${CLIENT_PRIVATE_KEY}" not in out
```

- [ ] **Step 2: Run to verify failure**

```bash
cd corpweb/backend && python -m pytest tests/test_wg_templates.py -k "custom_allowed_ips or with_private_key" -v
```
Expected: TypeError — unexpected keyword arguments

- [ ] **Step 3: Update render_client_conf signature in wg_templates.py**

Add `allowed_ips` and `client_private_key` keyword-only params:

```python
def render_client_conf(
    peer: Peer,
    iface: str,
    server_pubkey: str,
    endpoint_host: str,
    flavor: str,
    *,
    allowed_ips: str | None = None,
    client_private_key: str | None = None,
) -> str:
```

In the body, change the PrivateKey line:
```python
    privkey_line = f"PrivateKey = {client_private_key}" if client_private_key else "PrivateKey = ${CLIENT_PRIVATE_KEY}"
    lines.append(privkey_line)
```

Change the AllowedIPs logic:
```python
    if iface == "vpn":
        lines.append("AllowedIPs = 0.0.0.0/0, ::/0")
    elif allowed_ips:
        lines.append(f"AllowedIPs = {allowed_ips}")
    else:
        lines.append("AllowedIPs = 10.29.8.0/24")
```

- [ ] **Step 4: Run tests**

```bash
cd corpweb/backend && python -m pytest tests/test_wg_templates.py -v
```
Expected: all pass

- [ ] **Step 5: Add LB_ENDPOINT_HOST to config.py**

In `corpweb/backend/app/config.py`, add to Settings class:
```python
    # HA: endpoint hostname for client configs (defaults to FRONTEND_URL hostname)
    LB_ENDPOINT_HOST: str = ""
```

- [ ] **Step 6: Write failing test for vpn_manager_new**

Add to `corpweb/backend/tests/test_vpn_manager_new.py`:

```python
def test_get_client_conf_with_private_key(db):
    mgr = VpnManager()
    mgr.bootstrap(db)
    info = mgr.add_peer(db, "dave-1")
    conf = mgr.get_client_conf(db, "dave-1", "awg", "lb.example.com",
                                client_private_key=info["private_key"])
    assert info["private_key"] in conf
    assert "${CLIENT_PRIVATE_KEY}" not in conf

def test_get_antizapret_allowed_ips_missing(db):
    mgr = VpnManager()
    assert mgr.get_antizapret_allowed_ips(db) is None

def test_get_antizapret_allowed_ips_present(db):
    mgr = VpnManager()
    from app.services.wg_blob_store import WgBlobStore
    store = WgBlobStore(db)
    store.put("antizapret:allowed_ips", b"10.29.8.0/24, 1.2.3.0/24", by="test")
    result = mgr.get_antizapret_allowed_ips(db)
    assert "1.2.3.0/24" in result

def test_check_all_nodes_applied_no_nodes(db):
    mgr = VpnManager()
    # No nodes → trivially applied
    assert mgr.check_all_nodes_applied(db, "/etc/wireguard/antizapret.conf") is True
```

- [ ] **Step 7: Update vpn_manager_new.py**

Add `get_antizapret_allowed_ips` method:
```python
def get_antizapret_allowed_ips(self, db: Session) -> str | None:
    store = WgBlobStore(db)
    blob = store.get("antizapret:allowed_ips")
    return blob.decode() if blob else None
```

Add `check_all_nodes_applied` method:
```python
def check_all_nodes_applied(self, db: Session, path: str) -> bool:
    """Check if all live nodes have applied the current version of path."""
    from app.db.models import Node
    store = WgBlobStore(db)
    paths = store.get_all_paths()
    current_sha = paths.get(path)
    if not current_sha:
        return True  # no file → nothing to apply

    live_nodes = db.query(Node).filter(Node.health.in_(["ok", "degraded"])).all()
    if not live_nodes:
        return True  # no live nodes → trivially applied

    for node in live_nodes:
        node_sha = (node.applied_sha or {}).get(path)
        if node_sha != current_sha:
            return False
    return True
```

Update `get_client_conf` to accept and pass through `client_private_key` and `allowed_ips`:
```python
def get_client_conf(
    self, db: Session, name: str, flavor: str, endpoint_host: str,
    iface: str = "antizapret", *,
    client_private_key: str | None = None,
    allowed_ips: str | None = None,
) -> str:
    # ... existing code ...
    return render_client_conf(
        peer=target, iface=iface, server_pubkey=server_keys.public_key,
        endpoint_host=endpoint_host, flavor=flavor,
        client_private_key=client_private_key, allowed_ips=allowed_ips,
    )
```

- [ ] **Step 8: Run tests**

```bash
cd corpweb/backend && python -m pytest tests/test_vpn_manager_new.py tests/test_wg_templates.py -v
```
Expected: all pass

- [ ] **Step 9: Commit**

```bash
git add corpweb/backend/app/services/wg_templates.py \
        corpweb/backend/app/services/vpn_manager_new.py \
        corpweb/backend/app/config.py \
        corpweb/backend/tests/
git commit -m "feat: render_client_conf private_key/allowed_ips + check_all_nodes_applied"
```

---

### Task C: Apply-status SSE endpoint for frontend

**Files:**
- Create: `corpweb/backend/app/api/v1/apply_status.py`
- Modify: `corpweb/backend/app/main.py`
- Test: `corpweb/backend/tests/test_apply_status.py`

- [ ] **Step 1: Write failing tests**

```python
# corpweb/backend/tests/test_apply_status.py
from tests.conftest import auth_header


def test_apply_status_requires_auth(client, db):
    resp = client.get("/api/v1/apply-status?path=/etc/wireguard/antizapret.conf")
    assert resp.status_code == 401


def test_apply_status_no_nodes_returns_ready(client, db, admin_user, admin_token):
    """With no live nodes, status is immediately ready."""
    from app.services.wg_blob_store import WgBlobStore
    store = WgBlobStore(db)
    store.put("/etc/wireguard/antizapret.conf", b"content", by="test")

    resp = client.get(
        "/api/v1/apply-status?path=/etc/wireguard/antizapret.conf",
        headers=auth_header(admin_token),
    )
    assert resp.status_code == 200
    data = resp.json()
    assert data["applied"] is True
```

- [ ] **Step 2: Run to verify failure**

```bash
cd corpweb/backend && python -m pytest tests/test_apply_status.py -v
```
Expected: 404 (route not registered)

- [ ] **Step 3: Create apply_status.py**

```python
# corpweb/backend/app/api/v1/apply_status.py
"""
Apply-status endpoints for frontend.

GET  /apply-status?path=P  — JSON: are all live nodes synced for this path?
GET  /apply-status/stream?path=P  — SSE: stream until all nodes synced or 30s timeout
"""
import asyncio
import logging
import os
from typing import AsyncGenerator

from fastapi import APIRouter, Depends, Query
from fastapi.responses import StreamingResponse
from sqlalchemy.orm import Session

from app.db.session import get_db
from app.db.models import Node
from app.api.deps import get_current_user
from app.services.vpn_manager_new import vpn_manager

logger = logging.getLogger(__name__)
router = APIRouter()


def _check_applied(db: Session, path: str) -> dict:
    """Check if all live nodes have applied the current sha for path."""
    from app.services.wg_blob_store import WgBlobStore
    store = WgBlobStore(db)
    paths = store.get_all_paths()
    current_sha = paths.get(path)

    live_nodes = db.query(Node).filter(Node.health.in_(["ok", "degraded"])).all()

    if not live_nodes or not current_sha:
        return {"applied": True, "live_nodes": len(live_nodes), "synced_nodes": len(live_nodes)}

    synced = sum(1 for n in live_nodes if (n.applied_sha or {}).get(path) == current_sha)
    return {
        "applied": synced == len(live_nodes),
        "live_nodes": len(live_nodes),
        "synced_nodes": synced,
    }


@router.get("")
def apply_status(
    path: str = Query(...),
    db: Session = Depends(get_db),
    _=Depends(get_current_user),
):
    return _check_applied(db, path)


@router.get("/stream")
async def apply_status_stream(
    path: str = Query(...),
    db: Session = Depends(get_db),
    _=Depends(get_current_user),
):
    """
    SSE stream that emits status events until all live nodes have applied,
    or 30s timeout. Frontend connects after POST /configs.
    """
    async def stream() -> AsyncGenerator[str, None]:
        database_url = os.environ.get("DATABASE_URL", "")
        deadline = asyncio.get_event_loop().time() + 30.0

        # Quick check — maybe already applied
        status = _check_applied(db, path)
        if status["applied"]:
            yield f'data: {{"status": "ready", "synced": {status["synced_nodes"]}, "total": {status["live_nodes"]}}}\n\n'
            return

        # In SQLite tests, skip asyncpg
        if not database_url.startswith("postgresql"):
            yield 'data: {"status": "ready", "synced": 0, "total": 0}\n\n'
            return

        try:
            import asyncpg
            queue: asyncio.Queue = asyncio.Queue()
            conn = await asyncpg.connect(database_url)

            def on_notify(conn, pid, channel, payload):
                queue.put_nowait(payload)

            await conn.add_listener("node_applied", on_notify)

            try:
                while True:
                    remaining = deadline - asyncio.get_event_loop().time()
                    if remaining <= 0:
                        # Timeout — send ready with warning
                        status = _check_applied(db, path)
                        warning = "" if status["applied"] else ', "warning": "timeout: not all nodes synced"'
                        yield f'data: {{"status": "ready", "synced": {status["synced_nodes"]}, "total": {status["live_nodes"]}{warning}}}\n\n'
                        return

                    try:
                        await asyncio.wait_for(queue.get(), timeout=min(remaining, 3.0))
                    except asyncio.TimeoutError:
                        pass

                    # Re-check after notification or periodic tick
                    db.expire_all()  # refresh from DB
                    status = _check_applied(db, path)
                    yield f'data: {{"status": "{"ready" if status["applied"] else "applying"}", "synced": {status["synced_nodes"]}, "total": {status["live_nodes"]}}}\n\n'

                    if status["applied"]:
                        return
            finally:
                await conn.remove_listener("node_applied", on_notify)
                await conn.close()

        except Exception as e:
            logger.error("Apply-status SSE error: %s", e)
            yield 'data: {"status": "ready", "synced": 0, "total": 0, "warning": "SSE error"}\n\n'

    return StreamingResponse(
        stream(),
        media_type="text/event-stream",
        headers={"Cache-Control": "no-cache", "X-Accel-Buffering": "no"},
    )
```

- [ ] **Step 4: Register router in main.py**

```python
from app.api.v1 import apply_status
app.include_router(apply_status.router, prefix="/api/v1/apply-status", tags=["apply-status"])
```

Also add SSE proxy location in `control-plane/nginx.conf`:
```nginx
location /api/v1/apply-status/stream {
    proxy_pass http://corpweb_backend;
    proxy_http_version 1.1;
    proxy_read_timeout 60s;
    proxy_buffering off;
    proxy_cache off;
    proxy_set_header Connection '';
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
    chunked_transfer_encoding on;
}
```

- [ ] **Step 5: Run tests**

```bash
cd corpweb/backend && python -m pytest tests/test_apply_status.py -v
```
Expected: 2 passed

- [ ] **Step 6: Commit**

```bash
git add corpweb/backend/app/api/v1/apply_status.py \
        corpweb/backend/app/main.py \
        corpweb/backend/tests/test_apply_status.py \
        control-plane/nginx.conf
git commit -m "feat: apply-status SSE endpoint — frontend waits for nodes to confirm"
```

---

### Task D: Wire existing API endpoints to vpn_manager_new

**Files:**
- Modify: `corpweb/backend/app/api/v1/configs.py`
- Modify: `corpweb/backend/app/api/v1/admin.py`
- Modify: `corpweb/backend/app/api/v1/public.py`
- Test: `corpweb/backend/tests/test_configs_new.py`

- [ ] **Step 1: Write failing test**

```python
# corpweb/backend/tests/test_configs_new.py
"""Tests for configs endpoints using DB-backed vpn_manager_new."""
from tests.conftest import auth_header
from app.services.vpn_manager_new import VpnManager


def test_create_config_writes_to_db(client, db, admin_user, admin_token, system_settings):
    # Bootstrap the new vpn manager
    mgr = VpnManager()
    mgr.bootstrap(db)

    resp = client.post(
        "/api/v1/configs",
        headers=auth_header(admin_token),
        json={"config_type": "awg_antizapret"},
    )
    assert resp.status_code == 201
    data = resp.json()
    assert data["client_name"].startswith("admin-")

    # Peer must exist in wg_file_state blob, not on disk
    from app.services.wg_blob_store import WgBlobStore
    store = WgBlobStore(db)
    content = store.get("/etc/wireguard/antizapret.conf")
    assert content is not None
    assert b"admin-" in content


def test_create_config_stores_private_key(client, db, admin_user, admin_token, system_settings):
    mgr = VpnManager()
    mgr.bootstrap(db)

    resp = client.post(
        "/api/v1/configs",
        headers=auth_header(admin_token),
        json={"config_type": "awg_antizapret"},
    )
    assert resp.status_code == 201
    config_id = resp.json()["id"]

    # Check config_metadata has private_key
    from app.db.models import VPNConfig
    config = db.query(VPNConfig).filter(VPNConfig.id == config_id).first()
    assert config.config_metadata is not None
    assert "private_key" in config.config_metadata
    assert len(config.config_metadata["private_key"]) > 20


def test_delete_config_removes_from_blob(client, db, admin_user, admin_token, system_settings):
    mgr = VpnManager()
    mgr.bootstrap(db)

    # Create
    resp = client.post(
        "/api/v1/configs",
        headers=auth_header(admin_token),
        json={"config_type": "awg_antizapret"},
    )
    config_id = resp.json()["id"]
    client_name = resp.json()["client_name"]

    # Delete
    resp = client.delete(
        f"/api/v1/configs/{config_id}",
        headers=auth_header(admin_token),
    )
    assert resp.status_code == 204

    # Peer should be gone from blob
    from app.services.wg_blob_store import WgBlobStore
    store = WgBlobStore(db)
    content = store.get("/etc/wireguard/antizapret.conf")
    assert client_name.encode() not in content
```

- [ ] **Step 2: Run to verify failure**

```bash
cd corpweb/backend && python -m pytest tests/test_configs_new.py -v
```
Expected: FAIL (still calls old vpn_manager → subprocess)

- [ ] **Step 3: Update `configs.py`**

Replace import:
```python
# OLD:
from app.services.vpn_manager import vpn_manager, generate_client_name, VPNManagerError
# NEW:
from app.services.vpn_manager_new import vpn_manager, generate_client_name
```

Update `create_config`:
```python
    try:
        result = vpn_manager.add_peer(db, client_name)
    except (ValueError, Exception) as e:
        logger.error(f"Failed to create VPN config: {e}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Failed to create VPN config: {str(e)}"
        )

    config = crud_config.create(
        db,
        user_id=current_user.id,
        client_name=client_name,
        config_type=data.config_type,
        config_file_path=None,  # no longer on disk
        config_metadata={
            "vpn_ip": result.get("vpn_ip"),
            "private_key": result.get("private_key"),
            "preshared_key": result.get("preshared_key"),
        }
    )
```

Update `download_config` — replace `vpn_manager.read_config_file`:
```python
    if config.config_type == "awg_antizapret":
        iface, flavor = "antizapret", "awg"
    else:
        iface, flavor = "vpn", "awg"

    from app.config import settings as app_settings
    endpoint_host = app_settings.LB_ENDPOINT_HOST or urlparse(app_settings.FRONTEND_URL).hostname

    try:
        allowed_ips = vpn_manager.get_antizapret_allowed_ips(db) if iface == "antizapret" else None
        private_key = config.config_metadata.get("private_key") if config.config_metadata else None
        content = vpn_manager.get_client_conf(
            db, config.client_name, flavor, endpoint_host, iface,
            client_private_key=private_key,
            allowed_ips=allowed_ips,
        )
    except ValueError as e:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail=str(e))
```

Update `get_config_qr` — same pattern as download.

Update `delete_config`:
```python
    # OLD: vpn_manager.delete_client(config.client_name)
    # NEW:
    try:
        vpn_manager.delete_peer(db, config.client_name)
    except Exception as e:
        logger.error(f"Failed to delete VPN peer {config.client_name}: {e}")
```

- [ ] **Step 4: Update `admin.py`**

Replace import:
```python
# OLD: from app.services.vpn_manager import vpn_manager, VPNManagerError
# NEW: from app.services.vpn_manager_new import vpn_manager
```

Update `toggle_user_block`:
```python
    # OLD: vpn_manager.disable_peer(client_name)
    # NEW: vpn_manager.disable_peer(db, client_name)
    # OLD: vpn_manager.enable_peer(client_name)
    # NEW: vpn_manager.enable_peer(db, client_name)
```

Update `delete_user`:
```python
    # OLD: vpn_manager.delete_client(config.client_name)
    # NEW: vpn_manager.delete_peer(db, config.client_name)
```

Replace `VPNManagerError` catches with `(ValueError, Exception)`.

- [ ] **Step 5: Update `public.py`**

Replace import and update `download_shared_config`:
```python
# OLD: from app.services.vpn_manager import vpn_manager, VPNManagerError
# NEW: from app.services.vpn_manager_new import vpn_manager
```

Same download pattern as configs.py — replace `read_config_file` with `get_client_conf`.

- [ ] **Step 6: Run tests**

```bash
cd corpweb/backend && python -m pytest tests/test_configs_new.py tests/test_agent_api.py tests/test_import_wgfiles.py -v
```
Expected: all pass

- [ ] **Step 7: Commit**

```bash
git add corpweb/backend/app/api/v1/configs.py \
        corpweb/backend/app/api/v1/admin.py \
        corpweb/backend/app/api/v1/public.py \
        corpweb/backend/tests/test_configs_new.py
git commit -m "feat: wire configs/admin/public endpoints to DB-backed vpn_manager_new"
```

---

### Task E: Data migration script

**Files:**
- Create: `corpweb/backend/app/migrate.py`
- Test: `corpweb/backend/tests/test_migration.py`

- [ ] **Step 1: Write failing test**

```python
# corpweb/backend/tests/test_migration.py
import os
import tempfile
from pathlib import Path

from app.migrate import migrate_files_to_db, extract_client_private_keys
from app.services.wg_blob_store import WgBlobStore
from app.db.models import WgServerKeys, VPNConfig

SAMPLE_SERVER_CONF = """\
[Interface]
PrivateKey = yC5Y8Nf0EAZsSmZ16uvNpQ7mHT3nXA7KWyxkQBOVYUg=
Address = 10.29.8.1/21
ListenPort = 51443

# Client = alice-1
# PrivateKey = ALICE_PRIV_KEY==
[Peer]
PublicKey = ALICE_PUB==
PresharedKey = ALICE_PSK==
AllowedIPs = 10.29.8.2/32
"""

SAMPLE_KEY_FILE = "PRIVATE_KEY=yC5Y8Nf0EAZsSmZ16uvNpQ7mHT3nXA7KWyxkQBOVYUg=\nPUBLIC_KEY=gJJVrPl8KazvYzf8Yp5UxgrYnDqYyjjdYO8rfqzl6nI=\n"


def test_extract_client_private_keys():
    keys = extract_client_private_keys(SAMPLE_SERVER_CONF)
    assert keys["alice-1"] == "ALICE_PRIV_KEY=="


def test_migrate_files_to_db(db):
    with tempfile.TemporaryDirectory() as tmpdir:
        wg_dir = os.path.join(tmpdir, "etc/wireguard")
        os.makedirs(wg_dir)
        Path(os.path.join(wg_dir, "antizapret.conf")).write_text(SAMPLE_SERVER_CONF)
        Path(os.path.join(wg_dir, "vpn.conf")).write_text(SAMPLE_SERVER_CONF.replace("51443", "51080"))
        Path(os.path.join(wg_dir, "key")).write_text(SAMPLE_KEY_FILE)

        config_dir = os.path.join(tmpdir, "root/antizapret/config")
        os.makedirs(config_dir)
        Path(os.path.join(config_dir, "include-hosts.txt")).write_text("example.com\n")

        client_dir = os.path.join(tmpdir, "root/antizapret/client/amneziawg/antizapret")
        os.makedirs(client_dir)
        Path(os.path.join(client_dir, "antizapret-alice-1-(host)-am.conf")).write_text(
            "[Interface]\n[Peer]\nAllowedIPs = 10.29.8.0/24, 1.2.3.0/24\n"
        )

        migrate_files_to_db(db, root=tmpdir)

        store = WgBlobStore(db)
        assert store.get("/etc/wireguard/antizapret.conf") is not None
        assert store.get("/root/antizapret/config/include-hosts.txt") is not None

        keys = db.get(WgServerKeys, "antizapret")
        assert keys.private_key == "yC5Y8Nf0EAZsSmZ16uvNpQ7mHT3nXA7KWyxkQBOVYUg="

        allowed = store.get("antizapret:allowed_ips")
        assert allowed is not None
        assert b"1.2.3.0/24" in allowed
```

- [ ] **Step 2: Run to verify failure**

```bash
cd corpweb/backend && python -m pytest tests/test_migration.py -v
```
Expected: `ModuleNotFoundError`

- [ ] **Step 3: Create `corpweb/backend/app/migrate.py`**

```python
"""
One-time migration: files on disk → DB.

Usage:  cd /opt/corpweb/backend && python3 -m app.migrate

Idempotent — safe to run multiple times.
"""
import logging
import os
from pathlib import Path

from sqlalchemy.orm import Session

from app.db.models import WgServerKeys, VPNConfig
from app.services.wg_blob_store import WgBlobStore

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
log = logging.getLogger("migrate")

MANAGED_FILES = [
    "/etc/wireguard/antizapret.conf",
    "/etc/wireguard/vpn.conf",
    "/root/antizapret/setup",
    "/root/antizapret/config/include-hosts.txt",
    "/root/antizapret/config/exclude-hosts.txt",
    "/root/antizapret/config/include-ips.txt",
    "/root/antizapret/config/exclude-ips.txt",
    "/root/antizapret/config/allow-ips.txt",
    "/root/antizapret/config/forward-ips.txt",
    "/root/antizapret/config/include-adblock-hosts.txt",
    "/root/antizapret/config/exclude-adblock-hosts.txt",
    "/root/antizapret/config/remove-hosts.txt",
]


def extract_client_private_keys(server_conf: str) -> dict[str, str]:
    """Parse '# Client = name' + '# PrivateKey = key' from server conf."""
    result = {}
    current_name = None
    for line in server_conf.splitlines():
        stripped = line.strip()
        if stripped.startswith("# Client") and "=" in stripped:
            current_name = stripped.split("=", 1)[1].strip()
        elif stripped.startswith("# PrivateKey") and "=" in stripped and current_name:
            result[current_name] = stripped.split("=", 1)[1].strip()
            current_name = None
    return result


def _extract_allowed_ips(client_conf_dir: str) -> str | None:
    """Read any antizapret client conf, extract AllowedIPs value."""
    p = Path(client_conf_dir)
    if not p.exists():
        return None
    for f in p.glob("antizapret-*-am.conf"):
        for line in f.read_text().splitlines():
            if line.strip().lower().startswith("allowedips"):
                return line.split("=", 1)[1].strip()
        break
    return None


def migrate_files_to_db(db: Session, root: str = "") -> None:
    store = WgBlobStore(db)
    migrated = 0

    # 1. Managed files → wg_file_state
    for rel_path in MANAGED_FILES:
        abs_path = os.path.join(root, rel_path.lstrip("/"))
        if not os.path.exists(abs_path):
            log.warning("Not found, skip: %s", abs_path)
            continue
        content = Path(abs_path).read_bytes()
        store.put(rel_path, content, by="migrate")
        migrated += 1
        log.info("Migrated %s (%d bytes)", rel_path, len(content))

    # 2. Server keypair → wg_server_keys
    key_path = os.path.join(root, "etc/wireguard/key")
    if os.path.exists(key_path):
        priv = pub = None
        for line in Path(key_path).read_text().splitlines():
            if line.startswith("PRIVATE_KEY="):
                priv = line.split("=", 1)[1].strip()
            elif line.startswith("PUBLIC_KEY="):
                pub = line.split("=", 1)[1].strip()
        if priv and pub:
            for iface in ("antizapret", "vpn"):
                existing = db.get(WgServerKeys, iface)
                if existing:
                    existing.private_key = priv
                    existing.public_key = pub
                else:
                    db.add(WgServerKeys(iface=iface, private_key=priv, public_key=pub))
            db.commit()
            log.info("Migrated server keypair")

    # 3. Client private keys → vpn_configs.config_metadata
    az_path = os.path.join(root, "etc/wireguard/antizapret.conf")
    if os.path.exists(az_path):
        client_keys = extract_client_private_keys(Path(az_path).read_text())
        updated = 0
        for config in db.query(VPNConfig).all():
            priv = client_keys.get(config.client_name)
            if priv:
                meta = dict(config.config_metadata or {})
                meta["private_key"] = priv
                config.config_metadata = meta
                updated += 1
        db.commit()
        log.info("Updated %d vpn_configs with client private keys", updated)

    # 4. AllowedIPs template from existing client conf
    client_dir = os.path.join(root, "root/antizapret/client/amneziawg/antizapret")
    allowed_ips = _extract_allowed_ips(client_dir)
    if allowed_ips:
        store.put("antizapret:allowed_ips", allowed_ips.encode(), by="migrate")
        log.info("Stored AllowedIPs template (%d chars)", len(allowed_ips))

    log.info("Done: %d files migrated", migrated)


if __name__ == "__main__":
    from app.db.session import SessionLocal
    db = SessionLocal()
    try:
        migrate_files_to_db(db)
    finally:
        db.close()
```

- [ ] **Step 4: Run tests**

```bash
cd corpweb/backend && python -m pytest tests/test_migration.py -v
```
Expected: 2 passed

- [ ] **Step 5: Commit**

```bash
git add corpweb/backend/app/migrate.py corpweb/backend/tests/test_migration.py
git commit -m "feat: file-to-DB migration script (python3 -m app.migrate)"
```

---

### Task F: Frontend — spinner during config creation

**Files:**
- Modify: frontend config creation flow (check exact component by reading App.tsx/pages)
- Create or modify: `corpweb/frontend/src/api/configs.ts` or equivalent

Read the existing frontend code first to find:
1. Which component handles "Create config" button
2. How the current create flow works
3. Where to add the SSE subscription

The frontend change:
1. After `POST /configs` returns `201`, connect to `GET /api/v1/apply-status/stream?path=/etc/wireguard/antizapret.conf`
2. Show spinner "Применяю конфигурацию..."
3. When SSE sends `{"status": "ready"}` → close connection, show config card with download button
4. Add `EventSource` helper in `src/api/` module

- [ ] **Step 1: Read existing frontend config creation code**

```bash
grep -rn "POST.*configs\|createConfig\|create_config" corpweb/frontend/src/
```

- [ ] **Step 2: Add SSE helper to api module**

```typescript
// In src/api/configs.ts or new file src/api/applyStatus.ts
export function waitForApply(path: string): Promise<{status: string; warning?: string}> {
  return new Promise((resolve) => {
    const token = localStorage.getItem('access_token');
    const url = `/api/v1/apply-status/stream?path=${encodeURIComponent(path)}`;
    const es = new EventSource(url);  // Note: EventSource doesn't support auth headers
    // Use fetch with ReadableStream instead:

    fetch(url, {
      headers: { Authorization: `Bearer ${token}` },
    }).then(async (resp) => {
      const reader = resp.body!.getReader();
      const decoder = new TextDecoder();
      while (true) {
        const { done, value } = await reader.read();
        if (done) break;
        const text = decoder.decode(value);
        for (const line of text.split('\n')) {
          if (line.startsWith('data:')) {
            const data = JSON.parse(line.slice(5).trim());
            if (data.status === 'ready') {
              resolve(data);
              reader.cancel();
              return;
            }
          }
        }
      }
      resolve({ status: 'ready' });
    }).catch(() => resolve({ status: 'ready' }));
  });
}
```

- [ ] **Step 3: Update config creation component**

After `POST /configs` → show spinner → call `waitForApply("/etc/wireguard/antizapret.conf")` → on resolve → show download button.

Exact component paths depend on the existing code — read first, then modify.

- [ ] **Step 4: Build and test**

```bash
cd corpweb/frontend && npx tsc --noEmit && npm run build
```

- [ ] **Step 5: Commit**

```bash
git add corpweb/frontend/src/
git commit -m "feat: frontend waits for node apply confirmation before showing download"
```

---

### Task G: Full test suite + final commit

- [ ] **Step 1: Run all backend tests**

```bash
cd corpweb/backend && python -m pytest -v
```
Expected: all pass

- [ ] **Step 2: Build frontend**

```bash
cd corpweb/frontend && npm run build
```

- [ ] **Step 3: Commit any fixes**

---

## Deployment Runbook

```bash
# === On wgfi2 ===

# 1. Deploy code
rsync -av <repo>/corpweb/ /opt/corpweb/ --exclude .git --exclude venv --exclude node_modules

# 2. Backend deps
cd /opt/corpweb/backend && source venv/bin/activate && pip install -r requirements.txt

# 3. Frontend build
cd /opt/corpweb/frontend && npm ci && npm run build

# 4. Alembic migration
cd /opt/corpweb/backend
alembic stamp base       # mark existing tables as base
alembic upgrade head     # create 3 new tables + 2 triggers

# 5. Migrate files to DB
python3 -m app.migrate
# Expected: 12 files + keypair + 517 private keys + AllowedIPs template

# 6. Restart backend
systemctl restart corpweb-backend
curl -s https://wgfi2.p4i.ru/api/health  # verify

# 7. Test: create config in panel, verify spinner, verify download works

# 8. Install sync-agent (localhost mode)
# First: create node "wgfi2" via panel → get enroll token
CORPWEB_CP_URL=http://127.0.0.1:8000 CORPWEB_TOKEN=<token> bash /opt/corpweb/agent/install.sh

# === Cutover to new CP (later) ===

# 9. Backup
pg_dump -U corpweb corpweb_db > /tmp/corpweb_backup.sql

# 10. On new CP: deploy + restore
# install.sh + psql corpweb_db < backup.sql + systemctl start

# 11. On wgfi2: point agent to new CP
sed -i 's|http://127.0.0.1:8000|https://panel.example.com|' /etc/corpweb-sync-agent.env
systemctl restart corpweb-sync-agent

# 12. DNS: wgfi2.p4i.ru → new CP IP
# 13. nginx on CP: add wgfi2 to upstream blocks, nginx -s reload
```
