"""
Tests for AntizapretService backed by WgBlobStore (Task 4).
"""
from app.services.antizapret import AntizapretService, EDITABLE_FILES
from app.services.wg_blob_store import WgBlobStore


def test_get_file_from_blobstore(db):
    store = WgBlobStore(db)
    store.put("/root/antizapret/config/include-hosts.txt", b"example.com\n", by="test")
    svc = AntizapretService(db)
    assert svc.get_file_content("include_hosts") == "example.com\n"


def test_save_file_to_blobstore(db):
    svc = AntizapretService(db)
    svc.save_file_content("include_hosts", "new.example.com\n")
    store = WgBlobStore(db)
    assert store.get("/root/antizapret/config/include-hosts.txt") == b"new.example.com\n"


def test_get_settings_from_blobstore(db):
    store = WgBlobStore(db)
    store.put("/root/antizapret/setup", b"DISCORD_INCLUDE=y\nROUTE_ALL=n\n", by="test")
    svc = AntizapretService(db)
    settings = svc.get_settings()
    assert settings["DISCORD_INCLUDE"] == "y"
    assert settings["ROUTE_ALL"] == "n"


def test_update_settings_in_blobstore(db):
    store = WgBlobStore(db)
    store.put("/root/antizapret/setup", b"DISCORD_INCLUDE=y\nROUTE_ALL=n\n", by="test")
    svc = AntizapretService(db)
    assert svc.update_settings({"ROUTE_ALL": "y"}) == 1
    assert b"ROUTE_ALL=y" in store.get("/root/antizapret/setup")


def test_roundtrip_preserves_bytes(db):
    original = "# Comment\nexample.com\n\ntest.org\n"
    svc = AntizapretService(db)
    svc.save_file_content("include_hosts", original)
    assert svc.get_file_content("include_hosts") == original


# ── All 9 editable files ──

def test_all_editable_files_roundtrip(db):
    """Every file in EDITABLE_FILES can be saved and read back identically."""
    svc = AntizapretService(db)
    for key, path in EDITABLE_FILES.items():
        content = f"# Test for {key}\n192.168.1.0/24\nexample.com\n"
        svc.save_file_content(key, content)
        result = svc.get_file_content(key)
        assert result == content, f"Roundtrip failed for {key}"


def test_new_files_exist_in_editable(db):
    """Verify all 9 expected files are in EDITABLE_FILES."""
    expected = [
        "include_hosts", "exclude_hosts", "include_ips",
        "exclude_ips", "allow_ips", "forward_ips",
        "include_adblock_hosts", "exclude_adblock_hosts", "remove_hosts",
    ]
    for key in expected:
        assert key in EDITABLE_FILES, f"Missing: {key}"
    assert len(EDITABLE_FILES) == 9


# ── Numeric boolean settings (1/0) ──

def test_numeric_boolean_antizapret_dns(db):
    store = WgBlobStore(db)
    store.put("/root/antizapret/setup", b"ANTIZAPRET_DNS=1\nVPN_DNS=0\n", by="test")
    svc = AntizapretService(db)
    settings = svc.get_settings()
    assert settings["ANTIZAPRET_DNS"] == "1"
    assert settings["VPN_DNS"] == "0"


def test_update_numeric_boolean_saves_as_number(db):
    store = WgBlobStore(db)
    store.put("/root/antizapret/setup", b"ANTIZAPRET_DNS=1\nVPN_DNS=1\n", by="test")
    svc = AntizapretService(db)
    svc.update_settings({"ANTIZAPRET_DNS": "false", "VPN_DNS": "true"})
    blob = store.get("/root/antizapret/setup")
    assert b"ANTIZAPRET_DNS=0" in blob
    assert b"VPN_DNS=1" in blob


# ── New settings ──

def test_client_isolation_setting(db):
    store = WgBlobStore(db)
    store.put("/root/antizapret/setup", b"CLIENT_ISOLATION=y\n", by="test")
    svc = AntizapretService(db)
    assert svc.get_settings()["CLIENT_ISOLATION"] == "y"
    svc.update_settings({"CLIENT_ISOLATION": "n"})
    assert b"CLIENT_ISOLATION=n" in store.get("/root/antizapret/setup")


def test_wireguard_backup_setting(db):
    from app.services.wg_blob_store import WgBlobStore
    from app.services.antizapret import AntizapretService
    store = WgBlobStore(db)
    store.put("/root/antizapret/setup", b"WIREGUARD_BACKUP=n\n", by="test")
    svc = AntizapretService(db)
    assert svc.get_settings()["WIREGUARD_BACKUP"] == "n"
    svc.update_settings({"WIREGUARD_BACKUP": "y"})
    assert b"WIREGUARD_BACKUP=y" in store.get("/root/antizapret/setup")


def test_warp_outbound_string_setting(db):
    store = WgBlobStore(db)
    store.put("/root/antizapret/setup", b"WARP_OUTBOUND=\n", by="test")
    svc = AntizapretService(db)
    assert svc.get_settings()["WARP_OUTBOUND"] == ""
    svc.update_settings({"WARP_OUTBOUND": "wg-warp"})
    assert b"WARP_OUTBOUND=wg-warp" in store.get("/root/antizapret/setup")
