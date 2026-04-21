"""
DB-backed lifecycle for AmneziaWG obfuscation parameters.

Thin wrapper over :mod:`app.services.obfuscation` (pure generator) and the
``WgObfuscationParams`` model. Exposes three operations:

* :func:`get_params` — fetch a stored set as dict, or ``None``.
* :func:`ensure_initialized` — idempotent; generates params only for
  ifaces that do not yet have a row (used in bootstrap / lifespan).
* :func:`regenerate` — admin-triggered rotation; overwrites existing
  rows (or creates them if missing).
"""
from __future__ import annotations

from sqlalchemy.orm import Session

from app.db.models import WgObfuscationParams
from app.services.obfuscation import generate_params


def _row_to_dict(row: WgObfuscationParams) -> dict:
    return {
        "jc": row.jc,
        "jmin": row.jmin,
        "jmax": row.jmax,
        "s1": row.s1,
        "s2": row.s2,
        "h1": row.h1,
        "h2": row.h2,
        "h3": row.h3,
        "h4": row.h4,
        "i1": row.i1,
    }


def get_params(db: Session, iface: str) -> dict | None:
    """Return stored params for *iface* as a dict, or ``None`` if missing."""
    row = db.get(WgObfuscationParams, iface)
    return _row_to_dict(row) if row else None


def ensure_initialized(db: Session, ifaces: list[str]) -> None:
    """
    Generate + store params for every iface missing a row.

    Idempotent: ifaces that already have a row are left untouched.
    """
    created = False
    for iface in ifaces:
        if db.get(WgObfuscationParams, iface) is None:
            params = generate_params()
            db.add(WgObfuscationParams(iface=iface, **params))
            created = True
    if created:
        db.commit()


def regenerate(db: Session, ifaces: list[str]) -> None:
    """
    Overwrite params for each iface (admin-triggered rotation).

    If a row is missing, create it. Always commits.
    """
    for iface in ifaces:
        row = db.get(WgObfuscationParams, iface)
        params = generate_params()
        if row is None:
            db.add(WgObfuscationParams(iface=iface, **params))
        else:
            for k, v in params.items():
                setattr(row, k, v)
    db.commit()
