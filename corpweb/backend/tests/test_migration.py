"""
Tests for the one-time file→DB migration script (app/migrate.py).

All tests use a temp directory as the filesystem root so no real system
files are touched.  The `root` parameter passed to migrate functions acts
as a prefix for every absolute path the script would normally access.
"""
import os
import pytest

from app.db.models import WgFileState, WgServerKeys, VPNConfig, User
from app.services.wg_blob_store import WgBlobStore


# ---------------------------------------------------------------------------
# Helpers to build fake filesystem trees
# ---------------------------------------------------------------------------

def _write(path: str, content: str) -> None:
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w") as f:
        f.write(content)


def _build_fake_fs(root: str) -> dict:
    """
    Create the fake filesystem under *root*.

    Returns a dict of interesting values for assertions.
    """
    private_key = "yC5Y8Nf0EAZsSmZ16uvNpQ7mHT3nXA7KWyxkQBOVYUg="
    public_key  = "gJJVrPl8KazvYzf8Yp5UxgrYnDqYyjjdYO8rfqzl6nI="

    alice_privkey = "SLqNefHfHeFRkEm51kl4PlVEsKn20/+PmOsNOfIbcEU="
    alice_pubkey  = "y5NLYcmC3YgIQWQq33IIv5c/B6tOCRPGN30YRr7UQnA="

    allowed_ips = "10.29.8.0/21, 100.64.0.0/10"

    # /etc/wireguard/key
    _write(
        os.path.join(root, "etc/wireguard/key"),
        f"PRIVATE_KEY={private_key}\nPUBLIC_KEY={public_key}\n",
    )

    # antizapret server conf with one peer
    antizapret_conf = (
        "[Interface]\n"
        f"PrivateKey = {private_key}\n"
        "Address = 10.29.8.1/21\n"
        "ListenPort = 51443\n"
        "\n"
        "# Client = alice-1\n"
        f"# PrivateKey = {alice_privkey}\n"
        "[Peer]\n"
        f"PublicKey = {alice_pubkey}\n"
        "PresharedKey = AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=\n"
        "AllowedIPs = 10.29.8.2/32\n"
    )
    _write(os.path.join(root, "etc/wireguard/antizapret.conf"), antizapret_conf)

    # vpn server conf (no peers)
    _write(
        os.path.join(root, "etc/wireguard/vpn.conf"),
        "[Interface]\nPrivateKey = dummy\nAddress = 10.28.8.1/21\nListenPort = 51080\n",
    )

    # /root/antizapret/setup
    _write(os.path.join(root, "root/antizapret/setup"), "#!/bin/bash\necho setup\n")

    # Config files
    config_names = [
        "include-hosts.txt",
        "exclude-hosts.txt",
        "include-ips.txt",
        "exclude-ips.txt",
        "allow-ips.txt",
        "forward-ips.txt",
        "include-adblock-hosts.txt",
        "exclude-adblock-hosts.txt",
        "remove-hosts.txt",
    ]
    for name in config_names:
        _write(
            os.path.join(root, f"root/antizapret/config/{name}"),
            f"# {name} contents\n",
        )

    # Client antizapret conf with AllowedIPs
    client_conf = (
        "[Interface]\n"
        "PrivateKey = ${CLIENT_PRIVATE_KEY}\n"
        "Address = 10.29.8.2/32\n"
        "DNS = 10.29.8.1\n"
        "\n"
        "[Peer]\n"
        f"PublicKey = {public_key}\n"
        "PresharedKey = AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=\n"
        "Endpoint = vpn.example.com:51443\n"
        f"AllowedIPs = {allowed_ips}\n"
        "PersistentKeepalive = 15\n"
    )
    _write(
        os.path.join(root, "root/antizapret/client/amneziawg/antizapret/antizapret-alice-am.conf"),
        client_conf,
    )

    return {
        "private_key": private_key,
        "public_key": public_key,
        "alice_privkey": alice_privkey,
        "allowed_ips": allowed_ips,
        "config_names": config_names,
    }


# ---------------------------------------------------------------------------
# Tests: server conf and setup files → wg_file_state
# ---------------------------------------------------------------------------

