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


def _conf_path_for(iface: str) -> str:
    """Mirror _IFACE_CONFIG[iface]["conf_path"] without importing the dict."""
    if iface.endswith("_escape"):
        return f"/etc/amnezia/amneziawg/{iface}.conf"
    return f"/etc/wireguard/{iface}.conf"


# ---------------------------------------------------------------------------
# bootstrap
# ---------------------------------------------------------------------------

class TestBootstrap:
    def test_creates_four_keypairs(self, db):
        mgr = _make_manager()
        mgr.bootstrap(db)

        from app.db.models import WgServerKeys

        keys = db.query(WgServerKeys).all()
        ifaces = {k.iface for k in keys}
        assert ifaces == {"antizapret", "vpn", "az_escape", "vpn_escape"}

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
        for iface in ("antizapret", "vpn", "az_escape", "vpn_escape"):
            blob = store.get(_conf_path_for(iface))
            assert blob is not None, f"missing conf blob for {iface}"
            assert b"[Interface]" in blob

    def test_iface_config_has_escape_entries(self):
        from app.services.vpn_manager_new import _IFACE_CONFIG
        assert "az_escape" in _IFACE_CONFIG
        assert "vpn_escape" in _IFACE_CONFIG
        assert _IFACE_CONFIG["az_escape"]["subnet"] == "10.27.8.0/21"
        assert _IFACE_CONFIG["vpn_escape"]["subnet"] == "10.26.8.0/21"

    def test_bootstrap_writes_awg_params_into_escape_server_confs(self, db):
        """Escape server confs must contain obfuscation fields (Jc/S1/H1)."""
        mgr = _make_manager()
        mgr.bootstrap(db)

        from app.services.wg_blob_store import WgBlobStore

        store = WgBlobStore(db)
        for iface in ("az_escape", "vpn_escape"):
            content = store.get(_conf_path_for(iface)).decode()
            assert "Jc = " in content, f"{iface} missing Jc"
            assert "S1 = " in content, f"{iface} missing S1"
            assert "H1 = " in content, f"{iface} missing H1"

    def test_bootstrap_base_ifaces_have_no_awg_params(self, db):
        """Base ifaces must not get obfuscation fields in their server conf."""
        mgr = _make_manager()
        mgr.bootstrap(db)

        from app.services.wg_blob_store import WgBlobStore

        store = WgBlobStore(db)
        for iface in ("antizapret", "vpn"):
            content = store.get(f"/etc/wireguard/{iface}.conf").decode()
            # Match the exact "Field = " pattern at line-start — substrings like
            # "Jc" can appear inside random base64 keys otherwise.
            for line in content.splitlines():
                assert not line.startswith("Jc = "), f"{iface} has Jc line"
                assert not line.startswith("S1 = "), f"{iface} has S1 line"
                assert not line.startswith("H1 = "), f"{iface} has H1 line"


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

    def test_peer_written_to_all_four_ifaces(self, db):
        """Peer must land in every iface's server conf, including escape ifaces."""
        from app.services.wg_blob_store import WgBlobStore
        from app.services.wg_templates import parse_peers

        mgr = _make_manager()
        mgr.bootstrap(db)
        mgr.add_peer(db, "alice-1")

        store = WgBlobStore(db)
        for iface in ("antizapret", "vpn", "az_escape", "vpn_escape"):
            blob = store.get(_conf_path_for(iface))
            names = [p.name for p in parse_peers(blob.decode())]
            assert "alice-1" in names, f"alice-1 missing in {iface}"

    def test_peer_shares_host_part_across_all_four_ifaces(self, db):
        """IPs in all 4 ifaces share the last two octets (parallel subnets)."""
        from app.services.wg_blob_store import WgBlobStore
        from app.services.wg_templates import parse_peers

        mgr = _make_manager()
        mgr.bootstrap(db)
        mgr.add_peer(db, "bob-1")

        store = WgBlobStore(db)
        ips: dict[str, str] = {}
        for iface in ("antizapret", "vpn", "az_escape", "vpn_escape"):
            peers = parse_peers(
                store.get(_conf_path_for(iface)).decode()
            )
            ips[iface] = next(p.allowed_ips.split("/")[0]
                              for p in peers if p.name == "bob-1")

        host_parts = {ip.split(".", 2)[-1] for ip in ips.values()}
        assert len(host_parts) == 1, f"host parts differ: {ips}"

        # Subnet prefixes must match the design (10.29, 10.28, 10.27, 10.26).
        assert ips["antizapret"].startswith("10.29.")
        assert ips["vpn"].startswith("10.28.")
        assert ips["az_escape"].startswith("10.27.")
        assert ips["vpn_escape"].startswith("10.26.")

    def test_escape_server_confs_keep_awg_params_after_add_peer(self, db):
        """Re-rendering escape server confs with peers must preserve awg fields."""
        from app.services.wg_blob_store import WgBlobStore

        mgr = _make_manager()
        mgr.bootstrap(db)
        mgr.add_peer(db, "carol-1")

        store = WgBlobStore(db)
        for iface in ("az_escape", "vpn_escape"):
            content = store.get(_conf_path_for(iface)).decode()
            assert "Jc = " in content
            assert "S1 = " in content
            assert "H1 = " in content

    def test_base_server_confs_have_no_awg_params_after_add_peer(self, db):
        """Base ifaces must still not pick up any obfuscation fields."""
        from app.services.wg_blob_store import WgBlobStore

        mgr = _make_manager()
        mgr.bootstrap(db)
        mgr.add_peer(db, "carol-1")

        store = WgBlobStore(db)
        for iface in ("antizapret", "vpn"):
            content = store.get(f"/etc/wireguard/{iface}.conf").decode()
            # Use line-start match to avoid false positives from random base64
            # substrings inside PublicKey / PresharedKey.
            for line in content.splitlines():
                assert not line.startswith("Jc = "), f"{iface}: {line!r}"
                assert not line.startswith("S1 = "), f"{iface}: {line!r}"
                assert not line.startswith("H1 = "), f"{iface}: {line!r}"


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


