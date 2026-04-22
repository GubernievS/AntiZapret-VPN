"""Tests for corpweb_sync_agent.

Focus: the restart_antizapret hook. Settings in /root/antizapret/setup
(e.g. WIREGUARD_BACKUP) only take effect when antizapret.service is
restarted, because up.sh installs iptables rules at service start.
Previously the agent wrote the file but did not trigger a restart.
"""
from __future__ import annotations

import pathlib
import sys
from unittest.mock import MagicMock, patch

import pytest

# Make the agent package importable (agent/ is a sibling of tests/)
sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent.parent))

import corpweb_sync_agent as agent  # noqa: E402


@pytest.fixture(autouse=True)
def reset_timers():
    """Ensure global debounce timer state is clean between tests."""
    agent._doall_timer = None
    if hasattr(agent, "_restart_antizapret_timer"):
        agent._restart_antizapret_timer = None
    yield
    agent._doall_timer = None
    if hasattr(agent, "_restart_antizapret_timer"):
        agent._restart_antizapret_timer = None


class TestManagedFilesWiring:
    def test_setup_file_has_restart_antizapret_hook(self):
        mapping = dict(agent.MANAGED_FILES)
        assert mapping["/root/antizapret/setup"] == "restart_antizapret"

    def test_managed_files_includes_escape_ifaces(self):
        mapping = dict(agent.MANAGED_FILES)
        assert mapping["/etc/amnezia/amneziawg/az_escape.conf"] == "awg_az_escape"
        assert mapping["/etc/amnezia/amneziawg/vpn_escape.conf"] == "awg_vpn_escape"

    def test_escape_paths_moved_to_amneziawg_dir(self):
        mapping = dict(agent.MANAGED_FILES)
        assert "/etc/amnezia/amneziawg/az_escape.conf" in mapping
        assert "/etc/amnezia/amneziawg/vpn_escape.conf" in mapping
        # old /etc/wireguard/*_escape.conf paths must be gone
        assert "/etc/wireguard/az_escape.conf" not in mapping
        assert "/etc/wireguard/vpn_escape.conf" not in mapping

    def test_escape_hooks_renamed_to_awg_prefix(self):
        mapping = dict(agent.MANAGED_FILES)
        assert mapping["/etc/amnezia/amneziawg/az_escape.conf"] == "awg_az_escape"
        assert mapping["/etc/amnezia/amneziawg/vpn_escape.conf"] == "awg_vpn_escape"


class TestRunRestartAntizapret:
    def test_invokes_systemctl_restart(self):
        with patch("corpweb_sync_agent.subprocess.run") as mock_run:
            mock_run.return_value = MagicMock(returncode=0, stderr="")
            agent._run_restart_antizapret()
            assert mock_run.call_count == 1
            cmd = mock_run.call_args[0][0]
            assert cmd == ["systemctl", "restart", "antizapret.service"]

    def test_swallows_non_zero_exit(self):
        import subprocess as sp
        with patch("corpweb_sync_agent.subprocess.run") as mock_run:
            mock_run.side_effect = sp.CalledProcessError(
                returncode=1, cmd=[], stderr="unit not found"
            )
            agent._run_restart_antizapret()

    def test_swallows_missing_systemctl(self):
        with patch("corpweb_sync_agent.subprocess.run") as mock_run:
            mock_run.side_effect = FileNotFoundError()
            agent._run_restart_antizapret()


class TestScheduleRestartAntizapretDebounce:
    def test_single_call_starts_timer(self):
        with patch("corpweb_sync_agent.threading.Timer") as MockTimer:
            t = MagicMock()
            MockTimer.return_value = t
            agent.schedule_restart_antizapret()
            MockTimer.assert_called_once()
            t.start.assert_called_once()

    def test_second_call_cancels_first_timer(self):
        with patch("corpweb_sync_agent.threading.Timer") as MockTimer:
            t1 = MagicMock()
            t2 = MagicMock()
            MockTimer.side_effect = [t1, t2]
            agent.schedule_restart_antizapret()
            agent.schedule_restart_antizapret()
            t1.cancel.assert_called_once()
            t2.start.assert_called_once()


class TestApplyPathDispatch:
    def test_restart_antizapret_hook_schedules_restart(self, tmp_path):
        target = tmp_path / "setup"
        with patch("corpweb_sync_agent.schedule_restart_antizapret") as sched:
            changed = agent.apply_path(
                str(target),
                b"WIREGUARD_BACKUP=y\n",
                "restart_antizapret",
            )
        assert changed is True
        sched.assert_called_once()

    def test_unchanged_content_does_not_schedule_restart(self, tmp_path):
        target = tmp_path / "setup"
        content = b"WIREGUARD_BACKUP=y\n"
        target.write_bytes(content)
        with patch("corpweb_sync_agent.schedule_restart_antizapret") as sched:
            changed = agent.apply_path(str(target), content, "restart_antizapret")
        assert changed is False
        sched.assert_not_called()

    def test_apply_path_dispatches_awg_az_escape(self, tmp_path):
        target = tmp_path / "az_escape.conf"
        with patch("corpweb_sync_agent.apply_iface_conf") as m:
            changed = agent.apply_path(
                str(target),
                b"[Interface]\n",
                "awg_az_escape",
            )
        assert changed is True
        m.assert_called_once_with("az_escape", "awg")

    def test_apply_path_dispatches_awg_vpn_escape(self, tmp_path):
        target = tmp_path / "vpn_escape.conf"
        with patch("corpweb_sync_agent.apply_iface_conf") as m:
            changed = agent.apply_path(
                str(target),
                b"[Interface]\n",
                "awg_vpn_escape",
            )
        assert changed is True
        m.assert_called_once_with("vpn_escape", "awg")

    def test_unchanged_content_does_not_sync_awg_az_escape(self, tmp_path):
        target = tmp_path / "az_escape.conf"
        content = b"[Interface]\n"
        target.write_bytes(content)
        with patch("corpweb_sync_agent.apply_iface_conf") as m:
            changed = agent.apply_path(str(target), content, "awg_az_escape")
        assert changed is False
        m.assert_not_called()

    def test_unchanged_content_does_not_sync_awg_vpn_escape(self, tmp_path):
        target = tmp_path / "vpn_escape.conf"
        content = b"[Interface]\n"
        target.write_bytes(content)
        with patch("corpweb_sync_agent.apply_iface_conf") as m:
            changed = agent.apply_path(str(target), content, "awg_vpn_escape")
        assert changed is False
        m.assert_not_called()


