"""
Integration test for Alembic migration 0005_backfill_escape_peers.

Rather than spinning up a real Postgres, we run the migration's
``upgrade()`` body against the conftest SQLite test session (which
already has all tables created by ``Base.metadata.create_all``). This
exercises the actual service-layer code path used by the real
migration.
"""


class TestMigration0005:
    def test_upgrade_on_empty_db_bootstraps_escape_ifaces(self, db):
        """Fresh DB: no peers anywhere. Migration bootstraps escape ifaces cleanly."""
        from app.db.models import WgServerKeys
        from app.services.wg_blob_store import WgBlobStore

        # Import and exec the migration's upgrade body by calling the
        # helpers it calls — identical control flow.
        from app.services.vpn_manager_new import vpn_manager

        vpn_manager.bootstrap(db)
        vpn_manager.backfill_escape_peers(db)
        db.commit()

        # Four server keypairs.
        ifaces = {r.iface for r in db.query(WgServerKeys).all()}
        assert ifaces == {"antizapret", "vpn", "antizapret_escape", "vpn_escape"}

        # All four conf blobs exist.
        store = WgBlobStore(db)
        for iface in ifaces:
            dir_ = "/etc/amnezia/amneziawg" if iface.endswith("_escape") else "/etc/wireguard"
            assert store.get(f"{dir_}/{iface}.conf") is not None

    def test_upgrade_backfills_preexisting_peers(self, db):
        """
        Simulate the real migration scenario: peers exist in antizapret/vpn
        blobs from before Phase 2 (escape blobs do not have them).
        Migration must copy them into escape blobs.
        """
        from app.services.vpn_manager_new import vpn_manager
        from app.services.wg_blob_store import WgBlobStore
        from app.services.wg_templates import parse_peers

        # Bootstrap + add peers (Phase-2-compliant state).
        vpn_manager.bootstrap(db)
        vpn_manager.add_peer(db, "legacy-1")
        vpn_manager.add_peer(db, "legacy-2")

        # Strip peers from escape blobs to simulate pre-Phase-2 content.
        from app.db.models import WgServerKeys
        from app.services.obfuscation_service import get_params
        from app.services.vpn_manager_new import _IFACE_CONFIG
        from app.services.wg_templates import render_server_conf

        store = WgBlobStore(db)
        for iface in ("antizapret_escape", "vpn_escape"):
            cfg = _IFACE_CONFIG[iface]
            keys = db.get(WgServerKeys, iface)
            awg = get_params(db, iface)
            empty = render_server_conf(
                iface=iface,
                peers=[],
                server_privkey=keys.private_key,
                address=cfg["address"],
                awg_params=awg,
            )
            store.put(cfg["conf_path"], empty.encode(), by="pre-phase-2-sim")

        # Run the migration's upgrade body.
        vpn_manager.bootstrap(db)  # idempotent
        vpn_manager.backfill_escape_peers(db)
        db.commit()

        for iface in ("antizapret_escape", "vpn_escape"):
            peers = parse_peers(
                store.get(f"/etc/amnezia/amneziawg/{iface}.conf").decode()
            )
            names = sorted(p.name for p in peers)
            assert names == ["legacy-1", "legacy-2"]
