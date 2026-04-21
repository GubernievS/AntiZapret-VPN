"""
Tests for balancer pure functions (no subprocess/iptables calls).
"""
import pytest

from app.services.balancer import (
    weights_to_probabilities,
    generate_iptables_rules,
    parse_iptables_output,
    needs_reconcile,
    get_active_ports,
    BASE_PORTS,
    ESCAPE_PORTS,
    DEFAULT_PORTS,
)


# ── weights_to_probabilities ──────────────────────────────────────────────────

def test_weights_to_probabilities_two():
    assert weights_to_probabilities([50, 50]) == [0.5, None]


def test_weights_to_probabilities_three():
    probs = weights_to_probabilities([50, 30, 20])
    assert abs(probs[0] - 0.5) < 0.01
    assert abs(probs[1] - 0.6) < 0.01
    assert probs[2] is None


def test_weights_to_probabilities_single():
    assert weights_to_probabilities([100]) == [None]


def test_weights_to_probabilities_asymmetric():
    # [70, 30] → prob[0] = 70/100 = 0.7, prob[1] = None
    probs = weights_to_probabilities([70, 30])
    assert abs(probs[0] - 0.7) < 0.01
    assert probs[1] is None


def test_weights_to_probabilities_four():
    # [40, 30, 20, 10] →
    # prob[0] = 40/100 = 0.4
    # prob[1] = 30/60  = 0.5
    # prob[2] = 20/30  ≈ 0.667
    # prob[3] = None
    probs = weights_to_probabilities([40, 30, 20, 10])
    assert abs(probs[0] - 0.4) < 0.01
    assert abs(probs[1] - 0.5) < 0.01
    assert abs(probs[2] - (20 / 30)) < 0.01
    assert probs[3] is None


# ── generate_iptables_rules ───────────────────────────────────────────────────

def test_generate_rules_two_nodes():
    nodes = [
        {"ip": "1.1.1.1", "weight": 50, "enabled": True},
        {"ip": "2.2.2.2", "weight": 50, "enabled": True},
    ]
    rules = generate_iptables_rules(nodes, ports=[51443])
    assert len(rules) == 2
    assert "--probability" in rules[0]
    assert "--probability" not in rules[1]  # fallback
    assert "1.1.1.1:51443" in rules[0]
    assert "2.2.2.2:51443" in rules[1]


def test_generate_rules_disabled_node():
    nodes = [
        {"ip": "1.1.1.1", "weight": 100, "enabled": True},
        {"ip": "2.2.2.2", "weight": 0, "enabled": False},
    ]
    rules = generate_iptables_rules(nodes, ports=[51443])
    assert len(rules) == 1
    assert "2.2.2.2" not in rules[0]


def test_generate_rules_single_node_no_probability():
    nodes = [{"ip": "10.0.0.1", "weight": 100, "enabled": True}]
    rules = generate_iptables_rules(nodes, ports=[51443])
    assert len(rules) == 1
    assert "--probability" not in rules[0]
    assert "10.0.0.1:51443" in rules[0]


def test_generate_rules_default_ports():
    """Without explicit ports= argument, all six default ports are used."""
    nodes = [{"ip": "10.0.0.1", "weight": 100, "enabled": True}]
    rules = generate_iptables_rules(nodes)
    assert len(rules) == 6  # one per default port (4 primary + 2 backup)
    ports_in_rules = {"51443", "51080", "52443", "52080", "540", "580"}
    for port in ports_in_rules:
        assert any(f"--dport {port}" in r for r in rules)


def test_generate_rules_multiple_ports():
    nodes = [
        {"ip": "1.1.1.1", "weight": 50, "enabled": True},
        {"ip": "2.2.2.2", "weight": 50, "enabled": True},
    ]
    rules = generate_iptables_rules(nodes, ports=[51443, 51080])
    # 2 nodes × 2 ports = 4 rules
    assert len(rules) == 4


def test_generate_rules_protocol_and_action():
    nodes = [{"ip": "1.2.3.4", "weight": 100, "enabled": True}]
    rules = generate_iptables_rules(nodes, ports=[51443])
    assert "-A PREROUTING" in rules[0]
    assert "-p udp" in rules[0]
    assert "-j DNAT" in rules[0]
    assert "--to-destination 1.2.3.4:51443" in rules[0]


