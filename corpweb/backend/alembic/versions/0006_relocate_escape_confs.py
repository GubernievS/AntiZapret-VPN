"""relocate escape confs to /etc/amnezia/amneziawg/

Revision ID: 0006
Revises: 0005
"""
from alembic import op
from sqlalchemy.orm import Session


revision = "0006"
down_revision = "0005"
branch_labels = None
depends_on = None


def upgrade():
    from app.services.vpn_manager_new import relocate_escape_conf_paths
    db = Session(bind=op.get_bind())
    try:
        relocate_escape_conf_paths(db)
    finally:
        db.close()


def downgrade():
    # Reverse: move rows back to /etc/wireguard/
    from app.db.models import WgFileState
    db = Session(bind=op.get_bind())
    try:
        moves = [
            ("/etc/amnezia/amneziawg/antizapret_escape.conf",
             "/etc/wireguard/antizapret_escape.conf"),
            ("/etc/amnezia/amneziawg/vpn_escape.conf",
             "/etc/wireguard/vpn_escape.conf"),
        ]
        for old, new in moves:
            row = db.query(WgFileState).filter_by(path=old).one_or_none()
            if row and not db.query(WgFileState).filter_by(path=new).one_or_none():
                row.path = new
        db.commit()
    finally:
        db.close()
