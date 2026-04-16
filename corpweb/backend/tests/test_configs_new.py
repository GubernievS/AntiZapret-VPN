"""
Tests for config endpoints wired to vpn_manager_new (DB-backed).
"""
from tests.conftest import auth_header
from app.services.vpn_manager_new import VpnManager


def test_create_config_writes_to_db(client, db, admin_user, admin_token, system_settings):
    mgr = VpnManager()
    mgr.bootstrap(db)

    resp = client.post(
        "/api/v1/configs",
        headers=auth_header(admin_token),
        json={"config_type": "awg_antizapret"},
    )
    assert resp.status_code == 201
    data = resp.json()
    assert data["client_name"].startswith("admin-")

    from app.services.wg_blob_store import WgBlobStore
    store = WgBlobStore(db)
    content = store.get("/etc/wireguard/antizapret.conf")
    assert content is not None
    assert b"admin-" in content


def test_create_config_stores_private_key(client, db, admin_user, admin_token, system_settings):
    mgr = VpnManager()
    mgr.bootstrap(db)

    resp = client.post(
        "/api/v1/configs",
        headers=auth_header(admin_token),
        json={"config_type": "awg_antizapret"},
    )
    assert resp.status_code == 201

    from app.db.models import VPNConfig
    config = db.query(VPNConfig).filter(VPNConfig.client_name == resp.json()["client_name"]).first()
    assert config.config_metadata is not None
    assert "private_key" in config.config_metadata
    assert len(config.config_metadata["private_key"]) > 20


def test_delete_config_removes_from_blob(client, db, admin_user, admin_token, system_settings):
    mgr = VpnManager()
    mgr.bootstrap(db)

    resp = client.post(
        "/api/v1/configs",
        headers=auth_header(admin_token),
        json={"config_type": "awg_antizapret"},
    )
    config_id = resp.json()["id"]
    client_name = resp.json()["client_name"]

    resp = client.delete(
        f"/api/v1/configs/{config_id}",
        headers=auth_header(admin_token),
    )
    assert resp.status_code == 204

    from app.services.wg_blob_store import WgBlobStore
    store = WgBlobStore(db)
    content = store.get("/etc/wireguard/antizapret.conf")
    assert client_name.encode() not in content
