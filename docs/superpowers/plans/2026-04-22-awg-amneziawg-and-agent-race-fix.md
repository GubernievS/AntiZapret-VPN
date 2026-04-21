# AmneziaWG on Nodes + Agent Race Fix — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Unblock CorpAdmin-AZ-roo Phase 7 — install `amneziawg` on nodes, make the agent use `awg`/`awg-quick` for escape ifaces, eliminate the `register_if_needed` ↔ SSE race, add regression tests for peer-management ops on escape ifaces.

**Architecture:** Agent-only install path for `amneziawg` (idempotent block in `agent/install.sh`). Agent refactored: one unified `apply_iface_conf(iface, flavor)` that either brings iface up via `(wg|awg)-quick@<iface>` or syncconfs it; `register_if_needed` writes keys only. Backend relocates escape `.conf` blob paths in `_IFACE_CONFIG` + alembic `0006` renames keys in `wg_file_state`. Regression tests for `delete_peer` / `disable_peer` / `enable_peer` on escape ifaces to lock in AWG `[Interface]` preservation.

**Tech Stack:** Bash (install.sh), Python 3.13 (agent + backend), FastAPI/SQLAlchemy/Alembic (backend), `amneziawg-dkms` + `amneziawg-tools` (nodes), systemd, pytest.

**Related:** spec `docs/superpowers/specs/2026-04-22-awg-amneziawg-and-agent-race-fix-design.md`; bug `CorpAdmin-AZ-3qe`; parent epic `CorpAdmin-AZ-roo`; blocks Phase 7 sub-task `CorpAdmin-AZ-cpk`.

---

## File structure overview

| File | Responsibility |
|---|---|
| `agent/install.sh` | System package bootstrap — add idempotent `install_amneziawg()` function. |
| `agent/corpweb_sync_agent.py` | MANAGED_FILES paths → `/etc/amnezia/amneziawg/` for escape; unified `apply_iface_conf()`; `register_if_needed` stops starting units. |
| `agent/tests/test_sync_agent.py` | Tests for new hook names, up-vs-sync branching, no-start in register. |
| `corpweb/backend/app/services/vpn_manager_new.py` | Update `conf_path` for escape ifaces in `_IFACE_CONFIG`. |
| `corpweb/backend/alembic/versions/0006_relocate_escape_confs.py` | UPDATE `wg_file_state.path` for 2 rows. |
| `corpweb/backend/tests/test_vpn_manager_new.py` | Regression tests for `delete_peer`, `disable_peer`, `enable_peer` on escape ifaces. |
| `README.md` | AmneziaWG requirement + escape-mode section (final commit only). |

---

## Phase 1 — Agent `install.sh` picks up amneziawg

### Task 1: Add idempotent `install_amneziawg()` block to `agent/install.sh`

**Files:**
- Modify: `agent/install.sh`

- [ ] **Step 1: Inspect current install.sh to find the right insertion point**

Run:
```bash
cd /home/brolin/Documents/ITSS/AdminAZWG/CorpAdmin-AZ
grep -nE "apt-get install|pip install|install -m" agent/install.sh | head -20
```

You need to insert the amneziawg block **after** the script's own root-check and apt-update, **before** the sync-agent Python daemon is installed. The existing script is short; insert the function definition near the top and call it in the main flow.

- [ ] **Step 2: Add the install function**

Add this function after the existing `require_root` / `ensure_pkg` helpers in `agent/install.sh`. If no such helpers exist, add it near the top below the shebang:

```bash
install_amneziawg() {
    if command -v awg >/dev/null 2>&1; then
        echo "[agent] amneziawg already installed — skipping"
        return 0
    fi

    echo "[agent] installing amneziawg…"
    install -d /etc/apt/keyrings
    apt-get update -qq

    # Primary path: amnezia official apt repo
    if curl -fsSL --max-time 10 https://apt.amnezia.org/amnezia-archive-keyring.gpg \
          -o /etc/apt/keyrings/amnezia-archive-keyring.gpg 2>/dev/null; then
        local codename
        codename=$(lsb_release -cs 2>/dev/null || awk -F= '/^VERSION_CODENAME=/ {print $2}' /etc/os-release)
        echo "deb [signed-by=/etc/apt/keyrings/amnezia-archive-keyring.gpg] https://apt.amnezia.org/ ${codename} main" \
            > /etc/apt/sources.list.d/amnezia.list
        apt-get update -qq
        if apt-get install -y amneziawg amneziawg-tools; then
            echo "[agent] amneziawg installed via apt"
            return 0
        fi
        echo "[agent] apt install failed — falling back to GitHub releases"
    else
        echo "[agent] amnezia apt repo unreachable — using GitHub releases"
    fi

    # Fallback: download .deb artefacts from GitHub releases
    local tmpdir
    tmpdir=$(mktemp -d)
    local arch
    arch=$(dpkg --print-architecture)

    # Pull latest kmod + tools .debs
    # Repo releases name pattern: amneziawg-dkms_<ver>_all.deb, amneziawg-tools_<ver>_<arch>.deb
    curl -fsSL "https://api.github.com/repos/amnezia-vpn/amneziawg-linux-kernel-module/releases/latest" \
        | grep -oE 'https://[^"]+amneziawg-dkms[^"]+\.deb' | head -1 \
        | xargs -r curl -fsSL -o "$tmpdir/amneziawg-dkms.deb"
    curl -fsSL "https://api.github.com/repos/amnezia-vpn/amneziawg-tools/releases/latest" \
        | grep -oE "https://[^\"]+amneziawg-tools[^\"]+${arch}\\.deb" | head -1 \
        | xargs -r curl -fsSL -o "$tmpdir/amneziawg-tools.deb"

    if [[ -s "$tmpdir/amneziawg-dkms.deb" && -s "$tmpdir/amneziawg-tools.deb" ]]; then
        apt-get install -y dkms linux-headers-"$(uname -r)" || true
        dpkg -i "$tmpdir/amneziawg-dkms.deb" "$tmpdir/amneziawg-tools.deb" || apt-get install -f -y
        rm -rf "$tmpdir"
        if command -v awg >/dev/null 2>&1; then
            echo "[agent] amneziawg installed via GitHub .deb"
            return 0
        fi
    fi

    rm -rf "$tmpdir"
    echo "[agent] ERROR: could not install amneziawg automatically." >&2
    echo "[agent] Install it manually, then re-run this script." >&2
    return 1
}
```

- [ ] **Step 3: Call `install_amneziawg` from the main flow**

