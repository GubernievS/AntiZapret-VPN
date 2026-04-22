# Escape-rules via `custom-up.sh` hook — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make `az_escape` (10.27.x) and `vpn_escape` (10.26.x) tunnels functional end-to-end by injecting iptables rules via upstream's `custom-up.sh` / `custom-down.sh` hooks, managed by the sync-agent.

**Architecture:** Agent owns a marker-bracketed block inside `/root/antizapret/custom-up.sh` and `/root/antizapret/custom-down.sh`. Upstream `up.sh`/`down.sh` already call these hooks at their tail, so our rules apply after every `antizapret.service` start without touching upstream code. Agent syncs the files on startup and on every heartbeat; when drift is detected, it rewrites them and restarts `antizapret.service`.

**Tech Stack:** Python 3.11+ (agent), pytest, shell scripts (generated), iptables/AmneziaWG (runtime, not touched here).

**Spec:** [docs/superpowers/specs/2026-04-22-escape-rules-custom-up-sh-design.md](../specs/2026-04-22-escape-rules-custom-up-sh-design.md)
**Bead:** `CorpAdmin-AZ-6za` (P1, bug)

---

## File Structure

| File | Role |
|---|---|
| `agent/corpweb_sync_agent.py` | +module-level constants (markers, rule-file paths) +pure functions `render_custom_up_sh`, `render_custom_down_sh`, `parse_setup_env`, `validate_setup_env` +idempotent FS helper `sync_custom_script` +orchestrator `sync_escape_rules` +hook in `register_if_needed` and heartbeat loop +heartbeat metrics. |
| `agent/tests/test_escape_rules.py` | **NEW.** L1/L2 unit tests for all pure functions + sync_custom_script. |
| `agent/tests/test_sync_agent.py` | +L3 integration tests: orchestrator wiring, one-restart-per-cycle, heartbeat payload carries drift metrics. |

Backend, frontend, alembic, install scripts, systemd units: **untouched**.

---

## Conventions

- Python code must pass existing test-suite AND new tests: `cd corpweb/backend && .venv/bin/python -m pytest ../../agent/tests/ -q` (existing agent tests: 26 — must stay green).
- Run single test with: `.venv/bin/python -m pytest ../../agent/tests/test_escape_rules.py::TestRenderCustomUpSh::test_name -v`
- Every task ends with a commit. Commit messages are in English, imperative mood, `feat:` / `test:` / `fix:` prefixes.
- No backend/frontend changes in any task.
- Never add comments that merely explain what the code already says — only add comment when WHY is non-obvious.

---

## Task 1: Module constants + skeleton for render_custom_up_sh

**Files:**
- Modify: `agent/corpweb_sync_agent.py` — after the `MANAGED_FILES` block (around line 90)
- Create: `agent/tests/test_escape_rules.py`

- [ ] **Step 1: Write failing test for module constants**

Create `agent/tests/test_escape_rules.py`:

```python
"""Unit tests for escape-rules script generation and validation."""
from __future__ import annotations

import pathlib
import sys

import pytest

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent.parent))

import corpweb_sync_agent as agent  # noqa: E402


class TestConstants:
    def test_marker_begin_is_a_bash_comment(self):
        assert agent.ESCAPE_MARKER_BEGIN.startswith("#")
        assert "CorpAdmin" in agent.ESCAPE_MARKER_BEGIN

    def test_marker_end_is_a_bash_comment(self):
        assert agent.ESCAPE_MARKER_END.startswith("#")
        assert "CorpAdmin" in agent.ESCAPE_MARKER_END

    def test_custom_up_path_is_under_antizapret(self):
        assert agent.CUSTOM_UP_PATH == "/root/antizapret/custom-up.sh"

    def test_custom_down_path_is_under_antizapret(self):
        assert agent.CUSTOM_DOWN_PATH == "/root/antizapret/custom-down.sh"

    def test_antizapret_setup_path(self):
        assert agent.ANTIZAPRET_SETUP_PATH == "/root/antizapret/setup"
```

- [ ] **Step 2: Verify test fails**

```
cd corpweb/backend && .venv/bin/python -m pytest ../../agent/tests/test_escape_rules.py::TestConstants -v
```

Expected: FAIL with `AttributeError: module 'corpweb_sync_agent' has no attribute 'ESCAPE_MARKER_BEGIN'`

- [ ] **Step 3: Add constants to agent**

In `agent/corpweb_sync_agent.py`, after the `MANAGED_FILES` / `MANAGED_PATHS` block (around line 92), add:

```python
# ---------------------------------------------------------------------------
# Escape-rules extension (via upstream custom-up.sh / custom-down.sh hooks)
# ---------------------------------------------------------------------------

ESCAPE_MARKER_BEGIN = "# === BEGIN CorpAdmin escape rules (managed by corpweb-sync-agent) ==="
ESCAPE_MARKER_END = "# === END CorpAdmin escape rules ==="

CUSTOM_UP_PATH = "/root/antizapret/custom-up.sh"
CUSTOM_DOWN_PATH = "/root/antizapret/custom-down.sh"
ANTIZAPRET_SETUP_PATH = "/root/antizapret/setup"
```

- [ ] **Step 4: Verify test passes**

```
cd corpweb/backend && .venv/bin/python -m pytest ../../agent/tests/test_escape_rules.py::TestConstants -v
```

Expected: 5 passed.

- [ ] **Step 5: Commit**

```
git add agent/corpweb_sync_agent.py agent/tests/test_escape_rules.py
git commit -m "feat(agent): escape-rules module constants + test scaffold"
```

---

## Task 2: render_custom_up_sh — markers + shell preamble

**Files:**
- Modify: `agent/corpweb_sync_agent.py`
- Modify: `agent/tests/test_escape_rules.py`

- [ ] **Step 1: Add failing tests for preamble**

Append to `agent/tests/test_escape_rules.py`:

```python
class TestRenderCustomUpSh:
    def test_begin_marker_present(self):
        out = agent.render_custom_up_sh()
        assert agent.ESCAPE_MARKER_BEGIN in out

    def test_end_marker_present(self):
        out = agent.render_custom_up_sh()
        assert agent.ESCAPE_MARKER_END in out

    def test_begin_appears_before_end(self):
        out = agent.render_custom_up_sh()
        assert out.index(agent.ESCAPE_MARKER_BEGIN) < out.index(agent.ESCAPE_MARKER_END)

    def test_sources_setup(self):
        out = agent.render_custom_up_sh()
        assert "source setup" in out

    def test_cd_into_antizapret(self):
        out = agent.render_custom_up_sh()
        assert "cd /root/antizapret" in out

    def test_has_set_e(self):
        out = agent.render_custom_up_sh()
        assert "set -e" in out

    def test_idempotent(self):
        a = agent.render_custom_up_sh()
        b = agent.render_custom_up_sh()
        assert a == b
```

- [ ] **Step 2: Verify tests fail**

```
cd corpweb/backend && .venv/bin/python -m pytest ../../agent/tests/test_escape_rules.py::TestRenderCustomUpSh -v
```

Expected: all 7 FAIL with `AttributeError: ... has no attribute 'render_custom_up_sh'`.

- [ ] **Step 3: Minimal implementation**

In `agent/corpweb_sync_agent.py`, directly after the constants block from Task 1, add:

```python
def render_custom_up_sh() -> str:
    """
    Return the content to write between the markers in /root/antizapret/custom-up.sh.
    The returned string includes the markers themselves and is safe to drop into
    an empty file or between existing markers.

    The script itself defers conditional logic (RESTRICT_FORWARD, VPN_DNS,
    MASQUERADE vs SNAT) to bash at runtime, so this function takes no args
    and always returns the same content.
    """
    lines = [
        ESCAPE_MARKER_BEGIN,
        "set -e",
        "cd /root/antizapret",
        "source setup",
        ESCAPE_MARKER_END,
    ]
    return "\n".join(lines) + "\n"
```

- [ ] **Step 4: Verify tests pass**

```
cd corpweb/backend && .venv/bin/python -m pytest ../../agent/tests/test_escape_rules.py::TestRenderCustomUpSh -v
```

Expected: 7 passed.

- [ ] **Step 5: Commit**

