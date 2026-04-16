"""
Tests for vpn_manager_new — DB-backed VPN management (no file I/O, no subprocess).
"""
import base64

import pytest

from app.services.vpn_manager_new import VpnManager, generate_client_name


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _make_manager() -> VpnManager:
    return VpnManager()


# ---------------------------------------------------------------------------
# bootstrap
# ---------------------------------------------------------------------------

class TestBootstrap:
    def test_creates_two_keypairs(self, db):
        mgr = _make_manager()
        mgr.bootstrap(db)

        from app.db.models import WgServerKeys

        keys = db.query(WgServerKeys).all()
        ifaces = {k.iface for k in keys}
        assert ifaces == {"antizapret", "vpn"}

    def test_keypairs_are_valid_base64(self, db):
        mgr = _make_manager()
        mgr.bootstrap(db)

        from app.db.models import WgServerKeys

        for row in db.query(WgServerKeys).all():
            priv_bytes = base64.b64decode(row.private_key)
            pub_bytes = base64.b64decode(row.public_key)
            assert len(priv_bytes) == 32
            assert len(pub_bytes) == 32

    def test_idempotent(self, db):
        mgr = _make_manager()
        mgr.bootstrap(db)

        from app.db.models import WgServerKeys

        first_keys = {
            row.iface: (row.private_key, row.public_key)
            for row in db.query(WgServerKeys).all()
        }

        mgr.bootstrap(db)

        second_keys = {
            row.iface: (row.private_key, row.public_key)
            for row in db.query(WgServerKeys).all()
        }

        assert first_keys == second_keys

    def test_creates_empty_conf_blobs(self, db):
        mgr = _make_manager()
        mgr.bootstrap(db)

        from app.services.wg_blob_store import WgBlobStore

        store = WgBlobStore(db)
        az_blob = store.get("/etc/wireguard/antizapret.conf")
        vpn_blob = store.get("/etc/wireguard/vpn.conf")
        assert az_blob is not None
        assert vpn_blob is not None
        # Should be valid server confs (contain [Interface])
        assert b"[Interface]" in az_blob
        assert b"[Interface]" in vpn_blob


# ---------------------------------------------------------------------------
# add_peer
# ---------------------------------------------------------------------------

class TestAddPeer:
    def test_returns_correct_dict_keys(self, db):
        mgr = _make_manager()
        mgr.bootstrap(db)
        result = mgr.add_peer(db, "alice-1")
        assert "client_name" in result
        assert "vpn_ip" in result
        assert "private_key" in result
        assert "public_key_antizapret" in result
        assert "preshared_key" in result

    def test_client_name_matches(self, db):
        mgr = _make_manager()
        mgr.bootstrap(db)
        result = mgr.add_peer(db, "alice-1")
        assert result["client_name"] == "alice-1"

    def test_vpn_ip_starts_at_dot_2(self, db):
        mgr = _make_manager()
        mgr.bootstrap(db)
        result = mgr.add_peer(db, "alice-1")
        assert result["vpn_ip"] == "10.29.8.2"

    def test_second_peer_gets_dot_3(self, db):
        mgr = _make_manager()
        mgr.bootstrap(db)
        mgr.add_peer(db, "alice-1")
        result = mgr.add_peer(db, "bob-1")
        assert result["vpn_ip"] == "10.29.8.3"

    def test_private_key_is_valid_base64(self, db):
        mgr = _make_manager()
        mgr.bootstrap(db)
        result = mgr.add_peer(db, "alice-1")
        raw = base64.b64decode(result["private_key"])
        assert len(raw) == 32

    def test_preshared_key_is_valid_base64(self, db):
        mgr = _make_manager()
        mgr.bootstrap(db)
        result = mgr.add_peer(db, "alice-1")
        raw = base64.b64decode(result["preshared_key"])
        assert len(raw) == 32

    def test_appears_in_list_peers(self, db):
        mgr = _make_manager()
        mgr.bootstrap(db)
        mgr.add_peer(db, "alice-1")
        peers = mgr.list_peers(db)
        names = [p["name"] for p in peers]
        assert "alice-1" in names

    def test_peer_in_both_confs(self, db):
        """Peer should appear in both antizapret and vpn conf blobs."""
        mgr = _make_manager()
        mgr.bootstrap(db)
        mgr.add_peer(db, "alice-1")

        from app.services.wg_blob_store import WgBlobStore

        store = WgBlobStore(db)
        az_blob = store.get("/etc/wireguard/antizapret.conf")
        vpn_blob = store.get("/etc/wireguard/vpn.conf")
        assert b"# Client = alice-1" in az_blob
        assert b"# Client = alice-1" in vpn_blob


