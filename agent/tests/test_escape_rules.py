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
