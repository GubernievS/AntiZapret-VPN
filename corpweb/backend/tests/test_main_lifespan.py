"""
Tests for FastAPI lifespan startup initialization.

Lifespan must call ``vpn_manager.bootstrap(db)`` before
``ensure_ports_reconciled(db)`` so that escape-iface keypairs, obfuscation
params and server .conf blobs exist before the balancer tries to DNAT to
them.

Both calls are wrapped in try/except in main.py so a failure in bootstrap
must not prevent ``ensure_ports_reconciled`` from running (self-heal
semantics from the WireGuard-backup-ports feature).
"""
from unittest.mock import patch

from fastapi.testclient import TestClient

from app.main import app


class TestLifespanBootstrap:
    def test_bootstrap_called_on_startup(self, db):
        """TestClient context-manager entry triggers the lifespan; verify bootstrap ran."""
        with patch(
            "app.services.vpn_manager_new.vpn_manager.bootstrap"
        ) as m_bootstrap, patch(
            "app.services.balancer.ensure_ports_reconciled"
        ):
            with TestClient(app):
                pass
            assert m_bootstrap.called, "lifespan must call vpn_manager.bootstrap"

    def test_bootstrap_called_before_reconcile(self, db):
        """Bootstrap must run before ensure_ports_reconciled so DNAT targets exist."""
        call_order: list[str] = []

        def _boot(_db):
            call_order.append("bootstrap")

        def _reconcile(_db):
            call_order.append("reconcile")

        with patch(
            "app.services.vpn_manager_new.vpn_manager.bootstrap",
            side_effect=_boot,
        ), patch(
            "app.services.balancer.ensure_ports_reconciled",
            side_effect=_reconcile,
        ):
            with TestClient(app):
                pass

        assert call_order == ["bootstrap", "reconcile"], (
            f"expected bootstrap before reconcile, got {call_order}"
        )

    def test_bootstrap_failure_does_not_block_reconcile(self, db):
        """Bootstrap wrapped in its own try/except — reconcile still runs."""
        called: dict[str, bool] = {"reconcile": False}

        def _reconcile(_db):
            called["reconcile"] = True

        with patch(
            "app.services.vpn_manager_new.vpn_manager.bootstrap",
            side_effect=RuntimeError("boom"),
        ), patch(
            "app.services.balancer.ensure_ports_reconciled",
            side_effect=_reconcile,
        ):
            with TestClient(app):
                pass

        assert called["reconcile"], (
            "ensure_ports_reconciled must still run when bootstrap raises"
        )
