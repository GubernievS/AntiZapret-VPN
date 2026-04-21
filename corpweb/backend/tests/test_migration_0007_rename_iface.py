"""Tests for alembic 0007 — rename antizapret_escape iface to az_escape."""
import hashlib

from app.db.models import WgFileState, WgObfuscationParams, WgServerKeys


def _put_file(db, path, content=b"x"):
    db.add(WgFileState(
        path=path,
        content=content,
        sha256=hashlib.sha256(content).hexdigest(),
        size_bytes=len(content),
        updated_by="test",
    ))
    db.commit()


def _run_upgrade(db):
    """Execute the same body as alembic 0007 upgrade, inline (SQLite-friendly)."""
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


def test_upgrade_renames_server_keys(db):
    db.add(WgServerKeys(
        iface="antizapret_escape",
        private_key="priv",
        public_key="pub",
    ))
    db.commit()

    _run_upgrade(db)

    assert db.query(WgServerKeys).filter_by(iface="antizapret_escape").one_or_none() is None
    row = db.query(WgServerKeys).filter_by(iface="az_escape").one()
    assert row.private_key == "priv"
    assert row.public_key == "pub"


def test_upgrade_renames_obfuscation_params(db):
    db.add(WgObfuscationParams(
        iface="antizapret_escape",
        jc=4, jmin=50, jmax=1000, s1=88, s2=136,
        h1=1, h2=2, h3=3, h4=4, i1="",
    ))
    db.commit()

    _run_upgrade(db)

    assert db.query(WgObfuscationParams).filter_by(iface="antizapret_escape").one_or_none() is None
    row = db.query(WgObfuscationParams).filter_by(iface="az_escape").one()
    assert row.s1 == 88


def test_upgrade_renames_file_state_path(db):
    _put_file(db, "/etc/amnezia/amneziawg/antizapret_escape.conf", b"az_escape_body")

    _run_upgrade(db)

    paths = {r.path for r in db.query(WgFileState).all()}
    assert "/etc/amnezia/amneziawg/antizapret_escape.conf" not in paths
    assert "/etc/amnezia/amneziawg/az_escape.conf" in paths


def test_upgrade_noop_when_already_renamed(db):
    """Idempotent: running twice must not duplicate or error."""
    db.add(WgServerKeys(iface="az_escape", private_key="p", public_key="P"))
    _put_file(db, "/etc/amnezia/amneziawg/az_escape.conf", b"body")
    db.commit()

    _run_upgrade(db)
    _run_upgrade(db)  # must not error

    assert db.query(WgServerKeys).filter_by(iface="az_escape").count() == 1
    assert db.query(WgFileState)\
        .filter_by(path="/etc/amnezia/amneziawg/az_escape.conf").count() == 1


def test_upgrade_deletes_duplicate_when_target_exists(db):
    """If both old and new rows exist, old is deleted (not a merge)."""
    db.add(WgServerKeys(iface="antizapret_escape", private_key="OLD", public_key="OLD_PUB"))
    db.add(WgServerKeys(iface="az_escape", private_key="NEW", public_key="NEW_PUB"))
    db.commit()

    _run_upgrade(db)

    rows = db.query(WgServerKeys).filter(
        WgServerKeys.iface.in_(["antizapret_escape", "az_escape"])
    ).all()
    assert len(rows) == 1
    assert rows[0].iface == "az_escape"
    assert rows[0].private_key == "NEW"  # existing target wins
