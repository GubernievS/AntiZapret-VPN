"""
Balancer service: iptables DNAT abstraction for load-balancing across nodes.

Pure functions (weights_to_probabilities, generate_iptables_rules,
parse_iptables_output) are kept side-effect-free for easy unit testing.
Functions that touch iptables/subprocess (apply_rules, read_current_state)
are kept separate and are not covered by unit tests.
"""
from __future__ import annotations

import re
import subprocess
import logging
from typing import Optional

logger = logging.getLogger(__name__)

DEFAULT_PORTS = [51443, 51080, 52443, 52080]


# ── Pure functions ────────────────────────────────────────────────────────────

def weights_to_probabilities(weights: list[int]) -> list[Optional[float]]:
    """
    Convert a list of integer weights into iptables --probability values.

    The last entry is always None (it acts as a fallback catch-all rule that
    requires no --probability flag).

    Formula (sequential application):
        prob[i] = weight[i] / sum(weight[i:])

    Example:
        [50, 30, 20] → [0.5, 0.6, None]
        [50, 50]     → [0.5, None]
        [100]        → [None]
    """
    probs: list[Optional[float]] = []
    n = len(weights)
    for i in range(n):
        if i == n - 1:
            probs.append(None)
        else:
            remaining = sum(weights[i:])
            if remaining == 0:
                probs.append(None)
            else:
                probs.append(weights[i] / remaining)
    return probs


def generate_iptables_rules(
    nodes: list[dict],
    ports: list[int] = None,
) -> list[str]:
    """
    Generate iptables DNAT PREROUTING rules for load-balancing UDP traffic.

    Only ``enabled`` nodes are included.  For each port, the last enabled
    node becomes the fallback (no --probability flag); all preceding nodes
    carry a probability calculated via :func:`weights_to_probabilities`.

    Returns a flat list of iptables rule strings (one per node per port),
    suitable for embedding in an iptables-restore script.
    """
    if ports is None:
        ports = DEFAULT_PORTS

    enabled_nodes = [n for n in nodes if n.get("enabled", False)]
    if not enabled_nodes:
        return []

    weights = [n["weight"] for n in enabled_nodes]
    probs = weights_to_probabilities(weights)

    rules: list[str] = []
    for port in ports:
        for node, prob in zip(enabled_nodes, probs):
            ip = node["ip"]
            if prob is not None:
                stat_part = f"-m statistic --mode random --probability {prob:.11f} "
            else:
                stat_part = ""
            rule = (
                f"-A PREROUTING -p udp --dport {port} "
                f"{stat_part}"
                f"-j DNAT --to-destination {ip}:{port}"
            )
            rules.append(rule)
    return rules


def parse_iptables_output(output: str) -> dict[str, dict]:
    """
    Parse the text output of ``iptables -t nat -L PREROUTING -n``.

    Extracts all DNAT rules, reverse-calculates weights from probability
    values, and returns a dict keyed by IP address:

        {
            "1.1.1.1": {"weight": 50, "enabled": True},
            "2.2.2.2": {"weight": 50, "enabled": True},
        }

    For rules without a probability (fallback / last node), the weight is
    derived from the remaining probability budget.

    Only the first port seen is used for weight reconstruction to avoid
    double-counting when multiple ports have identical rule sets.
    """
    # Match lines like:
    #   DNAT  17  --  0/0  0/0  udp dpt:PORT [statistic ... probability PROB] to:IP:PORT
    prob_pattern = re.compile(
        r"DNAT\s+\S+\s+--\s+\S+\s+\S+\s+udp\s+dpt:(\d+)"
        r"(?:\s+statistic\s+mode\s+random\s+probability\s+(\S+))?"
        r"\s+to:(\d+\.\d+\.\d+\.\d+):\d+"
    )

    # Group lines by port to reconstruct weights once per port group
    port_groups: dict[str, list[tuple[str, Optional[float]]]] = {}
    for line in output.splitlines():
        m = prob_pattern.search(line)
        if not m:
            continue
        port = m.group(1)
        prob_str = m.group(2)
        ip = m.group(3)
        prob = float(prob_str) if prob_str else None
        port_groups.setdefault(port, []).append((ip, prob))

    if not port_groups:
        return {}

    # Use only the first port group for weight reconstruction
    first_port = next(iter(port_groups))
    entries = port_groups[first_port]

    # Reverse-calculate weights from sequential probabilities
    # prob[i] = w[i] / sum(w[i:])  →  w[i] = prob[i] * sum(w[i:])
    # We work backwards: remaining starts at 100, each node's weight =
    # prob * remaining, then remaining -= weight.
    remaining = 100.0
    result: dict[str, dict] = {}
    for ip, prob in entries:
        if prob is None:
            # last node: consumes all remaining probability
            weight = remaining
        else:
            weight = prob * remaining
            remaining -= weight
        result[ip] = {"weight": round(weight), "enabled": True}

    return result


# ── Subprocess helpers (not unit-tested) ─────────────────────────────────────

def _run(cmd: list[str], input_data: str | None = None) -> subprocess.CompletedProcess:
    """Run a shell command, raise on non-zero exit."""
    return subprocess.run(
        cmd,
        input=input_data,
        text=True,
        capture_output=True,
        check=True,
    )


def read_current_state() -> dict:
    """
    Query live iptables state and return parsed weight map.

    Returns dict as produced by :func:`parse_iptables_output`.
    """
    result = _run(["iptables", "-t", "nat", "-L", "PREROUTING", "-n"])
    return parse_iptables_output(result.stdout)


def apply_rules(nodes: list[dict], cp_ip: str) -> dict:
    """
    Build an iptables-restore script for the nat table and apply it atomically.

    Steps:
    1. Build PREROUTING DNAT rules + POSTROUTING SNAT masquerade rule.
    2. Test with ``iptables-restore --test``.
    3. Apply with ``iptables-restore``.
    4. Persist with ``netfilter-persistent save``.
    5. Return current state via :func:`read_current_state`.

    ``cp_ip`` is the control-plane IP used for the POSTROUTING SNAT rule.
    """
    dnat_rules = generate_iptables_rules(nodes)

    lines = [
        "*nat",
        ":PREROUTING ACCEPT [0:0]",
        ":POSTROUTING ACCEPT [0:0]",
        ":OUTPUT ACCEPT [0:0]",
    ]
    lines.extend(dnat_rules)
    lines.append(
        f"-A POSTROUTING -j SNAT --to-source {cp_ip}"
    )
    lines.append("COMMIT")

    restore_input = "\n".join(lines) + "\n"

    # Dry-run first
    _run(["iptables-restore", "--test"], input_data=restore_input)

    # Apply
    _run(["iptables-restore"], input_data=restore_input)

    # Persist across reboots
    try:
        _run(["netfilter-persistent", "save"])
    except (subprocess.CalledProcessError, FileNotFoundError) as exc:
        logger.warning("netfilter-persistent save failed (non-fatal): %s", exc)

    return read_current_state()
