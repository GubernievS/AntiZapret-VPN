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
        assert mapping["/etc/wireguard/antizapret_escape.conf"] == "wg_antizapret_escape"
        assert mapping["/etc/wireguard/vpn_escape.conf"] == "wg_vpn_escape"


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

    def test_apply_path_dispatches_wg_antizapret_escape(self, tmp_path):
        target = tmp_path / "antizapret_escape.conf"
        with patch("corpweb_sync_agent.apply_wg_syncconf") as m:
            changed = agent.apply_path(
                str(target),
                b"[Interface]\n",
                "wg_antizapret_escape",
            )
        assert changed is True
        m.assert_called_once_with("antizapret_escape")

    def test_apply_path_dispatches_wg_vpn_escape(self, tmp_path):
        target = tmp_path / "vpn_escape.conf"
        with patch("corpweb_sync_agent.apply_wg_syncconf") as m:
            changed = agent.apply_path(
                str(target),
                b"[Interface]\n",
                "wg_vpn_escape",
            )
        assert changed is True
        m.assert_called_once_with("vpn_escape")

    def test_unchanged_content_does_not_sync_wg_antizapret_escape(self, tmp_path):
        target = tmp_path / "antizapret_escape.conf"
        content = b"[Interface]\n"
        target.write_bytes(content)
        with patch("corpweb_sync_agent.apply_wg_syncconf") as m:
            changed = agent.apply_path(str(target), content, "wg_antizapret_escape")
        assert changed is False
        m.assert_not_called()

    def test_unchanged_content_does_not_sync_wg_vpn_escape(self, tmp_path):
        target = tmp_path / "vpn_escape.conf"
        content = b"[Interface]\n"
        target.write_bytes(content)
        with patch("corpweb_sync_agent.apply_wg_syncconf") as m:
            changed = agent.apply_path(str(target), content, "wg_vpn_escape")
        assert changed is False
        m.assert_not_called()