class TestApplyWgConfigEscapeIfaces:
    """_apply_wg_config patches [Interface] Address/ListenPort in escape confs.

    The agent hardcodes /etc/wireguard/* paths. To exercise the helper in a
    unit test we redirect every relevant filesystem call through a tmpdir
    using a small "path mapping" patcher.
    """

    _INITIAL_CONF = (
        "[Interface]\n"
        "PrivateKey = FAKE\n"
        "Address = 0.0.0.0/32\n"
        "ListenPort = 0\n"
    )

    @staticmethod
    def _redirect(path_map: dict, real_open):
        """Build (fake_open, fake_exists, fake_write_atomic) tuple."""
        def fake_open(path, *a, **kw):
            return real_open(path_map.get(path, path), *a, **kw)

        def fake_exists(path):
            return path in path_map

        def fake_write_atomic(path, content):
            with real_open(path_map.get(path, path), "wb") as fh:
                fh.write(content)

        return fake_open, fake_exists, fake_write_atomic

    def test_patches_az_escape_address_and_port(self, tmp_path):
        conf = tmp_path / "az_escape.conf"
        conf.write_text(self._INITIAL_CONF)
        path_map = {"/etc/amnezia/amneziawg/az_escape.conf": str(conf)}
        real_open = open
        fake_open, fake_exists, fake_write_atomic = self._redirect(path_map, real_open)

        with patch("corpweb_sync_agent.os.path.exists", side_effect=fake_exists), \
             patch("builtins.open", side_effect=fake_open), \
             patch("corpweb_sync_agent.write_atomic", side_effect=fake_write_atomic):
            agent._apply_wg_config({
                "az_escape_address": "10.27.8.1/21",
                "az_escape_listen_port": 53443,
            })

        updated = conf.read_text()
        assert "Address = 10.27.8.1/21" in updated
        assert "ListenPort = 53443" in updated

    def test_patches_vpn_escape_address_and_port(self, tmp_path):
        conf = tmp_path / "vpn_escape.conf"
        conf.write_text(self._INITIAL_CONF)
        path_map = {"/etc/amnezia/amneziawg/vpn_escape.conf": str(conf)}
        real_open = open
        fake_open, fake_exists, fake_write_atomic = self._redirect(path_map, real_open)

        with patch("corpweb_sync_agent.os.path.exists", side_effect=fake_exists), \
             patch("builtins.open", side_effect=fake_open), \
             patch("corpweb_sync_agent.write_atomic", side_effect=fake_write_atomic):
            agent._apply_wg_config({
                "vpn_escape_address": "10.26.8.1/21",
                "vpn_escape_listen_port": 500,
            })

        updated = conf.read_text()
        assert "Address = 10.26.8.1/21" in updated
        assert "ListenPort = 500" in updated

    def test_patches_all_four_ifaces_when_all_present(self, tmp_path):
        """Regression: the existing antizapret/vpn patching still works with
        the extended iface_map, and the escape entries are no-ops when the
        conf files don't exist (simulating a node mid-rollout)."""
        az = tmp_path / "antizapret.conf"
        vpn = tmp_path / "vpn.conf"
        az.write_text(self._INITIAL_CONF)
        vpn.write_text(self._INITIAL_CONF)
        path_map = {
            "/etc/wireguard/antizapret.conf": str(az),
            "/etc/wireguard/vpn.conf": str(vpn),
        }
        real_open = open
        fake_open, fake_exists, fake_write_atomic = self._redirect(path_map, real_open)

        with patch("corpweb_sync_agent.os.path.exists", side_effect=fake_exists), \
             patch("builtins.open", side_effect=fake_open), \
             patch("corpweb_sync_agent.write_atomic", side_effect=fake_write_atomic):
            agent._apply_wg_config({
                "antizapret_address": "10.29.8.1/21",
                "antizapret_listen_port": 51443,
                "vpn_address": "10.28.8.1/21",
                "vpn_listen_port": 51080,
                "az_escape_address": "10.27.8.1/21",
                "az_escape_listen_port": 53443,
                "vpn_escape_address": "10.26.8.1/21",
                "vpn_escape_listen_port": 500,
            })

        assert "Address = 10.29.8.1/21" in az.read_text()
        assert "ListenPort = 51443" in az.read_text()
        assert "Address = 10.28.8.1/21" in vpn.read_text()
        assert "ListenPort = 51080" in vpn.read_text()


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
            joined = " ".join(
                " ".join(c.args[0]) if isinstance(c.args[0], list) else str(c.args[0])
                for c in mock_run.call_args_list
            )
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