```
git add agent/corpweb_sync_agent.py agent/tests/test_escape_rules.py
git commit -m "feat(agent): render_custom_up_sh — markers + shell preamble"
```

---

## Task 3: render_custom_up_sh — IP/FAKE_IP + OUT_IFACE derivation (mirror up.sh)

**Files:**
- Modify: `agent/corpweb_sync_agent.py`
- Modify: `agent/tests/test_escape_rules.py`

- [ ] **Step 1: Add failing tests**

Append to `TestRenderCustomUpSh` class:

```python
    def test_derives_ip_from_alternative_client_ip(self):
        out = agent.render_custom_up_sh()
        # mirror up.sh line 38
        assert '[[ "$ALTERNATIVE_CLIENT_IP" == \'y\' ]] && IP="${CLIENT_IP:-172}" || IP=10' in out

    def test_derives_fake_ip(self):
        out = agent.render_custom_up_sh()
        # mirror up.sh line 39
        assert 'FAKE_IP="${FAKE_IP:-198.18}"' in out
        assert 'FAKE_IP="$IP.30"' in out

    def test_resolves_default_interface_if_missing(self):
        out = agent.render_custom_up_sh()
        assert 'ip route get 1.2.3.4' in out
        assert 'DEFAULT_INTERFACE=' in out

    def test_resolves_antizapret_out_iface_defaults(self):
        out = agent.render_custom_up_sh()
        assert 'ANTIZAPRET_OUT_INTERFACE="${ANTIZAPRET_OUT_INTERFACE:-$DEFAULT_INTERFACE}"' in out
        assert 'ANTIZAPRET_OUT_IP="${ANTIZAPRET_OUT_IP:-$DEFAULT_IP}"' in out

    def test_resolves_vpn_out_iface_defaults(self):
        out = agent.render_custom_up_sh()
        assert 'VPN_OUT_INTERFACE="${VPN_OUT_INTERFACE:-$DEFAULT_INTERFACE}"' in out
        assert 'VPN_OUT_IP="${VPN_OUT_IP:-$DEFAULT_IP}"' in out
```

- [ ] **Step 2: Verify tests fail**

```
cd corpweb/backend && .venv/bin/python -m pytest ../../agent/tests/test_escape_rules.py::TestRenderCustomUpSh -v
```

Expected: 5 new tests FAIL, previous 7 still pass.

- [ ] **Step 3: Extend implementation**

Replace the body of `render_custom_up_sh` with:

```python
def render_custom_up_sh() -> str:
    """
    Return content for /root/antizapret/custom-up.sh (with markers, shell
    preamble, and IP/OUT-iface derivation). Defers all conditional logic
    (RESTRICT_FORWARD, VPN_DNS, MASQUERADE vs SNAT) to bash at runtime.
    """
    body = """\
set -e
cd /root/antizapret
source setup

[[ "$ALTERNATIVE_CLIENT_IP" == 'y' ]] && IP="${CLIENT_IP:-172}" || IP=10
[[ "$ALTERNATIVE_FAKE_IP" == 'y' ]] && FAKE_IP="${FAKE_IP:-198.18}" || FAKE_IP="$IP.30"

if [[ -z "$DEFAULT_INTERFACE" ]]; then
    DEFAULT_INTERFACE="$(ip route get 1.2.3.4 2>/dev/null | grep -oP 'dev \\K\\S+')"
    DEFAULT_IP="$(ip route get 1.2.3.4 2>/dev/null | grep -oP 'src \\K\\S+')"
fi
ANTIZAPRET_OUT_INTERFACE="${ANTIZAPRET_OUT_INTERFACE:-$DEFAULT_INTERFACE}"
ANTIZAPRET_OUT_IP="${ANTIZAPRET_OUT_IP:-$DEFAULT_IP}"
VPN_OUT_INTERFACE="${VPN_OUT_INTERFACE:-$DEFAULT_INTERFACE}"
VPN_OUT_IP="${VPN_OUT_IP:-$DEFAULT_IP}"
"""
    return ESCAPE_MARKER_BEGIN + "\n" + body + ESCAPE_MARKER_END + "\n"
```

- [ ] **Step 4: Verify tests pass**

```
cd corpweb/backend && .venv/bin/python -m pytest ../../agent/tests/test_escape_rules.py::TestRenderCustomUpSh -v
```

Expected: 12 passed.

- [ ] **Step 5: Commit**

```
git add agent/corpweb_sync_agent.py agent/tests/test_escape_rules.py
git commit -m "feat(agent): render_custom_up_sh — IP/OUT_IFACE derivation block"
```

---

## Task 4: render_custom_up_sh — az_escape DNS + MAPPING + POSTROUTING

**Files:**
- Modify: `agent/corpweb_sync_agent.py`
- Modify: `agent/tests/test_escape_rules.py`

- [ ] **Step 1: Add failing tests**

Append to `TestRenderCustomUpSh`:

```python
    def test_az_escape_dns_dnat_udp(self):
        out = agent.render_custom_up_sh()
        assert 'iptables -w -t nat -A PREROUTING -s 10.27.0.0/16 -p udp --dport 53 -j DNAT --to-destination 127.0.0.1' in out

    def test_az_escape_dns_dnat_tcp(self):
        out = agent.render_custom_up_sh()
        assert 'iptables -w -t nat -A PREROUTING -s 10.27.0.0/16 -p tcp --dport 53 -j DNAT --to-destination 127.0.0.1' in out

    def test_az_escape_fake_ip_mapping(self):
        out = agent.render_custom_up_sh()
        assert 'iptables -w -t nat -A PREROUTING -s 10.27.0.0/16 -d "$FAKE_IP.0.0/15" -j ANTIZAPRET-MAPPING' in out

    def test_az_escape_restrict_forward_block_is_conditional(self):
        out = agent.render_custom_up_sh()
        assert 'if [[ "$RESTRICT_FORWARD" == \'y\' ]]; then' in out
        assert 'iptables -w -t nat -A PREROUTING -s 10.27.0.0/16 ! -d "$FAKE_IP.0.0/15" -j CONNMARK --set-mark 0x1' in out
        assert 'iptables -w -I FORWARD 2 -s 10.27.0.0/16 -m connmark --mark 0x1 -m set ! --match-set antizapret-forward dst -j DROP' in out

    def test_az_escape_postrouting_masquerade_branch(self):
        out = agent.render_custom_up_sh()
        assert 'if [[ -z "$ANTIZAPRET_OUT_IP" ]]; then' in out
        assert 'iptables -w -t nat -A POSTROUTING -s 10.27.0.0/16 -o "$ANTIZAPRET_OUT_INTERFACE" -j MASQUERADE' in out

    def test_az_escape_postrouting_snat_branch(self):
        out = agent.render_custom_up_sh()
        assert 'iptables -w -t nat -A POSTROUTING -s 10.27.0.0/16 -o "$ANTIZAPRET_OUT_INTERFACE" -j SNAT --to-source "$ANTIZAPRET_OUT_IP"' in out
```

- [ ] **Step 2: Verify tests fail**

```
cd corpweb/backend && .venv/bin/python -m pytest ../../agent/tests/test_escape_rules.py::TestRenderCustomUpSh -v
```

Expected: 6 new tests FAIL.

- [ ] **Step 3: Extend implementation**

Replace the `body` multi-line string inside `render_custom_up_sh` by appending (between the OUT-iface block and the closing `"""`):

