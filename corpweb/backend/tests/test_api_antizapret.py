"""
Tests for antizapret API endpoints that are not covered by test_antizapret_blob.py
(service-level tests). These are HTTP-level integration tests.
"""
from tests.conftest import auth_header


class TestObfuscationRegenerate:
    def test_regenerate_requires_admin(self, client, regular_user, user_token):
        resp = client.post(
            "/api/v1/antizapret/obfuscation/regenerate",
            headers=auth_header(user_token),
        )
        assert resp.status_code == 403

    def test_regenerate_admin_ok(self, client, db, admin_user, admin_token):
        # Bootstrap escape ifaces so rerender has something to re-render
        from app.services.vpn_manager_new import vpn_manager
        vpn_manager.bootstrap(db)

        from app.services.obfuscation_service import get_params
        before_az = get_params(db, "antizapret_escape")
        before_vpn = get_params(db, "vpn_escape")

        resp = client.post(
            "/api/v1/antizapret/obfuscation/regenerate",
            headers=auth_header(admin_token),
        )
        assert resp.status_code == 200
        assert resp.json()["status"] == "ok"

        # Params must have changed
        db.expire_all()
        after_az = get_params(db, "antizapret_escape")
        after_vpn = get_params(db, "vpn_escape")
        assert before_az != after_az
        assert before_vpn != after_vpn

    def test_regenerate_rerenders_escape_server_confs(
        self, client, db, admin_user, admin_token
    ):
        """After regenerate, the server confs for *_escape ifaces must
        contain the freshly-generated H1 value."""
        from app.services.vpn_manager_new import vpn_manager
        from app.services.wg_blob_store import WgBlobStore
        vpn_manager.bootstrap(db)

        resp = client.post(
            "/api/v1/antizapret/obfuscation/regenerate",
            headers=auth_header(admin_token),
        )
        assert resp.status_code == 200

        from app.services.obfuscation_service import get_params
        db.expire_all()
        store = WgBlobStore(db)
        for iface in ("antizapret_escape", "vpn_escape"):
            params = get_params(db, iface)
            blob = store.get(f"/etc/amnezia/amneziawg/{iface}.conf")
            assert blob is not None
            text = blob.decode()
            assert f"H1 = {params['h1']}" in text
            assert f"S1 = {params['s1']}" in text