def test_add_peer_uses_correct_subnet_per_iface(db):
    """
    VPN peer must use 10.28.x.x subnet, antizapret peer must use 10.29.x.x,
    with the SAME host part (last 2 octets). This was a bug: both ifaces
    used the same IP, causing VPN client Address to be in wrong subnet.
    """
    from app.services.vpn_manager_new import VpnManager
    from app.services.wg_blob_store import WgBlobStore
    from app.services.wg_templates import parse_peers

    mgr = VpnManager()
    mgr.bootstrap(db)
    mgr.add_peer(db, "alice-1")

    store = WgBlobStore(db)
    az_peers = parse_peers(store.get("/etc/wireguard/antizapret.conf").decode())
    vpn_peers = parse_peers(store.get("/etc/wireguard/vpn.conf").decode())

    az_peer = next(p for p in az_peers if p.name == "alice-1")
    vpn_peer = next(p for p in vpn_peers if p.name == "alice-1")

    az_ip = az_peer.allowed_ips.split("/")[0]
    vpn_ip = vpn_peer.allowed_ips.split("/")[0]

    # AZ subnet 10.29.x.x, VPN subnet 10.28.x.x
    assert az_ip.startswith("10.29."), f"AZ IP should be 10.29.x, got {az_ip}"
    assert vpn_ip.startswith("10.28."), f"VPN IP should be 10.28.x, got {vpn_ip}"

    # Same host part (last 2 octets)
    assert az_ip.split(".")[2:] == vpn_ip.split(".")[2:], \
        f"Host parts differ: {az_ip} vs {vpn_ip}"


# ---------------------------------------------------------------------------
# generate_client_name (standalone function)
# ---------------------------------------------------------------------------

def test_get_client_conf_bypass_uses_escape_iface_and_params(db):
    from app.services.vpn_manager_new import VpnManager
    mgr = VpnManager()
    mgr.bootstrap(db)
    mgr.add_peer(db, "carol-1")
    conf = mgr.get_client_conf(
        db, "carol-1", flavor="awg",
        endpoint_host="cp.example.com", iface="vpn",
        bypass=True, client_private_key="PRV",
    )
    # vpn_escape uses port 500
    assert "Endpoint = cp.example.com:500" in conf
    # awg_params injected (not the hardcoded H1 = 1 / S1 = 0)
    assert "S1 = " in conf
    assert "H1 = " in conf
    assert "S1 = 0" not in conf
    assert "H1 = 1\n" not in conf
    # AllowedIPs for vpn_escape = full VPN
    assert "AllowedIPs = 0.0.0.0/0" in conf


