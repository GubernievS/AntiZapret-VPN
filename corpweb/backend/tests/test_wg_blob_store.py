import hashlib
from datetime import datetime, timezone
from app.services.wg_blob_store import WgBlobStore

def test_get_missing_returns_none(db):
    store = WgBlobStore(db)
    assert store.get("/etc/wireguard/antizapret.conf") is None

def test_put_and_get_roundtrip(db):
    store = WgBlobStore(db)
    content = b"[Interface]\nListenPort = 51443\n"
    store.put("/etc/wireguard/antizapret.conf", content, by="test")
    result = store.get("/etc/wireguard/antizapret.conf")
    assert result == content

def test_put_updates_sha256(db):
    store = WgBlobStore(db)
    content = b"hello"
    store.put("/path/file.txt", content, by="test")
    paths = store.get_all_paths()
    expected_sha = hashlib.sha256(content).hexdigest()
    assert paths["/path/file.txt"] == expected_sha

def test_put_upserts(db):
    store = WgBlobStore(db)
    store.put("/path/x", b"v1", by="test")
    store.put("/path/x", b"v2", by="test")
    assert store.get("/path/x") == b"v2"

def test_get_all_paths_multiple(db):
    store = WgBlobStore(db)
    store.put("/a", b"aa", by="test")
    store.put("/b", b"bb", by="test")
    paths = store.get_all_paths()
    assert set(paths.keys()) == {"/a", "/b"}