Find the `main` / top-level section of `agent/install.sh` (after root-check and before the sync-agent Python install). Add:

```bash
install_amneziawg
```

If the script has no explicit `main` function, just add the call at the appropriate top-level line.

- [ ] **Step 4: Syntax-check the script**

Run:
```bash
bash -n agent/install.sh
```

Expected: no output (clean parse).

- [ ] **Step 5: Commit**

```bash
git add agent/install.sh
git commit -m "feat(agent/install): idempotent amneziawg install with apt+GitHub fallback"
```

---

### Task 2: One-shot manual install on the two existing nodes (wgfi2 + wgfi3)

**Files:** none (operational step)

- [ ] **Step 1: Extract the install_amneziawg function into a standalone script**

Create a temporary standalone copy on your local machine:
```bash
sed -n '/^install_amneziawg() {/,/^}/p' /home/brolin/Documents/ITSS/AdminAZWG/CorpAdmin-AZ/agent/install.sh \
  > /tmp/install_amneziawg.sh
echo 'install_amneziawg' >> /tmp/install_amneziawg.sh
```

- [ ] **Step 2: Upload to each node**

```bash
for host in wgfi2-ssh.p4i.ru wgfi3.p4i.ru; do
  echo "=== $host ==="
  ssh -p 2201 brolin@$host 'cat > /tmp/install_amneziawg.sh' < /tmp/install_amneziawg.sh
done
```

- [ ] **Step 3: Run as root on each node**

```bash
for host in wgfi2-ssh.p4i.ru wgfi3.p4i.ru; do
  echo "=== $host ==="
  ssh -p 2201 brolin@$host 'su - -c "bash /tmp/install_amneziawg.sh && which awg && awg --version"' <<< '"rcnhfl1w2z'
done
```

Expected final output on each node: `awg` path + version string, no errors.

- [ ] **Step 4: Verify amneziawg kernel module loads**

```bash
for host in wgfi2-ssh.p4i.ru wgfi3.p4i.ru; do
  echo "=== $host ==="
  ssh -p 2201 brolin@$host 'su - -c "modprobe amneziawg && lsmod | grep amneziawg"' <<< '"rcnhfl1w2z'
done
```

Expected: `amneziawg` listed in each node's `lsmod` output.

- [ ] **Step 5: Cleanup**

```bash
for host in wgfi2-ssh.p4i.ru wgfi3.p4i.ru; do
  ssh -p 2201 brolin@$host 'rm -f /tmp/install_amneziawg.sh'
done
rm -f /tmp/install_amneziawg.sh
```

No commit — this is an operational action, not a code change.

---

## Phase 2 — Agent refactor (MANAGED_FILES + apply_iface_conf + register)

### Task 3: Update MANAGED_FILES paths + hook names for escape ifaces

**Files:**
- Modify: `agent/corpweb_sync_agent.py`
- Test: `agent/tests/test_sync_agent.py`

- [ ] **Step 1: Write failing tests**

Append to `agent/tests/test_sync_agent.py` (inside `class TestManagedFilesWiring`):

```python
    def test_escape_paths_moved_to_amneziawg_dir(self):
        mapping = dict(agent.MANAGED_FILES)
        assert "/etc/amnezia/amneziawg/antizapret_escape.conf" in mapping
        assert "/etc/amnezia/amneziawg/vpn_escape.conf" in mapping
        # old /etc/wireguard/*_escape.conf paths must be gone
        assert "/etc/wireguard/antizapret_escape.conf" not in mapping
        assert "/etc/wireguard/vpn_escape.conf" not in mapping

    def test_escape_hooks_renamed_to_awg_prefix(self):
        mapping = dict(agent.MANAGED_FILES)
        assert mapping["/etc/amnezia/amneziawg/antizapret_escape.conf"] == "awg_antizapret_escape"
        assert mapping["/etc/amnezia/amneziawg/vpn_escape.conf"] == "awg_vpn_escape"
```

- [ ] **Step 2: Run tests — verify they fail**

Run:
```bash
cd /home/brolin/Documents/ITSS/AdminAZWG/CorpAdmin-AZ/corpweb/backend
.venv/bin/python -m pytest ../../agent/tests/test_sync_agent.py -v -k "escape_paths_moved or escape_hooks_renamed"
```

Expected: both tests FAIL with `assert ... in mapping` / `KeyError`.

- [ ] **Step 3: Update MANAGED_FILES**

In `agent/corpweb_sync_agent.py`, find:
```python
    ("/etc/wireguard/antizapret_escape.conf", "wg_antizapret_escape"),
    ("/etc/wireguard/vpn_escape.conf", "wg_vpn_escape"),
```

Replace with:
```python
    ("/etc/amnezia/amneziawg/antizapret_escape.conf", "awg_antizapret_escape"),
    ("/etc/amnezia/amneziawg/vpn_escape.conf", "awg_vpn_escape"),
```

- [ ] **Step 4: Update the module docstring `hook_type` line**

Find:
```python
# hook_type: None | "wg_antizapret" | "wg_vpn" | "doall" | "restart_antizapret" | "wg_antizapret_escape" | "wg_vpn_escape"
```

Replace `"wg_antizapret_escape"` with `"awg_antizapret_escape"` and `"wg_vpn_escape"` with `"awg_vpn_escape"`.

- [ ] **Step 5: Run tests — verify pass**

Run:
```bash
.venv/bin/python -m pytest ../../agent/tests/test_sync_agent.py -v -k "escape_paths_moved or escape_hooks_renamed"
```

Expected: 2 PASS.

- [ ] **Step 6: Commit**

```bash
git add agent/corpweb_sync_agent.py agent/tests/test_sync_agent.py
git commit -m "feat(agent): escape confs in /etc/amnezia/amneziawg/ with awg_* hooks"
```

---

### Task 4: Extract unified `apply_iface_conf(iface, flavor)` with up-or-sync branching

**Files:**
- Modify: `agent/corpweb_sync_agent.py`
- Test: `agent/tests/test_sync_agent.py`

- [ ] **Step 1: Write failing tests**

Append to `agent/tests/test_sync_agent.py`:

```python
class TestApplyIfaceConfBranching:
    """apply_iface_conf(iface, flavor) brings iface up if down, syncs if up."""

    def test_up_branch_called_when_iface_down_wg(self):
        with patch("corpweb_sync_agent._iface_is_up", return_value=False), \
             patch("corpweb_sync_agent.subprocess.run") as mock_run:
            mock_run.return_value = MagicMock(returncode=0, stderr="")
            agent.apply_iface_conf("antizapret", "wg")
            # must call systemctl start wg-quick@antizapret.service
            assert any(
                "systemctl" in " ".join(call.args[0]) and "wg-quick@antizapret.service" in " ".join(call.args[0])
                for call in mock_run.call_args_list
            ), f"expected systemctl start wg-quick@antizapret.service, got {mock_run.call_args_list}"

    def test_sync_branch_called_when_iface_up_wg(self):
        with patch("corpweb_sync_agent._iface_is_up", return_value=True), \
             patch("corpweb_sync_agent.subprocess.run") as mock_run:
            mock_run.return_value = MagicMock(returncode=0, stderr="")
            agent.apply_iface_conf("antizapret", "wg")
            joined = " ".join(call.args[0] if isinstance(call.args[0], list) else [str(call.args[0])]
                              for call in mock_run.call_args_list)
            assert "syncconf" in joined or "wg syncconf antizapret" in joined

    def test_up_branch_uses_awg_quick_for_awg_flavor(self):
        with patch("corpweb_sync_agent._iface_is_up", return_value=False), \
             patch("corpweb_sync_agent.subprocess.run") as mock_run:
            mock_run.return_value = MagicMock(returncode=0, stderr="")
            agent.apply_iface_conf("vpn_escape", "awg")
            assert any(
                "awg-quick@vpn_escape.service" in " ".join(call.args[0])
                for call in mock_run.call_args_list
            )

    def test_sync_branch_uses_awg_binary_for_awg_flavor(self):
        with patch("corpweb_sync_agent._iface_is_up", return_value=True), \
             patch("corpweb_sync_agent.subprocess.run") as mock_run:
            mock_run.return_value = MagicMock(returncode=0, stderr="")
            agent.apply_iface_conf("vpn_escape", "awg")
            # The bash -c invocation should reference awg, not wg
            calls_text = " ".join(
                " ".join(c.args[0]) if isinstance(c.args[0], list) else str(c.args[0])
                for c in mock_run.call_args_list
            )
            assert "awg syncconf vpn_escape" in calls_text
            assert "awg-quick strip vpn_escape" in calls_text


class TestIfaceIsUp:
    def test_returns_true_when_ip_link_show_succeeds(self):
        with patch("corpweb_sync_agent.subprocess.run") as mock_run:
            mock_run.return_value = MagicMock(returncode=0)
            assert agent._iface_is_up("antizapret") is True

    def test_returns_false_when_ip_link_show_fails(self):
        with patch("corpweb_sync_agent.subprocess.run") as mock_run:
            mock_run.return_value = MagicMock(returncode=1)
            assert agent._iface_is_up("antizapret") is False
```

- [ ] **Step 2: Run tests — verify they fail**

Run:
```bash
cd /home/brolin/Documents/ITSS/AdminAZWG/CorpAdmin-AZ/corpweb/backend
.venv/bin/python -m pytest ../../agent/tests/test_sync_agent.py -v -k "TestApplyIfaceConfBranching or TestIfaceIsUp"
```

Expected: 6 FAILs with `AttributeError: module 'corpweb_sync_agent' has no attribute 'apply_iface_conf'` / `_iface_is_up`.

- [ ] **Step 3: Implement `_iface_is_up` and `apply_iface_conf`**

In `agent/corpweb_sync_agent.py`, add after the existing `apply_wg_syncconf` function:

```python
def _iface_is_up(iface: str) -> bool:
    """Return True if the network iface currently exists in the kernel."""
    try:
        result = subprocess.run(
            ["ip", "link", "show", iface],
            capture_output=True,
            text=True,
        )
        return result.returncode == 0
    except FileNotFoundError:
        return False


def apply_iface_conf(iface: str, flavor: str) -> None:
    """
    Bring iface up (if it doesn't exist yet) or syncconf it (if it already
    runs). ``flavor`` selects the tool pair:
        "wg"  → wg-quick / wg
        "awg" → awg-quick / awg
    """
    if flavor == "awg":
        tool, quick = "awg", "awg-quick"
    else:
        tool, quick = "wg", "wg-quick"

    unit = f"{quick}@{iface}.service"

    if not _iface_is_up(iface):
        log.info("Starting %s", unit)
        try:
            subprocess.run(
                ["systemctl", "start", unit],
                check=True,
                capture_output=True,
                text=True,
            )
        except subprocess.CalledProcessError as exc:
            log.error("systemctl start %s failed (rc=%d): %s",
                      unit, exc.returncode, exc.stderr.strip())
        return

    cmd = f"{tool} syncconf {iface} <({quick} strip {iface})"
    log.info("Running: bash -c %r", cmd)
    try:
        subprocess.run(
            ["bash", "-c", cmd],
            check=True,
            capture_output=True,
            text=True,
        )
    except subprocess.CalledProcessError as exc:
        log.error("%s syncconf %s failed (rc=%d): %s",
                  tool, iface, exc.returncode, exc.stderr.strip())
```

- [ ] **Step 4: Wire the new hooks in `apply_path` dispatch**

Find the `if hook == ... elif ...` block inside `apply_path`. Replace the existing escape-hook branches:

```python
    elif hook == "wg_antizapret_escape":
        apply_wg_syncconf("antizapret_escape")
    elif hook == "wg_vpn_escape":
        apply_wg_syncconf("vpn_escape")
```

with:

```python
    elif hook == "awg_antizapret_escape":
        apply_iface_conf("antizapret_escape", "awg")
    elif hook == "awg_vpn_escape":
        apply_iface_conf("vpn_escape", "awg")
```

Also replace the **base** iface branches to use the unified function (same behaviour, removes dead `apply_wg_syncconf`):

```python
    if hook == "wg_antizapret":
        apply_iface_conf("antizapret", "wg")
    elif hook == "wg_vpn":
        apply_iface_conf("vpn", "wg")
```

- [ ] **Step 5: Run the new tests — verify pass**

Run:
```bash
.venv/bin/python -m pytest ../../agent/tests/test_sync_agent.py -v -k "TestApplyIfaceConfBranching or TestIfaceIsUp"
```

Expected: 6 PASS.

- [ ] **Step 6: Run full agent suite to catch regressions**

```bash
.venv/bin/python -m pytest ../../agent/tests/ -v
```

If any pre-existing test relies on the old `apply_wg_syncconf` symbol directly, update it to patch `apply_iface_conf` instead.

- [ ] **Step 7: Commit**

```bash
git add agent/corpweb_sync_agent.py agent/tests/test_sync_agent.py
git commit -m "feat(agent): unified apply_iface_conf with up-or-sync branching"
```

---