def test_get_client_conf_bypass_antizapret_uses_escape_port_53443(db):
    from app.services.vpn_manager_new import VpnManager
    mgr = VpnManager()
    mgr.bootstrap(db)
    mgr.add_peer(db, "carol-1")
    conf = mgr.get_client_conf(
        db, "carol-1", flavor="awg",
        endpoint_host="cp.example.com", iface="antizapret",
        bypass=True, client_private_key="PRV",
    )
    assert "Endpoint = cp.example.com:53443" in conf
    assert "S1 = " in conf


def test_get_client_conf_bypass_forbidden_with_backup(db):
    import pytest as _pytest
    from app.services.vpn_manager_new import VpnManager
    mgr = VpnManager()
    mgr.bootstrap(db)
    mgr.add_peer(db, "dave-1")
    with _pytest.raises(ValueError, match="bypass.*backup"):
        mgr.get_client_conf(
            db, "dave-1", flavor="awg",
            endpoint_host="cp", iface="vpn",
            bypass=True, use_backup_port=True,
            client_private_key="PRV",
        )


def test_get_client_conf_bypass_false_behaves_as_before(db):
    """Default bypass=False must keep the legacy behaviour intact."""
    from app.services.vpn_manager_new import VpnManager
    mgr = VpnManager()
    mgr.bootstrap(db)
    mgr.add_peer(db, "eve-1")
    conf = mgr.get_client_conf(
        db, "eve-1", flavor="awg",
        endpoint_host="cp.example.com", iface="antizapret",
    )
    # Base antizapret awg port
    assert ":52443" in conf
    # Legacy hardcoded obfuscation (S1 = 0)
    assert "S1 = 0" in conf


def test_get_client_conf_backup_port(db):
    from app.services.vpn_manager_new import VpnManager
    mgr = VpnManager()
    mgr.bootstrap(db)
    info = mgr.add_peer(db, "backup-test")
    conf = mgr.get_client_conf(
        db, "backup-test", "awg", "host.test",
        client_private_key=info["private_key"],
        use_backup_port=True,
    )
    assert ":540" in conf
    assert ":52443" not in conf


def test_iface_config_escape_paths_moved_to_amneziawg_dir():
    from app.services.vpn_manager_new import _IFACE_CONFIG
    assert _IFACE_CONFIG["az_escape"]["conf_path"] == \
        "/etc/amnezia/amneziawg/az_escape.conf"
    assert _IFACE_CONFIG["vpn_escape"]["conf_path"] == \
        "/etc/amnezia/amneziawg/vpn_escape.conf"


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


# ---------------------------------------------------------------------------
# backfill_escape_peers
# ---------------------------------------------------------------------------

