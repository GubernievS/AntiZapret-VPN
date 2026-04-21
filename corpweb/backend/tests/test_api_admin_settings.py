"""
Tests for PATCH /api/v1/admin/settings — escape_enabled handling.

When admin toggles escape_enabled, the balancer must re-apply iptables
rules so the DNAT chain immediately reflects the new port set.
"""
from unittest.mock import patch

from tests.conftest import auth_header


class TestEscapeEnabledPatch:
    def test_patch_requires_admin(self, client, regular_user, user_token, system_settings):
        resp = client.patch(
            "/api/v1/admin/settings",
            json={"escape_enabled": True},
            headers=auth_header(user_token),
        )
        assert resp.status_code == 403

    def test_patch_escape_enabled_persists(
        self, client, db, admin_user, admin_token, system_settings
    ):
        """PATCH should update escape_enabled in DB, even without nodes."""
        with patch(
            "app.api.v1.admin.balancer.apply_rules", return_value={}
        ):
            resp = client.patch(
                "/api/v1/admin/settings",
                json={"escape_enabled": True},
                headers=auth_header(admin_token),
            )
        assert resp.status_code == 200
        assert resp.json()["escape_enabled"] is True

        from app.db.models import SystemSettings
        db.expire_all()
        s = db.query(SystemSettings).filter(SystemSettings.id == 1).first()
        assert s.escape_enabled is True

    def test_patch_escape_enabled_triggers_rebalance_with_escape_ports(
        self, client, db, admin_user, admin_token, system_settings
    ):
        """When escape_enabled flips, balancer.apply_rules must be called
        with escape_enabled=True so the DNAT chain gets ports 500/53443."""
        # Create one node so the balancer has work to do
        from app.db.models import Node
        node = Node(
            hostname="node1",
            private_ip="10.0.0.1",
            enroll_token="tok-1",
            health="ok",
        )
        db.add(node)
        # Set cp_ip so _detect_cp_ip works without running `ip` subprocess
        system_settings.cp_ip = "10.0.0.100"
        db.commit()

        with patch(
            "app.api.v1.admin.balancer.apply_rules", return_value={}
        ) as spy:
            resp = client.patch(
                "/api/v1/admin/settings",
                json={"escape_enabled": True},
                headers=auth_header(admin_token),
            )
        assert resp.status_code == 200
        spy.assert_called_once()
        kwargs = spy.call_args.kwargs
        args = spy.call_args.args
        # Accept either positional or kwarg for escape_enabled
        escape_kw = kwargs.get("escape_enabled")
        assert escape_kw is True, f"expected escape_enabled=True, got kwargs={kwargs}, args={args}"

    def test_patch_without_escape_change_does_not_call_balancer(
        self, client, db, admin_user, admin_token, system_settings
    ):
        """Toggling other fields should not trigger rebalance."""
        with patch(
            "app.api.v1.admin.balancer.apply_rules", return_value={}
        ) as spy:
            resp = client.patch(
                "/api/v1/admin/settings",
                json={"max_configs_per_user": 7},
                headers=auth_header(admin_token),
            )
        assert resp.status_code == 200
        assert resp.json()["max_configs_per_user"] == 7
        spy.assert_not_called()

    def test_get_settings_returns_escape_enabled(
        self, client, db, admin_user, admin_token, system_settings
    ):
        resp = client.get(
            "/api/v1/admin/settings",
            headers=auth_header(admin_token),
        )
        assert resp.status_code == 200
        assert resp.json()["escape_enabled"] is False