### Task 5: `register_if_needed` writes keys only (no `systemctl start`)

**Files:**
- Modify: `agent/corpweb_sync_agent.py`
- Test: `agent/tests/test_sync_agent.py`

- [ ] **Step 1: Write failing tests**

Append to `agent/tests/test_sync_agent.py`:

```python
class TestRegisterIfNeededNoStart:
    """After the race fix, register_if_needed must not start wg-quick units."""

    def test_register_does_not_call_systemctl_start_when_keys_change(self, tmp_path):
        fake_response = MagicMock()
        fake_response.json.return_value = {
            "wg_server_keys": {
                "antizapret": {"private_key": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa=",
                               "public_key":  "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb="},
            },
            "wg_config": {},
        }
        with patch("corpweb_sync_agent.WG_KEY_DIR", str(tmp_path)), \
             patch("corpweb_sync_agent.api_post", return_value=fake_response), \
             patch("corpweb_sync_agent.subprocess.run") as mock_run:
            agent.register_if_needed()
            starts = [c for c in mock_run.call_args_list
                      if len(c.args) > 0 and isinstance(c.args[0], list)
                      and "systemctl" in c.args[0] and "start" in c.args[0]]
            assert starts == [], f"register_if_needed called systemctl start: {starts}"

    def test_register_does_not_call_systemctl_stop_when_keys_change(self, tmp_path):
        fake_response = MagicMock()
        fake_response.json.return_value = {
            "wg_server_keys": {
                "antizapret": {"private_key": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa=",
                               "public_key":  "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb="},
            },
            "wg_config": {},
        }
        with patch("corpweb_sync_agent.WG_KEY_DIR", str(tmp_path)), \
             patch("corpweb_sync_agent.api_post", return_value=fake_response), \
             patch("corpweb_sync_agent.subprocess.run") as mock_run:
            agent.register_if_needed()
            stops = [c for c in mock_run.call_args_list
                     if len(c.args) > 0 and isinstance(c.args[0], list)
                     and "systemctl" in c.args[0] and "stop" in c.args[0]]
            assert stops == []
```

- [ ] **Step 2: Run — verify fail**

```bash
.venv/bin/python -m pytest ../../agent/tests/test_sync_agent.py::TestRegisterIfNeededNoStart -v
```

Expected: 2 FAILs — assertions trigger because current code calls `systemctl stop/start`.

- [ ] **Step 3: Remove the `systemctl stop`/`start` block from `register_if_needed`**

In `agent/corpweb_sync_agent.py`, find the block inside `register_if_needed`:

```python
        if key_changed:
            # Fix permissions on private key
            try:
                os.chmod(priv_path, 0o600)
            except OSError:
                pass
            log.info("Keys changed for %s — restarting wg-quick@%s", iface, iface)
            for action in ("stop", "start"):
                try:
                    subprocess.run(
                        ["systemctl", action, f"wg-quick@{iface}.service"],
                        check=True,
                        capture_output=True,
                    )
                except subprocess.CalledProcessError as exc:
                    log.error(
                        "systemctl %s wg-quick@%s failed: %s",
                        action,
                        iface,
                        exc.stderr,
                    )
```

Replace with:

```python
        if key_changed:
            # Fix permissions on private key
            try:
                os.chmod(priv_path, 0o600)
            except OSError:
                pass
            log.info("Keys changed for %s — iface will be (re)started on next conf apply", iface)
```

That's it — no more start/stop. The iface is brought up by `apply_iface_conf` once its `.conf` blob arrives via SSE (or the startup reconcile).

- [ ] **Step 4: Run — verify pass**

```bash
.venv/bin/python -m pytest ../../agent/tests/test_sync_agent.py::TestRegisterIfNeededNoStart -v
```

Expected: 2 PASS.

- [ ] **Step 5: Full agent + backend suite**

```bash
.venv/bin/python -m pytest ../../agent/tests/ -v
.venv/bin/python -m pytest -q
```

Expected: all green (backend 304, agent ≥ 24 with new tests).

- [ ] **Step 6: Commit**

```bash
git add agent/corpweb_sync_agent.py agent/tests/test_sync_agent.py
git commit -m "fix(agent): register_if_needed writes keys only; iface start deferred to apply_path"
```

---

## Phase 3 — Backend: conf_path relocation + migration + regression tests

### Task 6: Update escape `conf_path` in `_IFACE_CONFIG`

**Files:**
- Modify: `corpweb/backend/app/services/vpn_manager_new.py`
- Test: `corpweb/backend/tests/test_vpn_manager_new.py`

- [ ] **Step 1: Write failing test**

Append to `tests/test_vpn_manager_new.py` (top-level, near the existing iface-config tests):

```python
def test_iface_config_escape_paths_moved_to_amneziawg_dir():
    from app.services.vpn_manager_new import _IFACE_CONFIG
    assert _IFACE_CONFIG["antizapret_escape"]["conf_path"] == \
        "/etc/amnezia/amneziawg/antizapret_escape.conf"
    assert _IFACE_CONFIG["vpn_escape"]["conf_path"] == \
        "/etc/amnezia/amneziawg/vpn_escape.conf"
```

- [ ] **Step 2: Run — verify fail**

```bash
cd /home/brolin/Documents/ITSS/AdminAZWG/CorpAdmin-AZ/corpweb/backend
.venv/bin/python -m pytest tests/test_vpn_manager_new.py::test_iface_config_escape_paths_moved_to_amneziawg_dir -v
```

Expected: FAIL — old path `/etc/wireguard/...`.

- [ ] **Step 3: Update `_IFACE_CONFIG`**

In `app/services/vpn_manager_new.py`, find:
```python
    "antizapret_escape": {
        "address": "10.27.8.1/21",
        "subnet": "10.27.8.0/21",
        "conf_path": "/etc/wireguard/antizapret_escape.conf",
    },
    "vpn_escape": {
        "address": "10.26.8.1/21",
        "subnet": "10.26.8.0/21",
        "conf_path": "/etc/wireguard/vpn_escape.conf",
    },
```

Replace the two `conf_path` lines with:

```python
        "conf_path": "/etc/amnezia/amneziawg/antizapret_escape.conf",
```

and

```python
        "conf_path": "/etc/amnezia/amneziawg/vpn_escape.conf",
```

respectively.

- [ ] **Step 4: Run — verify pass**

```bash
.venv/bin/python -m pytest tests/test_vpn_manager_new.py::test_iface_config_escape_paths_moved_to_amneziawg_dir -v
.venv/bin/python -m pytest tests/test_vpn_manager_new.py -q
```