def test_generate_rules_all_disabled_returns_empty():
    nodes = [
        {"ip": "1.1.1.1", "weight": 0, "enabled": False},
    ]
    rules = generate_iptables_rules(nodes, ports=[51443])
    assert rules == []


# ── parse_iptables_output ─────────────────────────────────────────────────────

def test_parse_iptables_output():
    output = """\
Chain PREROUTING (policy ACCEPT)
target     prot opt source               destination
DNAT       17   --  0.0.0.0/0            0.0.0.0/0            udp dpt:51443 statistic mode random probability 0.50000000000 to:1.1.1.1:51443
DNAT       17   --  0.0.0.0/0            0.0.0.0/0            udp dpt:51443 to:2.2.2.2:51443"""
    result = parse_iptables_output(output)
    assert "1.1.1.1" in result
    assert "2.2.2.2" in result
    assert result["1.1.1.1"]["weight"] == 50
    assert result["2.2.2.2"]["weight"] == 50


def test_parse_iptables_output_single_node():
    """Single node = fallback, weight should be 100."""
    output = """\
Chain PREROUTING (policy ACCEPT)
target     prot opt source               destination
DNAT       17   --  0.0.0.0/0            0.0.0.0/0            udp dpt:51443 to:10.0.0.1:51443"""
    result = parse_iptables_output(output)
    assert "10.0.0.1" in result
    assert result["10.0.0.1"]["weight"] == 100
    assert result["10.0.0.1"]["enabled"] is True


def test_parse_iptables_output_empty():
    output = """\
Chain PREROUTING (policy ACCEPT)
target     prot opt source               destination"""
    result = parse_iptables_output(output)
    assert result == {}


def test_parse_iptables_output_three_nodes():
    """
    Three nodes with weights [50, 30, 20].
    probs = [0.5, 0.6, None]
    Reverse: w0=50, w1=30, w2=20 (total 100).
    """
    output = """\
Chain PREROUTING (policy ACCEPT)
target     prot opt source               destination
DNAT       17   --  0.0.0.0/0            0.0.0.0/0            udp dpt:51443 statistic mode random probability 0.50000000000 to:1.1.1.1:51443
DNAT       17   --  0.0.0.0/0            0.0.0.0/0            udp dpt:51443 statistic mode random probability 0.60000000000 to:2.2.2.2:51443
DNAT       17   --  0.0.0.0/0            0.0.0.0/0            udp dpt:51443 to:3.3.3.3:51443"""
    result = parse_iptables_output(output)
    assert abs(result["1.1.1.1"]["weight"] - 50) <= 1
    assert abs(result["2.2.2.2"]["weight"] - 30) <= 1
    assert abs(result["3.3.3.3"]["weight"] - 20) <= 1


# ── Safety checks ────────────────────────────────────────────────────────────


def test_default_ports_includes_backup():
    from app.services.balancer import DEFAULT_PORTS
    assert 540 in DEFAULT_PORTS
    assert 580 in DEFAULT_PORTS
    assert len(DEFAULT_PORTS) == 6


# ── get_active_ports ─────────────────────────────────────────────────────────

class TestActivePorts:
    """``get_active_ports(escape_enabled)`` decides which ports to DNAT."""

    def test_escape_disabled_returns_base_ports(self):
        assert get_active_ports(escape_enabled=False) == [
            51443, 51080, 52443, 52080, 540, 580,
        ]

    def test_escape_enabled_appends_escape_ports(self):
        got = get_active_ports(escape_enabled=True)
        assert 500 in got
        assert 53443 in got
        assert len(got) == 8

    def test_escape_enabled_preserves_base_ports(self):
        got = get_active_ports(escape_enabled=True)
        for port in (51443, 51080, 52443, 52080, 540, 580):
            assert port in got

    def test_default_ports_alias_equals_base_ports(self):
        """DEFAULT_PORTS kept as alias for BASE_PORTS (legacy callers)."""
        assert DEFAULT_PORTS == BASE_PORTS

    def test_escape_ports_constant(self):
        assert set(ESCAPE_PORTS) == {500, 53443}


# ── needs_reconcile ──────────────────────────────────────────────────────────