```python
def render_custom_up_sh() -> str:
    body = """\
set -e
cd /root/antizapret
source setup

[[ "$ALTERNATIVE_CLIENT_IP" == 'y' ]] && IP="${CLIENT_IP:-172}" || IP=10
[[ "$ALTERNATIVE_FAKE_IP" == 'y' ]] && FAKE_IP="${FAKE_IP:-198.18}" || FAKE_IP="$IP.30"

if [[ -z "$DEFAULT_INTERFACE" ]]; then
    DEFAULT_INTERFACE="$(ip route get 1.2.3.4 2>/dev/null | grep -oP 'dev \\K\\S+')"
    DEFAULT_IP="$(ip route get 1.2.3.4 2>/dev/null | grep -oP 'src \\K\\S+')"
fi
ANTIZAPRET_OUT_INTERFACE="${ANTIZAPRET_OUT_INTERFACE:-$DEFAULT_INTERFACE}"
ANTIZAPRET_OUT_IP="${ANTIZAPRET_OUT_IP:-$DEFAULT_IP}"
VPN_OUT_INTERFACE="${VPN_OUT_INTERFACE:-$DEFAULT_INTERFACE}"
VPN_OUT_IP="${VPN_OUT_IP:-$DEFAULT_IP}"

# az_escape (10.27) — mirror antizapret (10.29) split-tunnel semantics
iptables -w -t nat -A PREROUTING -s 10.27.0.0/16 -p udp --dport 53 -j DNAT --to-destination 127.0.0.1
iptables -w -t nat -A PREROUTING -s 10.27.0.0/16 -p tcp --dport 53 -j DNAT --to-destination 127.0.0.1
iptables -w -t nat -A PREROUTING -s 10.27.0.0/16 -d "$FAKE_IP.0.0/15" -j ANTIZAPRET-MAPPING
if [[ "$RESTRICT_FORWARD" == 'y' ]]; then
    iptables -w -t nat -A PREROUTING -s 10.27.0.0/16 ! -d "$FAKE_IP.0.0/15" -j CONNMARK --set-mark 0x1
    iptables -w -I FORWARD 2 -s 10.27.0.0/16 -m connmark --mark 0x1 -m set ! --match-set antizapret-forward dst -j DROP
fi
if [[ -z "$ANTIZAPRET_OUT_IP" ]]; then
    iptables -w -t nat -A POSTROUTING -s 10.27.0.0/16 -o "$ANTIZAPRET_OUT_INTERFACE" -j MASQUERADE
else
    iptables -w -t nat -A POSTROUTING -s 10.27.0.0/16 -o "$ANTIZAPRET_OUT_INTERFACE" -j SNAT --to-source "$ANTIZAPRET_OUT_IP"
fi
"""
    return ESCAPE_MARKER_BEGIN + "\n" + body + ESCAPE_MARKER_END + "\n"
```

- [ ] **Step 4: Verify tests pass**

```
cd corpweb/backend && .venv/bin/python -m pytest ../../agent/tests/test_escape_rules.py::TestRenderCustomUpSh -v
```

Expected: 18 passed.

- [ ] **Step 5: Commit**

```
git add agent/corpweb_sync_agent.py agent/tests/test_escape_rules.py
git commit -m "feat(agent): render_custom_up_sh — az_escape (10.27) rules"
```

---

## Task 5: render_custom_up_sh — vpn_escape DNS + POSTROUTING

**Files:**
- Modify: `agent/corpweb_sync_agent.py`
- Modify: `agent/tests/test_escape_rules.py`

- [ ] **Step 1: Add failing tests**

Append to `TestRenderCustomUpSh`:

```python
    def test_vpn_escape_dns_dnat_is_conditional_on_vpn_dns(self):
        out = agent.render_custom_up_sh()
        assert 'if [[ "$VPN_DNS" == \'1\' ]]; then' in out
        assert 'iptables -w -t nat -A PREROUTING -s 10.26.0.0/16 -p udp --dport 53 -j DNAT --to-destination 127.0.0.2' in out
        assert 'iptables -w -t nat -A PREROUTING -s 10.26.0.0/16 -p tcp --dport 53 -j DNAT --to-destination 127.0.0.2' in out

    def test_vpn_escape_postrouting_masquerade_branch(self):
        out = agent.render_custom_up_sh()
        assert 'if [[ -z "$VPN_OUT_IP" ]]; then' in out
        assert 'iptables -w -t nat -A POSTROUTING -s 10.26.0.0/16 -o "$VPN_OUT_INTERFACE" -j MASQUERADE' in out

    def test_vpn_escape_postrouting_snat_branch(self):
        out = agent.render_custom_up_sh()
        assert 'iptables -w -t nat -A POSTROUTING -s 10.26.0.0/16 -o "$VPN_OUT_INTERFACE" -j SNAT --to-source "$VPN_OUT_IP"' in out
```

- [ ] **Step 2: Verify tests fail**

```
cd corpweb/backend && .venv/bin/python -m pytest ../../agent/tests/test_escape_rules.py::TestRenderCustomUpSh -v
```

Expected: 3 new tests FAIL.

- [ ] **Step 3: Extend implementation**

Inside the `body` string of `render_custom_up_sh`, append (before the closing `"""`):

```python
# vpn_escape (10.26) — mirror vpn (10.28) full-VPN semantics
if [[ "$VPN_DNS" == '1' ]]; then
    iptables -w -t nat -A PREROUTING -s 10.26.0.0/16 -p udp --dport 53 -j DNAT --to-destination 127.0.0.2
    iptables -w -t nat -A PREROUTING -s 10.26.0.0/16 -p tcp --dport 53 -j DNAT --to-destination 127.0.0.2
fi
if [[ -z "$VPN_OUT_IP" ]]; then
    iptables -w -t nat -A POSTROUTING -s 10.26.0.0/16 -o "$VPN_OUT_INTERFACE" -j MASQUERADE
else
    iptables -w -t nat -A POSTROUTING -s 10.26.0.0/16 -o "$VPN_OUT_INTERFACE" -j SNAT --to-source "$VPN_OUT_IP"
fi
```

(inside the triple-quoted string — do NOT make this Python code; it goes between `fi` of ANTIZAPRET_OUT_IP branch and the closing `"""` delimiter).

- [ ] **Step 4: Verify tests pass**

```
cd corpweb/backend && .venv/bin/python -m pytest ../../agent/tests/test_escape_rules.py::TestRenderCustomUpSh -v
```

Expected: 21 passed.

- [ ] **Step 5: Commit**

```
git add agent/corpweb_sync_agent.py agent/tests/test_escape_rules.py
git commit -m "feat(agent): render_custom_up_sh — vpn_escape (10.26) rules"
```

---

## Task 6: render_custom_down_sh — symmetric counterpart

**Files:**
- Modify: `agent/corpweb_sync_agent.py`
- Modify: `agent/tests/test_escape_rules.py`

- [ ] **Step 1: Add failing tests**

Append to `agent/tests/test_escape_rules.py`:

```python
class TestRenderCustomDownSh:
    def test_markers_present(self):
        out = agent.render_custom_down_sh()
        assert agent.ESCAPE_MARKER_BEGIN in out
        assert agent.ESCAPE_MARKER_END in out

    def test_sources_setup_and_derives_ip(self):
        out = agent.render_custom_down_sh()
        assert "source setup" in out
        assert 'IP=10' in out
        assert 'FAKE_IP="$IP.30"' in out

    def test_az_escape_dns_dnat_deletes(self):
        out = agent.render_custom_down_sh()
        assert 'iptables -w -t nat -D PREROUTING -s 10.27.0.0/16 -p udp --dport 53 -j DNAT --to-destination 127.0.0.1' in out
        assert 'iptables -w -t nat -D PREROUTING -s 10.27.0.0/16 -p tcp --dport 53 -j DNAT --to-destination 127.0.0.1' in out

    def test_az_escape_mapping_deletes(self):
        out = agent.render_custom_down_sh()
        assert 'iptables -w -t nat -D PREROUTING -s 10.27.0.0/16 -d "$FAKE_IP.0.0/15" -j ANTIZAPRET-MAPPING' in out

    def test_az_escape_restrict_forward_deletes_conditional(self):
        out = agent.render_custom_down_sh()
        assert 'if [[ "$RESTRICT_FORWARD" == \'y\' ]]; then' in out
        assert 'iptables -w -t nat -D PREROUTING -s 10.27.0.0/16 ! -d "$FAKE_IP.0.0/15" -j CONNMARK --set-mark 0x1' in out
        assert 'iptables -w -D FORWARD -s 10.27.0.0/16 -m connmark --mark 0x1 -m set ! --match-set antizapret-forward dst -j DROP' in out

    def test_az_escape_postrouting_deletes_both_branches(self):
        out = agent.render_custom_down_sh()
        assert 'iptables -w -t nat -D POSTROUTING -s 10.27.0.0/16 -o "$ANTIZAPRET_OUT_INTERFACE" -j MASQUERADE' in out
        assert 'iptables -w -t nat -D POSTROUTING -s 10.27.0.0/16 -o "$ANTIZAPRET_OUT_INTERFACE" -j SNAT --to-source "$ANTIZAPRET_OUT_IP"' in out

    def test_vpn_escape_dns_deletes_conditional(self):
        out = agent.render_custom_down_sh()
        assert 'if [[ "$VPN_DNS" == \'1\' ]]; then' in out
        assert 'iptables -w -t nat -D PREROUTING -s 10.26.0.0/16 -p udp --dport 53 -j DNAT --to-destination 127.0.0.2' in out
        assert 'iptables -w -t nat -D PREROUTING -s 10.26.0.0/16 -p tcp --dport 53 -j DNAT --to-destination 127.0.0.2' in out

    def test_vpn_escape_postrouting_deletes_both_branches(self):
        out = agent.render_custom_down_sh()
        assert 'iptables -w -t nat -D POSTROUTING -s 10.26.0.0/16 -o "$VPN_OUT_INTERFACE" -j MASQUERADE' in out
        assert 'iptables -w -t nat -D POSTROUTING -s 10.26.0.0/16 -o "$VPN_OUT_INTERFACE" -j SNAT --to-source "$VPN_OUT_IP"' in out

    def test_idempotent(self):
        a = agent.render_custom_down_sh()
        b = agent.render_custom_down_sh()
        assert a == b

    def test_down_is_tolerant_of_missing_rules(self):
        """Unlike up.sh, our down.sh must not abort mid-way if a rule was
        already removed (e.g. manual intervention). No `set -e` in the body."""
        out = agent.render_custom_down_sh()
        assert "set -e" not in out
```