Expected: target test PASS; full file green (bootstrap / add_peer / etc. use `cfg["conf_path"]` so they automatically follow the change).

- [ ] **Step 5: Commit**

```bash
git add corpweb/backend/app/services/vpn_manager_new.py corpweb/backend/tests/test_vpn_manager_new.py
git commit -m "feat(vpn_manager): escape conf_path lives in /etc/amnezia/amneziawg/"
```

---

### Task 7: Alembic migration 0006 — relocate paths in `wg_file_state`

**Files:**
- Create: `corpweb/backend/alembic/versions/0006_relocate_escape_confs.py`
- Test: `corpweb/backend/tests/test_migration_0006_relocate.py`

- [ ] **Step 1: Check current head**

```bash
cd /home/brolin/Documents/ITSS/AdminAZWG/CorpAdmin-AZ/corpweb/backend
.venv/bin/python -m alembic current
```

Expected: `0005 (head)`. If not 0005, adjust the `down_revision` below accordingly.

- [ ] **Step 2: Write failing test**

Create `tests/test_migration_0006_relocate.py`:

```python
"""Tests for the path-relocation logic used by alembic 0006."""
from sqlalchemy.orm import Session

from app.db.models import WgFileState


def _put(db, path, content=b"x"):
    import hashlib
    db.add(WgFileState(
        path=path, content=content,
        sha256=hashlib.sha256(content).hexdigest(),
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
```

- [ ] **Step 3: Run — verify fail**

```bash
.venv/bin/python -m pytest tests/test_migration_0006_relocate.py -v
```

Expected: FAIL — `ImportError: cannot import name 'relocate_escape_conf_paths'`.

- [ ] **Step 4: Implement `relocate_escape_conf_paths`**

Append to `app/services/vpn_manager_new.py`:

```python
def relocate_escape_conf_paths(db: Session) -> None:
    """
    Rename wg_file_state rows for escape ifaces from the /etc/wireguard/
    path to the /etc/amnezia/amneziawg/ path. Idempotent: if the target
    row already exists, delete the old (stale) source row without
    touching the target.
    """
    from app.db.models import WgFileState

    moves = [
        ("/etc/wireguard/antizapret_escape.conf",
         "/etc/amnezia/amneziawg/antizapret_escape.conf"),
        ("/etc/wireguard/vpn_escape.conf",
         "/etc/amnezia/amneziawg/vpn_escape.conf"),
    ]
    for old, new in moves:
        old_row = db.query(WgFileState).filter_by(path=old).one_or_none()
        if old_row is None:
            continue
        existing_new = db.query(WgFileState).filter_by(path=new).one_or_none()
        if existing_new is None:
            old_row.path = new
        else:
            db.delete(old_row)
    db.commit()
```

- [ ] **Step 5: Run — verify pass**

```bash
.venv/bin/python -m pytest tests/test_migration_0006_relocate.py -v
```

Expected: 2 PASS.

- [ ] **Step 6: Write the actual migration file**

Create `alembic/versions/0006_relocate_escape_confs.py`:

```python
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
```

- [ ] **Step 7: Dry-run migration against a scratch SQLite DB**

```bash
cd /home/brolin/Documents/ITSS/AdminAZWG/CorpAdmin-AZ/corpweb/backend
DATABASE_URL=sqlite:////tmp/alembic_0006_dry.db .venv/bin/python -c "
from app.db.session import engine
from app.db.base import Base
Base.metadata.create_all(bind=engine)
"
DATABASE_URL=sqlite:////tmp/alembic_0006_dry.db .venv/bin/python -m alembic stamp 0005
DATABASE_URL=sqlite:////tmp/alembic_0006_dry.db .venv/bin/python -m alembic upgrade head
DATABASE_URL=sqlite:////tmp/alembic_0006_dry.db .venv/bin/python -m alembic current
rm -f /tmp/alembic_0006_dry.db
```

Expected: `0006 (head)` in the final output.

- [ ] **Step 8: Commit**

```bash
git add -f corpweb/backend/alembic/versions/0006_relocate_escape_confs.py
git add corpweb/backend/app/services/vpn_manager_new.py corpweb/backend/tests/test_migration_0006_relocate.py
git commit -m "feat(db): migration 0006 + relocate_escape_conf_paths helper"
```

---

### Task 8: Regression tests — `delete_peer` on escape iface preserves AWG block

**Files:**
- Modify: `corpweb/backend/tests/test_vpn_manager_new.py`

- [ ] **Step 1: Write the failing-or-passing test (see notes below)**

Append to `tests/test_vpn_manager_new.py`:

```python
class TestDeletePeerEscapeRegression:
    """delete_peer on escape ifaces must not strip the [Interface] AWG block."""

    def test_delete_peer_preserves_awg_block_in_vpn_escape(self, db):
        from app.services.vpn_manager_new import vpn_manager
        from app.services.wg_blob_store import WgBlobStore

        vpn_manager.bootstrap(db)
        vpn_manager.add_peer(db, "erin")

        store = WgBlobStore(db)
        before = store.get("/etc/amnezia/amneziawg/vpn_escape.conf").decode()
        # sanity: peer is there
        assert "# Client = erin" in before
        # sanity: AWG fields present in Interface section
        for key in ("Jc", "Jmin", "Jmax", "S1", "S2", "H1", "H2", "H3", "H4"):
            assert f"{key} = " in before, f"AWG field {key} missing before delete"

        vpn_manager.delete_peer(db, "erin")

        after = store.get("/etc/amnezia/amneziawg/vpn_escape.conf").decode()
        assert "# Client = erin" not in after
        for key in ("Jc", "Jmin", "Jmax", "S1", "S2", "H1", "H2", "H3", "H4"):
            assert f"{key} = " in after, f"AWG field {key} lost after delete"

    def test_delete_peer_removes_from_all_four_ifaces(self, db):
        from app.services.vpn_manager_new import vpn_manager
        from app.services.wg_blob_store import WgBlobStore

        vpn_manager.bootstrap(db)
        vpn_manager.add_peer(db, "frank")
        vpn_manager.delete_peer(db, "frank")

        store = WgBlobStore(db)
        for path in (
            "/etc/wireguard/antizapret.conf",
            "/etc/wireguard/vpn.conf",
            "/etc/amnezia/amneziawg/antizapret_escape.conf",
            "/etc/amnezia/amneziawg/vpn_escape.conf",
        ):
            blob = store.get(path)
            assert blob is not None, f"{path} missing"
            assert "# Client = frank" not in blob.decode(), \
                f"peer still present in {path}"
```

