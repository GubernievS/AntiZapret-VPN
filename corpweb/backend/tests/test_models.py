"""
Tests for new DB models: WgObfuscationParams and SystemSettings.escape_enabled.
"""
from app.db.models import SystemSettings


def test_wg_obfuscation_params_roundtrip(db):
    from app.db.models import WgObfuscationParams
    row = WgObfuscationParams(
        iface="az_escape",
        jc=4, jmin=50, jmax=1000, s1=88, s2=136,
        h1=123456789, h2=987654321, h3=111222333, h4=444555666,
        i1="",
    )
    db.add(row)
    db.commit()
    fetched = db.query(WgObfuscationParams).filter_by(iface="az_escape").one()
    assert fetched.s1 == 88
    assert fetched.h1 == 123456789
    assert fetched.jmin == 50
    assert fetched.jmax == 1000
    assert fetched.i1 == ""


def test_system_settings_has_escape_enabled(db, system_settings):
    s = db.query(SystemSettings).filter_by(id=1).first()
    assert s is not None
    assert s.escape_enabled is False