- [ ] **Step 2: Verify tests fail**

```
cd corpweb/backend && .venv/bin/python -m pytest ../../agent/tests/test_escape_rules.py::TestRenderCustomDownSh -v
```

Expected: 10 FAIL with `AttributeError: ... has no attribute 'render_custom_down_sh'`.

- [ ] **Step 3: Implement**

Below `render_custom_up_sh` add:

```python
def render_custom_down_sh() -> str:
    """
    Return content for /root/antizapret/custom-down.sh (with markers).

    Symmetric counterpart to render_custom_up_sh: every ``-A``/``-I`` in the
    up-rules has a matching ``-D`` here, under the same conditional. No
    ``set -e`` because rules may legitimately be absent on a partial teardown
    and `iptables -D` returns non-zero in that case.
    """
    body = """\
exec 2>/dev/null
cd /root/antizapret
source setup

[[ "$ALTERNATIVE_CLIENT_IP" == 'y' ]] && IP="${CLIENT_IP:-172}" || IP=10
[[ "$ALTERNATIVE_FAKE_IP" == 'y' ]] && FAKE_IP="${FAKE_IP:-198.18}" || FAKE_IP="$IP.30"

if [[ -z "$DEFAULT_INTERFACE" ]]; then
    DEFAULT_INTERFACE="$(ip route get 1.2.3.4 2>/dev/null | grep -oP 'dev \\K\\S+')"
    DEFAULT_IP="$(ip route get 1.2.3.4 2>/dev/null | grep -oP 'src \\K\\S+')"
fi
ANTIZAPRET_OUT_INTERFACE="${ANTIZAPRET_OUT_INTERFACE:-$DEFAULT_INTERFACE}"
ANTIZAPRET_OUT_IP="${ANTIZAPRET_OUT_IP:-$DEFAULT_IP}"
VPN_OUT_INTERFACE="${VPN_OUT_INTERFACE:-$DEFAULT_INTERFACE}"
VPN_OUT_IP="${VPN_OUT_IP:-$DEFAULT_IP}"

# az_escape (10.27) — mirror antizapret removal
iptables -w -t nat -D PREROUTING -s 10.27.0.0/16 -p udp --dport 53 -j DNAT --to-destination 127.0.0.1
iptables -w -t nat -D PREROUTING -s 10.27.0.0/16 -p tcp --dport 53 -j DNAT --to-destination 127.0.0.1
iptables -w -t nat -D PREROUTING -s 10.27.0.0/16 -d "$FAKE_IP.0.0/15" -j ANTIZAPRET-MAPPING
if [[ "$RESTRICT_FORWARD" == 'y' ]]; then
    iptables -w -t nat -D PREROUTING -s 10.27.0.0/16 ! -d "$FAKE_IP.0.0/15" -j CONNMARK --set-mark 0x1
    iptables -w -D FORWARD -s 10.27.0.0/16 -m connmark --mark 0x1 -m set ! --match-set antizapret-forward dst -j DROP
fi
iptables -w -t nat -D POSTROUTING -s 10.27.0.0/16 -o "$ANTIZAPRET_OUT_INTERFACE" -j MASQUERADE
iptables -w -t nat -D POSTROUTING -s 10.27.0.0/16 -o "$ANTIZAPRET_OUT_INTERFACE" -j SNAT --to-source "$ANTIZAPRET_OUT_IP"

# vpn_escape (10.26) — mirror vpn removal
if [[ "$VPN_DNS" == '1' ]]; then
    iptables -w -t nat -D PREROUTING -s 10.26.0.0/16 -p udp --dport 53 -j DNAT --to-destination 127.0.0.2
    iptables -w -t nat -D PREROUTING -s 10.26.0.0/16 -p tcp --dport 53 -j DNAT --to-destination 127.0.0.2
fi
iptables -w -t nat -D POSTROUTING -s 10.26.0.0/16 -o "$VPN_OUT_INTERFACE" -j MASQUERADE
iptables -w -t nat -D POSTROUTING -s 10.26.0.0/16 -o "$VPN_OUT_INTERFACE" -j SNAT --to-source "$VPN_OUT_IP"
exit 0
"""
    return ESCAPE_MARKER_BEGIN + "\n" + body + ESCAPE_MARKER_END + "\n"
```

- [ ] **Step 4: Verify tests pass**

```
cd corpweb/backend && .venv/bin/python -m pytest ../../agent/tests/test_escape_rules.py -v
```

Expected: 31 passed (5 constants + 21 up + 10 down - 5 — actually re-count: Tasks 1-5 add 5+7+5+6+3 = 26 pure-function tests before this one; Task 6 adds 10. Total 36).

- [ ] **Step 5: Commit**

```
git add agent/corpweb_sync_agent.py agent/tests/test_escape_rules.py
git commit -m "feat(agent): render_custom_down_sh — symmetric teardown"
```

---

## Task 7: parse_setup_env — flat KEY=VALUE parser

**Files:**
- Modify: `agent/corpweb_sync_agent.py`
- Modify: `agent/tests/test_escape_rules.py`

- [ ] **Step 1: Add failing tests**

Append to `agent/tests/test_escape_rules.py`:

```python
class TestParseSetupEnv:
    def test_parses_simple_keys(self):
        text = "RESTRICT_FORWARD=y\nVPN_DNS=1\nCLIENT_ISOLATION=n\n"
        assert agent.parse_setup_env(text) == {
            "RESTRICT_FORWARD": "y",
            "VPN_DNS": "1",
            "CLIENT_ISOLATION": "n",
        }

    def test_ignores_blank_and_comment_lines(self):
        text = "# comment\nKEY=value\n\n  \n"
        assert agent.parse_setup_env(text) == {"KEY": "value"}

    def test_strips_quotes(self):
        text = 'KEY1="value1"\nKEY2=\'value2\'\n'
        assert agent.parse_setup_env(text) == {"KEY1": "value1", "KEY2": "value2"}

    def test_strips_whitespace(self):
        text = "  KEY = value  \n"
        assert agent.parse_setup_env(text) == {"KEY": "value"}

    def test_ignores_lines_without_equals(self):
        text = "FOO\nKEY=value\n"
        assert agent.parse_setup_env(text) == {"KEY": "value"}

    def test_empty_returns_empty_dict(self):
        assert agent.parse_setup_env("") == {}
```

- [ ] **Step 2: Verify tests fail**

```
cd corpweb/backend && .venv/bin/python -m pytest ../../agent/tests/test_escape_rules.py::TestParseSetupEnv -v
```