class TestNeedsReconcile:
    """Decide whether live iptables is missing any required ports."""

    def test_returns_true_when_no_live_rules(self):
        """Empty iptables → a reconcile is needed if DB has nodes."""
        assert needs_reconcile(
            live_ports=set(), has_nodes=True, escape_enabled=False,
        ) is True

    def test_returns_false_when_all_base_ports_present(self):
        assert needs_reconcile(
            live_ports=set(BASE_PORTS), has_nodes=True, escape_enabled=False,
        ) is False

    def test_returns_true_when_backup_ports_missing(self):
        """Old-style 4-port setup — needs reconcile to add 540/580."""
        old_ports = {51443, 51080, 52443, 52080}
        assert needs_reconcile(
            live_ports=old_ports, has_nodes=True, escape_enabled=False,
        ) is True

    def test_returns_true_when_one_port_missing(self):
        missing_one = set(BASE_PORTS) - {580}
        assert needs_reconcile(
            live_ports=missing_one, has_nodes=True, escape_enabled=False,
        ) is True

    def test_returns_false_when_no_nodes_in_db(self):
        """Nothing to reconcile if DB has no nodes (fresh install)."""
        assert needs_reconcile(
            live_ports=set(), has_nodes=False, escape_enabled=False,
        ) is False

    def test_extra_ports_in_live_do_not_trigger(self):
        """Presence of unrelated ports does not force a reconcile."""
        live = set(BASE_PORTS) | {12345}
        assert needs_reconcile(
            live_ports=live, has_nodes=True, escape_enabled=False,
        ) is False

    def test_default_escape_enabled_false(self):
        """Legacy callers (no escape_enabled kwarg) still work."""
        assert needs_reconcile(live_ports=set(BASE_PORTS), has_nodes=True) is False

    # ---- escape_enabled=True variants ----

    def test_returns_true_when_escape_ports_missing(self):
        """Escape on but 500/53443 missing → must reconcile."""
        assert needs_reconcile(
            live_ports=set(BASE_PORTS), has_nodes=True, escape_enabled=True,
        ) is True

    def test_returns_false_when_all_active_ports_present_with_escape(self):
        live = set(BASE_PORTS) | set(ESCAPE_PORTS)
        assert needs_reconcile(
            live_ports=live, has_nodes=True, escape_enabled=True,
        ) is False

    def test_returns_true_when_only_one_escape_port_present(self):
        live = set(BASE_PORTS) | {500}  # missing 53443
        assert needs_reconcile(
            live_ports=live, has_nodes=True, escape_enabled=True,
        ) is True

    def test_escape_disabled_ignores_extra_escape_ports(self):
        """Escape off: leftover 500/53443 entries don't force a reconcile."""
        live = set(BASE_PORTS) | set(ESCAPE_PORTS)
        assert needs_reconcile(
            live_ports=live, has_nodes=True, escape_enabled=False,
        ) is False


class TestRuleSafety:
    """Verify that generated rules cannot break general networking."""

    def test_dnat_rules_only_target_udp(self):
        """All DNAT rules must specify -p udp and a specific --dport."""
        nodes = [
            {"ip": "1.1.1.1", "weight": 50, "enabled": True},
            {"ip": "2.2.2.2", "weight": 50, "enabled": True},
        ]
        rules = generate_iptables_rules(nodes)
        for rule in rules:
            assert "-p udp" in rule, f"Rule missing -p udp: {rule}"
            assert "--dport" in rule, f"Rule missing --dport: {rule}"

    def test_dnat_rules_no_wildcard_snat(self):
        """DNAT rules must never contain SNAT or MASQUERADE."""
        nodes = [
            {"ip": "1.1.1.1", "weight": 50, "enabled": True},
            {"ip": "2.2.2.2", "weight": 50, "enabled": True},
        ]
        rules = generate_iptables_rules(nodes)
        for rule in rules:
            assert "SNAT" not in rule
            assert "MASQUERADE" not in rule

    def test_generate_rules_no_empty_destination(self):
        """Every rule must have a specific --to-destination with IP:port."""
        nodes = [
            {"ip": "10.0.0.1", "weight": 100, "enabled": True},
        ]
        rules = generate_iptables_rules(nodes)
        for rule in rules:
            assert "--to-destination 10.0.0.1:" in rule