class TestMigrateFileState:
    def test_antizapret_conf_stored(self, db, tmp_path):
        root = str(tmp_path)
        _build_fake_fs(root)

        from app import migrate
        migrate.run(db, root=root)

        store = WgBlobStore(db)
        blob = store.get("/etc/wireguard/antizapret.conf")
        assert blob is not None
        assert b"[Interface]" in blob

    def test_vpn_conf_stored(self, db, tmp_path):
        root = str(tmp_path)
        _build_fake_fs(root)

        from app import migrate
        migrate.run(db, root=root)

        store = WgBlobStore(db)
        blob = store.get("/etc/wireguard/vpn.conf")
        assert blob is not None
        assert b"[Interface]" in blob

    def test_setup_script_stored(self, db, tmp_path):
        root = str(tmp_path)
        _build_fake_fs(root)

        from app import migrate
        migrate.run(db, root=root)

        store = WgBlobStore(db)
        blob = store.get("/root/antizapret/setup")
        assert blob is not None
        assert b"echo setup" in blob

    def test_all_nine_config_files_stored(self, db, tmp_path):
        root = str(tmp_path)
        data = _build_fake_fs(root)

        from app import migrate
        migrate.run(db, root=root)

        store = WgBlobStore(db)
        for name in data["config_names"]:
            path = f"/root/antizapret/config/{name}"
            blob = store.get(path)
            assert blob is not None, f"Missing blob for {path}"
            assert name.encode() in blob

    def test_idempotent_double_run(self, db, tmp_path):
        root = str(tmp_path)
        _build_fake_fs(root)

        from app import migrate
        migrate.run(db, root=root)
        migrate.run(db, root=root)  # must not raise

        store = WgBlobStore(db)
        assert store.get("/etc/wireguard/antizapret.conf") is not None


# ---------------------------------------------------------------------------
# Tests: server keypair → wg_server_keys
# ---------------------------------------------------------------------------

class TestMigrateServerKeys:
    def test_antizapret_keys_stored(self, db, tmp_path):
        root = str(tmp_path)
        data = _build_fake_fs(root)

        from app import migrate
        migrate.run(db, root=root)

        row = db.get(WgServerKeys, "antizapret")
        assert row is not None
        assert row.private_key == data["private_key"]
        assert row.public_key == data["public_key"]

    def test_vpn_keys_stored(self, db, tmp_path):
        root = str(tmp_path)
        data = _build_fake_fs(root)

        from app import migrate
        migrate.run(db, root=root)

        row = db.get(WgServerKeys, "vpn")
        assert row is not None
        assert row.private_key == data["private_key"]
        assert row.public_key == data["public_key"]

    def test_both_ifaces_present(self, db, tmp_path):
        root = str(tmp_path)
        _build_fake_fs(root)

        from app import migrate
        migrate.run(db, root=root)

        ifaces = {row.iface for row in db.query(WgServerKeys).all()}
        assert ifaces == {"antizapret", "vpn"}

    def test_idempotent_keys(self, db, tmp_path):
        root = str(tmp_path)
        data = _build_fake_fs(root)

        from app import migrate
        migrate.run(db, root=root)
        migrate.run(db, root=root)

        row = db.get(WgServerKeys, "antizapret")
        assert row.private_key == data["private_key"]


# ---------------------------------------------------------------------------
# Tests: client private keys → vpn_configs.config_metadata
# ---------------------------------------------------------------------------