# ---------------------------------------------------------------------------
# delete_peer
# ---------------------------------------------------------------------------

class TestDeletePeer:
    def test_removes_from_list(self, db):
        mgr = _make_manager()
        mgr.bootstrap(db)
        mgr.add_peer(db, "alice-1")
        mgr.delete_peer(db, "alice-1")
        peers = mgr.list_peers(db)
        names = [p["name"] for p in peers]
        assert "alice-1" not in names

    def test_removes_from_both_confs(self, db):
        mgr = _make_manager()
        mgr.bootstrap(db)
        mgr.add_peer(db, "alice-1")
        mgr.delete_peer(db, "alice-1")

        from app.services.wg_blob_store import WgBlobStore

        store = WgBlobStore(db)
        az_blob = store.get("/etc/wireguard/antizapret.conf")
        vpn_blob = store.get("/etc/wireguard/vpn.conf")
        assert b"# Client = alice-1" not in az_blob
        assert b"# Client = alice-1" not in vpn_blob

    def test_ip_reused_after_delete(self, db):
        mgr = _make_manager()
        mgr.bootstrap(db)
        mgr.add_peer(db, "alice-1")
        mgr.delete_peer(db, "alice-1")
        result = mgr.add_peer(db, "bob-1")
        assert result["vpn_ip"] == "10.29.8.2"


# ---------------------------------------------------------------------------
# disable_peer / enable_peer
# ---------------------------------------------------------------------------

class TestDisableEnablePeer:
    def test_disable_changes_keys(self, db):
        mgr = _make_manager()
        mgr.bootstrap(db)
        result = mgr.add_peer(db, "alice-1")
        original_pub = result["public_key_antizapret"]

        mgr.disable_peer(db, "alice-1")

        peers = mgr.list_peers(db)
        alice = [p for p in peers if p["name"] == "alice-1"][0]
        assert alice["public_key"] != original_pub

    def test_roundtrip_preserves_key(self, db):
        mgr = _make_manager()
        mgr.bootstrap(db)
        result = mgr.add_peer(db, "alice-1")
        original_pub = result["public_key_antizapret"]

        mgr.disable_peer(db, "alice-1")
        mgr.enable_peer(db, "alice-1")

        peers = mgr.list_peers(db)
        alice = [p for p in peers if p["name"] == "alice-1"][0]
        assert alice["public_key"] == original_pub

    def test_disable_does_not_affect_other_peers(self, db):
        mgr = _make_manager()
        mgr.bootstrap(db)
        mgr.add_peer(db, "alice-1")
        bob_result = mgr.add_peer(db, "bob-1")
        bob_pub = bob_result["public_key_antizapret"]

        mgr.disable_peer(db, "alice-1")

        peers = mgr.list_peers(db)
        bob = [p for p in peers if p["name"] == "bob-1"][0]
        assert bob["public_key"] == bob_pub


# ---------------------------------------------------------------------------
# list_peers
# ---------------------------------------------------------------------------

class TestListPeers:
    def test_empty_after_bootstrap(self, db):
        mgr = _make_manager()
        mgr.bootstrap(db)
        peers = mgr.list_peers(db)
        assert peers == []

    def test_returns_dicts_with_expected_keys(self, db):
        mgr = _make_manager()
        mgr.bootstrap(db)
        mgr.add_peer(db, "alice-1")
        peers = mgr.list_peers(db)
        assert len(peers) == 1
        p = peers[0]
        assert "name" in p
        assert "public_key" in p
        assert "allowed_ips" in p


# ---------------------------------------------------------------------------
# get_client_conf
# ---------------------------------------------------------------------------