*Note:* Phase 2 already iterates all four ifaces for `delete_peer`, so the
`_removes_from_all_four_ifaces` test is expected to PASS immediately. It
is a regression-locker, not a RED step. The `_preserves_awg_block` test
is also expected to PASS (Phase 2 threads `awg_params` through
`render_server_conf`); it's a regression-locker too.

- [ ] **Step 2: Run — verify pass**

```bash
.venv/bin/python -m pytest tests/test_vpn_manager_new.py::TestDeletePeerEscapeRegression -v
```

Expected: 2 PASS.

If either FAILS, STOP and investigate. That would mean Phase 2 code is
actually broken for escape ifaces, and the fix is a real bug fix, not a
regression-locker.

- [ ] **Step 3: Commit**

```bash
git add corpweb/backend/tests/test_vpn_manager_new.py
git commit -m "test(vpn_manager): regression — delete_peer preserves escape AWG block"
```

---

### Task 9: Regression tests — `disable_peer` / `enable_peer` involution on escape iface

**Files:**
- Modify: `corpweb/backend/tests/test_vpn_manager_new.py`

- [ ] **Step 1: Write the tests**

Append to `tests/test_vpn_manager_new.py`:

```python
class TestTogglePeerEscapeRegression:
    """Disable/enable must reverse [Peer] keys across all four ifaces without
    touching the AWG [Interface] block of escape ifaces."""

    def test_disable_reverses_keys_in_all_four_ifaces(self, db):
        from app.services.vpn_manager_new import vpn_manager
        from app.services.wg_blob_store import WgBlobStore
        from app.services.wg_templates import parse_peers

        vpn_manager.bootstrap(db)
        vpn_manager.add_peer(db, "george")

        store = WgBlobStore(db)
        paths = [
            "/etc/wireguard/antizapret.conf",
            "/etc/wireguard/vpn.conf",
            "/etc/amnezia/amneziawg/antizapret_escape.conf",
            "/etc/amnezia/amneziawg/vpn_escape.conf",
        ]
        before = {}
        for p in paths:
            peers = parse_peers(store.get(p).decode())
            mine = [pr for pr in peers if pr.name == "george"][0]
            before[p] = (mine.public_key, mine.preshared_key)

        vpn_manager.disable_peer(db, "george")

        for p in paths:
            peers = parse_peers(store.get(p).decode())
            mine = [pr for pr in peers if pr.name == "george"][0]
            assert mine.public_key != before[p][0], f"pubkey not reversed in {p}"
            assert mine.preshared_key != before[p][1], f"psk not reversed in {p}"

    def test_disable_preserves_awg_block_in_escape_confs(self, db):
        from app.services.vpn_manager_new import vpn_manager
        from app.services.wg_blob_store import WgBlobStore

        vpn_manager.bootstrap(db)
        vpn_manager.add_peer(db, "helen")

        store = WgBlobStore(db)
        for path in (
            "/etc/amnezia/amneziawg/antizapret_escape.conf",
            "/etc/amnezia/amneziawg/vpn_escape.conf",
        ):
            before = store.get(path).decode()
            awg_before = [ln for ln in before.splitlines()
                          if any(ln.strip().startswith(f"{k} = ")
                                 for k in ("Jc","Jmin","Jmax","S1","S2","H1","H2","H3","H4"))]

            vpn_manager.disable_peer(db, "helen")

            after = store.get(path).decode()
            awg_after = [ln for ln in after.splitlines()
                         if any(ln.strip().startswith(f"{k} = ")
                                for k in ("Jc","Jmin","Jmax","S1","S2","H1","H2","H3","H4"))]

            assert awg_before == awg_after, \
                f"AWG fields mutated in {path}\nbefore: {awg_before}\nafter: {awg_after}"

            vpn_manager.enable_peer(db, "helen")  # reset state for next iter

    def test_enable_is_self_inverse_of_disable(self, db):
        from app.services.vpn_manager_new import vpn_manager
        from app.services.wg_blob_store import WgBlobStore
        from app.services.wg_templates import parse_peers

        vpn_manager.bootstrap(db)
        vpn_manager.add_peer(db, "ivan")

        store = WgBlobStore(db)
        path = "/etc/amnezia/amneziawg/vpn_escape.conf"
        peers = parse_peers(store.get(path).decode())
        orig = [p for p in peers if p.name == "ivan"][0]
        orig_pub, orig_psk = orig.public_key, orig.preshared_key

        vpn_manager.disable_peer(db, "ivan")
        vpn_manager.enable_peer(db, "ivan")

        peers = parse_peers(store.get(path).decode())
        after = [p for p in peers if p.name == "ivan"][0]
        assert after.public_key == orig_pub
        assert after.preshared_key == orig_psk
```

- [ ] **Step 2: Run — verify pass**

```bash
.venv/bin/python -m pytest tests/test_vpn_manager_new.py::TestTogglePeerEscapeRegression -v
```

Expected: 3 PASS. Like Task 8, these are regression-lockers (Phase 2 code already does the right thing).

If any FAILS, STOP and investigate.

- [ ] **Step 3: Commit**

```bash
git add corpweb/backend/tests/test_vpn_manager_new.py
git commit -m "test(vpn_manager): regression — disable/enable preserve escape AWG block"
```

---

## Phase 4 — Deploy + smoke + README + close bug

### Task 10: Full test suite green before deploy

**Files:** none

- [ ] **Step 1: Run backend tests**

```bash
cd /home/brolin/Documents/ITSS/AdminAZWG/CorpAdmin-AZ/corpweb/backend
.venv/bin/python -m pytest -q
```

Expected: all green; count should be 303 (Phase 4 baseline) + 2 (Task 6) + 2 (Task 7) + 2 (Task 8) + 3 (Task 9) = 312.

- [ ] **Step 2: Run agent tests**

```bash
.venv/bin/python -m pytest ../../agent/tests/ -q
```

Expected: all green; 16 baseline + 2 (Task 3) + 6 (Task 4) + 2 (Task 5) = 26.

- [ ] **Step 3: Frontend build sanity**

```bash
cd /home/brolin/Documents/ITSS/AdminAZWG/CorpAdmin-AZ/corpweb/frontend
npm run build 2>&1 | tail -5
```

Expected: `✓ built in ...`, no TS errors. (This plan touches no frontend; this is a belt-and-braces check.)

No commit.

---

### Task 11: Push + deploy backend to CP

**Files:** none (operational)

- [ ] **Step 1: Push**

