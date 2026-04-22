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
