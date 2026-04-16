"""
Tests for Apply-status endpoints.
GET /api/v1/apply-status?path=P — JSON check
GET /api/v1/apply-status/stream?path=P — SSE stream
"""
from tests.conftest import auth_header


def test_apply_status_requires_auth(client, db):
    resp = client.get("/api/v1/apply-status?path=/etc/wireguard/antizapret.conf")
    assert resp.status_code == 401


def test_apply_status_no_nodes_returns_applied(client, db, admin_user, admin_token):
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


def test_apply_status_node_not_synced(client, db, admin_user, admin_token):
    from app.services.wg_blob_store import WgBlobStore
    from app.db.models import Node
    store = WgBlobStore(db)
    store.put("/etc/wireguard/antizapret.conf", b"new content", by="test")

    # Create a live node that hasn't applied yet
    node = Node(hostname="node1", private_ip="10.0.0.1", enroll_token="tok1", health="ok", applied_sha={})
    db.add(node)
    db.commit()

    resp = client.get(
        "/api/v1/apply-status?path=/etc/wireguard/antizapret.conf",
        headers=auth_header(admin_token),
    )
    assert resp.status_code == 200
    data = resp.json()
    assert data["applied"] is False
    assert data["live_nodes"] == 1
    assert data["synced_nodes"] == 0


def test_apply_status_node_synced(client, db, admin_user, admin_token):
    """Node that has applied the current sha reports as synced."""
    import hashlib
    from app.services.wg_blob_store import WgBlobStore
    from app.db.models import Node

    content = b"synced content"
    sha = hashlib.sha256(content).hexdigest()
    store = WgBlobStore(db)
    store.put("/etc/wireguard/antizapret.conf", content, by="test")

    node = Node(
        hostname="node2",
        private_ip="10.0.0.2",
        enroll_token="tok2",
        health="ok",
        applied_sha={"/etc/wireguard/antizapret.conf": sha},
    )
    db.add(node)
    db.commit()

    resp = client.get(
        "/api/v1/apply-status?path=/etc/wireguard/antizapret.conf",
        headers=auth_header(admin_token),
    )
    assert resp.status_code == 200
    data = resp.json()
    assert data["applied"] is True
    assert data["live_nodes"] == 1
    assert data["synced_nodes"] == 1


def test_apply_status_degraded_node_counts_as_live(client, db, admin_user, admin_token):
    """Nodes with health='degraded' still count as live."""
    from app.services.wg_blob_store import WgBlobStore
    from app.db.models import Node

    store = WgBlobStore(db)
    store.put("/etc/wireguard/antizapret.conf", b"data", by="test")

    node = Node(
        hostname="node3",
        private_ip="10.0.0.3",
        enroll_token="tok3",
        health="degraded",
        applied_sha={},
    )
    db.add(node)
    db.commit()

    resp = client.get(
        "/api/v1/apply-status?path=/etc/wireguard/antizapret.conf",
        headers=auth_header(admin_token),
    )
    assert resp.status_code == 200
    data = resp.json()
    assert data["live_nodes"] == 1
    assert data["applied"] is False


def test_apply_status_draining_node_not_counted(client, db, admin_user, admin_token):
    """Nodes with health='draining' are NOT counted as live."""
    from app.services.wg_blob_store import WgBlobStore
    from app.db.models import Node

    store = WgBlobStore(db)
    store.put("/etc/wireguard/antizapret.conf", b"data", by="test")

    node = Node(
        hostname="node4",
        private_ip="10.0.0.4",
        enroll_token="tok4",
        health="draining",
        applied_sha={},
    )
    db.add(node)
    db.commit()

    resp = client.get(
        "/api/v1/apply-status?path=/etc/wireguard/antizapret.conf",
        headers=auth_header(admin_token),
    )
    assert resp.status_code == 200
    data = resp.json()
    # draining nodes not counted — no live nodes → applied=True
    assert data["live_nodes"] == 0
    assert data["applied"] is True


def test_apply_status_no_path_in_store(client, db, admin_user, admin_token):
    """Path doesn't exist in store — no live nodes either — returns applied=True."""
    resp = client.get(
        "/api/v1/apply-status?path=/etc/wireguard/nonexistent.conf",
        headers=auth_header(admin_token),
    )
    assert resp.status_code == 200
    data = resp.json()
    assert data["applied"] is True


# ── SSE stream endpoint ──


def test_apply_status_stream_requires_auth(client, db):
    resp = client.get("/api/v1/apply-status/stream?path=/etc/wireguard/antizapret.conf")
    assert resp.status_code == 401


def test_apply_status_stream_sqlite_returns_ready(client, db, admin_user, admin_token):
    """In SQLite test mode, stream immediately returns {status: ready}."""
    from app.services.wg_blob_store import WgBlobStore
    store = WgBlobStore(db)
    store.put("/etc/wireguard/antizapret.conf", b"content", by="test")

    resp = client.get(
        "/api/v1/apply-status/stream?path=/etc/wireguard/antizapret.conf",
        headers=auth_header(admin_token),
    )
    assert resp.status_code == 200
    assert "text/event-stream" in resp.headers["content-type"]
    assert "no-cache" in resp.headers.get("cache-control", "")
    # Parse SSE data line
    body = resp.text
    assert "ready" in body


def test_apply_status_stream_already_applied_returns_ready(client, db, admin_user, admin_token):
    """If already applied, stream sends ready immediately."""
    resp = client.get(
        "/api/v1/apply-status/stream?path=/etc/wireguard/antizapret.conf",
        headers=auth_header(admin_token),
    )
    assert resp.status_code == 200
    body = resp.text
    assert "ready" in body