class TestBackfillEscapePeers:
    """
    Data-migration helper: ensures peers present in base ifaces
    (antizapret / vpn) also appear in escape ifaces with parallel
    host-parts in 10.27.x.x and 10.26.x.x subnets.

    Meaningful for deployments that added peers BEFORE Phase 2 (when
    add_peer started writing to all four ifaces). Idempotent: safe to
    run multiple times.
    """

    def _reset_escape_blobs_to_empty_server_conf(self, db):
        """Simulate pre-Phase-2 state: escape .conf blobs exist but have no peers."""
        from app.db.models import WgServerKeys
        from app.services.obfuscation_service import get_params
        from app.services.vpn_manager_new import _IFACE_CONFIG
        from app.services.wg_blob_store import WgBlobStore
        from app.services.wg_templates import render_server_conf

        store = WgBlobStore(db)
        for iface in ("az_escape", "vpn_escape"):
            cfg = _IFACE_CONFIG[iface]
            keys = db.get(WgServerKeys, iface)
            awg = get_params(db, iface)
            conf = render_server_conf(
                iface=iface,
                peers=[],
                server_privkey=keys.private_key,
                address=cfg["address"],
                awg_params=awg,
            )
            store.put(cfg["conf_path"], conf.encode(), by="test-reset")

    def test_backfill_restores_peers_to_both_escape_ifaces(self, db):
        from app.services.vpn_manager_new import vpn_manager
        from app.services.wg_blob_store import WgBlobStore
        from app.services.wg_templates import parse_peers

        vpn_manager.bootstrap(db)
        vpn_manager.add_peer(db, "alice-1")
        vpn_manager.add_peer(db, "bob-1")

        # Simulate a pre-Phase-2 deployment: escape blobs empty.
        self._reset_escape_blobs_to_empty_server_conf(db)

        store = WgBlobStore(db)
        for iface in ("az_escape", "vpn_escape"):
            peers = parse_peers(
                store.get(f"/etc/amnezia/amneziawg/{iface}.conf").decode()
            )
            assert peers == [], f"setup: {iface} should be empty"

        # Run backfill.
        vpn_manager.backfill_escape_peers(db)

        for iface in ("az_escape", "vpn_escape"):
            peers = parse_peers(
                store.get(f"/etc/amnezia/amneziawg/{iface}.conf").decode()
            )
            names = sorted(p.name for p in peers)
            assert names == ["alice-1", "bob-1"], (
                f"{iface}: expected both peers restored, got {names}"
            )

    def test_backfill_uses_escape_subnets_with_parallel_host_parts(self, db):
        from app.services.vpn_manager_new import vpn_manager
        from app.services.wg_blob_store import WgBlobStore
        from app.services.wg_templates import parse_peers

        vpn_manager.bootstrap(db)
        vpn_manager.add_peer(db, "carol-1")

        # Capture host part from antizapret BEFORE we wipe escape blobs.
        store = WgBlobStore(db)
        az_peers = parse_peers(
            store.get("/etc/wireguard/antizapret.conf").decode()
        )
        az_ip = next(p.allowed_ips for p in az_peers if p.name == "carol-1")
        host_part = az_ip.split("/", 1)[0].split(".", 2)[-1]  # "x.y"

        self._reset_escape_blobs_to_empty_server_conf(db)
        vpn_manager.backfill_escape_peers(db)

        # Verify subnet prefixes + shared host-part.
        az_escape_peers = parse_peers(
            store.get("/etc/amnezia/amneziawg/az_escape.conf").decode()
        )
        vpn_escape_peers = parse_peers(
            store.get("/etc/amnezia/amneziawg/vpn_escape.conf").decode()
        )
        az_esc_ip = next(
            p.allowed_ips for p in az_escape_peers if p.name == "carol-1"
        ).split("/", 1)[0]
        vpn_esc_ip = next(
            p.allowed_ips for p in vpn_escape_peers if p.name == "carol-1"
        ).split("/", 1)[0]

        assert az_esc_ip == f"10.27.{host_part}"
        assert vpn_esc_ip == f"10.26.{host_part}"

    def test_backfill_preserves_public_and_preshared_keys(self, db):
        from app.services.vpn_manager_new import vpn_manager
        from app.services.wg_blob_store import WgBlobStore
        from app.services.wg_templates import parse_peers

        vpn_manager.bootstrap(db)
        vpn_manager.add_peer(db, "dave-1")

        store = WgBlobStore(db)
        az_peer = next(
            p for p in parse_peers(
                store.get("/etc/wireguard/antizapret.conf").decode()
            ) if p.name == "dave-1"
        )

        self._reset_escape_blobs_to_empty_server_conf(db)
        vpn_manager.backfill_escape_peers(db)

        for iface in ("az_escape", "vpn_escape"):
            peer = next(
                p for p in parse_peers(
                    store.get(f"/etc/amnezia/amneziawg/{iface}.conf").decode()
                ) if p.name == "dave-1"
            )
            assert peer.public_key == az_peer.public_key
            assert peer.preshared_key == az_peer.preshared_key

    def test_backfill_idempotent(self, db):
        """Running backfill twice must not duplicate peers."""
        from app.services.vpn_manager_new import vpn_manager
        from app.services.wg_blob_store import WgBlobStore
        from app.services.wg_templates import parse_peers

        vpn_manager.bootstrap(db)
        vpn_manager.add_peer(db, "eve-1")
        vpn_manager.add_peer(db, "frank-1")
        self._reset_escape_blobs_to_empty_server_conf(db)

        vpn_manager.backfill_escape_peers(db)
        vpn_manager.backfill_escape_peers(db)

        store = WgBlobStore(db)
        for iface in ("az_escape", "vpn_escape"):
            peers = parse_peers(
                store.get(f"/etc/amnezia/amneziawg/{iface}.conf").decode()
            )
            names = sorted(p.name for p in peers)
            assert names == ["eve-1", "frank-1"], (
                f"{iface}: expected no duplicates, got {names}"
            )

    def test_backfill_skips_peers_already_present(self, db):
        """Peers already in escape conf must not be re-added or mutated."""
        from app.services.vpn_manager_new import vpn_manager
        from app.services.wg_blob_store import WgBlobStore
        from app.services.wg_templates import parse_peers

        vpn_manager.bootstrap(db)
        vpn_manager.add_peer(db, "gina-1")

        # Partially-rolled-out: the peer is already in az_escape
        # (no-op expected), but we pretend vpn_escape was wiped.
        from app.db.models import WgServerKeys
        from app.services.obfuscation_service import get_params
        from app.services.vpn_manager_new import _IFACE_CONFIG
        from app.services.wg_templates import render_server_conf

        store = WgBlobStore(db)
        cfg = _IFACE_CONFIG["vpn_escape"]
        keys = db.get(WgServerKeys, "vpn_escape")
        awg = get_params(db, "vpn_escape")
        store.put(
            cfg["conf_path"],
            render_server_conf(
                iface="vpn_escape",
                peers=[],
                server_privkey=keys.private_key,
                address=cfg["address"],
                awg_params=awg,
            ).encode(),
            by="test-reset",
        )

        az_esc_peer_before = next(
            p for p in parse_peers(
                store.get("/etc/amnezia/amneziawg/az_escape.conf").decode()
            ) if p.name == "gina-1"
        )

        vpn_manager.backfill_escape_peers(db)

        az_esc_peer_after = next(
            p for p in parse_peers(
                store.get("/etc/amnezia/amneziawg/az_escape.conf").decode()
            ) if p.name == "gina-1"
        )
        assert az_esc_peer_before == az_esc_peer_after, (
            "already-present peer must not be mutated"
        )

        # And the wiped vpn_escape got the peer back.
        vpn_esc_peers = parse_peers(
            store.get("/etc/amnezia/amneziawg/vpn_escape.conf").decode()
        )
        assert [p.name for p in vpn_esc_peers] == ["gina-1"]


