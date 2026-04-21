"""
Tests for obfuscation params pure generator.
"""
from app.services.obfuscation import generate_params


def test_generate_returns_dict_with_all_keys():
    p = generate_params()
    assert set(p) == {"jc", "jmin", "jmax", "s1", "s2", "h1", "h2", "h3", "h4", "i1"}


def test_s_values_nonzero_and_in_range():
    p = generate_params()
    assert 15 <= p["s1"] <= 150
    assert 15 <= p["s2"] <= 150


def test_h_values_above_wg_reserved_and_unique():
    p = generate_params()
    hs = [p["h1"], p["h2"], p["h3"], p["h4"]]
    assert all(h > 4 for h in hs), "H must not collide with WG magic 1..4"
    assert len(set(hs)) == 4, "H values must be unique"
    assert all(h <= 0xFFFFFFFF for h in hs), "H is uint32"


def test_jc_in_recommended_range():
    p = generate_params()
    assert 3 <= p["jc"] <= 10


def test_two_calls_produce_different_params():
    assert generate_params() != generate_params()
