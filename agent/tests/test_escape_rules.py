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