# ---------------------------------------------------------------------------
# Regression: delete_peer on escape ifaces preserves AWG [Interface] block
# ---------------------------------------------------------------------------

class TestDeletePeerEscapeRegression:
    """delete_peer on escape ifaces must not strip the [Interface] AWG block."""

    def test_delete_peer_preserves_awg_block_in_vpn_escape(self, db):
        from app.services.vpn_manager_new import vpn_manager
        from app.services.wg_blob_store import WgBlobStore

        vpn_manager.bootstrap(db)
        vpn_manager.add_peer(db, "erin")

        store = WgBlobStore(db)
        before = store.get("/etc/amnezia/amneziawg/vpn_escape.conf").decode()
        # sanity: peer is there
        assert "# Client = erin" in before
        # sanity: AWG fields present in Interface section
        for key in ("Jc", "Jmin", "Jmax", "S1", "S2", "H1", "H2", "H3", "H4"):
            assert f"{key} = " in before, f"AWG field {key} missing before delete"

        vpn_manager.delete_peer(db, "erin")

        after = store.get("/etc/amnezia/amneziawg/vpn_escape.conf").decode()
        assert "# Client = erin" not in after
        for key in ("Jc", "Jmin", "Jmax", "S1", "S2", "H1", "H2", "H3", "H4"):
            assert f"{key} = " in after, f"AWG field {key} lost after delete"

    def test_delete_peer_removes_from_all_four_ifaces(self, db):
        from app.services.vpn_manager_new import vpn_manager
        from app.services.wg_blob_store import WgBlobStore

        vpn_manager.bootstrap(db)
        vpn_manager.add_peer(db, "frank")
        vpn_manager.delete_peer(db, "frank")

        store = WgBlobStore(db)
        for path in (
            "/etc/wireguard/antizapret.conf",
            "/etc/wireguard/vpn.conf",
            "/etc/amnezia/amneziawg/az_escape.conf",
            "/etc/amnezia/amneziawg/vpn_escape.conf",
        ):
            blob = store.get(path)
            assert blob is not None, f"{path} missing"
            assert "# Client = frank" not in blob.decode(), \
                f"peer still present in {path}"


