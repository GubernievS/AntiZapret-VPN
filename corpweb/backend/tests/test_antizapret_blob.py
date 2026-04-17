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
