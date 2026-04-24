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


def test_ip_map_resolves_escape_subnets(db):
    """_build_ip_map must resolve 10.27.x.x → az_escape and 10.26.x.x →
    vpn_escape to the same client_name as the baseline 10.29.x.x / 10.28.x.x
    pair, using the same host part."""
    from app.db.models import User, VPNConfig, Node
    from app.services.monitoring import MonitoringService
    import time

    user = User(email="esc@test", username="esc-user", password_hash="x", role="user", is_active=True)
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
        hostname="kvn-test",
        private_ip="10.0.0.9",
        enroll_token="tok-kvn-test",
        health="ok", last_seen=None,
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