Expected: 6 FAIL.

- [ ] **Step 3: Implement**

Below `render_custom_down_sh`, add:

```python
def parse_setup_env(text: str) -> dict[str, str]:
    """
    Parse /root/antizapret/setup — a flat KEY=VALUE file (no shell quoting
    semantics beyond trivial surrounding quotes). Blank lines, comment lines
    (leading ``#``), and lines without ``=`` are ignored. Surrounding single
    or double quotes around the value are stripped.
    """
    out: dict[str, str] = {}
    for line in text.splitlines():
        stripped = line.strip()
        if not stripped or stripped.startswith("#") or "=" not in stripped:
            continue
        key, _, value = stripped.partition("=")
        key = key.strip()
        value = value.strip()
        if len(value) >= 2 and value[0] == value[-1] and value[0] in ('"', "'"):
            value = value[1:-1]
        out[key] = value
    return out
```

- [ ] **Step 4: Verify tests pass**

```
cd corpweb/backend && .venv/bin/python -m pytest ../../agent/tests/test_escape_rules.py::TestParseSetupEnv -v
```

Expected: 6 passed.

- [ ] **Step 5: Commit**

```
git add agent/corpweb_sync_agent.py agent/tests/test_escape_rules.py
git commit -m "feat(agent): parse_setup_env — flat KEY=VALUE parser"
```

---

## Task 8: validate_setup_env — assert escape-compatible IP scheme

**Files:**
- Modify: `agent/corpweb_sync_agent.py`
- Modify: `agent/tests/test_escape_rules.py`

- [ ] **Step 1: Add failing tests**

Append to `agent/tests/test_escape_rules.py`:

```python
class TestValidateSetupEnv:
    def test_accepts_empty_env(self):
        # Absence of ALTERNATIVE_CLIENT_IP means default IP=10 scheme.
        agent.validate_setup_env({})

    def test_accepts_alternative_client_ip_n(self):
        agent.validate_setup_env({"ALTERNATIVE_CLIENT_IP": "n"})

    def test_accepts_alternative_client_ip_empty(self):
        agent.validate_setup_env({"ALTERNATIVE_CLIENT_IP": ""})

    def test_rejects_alternative_client_ip_y(self):
        with pytest.raises(agent.EscapeEnvError, match="ALTERNATIVE_CLIENT_IP"):
            agent.validate_setup_env({"ALTERNATIVE_CLIENT_IP": "y"})

    def test_rejects_alternative_client_ip_yes_upper(self):
        with pytest.raises(agent.EscapeEnvError):
            agent.validate_setup_env({"ALTERNATIVE_CLIENT_IP": "Y"})
```

- [ ] **Step 2: Verify tests fail**

```
cd corpweb/backend && .venv/bin/python -m pytest ../../agent/tests/test_escape_rules.py::TestValidateSetupEnv -v
```

Expected: 5 FAIL.

- [ ] **Step 3: Implement**

Below `parse_setup_env` add:

```python
class EscapeEnvError(Exception):
    """Raised when /root/antizapret/setup is incompatible with escape rules."""


def validate_setup_env(env: dict[str, str]) -> None:
    """
    Ensure the upstream setup uses the default IP=10 scheme that our
    escape subnets (10.26/10.27) depend on. Raises :class:`EscapeEnvError`
    when ALTERNATIVE_CLIENT_IP is affirmative — our hardcoded subnets would
    silently mis-route otherwise.
    """
    alt = env.get("ALTERNATIVE_CLIENT_IP", "").strip().lower()
    if alt == "y":
        raise EscapeEnvError(
            "ALTERNATIVE_CLIENT_IP=y in setup — escape rules require IP=10 scheme"
        )
```

- [ ] **Step 4: Verify tests pass**

```
cd corpweb/backend && .venv/bin/python -m pytest ../../agent/tests/test_escape_rules.py::TestValidateSetupEnv -v
```

Expected: 5 passed.

- [ ] **Step 5: Commit**

```
git add agent/corpweb_sync_agent.py agent/tests/test_escape_rules.py
git commit -m "feat(agent): validate_setup_env — reject ALTERNATIVE_CLIENT_IP=y"
```

---

## Task 9: sync_custom_script — write into empty file

**Files:**
- Modify: `agent/corpweb_sync_agent.py`
- Modify: `agent/tests/test_escape_rules.py`

- [ ] **Step 1: Add failing tests**

Append to `agent/tests/test_escape_rules.py`:

```python
class TestSyncCustomScript:
    def test_missing_file_creates_it(self, tmp_path):
        target = tmp_path / "custom-up.sh"
        expected = agent.render_custom_up_sh()
        changed = agent.sync_custom_script(str(target), expected)
        assert changed is True
        assert target.exists()
        assert agent.ESCAPE_MARKER_BEGIN in target.read_text()
        assert agent.ESCAPE_MARKER_END in target.read_text()

    def test_empty_file_gets_managed_block_appended(self, tmp_path):
        target = tmp_path / "custom-up.sh"
        target.write_text("")
        expected = agent.render_custom_up_sh()
        changed = agent.sync_custom_script(str(target), expected)
        assert changed is True
        assert agent.ESCAPE_MARKER_BEGIN in target.read_text()

    def test_file_with_only_shebang_preserves_shebang(self, tmp_path):
        target = tmp_path / "custom-up.sh"
        target.write_text("#!/bin/bash\n\n")
        expected = agent.render_custom_up_sh()
        agent.sync_custom_script(str(target), expected)
        content = target.read_text()
        assert content.startswith("#!/bin/bash\n\n")
        assert agent.ESCAPE_MARKER_BEGIN in content

    def test_no_op_when_already_in_sync(self, tmp_path):
        target = tmp_path / "custom-up.sh"
        expected = agent.render_custom_up_sh()
        agent.sync_custom_script(str(target), expected)  # first write
        changed = agent.sync_custom_script(str(target), expected)  # second call
        assert changed is False
```

- [ ] **Step 2: Verify tests fail**

```
cd corpweb/backend && .venv/bin/python -m pytest ../../agent/tests/test_escape_rules.py::TestSyncCustomScript -v
```

Expected: 4 FAIL with `AttributeError`.

- [ ] **Step 3: Implement**

Below `validate_setup_env` add:

```python
def _extract_managed_block(content: str) -> tuple[str, str, str]:
    """
    Split *content* into (prefix, managed, suffix) at marker boundaries.

    Returns ``(prefix, managed, suffix)``. If neither marker is present,
    returns ``(content, "", "")`` — managed block is absent and caller will
    append one. If only one marker is present, raises ValueError.
    """
    begin = content.find(ESCAPE_MARKER_BEGIN)
    end = content.find(ESCAPE_MARKER_END)
    if begin == -1 and end == -1:
        return content, "", ""
    if begin == -1 or end == -1 or end < begin:
        raise ValueError("custom-up.sh has malformed CorpAdmin markers")
    managed_end = end + len(ESCAPE_MARKER_END)
    return content[:begin], content[begin:managed_end], content[managed_end:]


def sync_custom_script(path: str, expected: str) -> bool:
    """
    Ensure the managed block in *path* equals *expected*.

    *expected* is the full managed block including BEGIN/END markers
    (as returned by :func:`render_custom_up_sh` / :func:`render_custom_down_sh`).

    Preserves any content outside the markers. Creates the file if absent,
    appending the managed block. Returns True iff the file changed on disk.
    """
    try:
        current = open(path).read()
    except FileNotFoundError:
        current = ""

    prefix, managed, suffix = _extract_managed_block(current)
    expected_stripped = expected.rstrip("\n")

    if managed:
        new_content = prefix + expected_stripped + suffix
    else:
        sep = "" if (not prefix or prefix.endswith("\n")) else "\n"
        new_content = prefix + sep + expected_stripped + "\n"

    if new_content == current:
        return False

    write_atomic(path, new_content.encode())
    return True
```

- [ ] **Step 4: Verify tests pass**

```
cd corpweb/backend && .venv/bin/python -m pytest ../../agent/tests/test_escape_rules.py::TestSyncCustomScript -v
```

Expected: 4 passed.

- [ ] **Step 5: Commit**

