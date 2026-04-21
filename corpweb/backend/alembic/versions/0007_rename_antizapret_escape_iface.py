"""rename antizapret_escape iface to az_escape (IFNAMSIZ fix)

Revision ID: 0007
Revises: 0006
"""
from alembic import op
from sqlalchemy.orm import Session


revision = "0007"
down_revision = "0006"
branch_labels = None
depends_on = None


def upgrade():
    bind = op.get_bind()
    db = Session(bind=bind)
    try:
        from app.db.models import WgServerKeys, WgObfuscationParams, WgFileState

        # Rename in wg_server_keys
        row = db.query(WgServerKeys).filter_by(iface="antizapret_escape").one_or_none()
        if row is not None:
            existing = db.query(WgServerKeys).filter_by(iface="az_escape").one_or_none()
            if existing is None:
                row.iface = "az_escape"
            else:
                db.delete(row)

        # Rename in wg_obfuscation_params
        op_row = db.query(WgObfuscationParams).filter_by(iface="antizapret_escape").one_or_none()
        if op_row is not None:
            existing = db.query(WgObfuscationParams).filter_by(iface="az_escape").one_or_none()
            if existing is None:
                op_row.iface = "az_escape"
            else:
                db.delete(op_row)

        # Rename in wg_file_state — path key
        old_path = "/etc/amnezia/amneziawg/antizapret_escape.conf"
        new_path = "/etc/amnezia/amneziawg/az_escape.conf"
        fs_row = db.query(WgFileState).filter_by(path=old_path).one_or_none()
        if fs_row is not None:
            existing = db.query(WgFileState).filter_by(path=new_path).one_or_none()
            if existing is None:
                fs_row.path = new_path
            else:
                db.delete(fs_row)

        db.commit()
    finally:
        db.close()


def downgrade():
    bind = op.get_bind()
    db = Session(bind=bind)
    try:
        from app.db.models import WgServerKeys, WgObfuscationParams, WgFileState

        row = db.query(WgServerKeys).filter_by(iface="az_escape").one_or_none()
        if row is not None:
            existing = db.query(WgServerKeys).filter_by(iface="antizapret_escape").one_or_none()
            if existing is None:
                row.iface = "antizapret_escape"
            else:
                db.delete(row)

        op_row = db.query(WgObfuscationParams).filter_by(iface="az_escape").one_or_none()
        if op_row is not None:
            existing = db.query(WgObfuscationParams).filter_by(iface="antizapret_escape").one_or_none()
            if existing is None:
                op_row.iface = "antizapret_escape"
            else:
                db.delete(op_row)

        new_path = "/etc/amnezia/amneziawg/az_escape.conf"
        old_path = "/etc/amnezia/amneziawg/antizapret_escape.conf"
        fs_row = db.query(WgFileState).filter_by(path=new_path).one_or_none()
        if fs_row is not None:
            existing = db.query(WgFileState).filter_by(path=old_path).one_or_none()
            if existing is None:
                fs_row.path = old_path
            else:
                db.delete(fs_row)

        db.commit()
    finally:
        db.close()
