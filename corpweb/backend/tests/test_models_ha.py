"""
Tests for HA-related database models: WgFileState, WgServerKeys, Node.
"""
import pytest
from datetime import datetime, timezone
from app.db.models import WgFileState, WgServerKeys, Node


def test_wg_file_state_create(db):
    row = WgFileState(
        path="/etc/wireguard/antizapret.conf",
        content=b"[Interface]\n",
        sha256="abc123",
        size_bytes=12,
        updated_at=datetime.now(timezone.utc),
        updated_by="test",
    )
    db.add(row)
    db.commit()
    db.refresh(row)
    assert row.path == "/etc/wireguard/antizapret.conf"
    assert row.content == b"[Interface]\n"


def test_wg_server_keys_create(db):
    row = WgServerKeys(
        iface="antizapret",
        private_key="priv==",
        public_key="pub==",
        created_at=datetime.now(timezone.utc),
    )
    db.add(row)
    db.commit()
    assert row.iface == "antizapret"


def test_node_create(db):
    row = Node(
        hostname="wgfi2",
        private_ip="10.0.0.1",
        enroll_token="tok123",
    )
    db.add(row)
    db.commit()
    db.refresh(row)
    assert row.id is not None
    assert row.health is None