```bash
cd /home/brolin/Documents/ITSS/AdminAZWG/CorpAdmin-AZ
git push origin CorpAdmin
```

- [ ] **Step 2: Deploy on CP**

Upload deploy script:
```bash
ssh -p 2201 brolin@wgfi2.p4i.ru 'cat > /tmp/deploy-amneziawg-fix.sh' << 'DEPLOY_EOF'
#!/bin/bash
set -euo pipefail
cd /root/CorpAdmin-AZ
echo "── git pull ──"
git fetch origin CorpAdmin && git pull origin CorpAdmin
echo "HEAD: $(git rev-parse --short HEAD) — $(git log -1 --format=%s)"

echo "── backend app ──"
rm -rf /opt/corpweb/backend/app
cp -r corpweb/backend/app /opt/corpweb/backend/app

echo "── alembic upgrade (0006 path relocation) ──"
cd /opt/corpweb/backend
cp -r /root/CorpAdmin-AZ/corpweb/backend/alembic/versions/*.py alembic/versions/ 2>/dev/null || true
source venv/bin/activate
alembic upgrade head 2>&1 | tail -5

echo "── restart backend ──"
systemctl restart corpweb-backend
sleep 3
systemctl is-active corpweb-backend
journalctl -u corpweb-backend --since "30 sec ago" --no-pager --output=cat | tail -8
echo "── DONE ──"
DEPLOY_EOF
```

Run:
```bash
ssh -p 2201 brolin@wgfi2.p4i.ru 'su - -c "bash /tmp/deploy-amneziawg-fix.sh"' <<< '"rcnhfl1w2z'
```

Expected: migration `0006` applied, backend `active`, no errors in log.

- [ ] **Step 3: Verify wg_file_state paths relocated**

```bash
ssh -p 2201 brolin@wgfi2.p4i.ru 'su - -c "sudo -u postgres psql corpweb_db -tA -c \"SELECT path FROM wg_file_state WHERE path LIKE '\''/etc/%'\'' ORDER BY path\""' <<< '"rcnhfl1w2z'
```

Expected: 4 rows, 2 of them `/etc/amnezia/amneziawg/*_escape.conf`, 2 of them `/etc/wireguard/{antizapret,vpn}.conf`. No `/etc/wireguard/*_escape.conf`.

No commit.

---

### Task 12: Deploy new agent to wgfi2 and wgfi3

**Files:** none (operational)

- [ ] **Step 1: Upload agent to both nodes**

```bash
for host in wgfi2-ssh.p4i.ru wgfi3.p4i.ru; do
  echo "── uploading agent to $host ──"
  ssh -p 2201 brolin@$host 'cat > /tmp/corpweb_sync_agent.py' \
      < /home/brolin/Documents/ITSS/AdminAZWG/CorpAdmin-AZ/agent/corpweb_sync_agent.py
done
```

- [ ] **Step 2: Install + restart agent on each node**

```bash
for host in wgfi2-ssh.p4i.ru wgfi3.p4i.ru; do
  echo "======== $host ========"
  ssh -p 2201 brolin@$host "su - -c 'install -m 0755 -o root -g root /tmp/corpweb_sync_agent.py /usr/local/bin/corpweb-sync-agent.py && systemctl restart corpweb-sync-agent && sleep 4 && systemctl is-active corpweb-sync-agent && rm -f /tmp/corpweb_sync_agent.py'" <<< '"rcnhfl1w2z'
done
```

Expected on each: `active`.

- [ ] **Step 3: Verify escape ifaces come up**

```bash
for host in wgfi2-ssh.p4i.ru wgfi3.p4i.ru; do
  echo "======== $host ========"
  ssh -p 2201 brolin@$host "su - -c 'sleep 4 && ls -la /etc/amnezia/amneziawg/ 2>/dev/null; echo --- ; awg show all 2>&1 | head -30 ; echo --- ; systemctl is-active awg-quick@antizapret_escape awg-quick@vpn_escape 2>&1'" <<< '"rcnhfl1w2z'
done
```

Expected on each node: both `.conf` files present under `/etc/amnezia/amneziawg/`; `awg show all` lists `antizapret_escape` and `vpn_escape` with peer counts; both `awg-quick@*` units `active`.

- [ ] **Step 4: Cleanup stale confs under /etc/wireguard/ (spec D5 cleanup step)**

```bash
for host in wgfi2-ssh.p4i.ru wgfi3.p4i.ru; do
  ssh -p 2201 brolin@$host "su - -c 'rm -f /etc/wireguard/antizapret_escape.conf /etc/wireguard/vpn_escape.conf /etc/wireguard/antizapret_escape.key /etc/wireguard/antizapret_escape.key.pub /etc/wireguard/vpn_escape.key /etc/wireguard/vpn_escape.key.pub 2>/dev/null ; ls /etc/wireguard/*escape* 2>&1'" <<< '"rcnhfl1w2z'
done
```

Expected: `ls: cannot access '/etc/wireguard/*escape*': No such file or directory` on each node (cleanup complete).

No commit.

---

### Task 13: End-to-end smoke test

**Files:** none (operational)

- [ ] **Step 1: Flip `ESCAPE_ENABLED` via UI**

Log in to the CP panel as admin. Navigate to Настройки AntiZapret → section «Обход блокировки» → toggle ON. Confirm you see «Сохранено — балансировщик обновлён».

- [ ] **Step 2: Verify CP iptables gained DNAT for 500 + 53443**

```bash
ssh -p 2201 brolin@wgfi2.p4i.ru 'su - -c "iptables -t nat -L PREROUTING -n | grep -cE \"udp dpt:(500|53443)\""' <<< '"rcnhfl1w2z'
```

Expected: `4` (2 ports × 2 nodes).

- [ ] **Step 3: Create or pick a test user; in LK download a bypass conf**

In LK as a user with at least one AWG-VPN config:
1. Toggle «Обход блокировки» ON (upper right of configs grid).
2. Click «Скачать» on the AWG-VPN config.
3. Inspect the downloaded `.zip` → `.conf` must contain:
   - `Endpoint = <CP_HOST>:500`
   - `Jc = …`, `S1 = …`, `H1 = …` in `[Interface]` section.

- [ ] **Step 4: Install in AmneziaWG client and connect**

On your phone or desktop: import the conf, connect.
Expected: handshake completes; `curl ifconfig.me` inside VPN returns the CP's public egress IP.

- [ ] **Step 5: Regenerate obfuscation params and confirm old conf stops working**

In CP Admin panel: click «Перегенерировать параметры обфускации» → confirm.
Expected: existing client disconnects (handshake fails after keepalive).

