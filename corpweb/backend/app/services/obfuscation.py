"""
Pure helpers for AmneziaWG obfuscation parameters.

Generation rules (per-iface, per-installation, manual-rotation-only):
- Jc: 3..10   (junk packets before handshake)
- Jmin/Jmax: 50..1000 (junk packet size range)
- S1/S2: 15..150 (junk prefix size in Init/Response)
- H1..H4: uint32 > 4, all distinct (custom magic bytes)
- I1: empty by default (optional initial blob)
"""
from __future__ import annotations

import secrets


def _urand_uint32_gt4(exclude: set[int]) -> int:
    """Return a uint32 in [5, 2^32-1] not present in *exclude*."""
    while True:
        # secrets.randbelow(n) returns an int in [0, n); adding 5 gives [5, n+4].
        # Upper bound 0xFFFFFFFE - 4 + 5 = 0xFFFFFFFF (uint32 max).
        n = secrets.randbelow(0xFFFFFFFE - 4) + 5
        if n not in exclude:
            return n


def generate_params() -> dict:
    """
    Generate a fresh set of AmneziaWG obfuscation parameters.

    Returns a dict with keys: jc, jmin, jmax, s1, s2, h1, h2, h3, h4, i1.
    H values are guaranteed distinct and >4 (WG reserves 1..4 as magic bytes).
    """
    hs: list[int] = []
    for _ in range(4):
        hs.append(_urand_uint32_gt4(set(hs)))
    return {
        "jc": secrets.randbelow(8) + 3,        # 3..10
        "jmin": 50,
        "jmax": 1000,
        "s1": secrets.randbelow(136) + 15,     # 15..150
        "s2": secrets.randbelow(136) + 15,
        "h1": hs[0],
        "h2": hs[1],
        "h3": hs[2],
        "h4": hs[3],
        "i1": "",
    }
