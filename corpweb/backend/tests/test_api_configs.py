"""
HTTP-level tests for /api/v1/configs endpoints — bypass (escape mode)
and client-links surface.
"""
import pytest

from tests.conftest import auth_header


# ── Fixtures ──────────────────────────────────────────────────────────────────

@pytest.fixture
def config_id(client, db, admin_user, admin_token, system_settings):
    """
    Bootstrap ifaces, create one config via the API, return its UUID string.
    """
    from app.services.vpn_manager_new import vpn_manager
    vpn_manager.bootstrap(db)

    resp = client.post(
        "/api/v1/configs",
        headers=auth_header(admin_token),
        json={"config_type": "awg_vpn"},
    )
    assert resp.status_code == 201, resp.text
    return resp.json()["id"]


@pytest.fixture
def set_escape(db, system_settings):
    """Return a callable that sets SystemSettings.escape_enabled."""
    from app.db.models import SystemSettings

    def _set(value: bool) -> None:
        s = db.query(SystemSettings).filter(SystemSettings.id == 1).first()
        s.escape_enabled = value
        db.commit()

    return _set


# ── Download: bypass query param ──────────────────────────────────────────────

class TestDownloadBypass:
    def test_bypass_forbidden_when_escape_disabled(
        self, client, admin_token, config_id, set_escape
    ):
        set_escape(False)
        resp = client.get(
            f"/api/v1/configs/{config_id}/download?bypass=true",
            headers=auth_header(admin_token),
        )
        assert resp.status_code == 403
        assert "escape" in resp.json()["detail"].lower()

    def test_bypass_allowed_when_escape_enabled(
        self, client, admin_token, config_id, set_escape
    ):
        set_escape(True)
        resp = client.get(
            f"/api/v1/configs/{config_id}/download?bypass=true",
            headers=auth_header(admin_token),
        )
        assert resp.status_code == 200
        assert resp.headers["content-type"] == "application/zip"

    def test_bypass_and_backup_mutually_exclusive(
        self, client, admin_token, config_id, set_escape
    ):
        set_escape(True)
        resp = client.get(
            f"/api/v1/configs/{config_id}/download?bypass=true&backup=true",
            headers=auth_header(admin_token),
        )
        assert resp.status_code == 400
        assert "mutually exclusive" in resp.json()["detail"].lower()


class TestQrBypass:
    def test_bypass_forbidden_when_escape_disabled(
        self, client, admin_token, config_id, set_escape
    ):
        set_escape(False)
        resp = client.get(
            f"/api/v1/configs/{config_id}/qr?bypass=true",
            headers=auth_header(admin_token),
        )
        assert resp.status_code == 403

    def test_bypass_allowed_when_escape_enabled(
        self, client, admin_token, config_id, set_escape
    ):
        set_escape(True)
        resp = client.get(
            f"/api/v1/configs/{config_id}/qr?bypass=true",
            headers=auth_header(admin_token),
        )
        assert resp.status_code == 200
        assert resp.headers["content-type"].startswith("image/png")

    def test_bypass_and_backup_mutually_exclusive(
        self, client, admin_token, config_id, set_escape
    ):
        set_escape(True)
        resp = client.get(
            f"/api/v1/configs/{config_id}/qr?bypass=true&backup=true",
            headers=auth_header(admin_token),
        )
        assert resp.status_code == 400


# ── Client links: escape_enabled flag ─────────────────────────────────────────

class TestClientLinksEscapeFlag:
    def test_escape_enabled_true(self, client, user_token, set_escape):
        set_escape(True)
        resp = client.get(
            "/api/v1/configs/client-links",
            headers=auth_header(user_token),
        )
        assert resp.status_code == 200
        assert resp.json()["escape_enabled"] is True

    def test_escape_enabled_false(self, client, user_token, set_escape):
        set_escape(False)
        resp = client.get(
            "/api/v1/configs/client-links",
            headers=auth_header(user_token),
        )
        assert resp.status_code == 200
        assert resp.json()["escape_enabled"] is False
