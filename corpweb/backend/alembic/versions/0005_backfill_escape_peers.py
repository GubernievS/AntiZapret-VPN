"""backfill escape peers

Revision ID: 0005
Revises: 0004
Create Date: 2026-04-21

Data migration: for deployments that existed before Phase 2 of the
AWG-escape epic (when ``add_peer`` started writing to all four ifaces),
peers only exist in antizapret.conf / vpn.conf. This migration copies
them into the two escape ifaces with parallel host-parts in the
10.27.x.x / 10.26.x.x subnets.

Idempotent: peers already present in an escape conf are skipped. Safe
to re-run on freshly deployed systems where every peer was already
added via the Phase-2 add_peer.
"""
from alembic import op
from sqlalchemy.orm import Session


revision = "0005"
down_revision = "0004"
branch_labels = None
depends_on = None


def upgrade() -> None:
    # Use the migration's connection as a SQLAlchemy Session so we can
    # call service-layer helpers that rely on ORM mappings.
    bind = op.get_bind()
    db = Session(bind=bind)
    try:
        # Import inside the function: avoids import-time side effects
        # (model registration, config validation) during Alembic's
        # env-setup phase.
        from app.services.vpn_manager_new import vpn_manager

        # bootstrap() is idempotent and guarantees escape keypairs +
        # obfuscation params + empty conf blobs exist before we try to
        # append peers into them. Fresh installs hit only this branch.
        vpn_manager.bootstrap(db)
        vpn_manager.backfill_escape_peers(db)
        db.commit()
    finally:
        db.close()


def downgrade() -> None:
    # No-op: we do not delete peers on downgrade. If you truly need to
    # roll back, drop the escape .conf blobs from wg_file_state manually.
    pass
