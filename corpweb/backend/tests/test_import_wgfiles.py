"""
Tests for import-wgfiles admin endpoint.
"""
import io

from tests.conftest import auth_header


def test_import_antizapret_conf(client, db, admin_user, admin_token):
    content = b"[Interface]\nListenPort = 51443\n"
    resp = client.post(
        "/api/v1/admin/import-wgfiles",
        headers=auth_header(admin_token),
        files={"antizapret_conf": ("antizapret.conf", io.BytesIO(content), "text/plain")},
    )
    assert resp.status_code == 200
    data = resp.json()
    assert "antizapret.conf" in data["imported"]
    assert data["count"] >= 1


def test_import_both_confs(client, db, admin_user, admin_token):
    az = b"[Interface]\nListenPort = 51443\n"
    vpn = b"[Interface]\nListenPort = 51080\n"
    resp = client.post(
        "/api/v1/admin/import-wgfiles",
        headers=auth_header(admin_token),
        files={
            "antizapret_conf": ("antizapret.conf", io.BytesIO(az), "text/plain"),
            "vpn_conf": ("vpn.conf", io.BytesIO(vpn), "text/plain"),
        },
    )
    assert resp.status_code == 200
    assert resp.json()["count"] == 2


def test_import_requires_admin(client, db):
    resp = client.post(
        "/api/v1/admin/import-wgfiles",
        files={"antizapret_conf": ("a.conf", io.BytesIO(b"x"), "text/plain")},
    )
    assert resp.status_code == 401
