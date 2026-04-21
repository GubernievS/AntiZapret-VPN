"""
Tests for obfuscation_service — DB-backed obfuscation param lifecycle.

Covers ``ensure_initialized`` (idempotent), ``get_params``, and
``regenerate`` (admin-triggered rotation).
"""
from app.services.obfuscation_service import (
    ensure_initialized,
    get_params,
    regenerate,
)


def test_get_params_returns_none_when_missing(db):
    assert get_params(db, "antizapret_escape") is None


def test_ensure_initialized_creates_missing_rows(db):
    ensure_initialized(db, ifaces=["antizapret_escape", "vpn_escape"])
    a = get_params(db, "antizapret_escape")
    v = get_params(db, "vpn_escape")
    assert a is not None and v is not None
    # Independent random generation → h1 must differ between ifaces.
    assert a["h1"] != v["h1"]


def test_ensure_initialized_idempotent(db):
    ensure_initialized(db, ifaces=["vpn_escape"])
    before = get_params(db, "vpn_escape")
    ensure_initialized(db, ifaces=["vpn_escape"])
    after = get_params(db, "vpn_escape")
    assert before == after


def test_ensure_initialized_only_fills_missing(db):
    """Second call with extra iface must keep the first iface's values."""
    ensure_initialized(db, ifaces=["antizapret_escape"])
    az_before = get_params(db, "antizapret_escape")
    ensure_initialized(db, ifaces=["antizapret_escape", "vpn_escape"])
    az_after = get_params(db, "antizapret_escape")
    assert az_before == az_after
    assert get_params(db, "vpn_escape") is not None


def test_regenerate_overwrites_existing(db):
    ensure_initialized(db, ifaces=["vpn_escape"])
    before = get_params(db, "vpn_escape")
    regenerate(db, ifaces=["vpn_escape"])
    after = get_params(db, "vpn_escape")
    assert before != after


def test_regenerate_creates_row_if_missing(db):
    """Calling regenerate on a missing iface should create the row."""
    assert get_params(db, "antizapret_escape") is None
    regenerate(db, ifaces=["antizapret_escape"])
    assert get_params(db, "antizapret_escape") is not None


def test_get_params_returns_dict_with_all_keys(db):
    ensure_initialized(db, ifaces=["vpn_escape"])
    p = get_params(db, "vpn_escape")
    assert set(p) == {"jc", "jmin", "jmax", "s1", "s2", "h1", "h2", "h3", "h4", "i1"}