```
git add agent/corpweb_sync_agent.py agent/tests/test_escape_rules.py
git commit -m "feat(agent): sync_custom_script — idempotent write with markers"
```

---

## Task 10: sync_custom_script — user content preservation + malformed markers

**Files:**
- Modify: `agent/tests/test_escape_rules.py` (coverage for existing impl)

- [ ] **Step 1: Add failing tests**

Append to `TestSyncCustomScript`:

```python
    def test_user_content_before_markers_preserved(self, tmp_path):
        target = tmp_path / "custom-up.sh"
        expected = agent.render_custom_up_sh()
        # simulate user who wrote their own rule, then our agent adds the block
        target.write_text("#!/bin/bash\n# user rule\niptables -A INPUT -j ACCEPT\n")
        agent.sync_custom_script(str(target), expected)
        content = target.read_text()
        assert "# user rule" in content
        assert "iptables -A INPUT -j ACCEPT" in content
        assert agent.ESCAPE_MARKER_BEGIN in content
        # user's rule must appear before our block
        assert content.index("# user rule") < content.index(agent.ESCAPE_MARKER_BEGIN)

    def test_user_content_outside_markers_preserved_on_update(self, tmp_path):
        target = tmp_path / "custom-up.sh"
        stale_block = (
            agent.ESCAPE_MARKER_BEGIN
            + "\n# old content\n"
            + agent.ESCAPE_MARKER_END
            + "\n"
        )
        target.write_text(
            "#!/bin/bash\n# user prefix\n" + stale_block + "# user suffix\n"
        )
        expected = agent.render_custom_up_sh()
        changed = agent.sync_custom_script(str(target), expected)
        assert changed is True
        content = target.read_text()
        assert "# user prefix" in content
        assert "# user suffix" in content
        assert "# old content" not in content  # replaced
        # new body present
        assert "10.27.0.0/16" in content

    def test_malformed_markers_begin_only_raises(self, tmp_path):
        target = tmp_path / "custom-up.sh"
        target.write_text(agent.ESCAPE_MARKER_BEGIN + "\n# stuck\n")
        with pytest.raises(ValueError, match="malformed"):
            agent.sync_custom_script(str(target), agent.render_custom_up_sh())

    def test_malformed_markers_end_only_raises(self, tmp_path):
        target = tmp_path / "custom-up.sh"
        target.write_text("# stuck\n" + agent.ESCAPE_MARKER_END + "\n")
        with pytest.raises(ValueError, match="malformed"):
            agent.sync_custom_script(str(target), agent.render_custom_up_sh())

    def test_malformed_markers_reversed_order_raises(self, tmp_path):
        target = tmp_path / "custom-up.sh"
        target.write_text(
            agent.ESCAPE_MARKER_END + "\nstuff\n" + agent.ESCAPE_MARKER_BEGIN + "\n"
        )
        with pytest.raises(ValueError, match="malformed"):
            agent.sync_custom_script(str(target), agent.render_custom_up_sh())
```

- [ ] **Step 2: Verify tests pass immediately**

The existing implementation from Task 9 should already handle these cases. Run:

```
cd corpweb/backend && .venv/bin/python -m pytest ../../agent/tests/test_escape_rules.py::TestSyncCustomScript -v
```

Expected: 9 passed (4 from Task 9 + 5 new).

If any of the 5 new tests fail, the Task 9 implementation has a gap — fix `_extract_managed_block` or `sync_custom_script` inline and re-run.

- [ ] **Step 3: Commit**

```
git add agent/tests/test_escape_rules.py
git commit -m "test(agent): sync_custom_script — user content & malformed markers"
```

---

## Task 11: sync_escape_rules — orchestrator happy path

**Files:**
- Modify: `agent/corpweb_sync_agent.py`
- Modify: `agent/tests/test_escape_rules.py`

- [ ] **Step 1: Add failing tests**

Append to `agent/tests/test_escape_rules.py`:

```python
from unittest.mock import patch


class TestSyncEscapeRules:
    def _write_setup(self, tmp_path, text="ALTERNATIVE_CLIENT_IP=n\nRESTRICT_FORWARD=y\n"):
        setup = tmp_path / "setup"
        setup.write_text(text)
        return setup

    def _patch_paths(self, tmp_path):
        """Monkeypatch the three agent path constants to point into tmp_path."""
        return patch.multiple(
            agent,
            ANTIZAPRET_SETUP_PATH=str(tmp_path / "setup"),
            CUSTOM_UP_PATH=str(tmp_path / "custom-up.sh"),
            CUSTOM_DOWN_PATH=str(tmp_path / "custom-down.sh"),
        )

    def test_happy_path_writes_both_files_and_restarts(self, tmp_path):
        self._write_setup(tmp_path)
        with self._patch_paths(tmp_path), \
             patch.object(agent, "_run_restart_antizapret") as mock_restart:
            metrics = agent.sync_escape_rules()
        assert (tmp_path / "custom-up.sh").exists()
        assert (tmp_path / "custom-down.sh").exists()
        assert agent.ESCAPE_MARKER_BEGIN in (tmp_path / "custom-up.sh").read_text()
        assert agent.ESCAPE_MARKER_BEGIN in (tmp_path / "custom-down.sh").read_text()
        assert mock_restart.call_count == 1
        assert metrics["escape_drift_detected"] is True
        assert metrics["escape_drift_applied_count"] == 1

    def test_no_op_when_files_match_does_not_restart(self, tmp_path):
        self._write_setup(tmp_path)
        with self._patch_paths(tmp_path), \
             patch.object(agent, "_run_restart_antizapret") as mock_restart:
            agent.sync_escape_rules()  # first call writes
            mock_restart.reset_mock()
            metrics = agent.sync_escape_rules()  # second call no-op
        assert mock_restart.call_count == 0
        assert metrics["escape_drift_detected"] is False
        assert metrics["escape_drift_applied_count"] == 0
```

- [ ] **Step 2: Verify tests fail**

```
cd corpweb/backend && .venv/bin/python -m pytest ../../agent/tests/test_escape_rules.py::TestSyncEscapeRules -v
```

Expected: 2 FAIL with `AttributeError: ... 'sync_escape_rules'`.

- [ ] **Step 3: Implement orchestrator**

Below `sync_custom_script` add:

```python
_escape_drift_total = 0


def sync_escape_rules() -> dict:
    """
    Reconcile /root/antizapret/custom-up.sh and custom-down.sh against the
    agent's canonical rule set. Triggers ``systemctl restart antizapret.service``
    at most once when either file changed. Returns heartbeat-shaped metrics.

    Errors (malformed markers, incompatible setup, missing setup) are captured
    in the returned dict under ``escape_error``; they do NOT raise, because
    this runs on every heartbeat cycle and must not break the loop.
    """
    global _escape_drift_total

    metrics: dict = {
        "escape_drift_detected": False,
        "escape_drift_applied_count": _escape_drift_total,
    }

    try:
        setup_text = open(ANTIZAPRET_SETUP_PATH).read()
    except FileNotFoundError:
        metrics["escape_error"] = "setup_missing"
        return metrics

    env = parse_setup_env(setup_text)
    try:
        validate_setup_env(env)
    except EscapeEnvError as exc:
        metrics["escape_error"] = str(exc)
        return metrics

    try:
        changed_up = sync_custom_script(CUSTOM_UP_PATH, render_custom_up_sh())
        changed_down = sync_custom_script(CUSTOM_DOWN_PATH, render_custom_down_sh())
    except ValueError as exc:
        metrics["escape_error"] = str(exc)
        return metrics

    if changed_up or changed_down:
        _run_restart_antizapret()
        _escape_drift_total += 1
        metrics["escape_drift_detected"] = True
        metrics["escape_drift_applied_count"] = _escape_drift_total

    return metrics
```

