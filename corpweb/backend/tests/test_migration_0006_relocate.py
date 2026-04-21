"""Tests for the path-relocation logic used by alembic 0006."""
from sqlalchemy.orm import Session

from app.db.models import WgFileState


def _put(db, path, content=b"x"):
    import hashlib
    db.add(WgFileState(
        path=path, content=content,
        sha256=hashlib.sha256(content).hexdigest(),
        size_bytes=len(content),
        updated_by="test",
    ))
    db.commit()


def test_relocate_helper_moves_wireguard_paths_to_amneziawg_dir(db):
    from app.services.vpn_manager_new import relocate_escape_conf_paths

    _put(db, "/etc/wireguard/antizapret_escape.conf", b"az_escape")
    _put(db, "/etc/wireguard/vpn_escape.conf",        b"vpn_escape")
    _put(db, "/etc/wireguard/antizapret.conf",        b"az_base")  # must NOT move

    relocate_escape_conf_paths(db)

    paths = {row.path for row in db.query(WgFileState).all()}
    assert "/etc/amnezia/amneziawg/antizapret_escape.conf" in paths
    assert "/etc/amnezia/amneziawg/vpn_escape.conf" in paths
    assert "/etc/wireguard/antizapret_escape.conf" not in paths
    assert "/etc/wireguard/vpn_escape.conf" not in paths
    # base iface untouched
    assert "/etc/wireguard/antizapret.conf" in paths


def test_relocate_is_idempotent(db):
    from app.services.vpn_manager_new import relocate_escape_conf_paths

    _put(db, "/etc/amnezia/amneziawg/antizapret_escape.conf", b"az_escape")
    _put(db, "/etc/amnezia/amneziawg/vpn_escape.conf", b"vpn_escape")

    relocate_escape_conf_paths(db)
    relocate_escape_conf_paths(db)  # second call — must not error, no dupes

    paths = [row.path for row in db.query(WgFileState).all()]
    assert paths.count("/etc/amnezia/amneziawg/antizapret_escape.conf") == 1
    assert paths.count("/etc/amnezia/amneziawg/vpn_escape.conf") == 1
