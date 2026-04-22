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