Re-download fresh conf in LK → install → connects.

No commit.

---

### Task 14: Update README.md with amneziawg + escape-mode documentation

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Add amneziawg requirement to the "Как это работает" section**

Open `README.md`. Find the existing "Как это работает" bullet list (in the root or corpweb/README.md — whichever is the operator-facing doc in this repo). Append a new bullet:

```markdown
6. **AmneziaWG (опционально, для «Обход блокировки»)** — при первой установке
   агента (`agent/install.sh`) на ноду ставится пакет `amneziawg` + `amneziawg-tools`.
   Без него работает только базовый режим (ванильный WireGuard); усиленная
   обфускация ТСПУ-bypass требует amneziawg kernel-модуля и идёт через
   отдельные интерфейсы `antizapret_escape` / `vpn_escape`.
```

- [ ] **Step 2: Add a dedicated "Escape mode (bypass)" section**

Append to the end of `README.md`, before license:

```markdown
## Обход блокировки ТСПУ (escape-режим)

Отдельная пара AmneziaWG-интерфейсов на нодах (`antizapret_escape`, `vpn_escape`)
с усиленной обфускацией handshake — `S1`/`S2` > 0, кастомные `H1..H4`.
Используется, когда ТСПУ блокирует даже стандартный AWG-handshake.

**Админ-сторона (CP):**
1. Панель → Настройки AntiZapret → секция «Обход блокировки»
2. Тумблер `ESCAPE_ENABLED` — включает/выключает DNAT на CP для портов 500 (UDP)
   и 53443 (UDP). Интерфейсы на нодах живут всегда; тумблер управляет только
   доступностью извне.
3. Кнопка «Перегенерировать параметры обфускации» — пересоздаёт `S1/S2/H1..H4`
   в БД и пересобирает серверные конфиги. Все текущие escape-клиенты теряют
   связь до пересоздания конфига.

**Пользовательская сторона (ЛК):**
- Над карточками конфигов появляется блок «Опции скачивания»: один тумблер
  «Резервный порт» (540/580), другой — «Обход блокировки» (500/53443). Они
  взаимоисключающие; включённый «Обход блокировки» отключает «Резервный порт».
- Выбор применяется к последующим «Скачать» и «QR» — прошлые выданные конфиги
  не меняются.

**Порты:**
- `500/udp` — vpn_escape (мимикрия под IKE)
- `53443/udp` — antizapret_escape

**Требования на ноде:** `amneziawg` + `amneziawg-tools` (ставятся автоматически
`agent/install.sh` при первой регистрации ноды).

**Файлы на ноде:**
- `/etc/amnezia/amneziawg/antizapret_escape.conf`
- `/etc/amnezia/amneziawg/vpn_escape.conf`
- systemd-юниты `awg-quick@antizapret_escape.service`, `awg-quick@vpn_escape.service`
```

- [ ] **Step 3: Commit**

```bash
git add README.md
git commit -m "docs(readme): amneziawg requirement + escape-mode section"
```

- [ ] **Step 4: Push**

```bash
git push origin CorpAdmin
```

---

### Task 15: Close bug CorpAdmin-AZ-3qe and Phase 7 sub-task CorpAdmin-AZ-cpk

**Files:** none (operational)

- [ ] **Step 1: Close the bug**

```bash
bd close CorpAdmin-AZ-3qe --reason "Fixed. amneziawg installed on wgfi2+wgfi3; agent uses awg/awg-quick for escape ifaces at /etc/amnezia/amneziawg/; register_if_needed defers iface-up to apply_path; alembic 0006 relocated wg_file_state paths; 5 regression tests locked in delete/disable/enable behavior for escape ifaces. End-to-end smoke: handshake via :500 + :53443, regeneration invalidation, toggle on/off all verified. README updated."
```

- [ ] **Step 2: Close Phase 7 sub-task**

```bash
bd close CorpAdmin-AZ-cpk --reason "Phase 7 deploy complete after CorpAdmin-AZ-3qe fix. CP running new backend (migrations through 0006); both nodes on new agent with amneziawg; escape ifaces up; DNAT for 500/53443 applied when ESCAPE_ENABLED=true. README updated with operator docs. End-to-end smoke green."
```

- [ ] **Step 3: Close the parent epic**

```bash
bd close CorpAdmin-AZ-roo --reason "AWG strong-obfuscation escape feature shipped. All 7 phases + amneziawg fix delivered. Deployed to production. Smoke tests pass end-to-end."
```

- [ ] **Step 4: Final verification**

```bash
bd list --status=open | head -10
git log --oneline origin/main..HEAD | head -20
```

Expected: no open issues related to this epic; the final commit log shows all phases.

No more commits.

---

## Self-review

**Spec coverage:**
- D1 (agent/install.sh only) → Task 1, Task 2 (manual one-shot on existing nodes). ✓
- D2 (awg + /etc/amnezia/amneziawg) → Task 3 (agent paths/hooks), Task 4 (apply_iface_conf flavor branching), Task 6 (backend conf_path). ✓
- D3 (lazy iface-up in apply_path) → Task 4 (up-or-sync), Task 5 (register_if_needed no-start). ✓
- D4 (delete/disable/enable regression tests) → Task 8, Task 9. ✓
- D5 (alembic 0006 path relocation + cleanup) → Task 7 (migration), Task 12 Step 4 (stale /etc/wireguard cleanup). ✓
- D6 (README) → Task 14. ✓

**Placeholder scan:** no "TBD", "implement later", or open-ended steps. All code blocks are complete; all commands have expected output. ✓

**Type / name consistency:**
- `apply_iface_conf(iface, flavor)` signature used identically in Tasks 4 (def) and later references. ✓
- `_iface_is_up(iface)` used in Task 4 def + tests. ✓
- `relocate_escape_conf_paths(db)` named the same in Task 7 def + alembic + test import. ✓
- `awg_antizapret_escape` / `awg_vpn_escape` hook names consistent across Tasks 3 and 4. ✓
- `/etc/amnezia/amneziawg/` path consistent across agent (Task 3), backend (Task 6), migration (Task 7), regression tests (Tasks 8–9), deploy verification (Task 11 Step 3, Task 12 Step 3). ✓

No gaps found.

## Execution handoff

Plan complete and saved to `docs/superpowers/plans/2026-04-22-awg-amneziawg-and-agent-race-fix.md`. Two execution options:

1. **Subagent-Driven (recommended)** — fresh subagent per phase, review between phases, fast iteration.
2. **Inline Execution** — execute in this session with checkpoints per phase.

Which approach?