class TestGetClientConf:
    def test_awg_contains_i1(self, db):
        mgr = _make_manager()
        mgr.bootstrap(db)
        mgr.add_peer(db, "alice-1")
        conf = mgr.get_client_conf(
            db, "alice-1", flavor="awg", endpoint_host="vpn.example.com"
        )
        assert "I1 = " in conf

    def test_wg_has_no_obfuscation(self, db):
        mgr = _make_manager()
        mgr.bootstrap(db)
        mgr.add_peer(db, "alice-1")
        conf = mgr.get_client_conf(
            db, "alice-1", flavor="wg", endpoint_host="vpn.example.com"
        )
        assert "Jc" not in conf
        assert "I1" not in conf

    def test_vpn_iface_allowed_ips(self, db):
        mgr = _make_manager()
        mgr.bootstrap(db)
        mgr.add_peer(db, "alice-1")
        conf = mgr.get_client_conf(
            db, "alice-1", flavor="wg", endpoint_host="vpn.example.com",
            iface="vpn",
        )
        assert "0.0.0.0/0" in conf

    def test_contains_server_pubkey(self, db):
        mgr = _make_manager()
        mgr.bootstrap(db)
        mgr.add_peer(db, "alice-1")
        conf = mgr.get_client_conf(
            db, "alice-1", flavor="wg", endpoint_host="vpn.example.com"
        )
        # Should contain the server's public key
        from app.db.models import WgServerKeys

        server_key = db.query(WgServerKeys).filter_by(iface="antizapret").first()
        assert f"PublicKey = {server_key.public_key}" in conf

    def test_peer_not_found_raises(self, db):
        mgr = _make_manager()
        mgr.bootstrap(db)
        with pytest.raises(ValueError, match="not found"):
            mgr.get_client_conf(
                db, "nonexistent", flavor="wg", endpoint_host="vpn.example.com"
            )

    def test_contains_client_private_key_placeholder(self, db):
        """Client conf uses ${CLIENT_PRIVATE_KEY} placeholder for PrivateKey."""
        mgr = _make_manager()
        mgr.bootstrap(db)
        mgr.add_peer(db, "alice-1")
        conf = mgr.get_client_conf(
            db, "alice-1", flavor="wg", endpoint_host="vpn.example.com"
        )
        assert "PrivateKey = ${CLIENT_PRIVATE_KEY}" in conf


# ---------------------------------------------------------------------------
# generate_client_name (standalone function)
# ---------------------------------------------------------------------------

# ---------------------------------------------------------------------------
# get_client_conf — client_private_key and allowed_ips pass-through
# ---------------------------------------------------------------------------

def test_get_client_conf_with_private_key(db):
    from app.services.vpn_manager_new import VpnManager
    mgr = VpnManager()
    mgr.bootstrap(db)
    info = mgr.add_peer(db, "dave-1")
    conf = mgr.get_client_conf(db, "dave-1", "awg", "lb.example.com",
                                client_private_key=info["private_key"])
    assert info["private_key"] in conf
    assert "${CLIENT_PRIVATE_KEY}" not in conf


def test_get_antizapret_allowed_ips_missing(db):
    from app.services.vpn_manager_new import VpnManager
    mgr = VpnManager()
    assert mgr.get_antizapret_allowed_ips(db) is None


def test_get_antizapret_allowed_ips_present(db):
    from app.services.vpn_manager_new import VpnManager
    from app.services.wg_blob_store import WgBlobStore
    mgr = VpnManager()
    store = WgBlobStore(db)
    store.put("antizapret:allowed_ips", b"10.29.8.0/24, 1.2.3.0/24", by="test")
    result = mgr.get_antizapret_allowed_ips(db)
    assert "1.2.3.0/24" in result


def test_check_all_nodes_applied_no_nodes(db):
    from app.services.vpn_manager_new import VpnManager
    mgr = VpnManager()
    assert mgr.check_all_nodes_applied(db, "/etc/wireguard/antizapret.conf") is True


# ---------------------------------------------------------------------------
# generate_client_name (standalone function)
# ---------------------------------------------------------------------------

class TestGenerateClientName:
    def test_first_config(self):
        name = generate_client_name("alice", [])
        assert name == "alice-1"

    def test_increments(self):
        name = generate_client_name("alice", ["alice-1", "alice-2"])
        assert name == "alice-3"

    def test_email_strips_domain(self):
        name = generate_client_name("alice@example.com", [])
        assert name == "alice-1"

    def test_special_chars_replaced(self):
        name = generate_client_name("alice.bob", [])
        assert name == "alice_bob-1"

    def test_gap_not_reused(self):
        """generate_client_name always increments max, doesn't fill gaps."""
        name = generate_client_name("alice", ["alice-1", "alice-3"])
        assert name == "alice-4"