class TestMigrateClientPrivateKeys:
    def _make_user_and_config(self, db) -> VPNConfig:
        import uuid
        from datetime import datetime
        user = User(
            id=uuid.uuid4(),
            email="alice@test.com",
            username="alice",
            role="user",
            auth_provider="local",
            is_active=True,
            created_at=datetime.utcnow(),
            updated_at=datetime.utcnow(),
        )
        db.add(user)
        db.flush()

        config = VPNConfig(
            id=uuid.uuid4(),
            user_id=user.id,
            client_name="alice-1",
            config_type="awg_antizapret",
            config_metadata={},
            is_active=True,
            created_at=datetime.utcnow(),
            updated_at=datetime.utcnow(),
        )
        db.add(config)
        db.commit()
        return config

    def test_private_key_stored_in_metadata(self, db, tmp_path):
        root = str(tmp_path)
        data = _build_fake_fs(root)
        self._make_user_and_config(db)

        from app import migrate
        migrate.run(db, root=root)

        db.expire_all()
        config = db.query(VPNConfig).filter_by(client_name="alice-1").first()
        assert config is not None
        assert config.config_metadata is not None
        assert config.config_metadata.get("private_key") == data["alice_privkey"]

    def test_no_match_leaves_metadata_unchanged(self, db, tmp_path):
        import uuid
        from datetime import datetime
        root = str(tmp_path)
        _build_fake_fs(root)

        user = User(
            id=uuid.uuid4(),
            email="bob@test.com",
            username="bob",
            role="user",
            auth_provider="local",
            is_active=True,
            created_at=datetime.utcnow(),
            updated_at=datetime.utcnow(),
        )
        db.add(user)
        db.flush()

        config = VPNConfig(
            id=uuid.uuid4(),
            user_id=user.id,
            client_name="bob-1",
            config_type="awg_antizapret",
            config_metadata={"other_key": "value"},
            is_active=True,
            created_at=datetime.utcnow(),
            updated_at=datetime.utcnow(),
        )
        db.add(config)
        db.commit()

        from app import migrate
        migrate.run(db, root=root)

        db.expire_all()
        config = db.query(VPNConfig).filter_by(client_name="bob-1").first()
        # metadata should be unchanged (no match in server conf)
        assert "private_key" not in (config.config_metadata or {})


# ---------------------------------------------------------------------------
# Tests: AllowedIPs template → wg_file_state
# ---------------------------------------------------------------------------

class TestMigrateAllowedIPs:
    def test_allowed_ips_blob_stored(self, db, tmp_path):
        root = str(tmp_path)
        data = _build_fake_fs(root)

        from app import migrate
        migrate.run(db, root=root)

        store = WgBlobStore(db)
        blob = store.get("antizapret:allowed_ips")
        assert blob is not None
        assert data["allowed_ips"].encode() == blob

    def test_no_client_conf_skips_gracefully(self, db, tmp_path):
        """migrate.run must not fail if the client conf directory is absent."""
        root = str(tmp_path)
        _build_fake_fs(root)
        # Remove the client conf directory entirely
        import shutil
        shutil.rmtree(os.path.join(root, "root/antizapret/client"), ignore_errors=True)

        from app import migrate
        migrate.run(db, root=root)  # must not raise

        store = WgBlobStore(db)
        # blob absent is acceptable
        assert store.get("antizapret:allowed_ips") is None


# ---------------------------------------------------------------------------
# Unit tests: extract_client_private_keys (pure parsing)
# ---------------------------------------------------------------------------

class TestExtractClientPrivateKeys:
    def test_parses_single_peer(self):
        from app.migrate import extract_client_private_keys

        conf = (
            "# Client = alice-1\n"
            "# PrivateKey = SLqNefHfHeFRkEm51kl4PlVEsKn20/+PmOsNOfIbcEU=\n"
            "[Peer]\n"
            "PublicKey = y5NLYcmC3YgIQWQq33IIv5c/B6tOCRPGN30YRr7UQnA=\n"
        )
        result = extract_client_private_keys(conf)
        assert result == {"alice-1": "SLqNefHfHeFRkEm51kl4PlVEsKn20/+PmOsNOfIbcEU="}

    def test_parses_multiple_peers(self):
        from app.migrate import extract_client_private_keys

        conf = (
            "# Client = alice-1\n"
            "# PrivateKey = AAAA=\n"
            "[Peer]\n"
            "PublicKey = BBBB=\n"
            "\n"
            "# Client = bob-2\n"
            "# PrivateKey = CCCC=\n"
            "[Peer]\n"
            "PublicKey = DDDD=\n"
        )
        result = extract_client_private_keys(conf)
        assert result == {"alice-1": "AAAA=", "bob-2": "CCCC="}

    def test_peer_without_private_key_comment_excluded(self):
        from app.migrate import extract_client_private_keys

        conf = (
            "# Client = alice-1\n"
            "[Peer]\n"
            "PublicKey = BBBB=\n"
        )
        result = extract_client_private_keys(conf)
        assert result == {}

    def test_empty_conf(self):
        from app.migrate import extract_client_private_keys
        assert extract_client_private_keys("") == {}

    def test_no_peers(self):
        from app.migrate import extract_client_private_keys
        conf = "[Interface]\nPrivateKey = SERVER_KEY\nAddress = 10.0.0.1/24\n"
        assert extract_client_private_keys(conf) == {}