Reset counter between tests — add to the existing `reset_timers` fixture in `test_sync_agent.py` (we'll touch that file in Task 13; for now mirror the same reset in a local fixture). Update `test_escape_rules.py` — add at top level after the imports:

```python
@pytest.fixture(autouse=True)
def _reset_escape_counter():
    agent._escape_drift_total = 0
    yield
    agent._escape_drift_total = 0
```

- [ ] **Step 4: Verify tests pass**

```
cd corpweb/backend && .venv/bin/python -m pytest ../../agent/tests/test_escape_rules.py -v
```

Expected: all tests green (36 + 6 + 5 + 9 + 2 = **58** passed; adjust if count drifts — what matters is zero failures).

- [ ] **Step 5: Commit**

```
git add agent/corpweb_sync_agent.py agent/tests/test_escape_rules.py
git commit -m "feat(agent): sync_escape_rules — orchestrator + drift metrics"
```

---

## Task 12: sync_escape_rules — error cases (missing setup, ALTERNATIVE_CLIENT_IP, malformed)

**Files:**
- Modify: `agent/tests/test_escape_rules.py`

- [ ] **Step 1: Add failing/validating tests**

Append to `TestSyncEscapeRules`:

```python
    def test_missing_setup_reports_and_skips(self, tmp_path):
        # Do NOT write setup file.
        with self._patch_paths(tmp_path), \
             patch.object(agent, "_run_restart_antizapret") as mock_restart:
            metrics = agent.sync_escape_rules()
        assert mock_restart.call_count == 0
        assert metrics["escape_error"] == "setup_missing"
        assert not (tmp_path / "custom-up.sh").exists()

    def test_alternative_client_ip_reports_and_skips(self, tmp_path):
        self._write_setup(tmp_path, text="ALTERNATIVE_CLIENT_IP=y\n")
        with self._patch_paths(tmp_path), \
             patch.object(agent, "_run_restart_antizapret") as mock_restart:
            metrics = agent.sync_escape_rules()
        assert mock_restart.call_count == 0
        assert "ALTERNATIVE_CLIENT_IP" in metrics["escape_error"]
        assert not (tmp_path / "custom-up.sh").exists()

    def test_malformed_up_sh_reports_and_skips(self, tmp_path):
        self._write_setup(tmp_path)
        (tmp_path / "custom-up.sh").write_text(
            agent.ESCAPE_MARKER_BEGIN + "\n# stuck — no end marker\n"
        )
        with self._patch_paths(tmp_path), \
             patch.object(agent, "_run_restart_antizapret") as mock_restart:
            metrics = agent.sync_escape_rules()
        assert mock_restart.call_count == 0
        assert "malformed" in metrics["escape_error"]

    def test_one_restart_per_cycle_even_if_both_files_changed(self, tmp_path):
        self._write_setup(tmp_path)
        with self._patch_paths(tmp_path), \
             patch.object(agent, "_run_restart_antizapret") as mock_restart:
            agent.sync_escape_rules()
        assert mock_restart.call_count == 1
```

- [ ] **Step 2: Run — tests should pass under the orchestrator from Task 11**

```
cd corpweb/backend && .venv/bin/python -m pytest ../../agent/tests/test_escape_rules.py::TestSyncEscapeRules -v
```

Expected: 6 passed (2 from Task 11 + 4 new). If any fail, fix the orchestrator inline.

- [ ] **Step 3: Commit**

```
git add agent/tests/test_escape_rules.py
git commit -m "test(agent): sync_escape_rules — error paths & single-restart invariant"
```

---

## Task 13: Hook sync_escape_rules into register_if_needed

**Files:**
- Modify: `agent/corpweb_sync_agent.py`
- Modify: `agent/tests/test_sync_agent.py`

- [ ] **Step 1: Add failing integration test**

Append a new class to `agent/tests/test_sync_agent.py`:

```python
class TestRegisterTriggersEscapeSync:
    def test_register_if_needed_calls_sync_escape_rules(self):
        fake_response = MagicMock()
        fake_response.json.return_value = {
            "node_id": "n1",
            "wg_server_keys": {},
            "wg_config": {},
        }
        with patch.object(agent, "api_post", return_value=fake_response), \
             patch.object(agent, "_local_ip", return_value="10.0.0.1"), \
             patch.object(agent, "_apply_wg_config"), \
             patch.object(agent, "sync_escape_rules") as mock_sync:
            mock_sync.return_value = {"escape_drift_detected": False}
            agent.register_if_needed()
        mock_sync.assert_called_once()
```

- [ ] **Step 2: Verify test fails**

```
cd corpweb/backend && .venv/bin/python -m pytest ../../agent/tests/test_sync_agent.py::TestRegisterTriggersEscapeSync -v
```

Expected: FAIL — `sync_escape_rules` not called inside `register_if_needed`.

- [ ] **Step 3: Hook the call**

In `agent/corpweb_sync_agent.py`, modify `register_if_needed`. Find the tail of the function (around line 411, just before `log.info("Registration complete")`) and insert:

```python
    # Reconcile escape-rules hooks (custom-up.sh / custom-down.sh).
    # Errors are captured in metrics and do not break registration.
    try:
        sync_escape_rules()
    except Exception as exc:  # defensive — sync_escape_rules itself swallows
        log.error("sync_escape_rules unexpectedly raised: %s", exc)
```

- [ ] **Step 4: Verify test passes**

```
cd corpweb/backend && .venv/bin/python -m pytest ../../agent/tests/test_sync_agent.py::TestRegisterTriggersEscapeSync -v
```

Expected: passed.

- [ ] **Step 5: Re-run full suite**

```
cd corpweb/backend && .venv/bin/python -m pytest ../../agent/tests/ -v
```

Expected: all green, no regressions on existing 26 tests.

- [ ] **Step 6: Commit**

```
git add agent/corpweb_sync_agent.py agent/tests/test_sync_agent.py
git commit -m "feat(agent): call sync_escape_rules at tail of register_if_needed"
```

---

## Task 14: Hook sync_escape_rules into heartbeat + merge drift metrics

**Files:**
- Modify: `agent/corpweb_sync_agent.py`
- Modify: `agent/tests/test_sync_agent.py`

- [ ] **Step 1: Add failing integration test**

Append a new class to `agent/tests/test_sync_agent.py`:

```python
class TestHeartbeatIncludesEscapeMetrics:
    def test_send_heartbeat_merges_sync_escape_rules_metrics(self):
        fake_resp = MagicMock()
        with patch.object(agent, "api_post", return_value=fake_resp) as mock_post, \
             patch.object(agent, "sync_escape_rules") as mock_sync, \
             patch.object(agent, "collect_metrics", return_value={"active_peers_antizapret": 3}), \
             patch.object(agent, "collect_peers", return_value=[]), \
             patch.object(agent, "_applied_shas", return_value={}):
            mock_sync.return_value = {
                "escape_drift_detected": True,
                "escape_drift_applied_count": 2,
            }
            agent.send_heartbeat()

        mock_sync.assert_called_once()
        payload = mock_post.call_args[0][1]
        assert payload["metrics"]["active_peers_antizapret"] == 3
        assert payload["metrics"]["escape_drift_detected"] is True
        assert payload["metrics"]["escape_drift_applied_count"] == 2

    def test_heartbeat_still_sends_when_sync_escape_rules_returns_error(self):
        fake_resp = MagicMock()
        with patch.object(agent, "api_post", return_value=fake_resp) as mock_post, \
             patch.object(agent, "sync_escape_rules") as mock_sync, \
             patch.object(agent, "collect_metrics", return_value={}), \
             patch.object(agent, "collect_peers", return_value=[]), \
             patch.object(agent, "_applied_shas", return_value={}):
            mock_sync.return_value = {"escape_error": "setup_missing"}
            agent.send_heartbeat()
        assert mock_post.called
        payload = mock_post.call_args[0][1]
        assert payload["metrics"]["escape_error"] == "setup_missing"
```

- [ ] **Step 2: Verify tests fail**

```
cd corpweb/backend && .venv/bin/python -m pytest ../../agent/tests/test_sync_agent.py::TestHeartbeatIncludesEscapeMetrics -v
```

Expected: 2 FAIL — `send_heartbeat` does not call `sync_escape_rules`.

- [ ] **Step 3: Wire into send_heartbeat**

In `agent/corpweb_sync_agent.py`, replace the body of `send_heartbeat` (around lines 614-629) with:

```python
def send_heartbeat() -> None:
    metrics = collect_metrics()
    try:
        escape_metrics = sync_escape_rules()
    except Exception as exc:  # defensive
        log.error("sync_escape_rules unexpectedly raised: %s", exc)
        escape_metrics = {"escape_error": f"unexpected: {exc.__class__.__name__}"}
    metrics.update(escape_metrics)

    payload = {
        "applied_sha": _applied_shas(),
        "health": "ok",
        "metrics": metrics,
        "peers": collect_peers(),
    }
    try:
        api_post(
            "/api/v1/agent/heartbeat",
            payload,
            timeout=15,
        )
        log.debug("Heartbeat sent")
    except (requests.HTTPError, requests.ConnectionError, requests.Timeout) as exc:
        log.warning("Heartbeat failed: %s", exc)
```

- [ ] **Step 4: Verify tests pass**

```
cd corpweb/backend && .venv/bin/python -m pytest ../../agent/tests/test_sync_agent.py::TestHeartbeatIncludesEscapeMetrics -v
```

Expected: 2 passed.

- [ ] **Step 5: Full agent suite green**

```
cd corpweb/backend && .venv/bin/python -m pytest ../../agent/tests/ -v
```

Expected: all green.

- [ ] **Step 6: Full backend suite green (no regression)**

```
cd corpweb/backend && .venv/bin/python -m pytest -q
```

Expected: existing 324 backend tests still green (no files were touched in backend, this is a safety net).

- [ ] **Step 7: Commit**

```
git add agent/corpweb_sync_agent.py agent/tests/test_sync_agent.py
git commit -m "feat(agent): heartbeat includes escape drift metrics"
```

---

## Task 15: Manual smoke + deploy checklist

**Files:**
- Modify: `corpweb/README.md` (operator-facing — extend «Обход блокировки» section)

- [ ] **Step 1: Locate the «Обход блокировки» section in corpweb/README.md**

```
cd corpweb/backend && grep -n "Обход блокировки ТСПУ" ../../corpweb/README.md
```

- [ ] **Step 2: Append an operator checklist under that section**

Append (or insert right before the next `##` heading) the following subsection:

```markdown
### Smoke-check escape-rules на ноде (после обновления агента)

После `systemctl restart corpweb-sync-agent` на ноде проверить:

1. Файлы сгенерированы агентом:
   ```
   grep "CorpAdmin escape rules" /root/antizapret/custom-up.sh /root/antizapret/custom-down.sh
   ```
   Оба файла должны содержать блок между `=== BEGIN CorpAdmin escape rules ===` и `=== END CorpAdmin escape rules ===`.

2. antizapret.service перезапущен агентом:
   ```
   journalctl -u antizapret.service --since "5 minutes ago" | tail
   ```

3. Правила в iptables:
   ```
   iptables -t nat -nvL POSTROUTING | grep -E '10\.2[67]\.0\.0/16'
   iptables -t nat -nvL PREROUTING | grep -E '10\.2[67]\.0\.0/16'
   ```
   Должно быть 2 POSTROUTING-правила (MASQUERADE/SNAT по 10.26 и 10.27) и ≥ 3 PREROUTING-правила (DNS DNAT × 2 + ANTIZAPRET-MAPPING для 10.27; при VPN_DNS=1 — ещё 2 для 10.26).

4. End-to-end:
   - клиент импортирует `*-azB.conf` → коннектится → открывает заблокированный сайт
   - клиент импортирует `*-vpnB.conf` → коннектится → открывает произвольный публичный сайт

5. Drift-recovery проверка (опционально):
   ```
   : > /root/antizapret/custom-up.sh    # очистить managed-блок вручную
   # подождать HEARTBEAT_INTERVAL (30s)
   grep -c "CorpAdmin escape rules" /root/antizapret/custom-up.sh   # ожидаем 2 (BEGIN + END)
   ```
   Heartbeat на CP должен показать `escape_drift_applied_count` > 0.
```

- [ ] **Step 3: Commit**

```
git add corpweb/README.md
git commit -m "docs: escape-rules agent smoke-check procedure"
```

---

## Task 16: Final verification before deploy

- [ ] **Step 1: All suites green**

```
cd corpweb/backend && .venv/bin/python -m pytest -q
.venv/bin/python -m pytest ../../agent/tests/ -q
```

Both should show zero failures.

- [ ] **Step 2: Frontend typecheck (no regressions even though we did not touch frontend)**

```
cd corpweb/frontend && npm run build
```

Expected: success (this project has no frontend-changes, so this is purely a sanity check).

- [ ] **Step 3: Review full diff vs main**

```
git log --oneline main..HEAD
git diff main..HEAD --stat
```

All commits should be on `agent/` paths and `docs/` + `corpweb/README.md`. No backend or frontend code changed.

- [ ] **Step 4: Mark beads task in-progress (if not already)**

```
bd update CorpAdmin-AZ-6za --claim
```

- [ ] **Step 5: Push branch**

```
git push origin CorpAdmin
```

- [ ] **Step 6: Deploy to wgfi3 (secondary) first**

Via `ssh brolin@wgfi3.p4i.ru -p 2201`:
1. `scp agent/corpweb_sync_agent.py brolin@wgfi3.p4i.ru:/tmp/`
2. SSH in, `su -c "install -m 0755 -o root -g root /tmp/corpweb_sync_agent.py /usr/local/bin/corpweb-sync-agent.py && systemctl restart corpweb-sync-agent"`
3. Run smoke-check from Task 15.

- [ ] **Step 7: Deploy to wgfi2 (primary) after smoke passes**

Same steps as wgfi3, but on `wgfi2-ssh.p4i.ru`.

- [ ] **Step 8: Close the beads task**

```
bd close CorpAdmin-AZ-6za --reason "Deployed to both nodes. az_escape + vpn_escape tunnels functional end-to-end; drift recovery verified via manual smoke."
```

---

## Self-Review

**Spec coverage:**
- Spec D1 (extension-point, not patching) → Tasks 2-6 render scripts targeting custom-up.sh/down.sh only; no upstream up.sh modification.
- Spec D2 (marker-bracketed managed block) → Task 1 constants, Task 9 _extract_managed_block, Task 10 user content preservation tests.
- Spec D3 (rule set per iface) → Tasks 4 (az_escape) and 5 (vpn_escape); Task 6 mirror in down.
- Spec D4 (WARP inheritance) → implicit — rules use `$ANTIZAPRET_OUT_INTERFACE` / `$VPN_OUT_INTERFACE` which upstream up.sh repoints to warp when WARP=y; no explicit test but the variable-based scheme proves it by construction.
- Spec D5 (unconditional deploy) → Task 11 does not gate on ESCAPE_ENABLED — sync runs always.
- Spec D6 (ALTERNATIVE_CLIENT_IP assertion) → Task 8 (`validate_setup_env`) and Task 12 (orchestrator returns error metric).
- Spec D7 (sync on startup + heartbeat) → Task 13 (register_if_needed) and Task 14 (send_heartbeat).
- Spec D8 (systemctl restart) → Task 11 orchestrator calls `_run_restart_antizapret`; Task 12 asserts one call per cycle.

**Testing pyramid:**
- L1 unit — Tasks 2-8 cover render / validate / parse pure functions.
- L2 sync-layer — Tasks 9-10 cover `sync_custom_script` with tmp_path.
- L3 integration — Tasks 11-14 cover orchestrator and hooks with mocked subprocess.
- L4/L5 manual — Task 15 smoke checklist in README, Task 16 deploy.

**Placeholder scan:** no TBD/TODO/"similar to Task N"/ambiguous steps.

**Type / signature consistency:** `render_custom_up_sh()` and `render_custom_down_sh()` take no args in every reference. `sync_custom_script(path: str, expected: str) -> bool` consistent. `sync_escape_rules() -> dict` consistent. `EscapeEnvError` defined once in Task 8, referenced in Task 11.

**Known gaps / explicit non-coverage:**
- No automated L4/L5 — L4 (real iptables) and L5 (drift recovery on a live node) are manual per Task 15 checklist. Full automation requires a node VM/fixture — out of scope.
- No test for WARP reassignment — proven-by-construction (we read the same variable upstream sets).
- No test asserts that `write_atomic` is the one used (vs `open(...).write()`); existing helper, trusted.
