"""
Tests for MonitoringService backed by node agent heartbeats (Task 5).
"""
import time
from app.services.monitoring import MonitoringService
from app.db.models import Node


def _node_with_peers(db, hostname="n1", peers=None):
    node = Node(
        hostname=hostname,
        private_ip="10.0.0.1",
        enroll_token=f"tok-{hostname}",
        health="ok",
        metrics={"active_peers_antizapret": 2, "rx_bytes_per_sec": 1000, "tx_bytes_per_sec": 2000},
        peers_snapshot=peers or [],
    )
    db.add(node)
    db.commit()
    return node


def test_active_connections(db):
    now = int(time.time())
    _node_with_peers(db, "n1", [
        {
            "public_key": "pk1",
            "allowed_ips": "10.29.8.2/32",
            "endpoint": "1.2.3.4:51443",
            "latest_handshake": now - 10,
            "rx_bytes": 100,
            "tx_bytes": 200,
            "interface": "antizapret",
        },
        {
            "public_key": "pk2",
            "allowed_ips": "10.29.8.3/32",
            "endpoint": "5.6.7.8:51443",
            "latest_handshake": now - 300,
            "rx_bytes": 100,
            "tx_bytes": 200,
            "interface": "antizapret",
        },
    ])
    conns = MonitoringService(db).get_active_connections()
    assert len(conns) == 1
    assert conns[0]["public_key"] == "pk1"
    assert conns[0]["node"] == "n1"


def test_traffic_stats(db):
    _node_with_peers(db, "n1")
    _node_with_peers(db, "n2")
    stats = MonitoringService(db).get_traffic_stats()
    assert stats["total_rx_bytes_per_sec"] == 2000
    assert len(stats["per_node"]) == 2