# ---------------------------------------------------------------------------
# Regression: disable/enable on escape ifaces — keys reverse, AWG block intact
# ---------------------------------------------------------------------------

class TestTogglePeerEscapeRegression:
    """Disable/enable must reverse [Peer] keys across all four ifaces without
    touching the AWG [Interface] block of escape ifaces."""

    def test_disable_reverses_keys_in_all_four_ifaces(self, db):
        from app.services.vpn_manager_new import vpn_manager
        from app.services.wg_blob_store import WgBlobStore
        from app.services.wg_templates import parse_peers

        vpn_manager.bootstrap(db)
        vpn_manager.add_peer(db, "george")

        store = WgBlobStore(db)
        paths = [
            "/etc/wireguard/antizapret.conf",
            "/etc/wireguard/vpn.conf",
            "/etc/amnezia/amneziawg/az_escape.conf",
            "/etc/amnezia/amneziawg/vpn_escape.conf",
        ]
        before = {}
        for p in paths:
            peers = parse_peers(store.get(p).decode())
            mine = next(pr for pr in peers if pr.name == "george")
            before[p] = (mine.public_key, mine.preshared_key)

        vpn_manager.disable_peer(db, "george")

        for p in paths:
            peers = parse_peers(store.get(p).decode())
            mine = next(pr for pr in peers if pr.name == "george")
            assert mine.public_key != before[p][0], f"pubkey not reversed in {p}"
            assert mine.preshared_key != before[p][1], f"psk not reversed in {p}"

    def test_disable_preserves_awg_block_in_escape_confs(self, db):
        from app.services.vpn_manager_new import vpn_manager
        from app.services.wg_blob_store import WgBlobStore

        vpn_manager.bootstrap(db)
        vpn_manager.add_peer(db, "helen")

        awg_keys = ("Jc", "Jmin", "Jmax", "S1", "S2", "H1", "H2", "H3", "H4")
        store = WgBlobStore(db)
        for path in (
            "/etc/amnezia/amneziawg/az_escape.conf",
            "/etc/amnezia/amneziawg/vpn_escape.conf",
        ):
            before = store.get(path).decode()
            awg_before = [
                ln for ln in before.splitlines()
                if any(ln.strip().startswith(f"{k} = ") for k in awg_keys)
            ]

            vpn_manager.disable_peer(db, "helen")

            after = store.get(path).decode()
            awg_after = [
                ln for ln in after.splitlines()
                if any(ln.strip().startswith(f"{k} = ") for k in awg_keys)
            ]

            assert awg_before == awg_after, (
                f"AWG fields mutated in {path}\nbefore: {awg_before}\nafter: {awg_after}"
            )

            vpn_manager.enable_peer(db, "helen")  # reset state for next iter

    def test_enable_is_self_inverse_of_disable(self, db):
        from app.services.vpn_manager_new import vpn_manager
        from app.services.wg_blob_store import WgBlobStore
        from app.services.wg_templates import parse_peers

        vpn_manager.bootstrap(db)
        vpn_manager.add_peer(db, "ivan")

        store = WgBlobStore(db)
        path = "/etc/amnezia/amneziawg/vpn_escape.conf"
        peers = parse_peers(store.get(path).decode())
        orig = next(p for p in peers if p.name == "ivan")
        orig_pub, orig_psk = orig.public_key, orig.preshared_key

        vpn_manager.disable_peer(db, "ivan")
        vpn_manager.enable_peer(db, "ivan")

        peers = parse_peers(store.get(path).decode())
        after = next(p for p in peers if p.name == "ivan")
        assert after.public_key == orig_pub
        assert after.preshared_key == orig_psk
