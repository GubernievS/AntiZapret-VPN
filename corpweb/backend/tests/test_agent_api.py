"""
Tests for Agent API and Nodes CRUD endpoints.
"""
import base64
import hashlib

from tests.conftest import auth_header
from app.db.models import Node, WgFileState, WgServerKeys


def _make_node(db, hostname="wgfi2", token="tok-test-001"):
    node = Node(hostname=hostname, private_ip="10.0.0.1", enroll_token=token)
    db.add(node)
    db.commit()
    db.refresh(node)
    return node


def _make_file(db, path="/etc/wireguard/wg0.conf", content=b"[Interface]\nAddress = 10.0.0.1/24"):
    sha = hashlib.sha256(content).hexdigest()
    row = WgFileState(
        path=path,
        content=content,
        sha256=sha,
        size_bytes=len(content),
        updated_by="test",
    )
    db.add(row)
    db.commit()
    db.refresh(row)
    return row


def _agent_auth(token="tok-test-001"):
    return {"Authorization": f"Bearer {token}"}


# ── Agent API tests ──


class TestAgentRegister:
    def test_register_valid_token(self, client, db):
        node = _make_node(db)
        resp = client.post(
            "/api/v1/agent/register",
            headers=_agent_auth(node.enroll_token),
            json={"hostname": "wgfi2", "private_ip": "10.0.0.2"},
        )
        assert resp.status_code == 200
        data = resp.json()
        assert data["node_id"] == node.id

    def test_register_wrong_token(self, client, db):
        resp = client.post(
            "/api/v1/agent/register",
            headers=_agent_auth("bad-token"),
            json={"hostname": "wgfi2", "private_ip": "10.0.0.2"},
        )
        assert resp.status_code == 401

    def test_register_missing_token(self, client, db):
        resp = client.post(
            "/api/v1/agent/register",
            json={"hostname": "wgfi2", "private_ip": "10.0.0.2"},
        )
        assert resp.status_code == 401


class TestAgentFile:
    def test_file_exists(self, client, db):
        node = _make_node(db)
        wf = _make_file(db)
        resp = client.get(
            "/api/v1/agent/file",
            headers=_agent_auth(node.enroll_token),
            params={"path": wf.path},
        )
        assert resp.status_code == 200
        data = resp.json()
        assert data["sha256"] == wf.sha256
        # Verify base64 content decodes correctly
        decoded = base64.b64decode(data["content"])
        assert decoded == b"[Interface]\nAddress = 10.0.0.1/24"

    def test_file_missing(self, client, db):
        node = _make_node(db)
        resp = client.get(
            "/api/v1/agent/file",
            headers=_agent_auth(node.enroll_token),
            params={"path": "/nonexistent"},
        )
        assert resp.status_code == 404

    def test_file_no_auth(self, client, db):
        resp = client.get(
            "/api/v1/agent/file",
            params={"path": "/etc/wireguard/wg0.conf"},
        )
        assert resp.status_code == 401


class TestAgentHeartbeat:
    def test_heartbeat_updates_node(self, client, db):
        node = _make_node(db)
        resp = client.post(
            "/api/v1/agent/heartbeat",
            headers=_agent_auth(node.enroll_token),
            json={
                "applied_sha": {"wg0.conf": "abc123"},
                "health": "healthy",
                "metrics": {"cpu": 12.5},
            },
        )
        assert resp.status_code == 200
        # Refresh from DB and verify updates
        db.refresh(node)
        assert node.health == "healthy"
        assert node.last_seen is not None
        assert node.applied_sha == {"wg0.conf": "abc123"}
        assert node.metrics == {"cpu": 12.5}


class TestAgentEvents:
    def test_events_wrong_token(self, client, db):
        resp = client.get(
            "/api/v1/agent/events",
            headers=_agent_auth("bad-token"),
        )
        assert resp.status_code == 401


class TestAgentDrain:
    def test_drain_sets_draining(self, client, db):
        node = _make_node(db)
        resp = client.post(
            "/api/v1/agent/drain",
            headers=_agent_auth(node.enroll_token),
        )
        assert resp.status_code == 200
        data = resp.json()
        assert data["ok"] is True
        assert data["ttl_minutes"] == 10
        # Verify node health updated
        db.refresh(node)
        assert node.health == "draining"


# ── Nodes CRUD tests ──


class TestNodesList:
    def test_list_nodes(self, client, db, admin_user, admin_token):
        _make_node(db, hostname="node-a", token="tok-a")
        _make_node(db, hostname="node-b", token="tok-b")
        resp = client.get("/api/v1/nodes", headers=auth_header(admin_token))
        assert resp.status_code == 200
        data = resp.json()
        assert len(data) == 2

    def test_list_nodes_no_auth(self, client, db):
        resp = client.get("/api/v1/nodes")
        assert resp.status_code == 401


class TestNodesCreate:
    def test_create_node(self, client, db, admin_user, admin_token):
        resp = client.post(
            "/api/v1/nodes",
            headers=auth_header(admin_token),
            json={"hostname": "new-node", "private_ip": "10.0.0.5"},
        )
        assert resp.status_code == 201
        data = resp.json()
        assert data["hostname"] == "new-node"
        assert "enroll_token" in data
        assert len(data["enroll_token"]) > 20  # secrets.token_urlsafe(32)

    def test_create_node_duplicate_hostname(self, client, db, admin_user, admin_token):
        _make_node(db, hostname="dup-node", token="tok-dup")
        resp = client.post(
            "/api/v1/nodes",
            headers=auth_header(admin_token),
            json={"hostname": "dup-node", "private_ip": "10.0.0.6"},
        )
        assert resp.status_code == 409

    def test_create_node_no_auth(self, client, db):
        resp = client.post(
            "/api/v1/nodes",
            json={"hostname": "x", "private_ip": "10.0.0.1"},
        )
        assert resp.status_code == 401


class TestNodesGet:
    def test_get_node(self, client, db, admin_user, admin_token):
        node = _make_node(db)
        resp = client.get(f"/api/v1/nodes/{node.id}", headers=auth_header(admin_token))
        assert resp.status_code == 200
        data = resp.json()
        assert data["hostname"] == node.hostname

    def test_get_node_not_found(self, client, db, admin_user, admin_token):
        resp = client.get("/api/v1/nodes/9999", headers=auth_header(admin_token))
        assert resp.status_code == 404


class TestNodesDelete:
    def test_delete_node(self, client, db, admin_user, admin_token):
        node = _make_node(db)
        resp = client.delete(f"/api/v1/nodes/{node.id}", headers=auth_header(admin_token))
        assert resp.status_code == 200
        # Verify deleted
        assert db.query(Node).filter_by(id=node.id).first() is None

    def test_delete_node_not_found(self, client, db, admin_user, admin_token):
        resp = client.delete("/api/v1/nodes/9999", headers=auth_header(admin_token))
        assert resp.status_code == 404


# ── Install script endpoints ──


class TestInstallScript:
    def test_install_sh_valid_token(self, client, db):
        node = _make_node(db)
        resp = client.get(f"/api/v1/agent/install.sh?token={node.enroll_token}")
        assert resp.status_code == 200
        assert "text/plain" in resp.headers["content-type"]
        body = resp.text
        assert "#!/usr/bin/env bash" in body
        assert node.enroll_token in body
        assert node.hostname in body

    def test_install_sh_invalid_token(self, client, db):
        resp = client.get("/api/v1/agent/install.sh?token=bad-token")
        assert resp.status_code == 404

    def test_install_sh_no_token(self, client, db):
        resp = client.get("/api/v1/agent/install.sh")
        assert resp.status_code == 422  # missing required query param
