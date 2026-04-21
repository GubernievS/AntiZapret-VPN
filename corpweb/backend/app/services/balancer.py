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

#: Ports always active — 4 primary (awg/wg × antizapret/vpn) + 2 backup (540/580).
BASE_PORTS = [51443, 51080, 52443, 52080, 540, 580]

#: Extra escape-mode ports, appended only when ``escape_enabled=True``:
#:   500    → vpn_escape (IKE mimicry)
#:   53443  → antizapret_escape
ESCAPE_PORTS = [500, 53443]

#: Legacy alias kept for callers that predate the escape feature.
DEFAULT_PORTS = BASE_PORTS


def get_active_ports(escape_enabled: bool) -> list[int]:
    """
    Return the list of UDP ports that must currently carry DNAT rules.

    Always includes :data:`BASE_PORTS`. When *escape_enabled* is True,
    :data:`ESCAPE_PORTS` are appended (500 and 53443).
    """
    return BASE_PORTS + (ESCAPE_PORTS if escape_enabled else [])


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


def needs_reconcile(
    live_ports: set[int],
    has_nodes: bool,
    escape_enabled: bool = False,
) -> bool:
    """
    Return True if live iptables is missing any required port
    (:func:`get_active_ports`) and there are nodes to balance across.

    Used on backend startup to self-heal after a code upgrade or after an
    admin toggles ``escape_enabled``: without this the operator has to
    manually click "Save" in the UI for new ports to appear in iptables.
    """
    if not has_nodes:
        return False
    required = set(get_active_ports(escape_enabled))
    return not required.issubset(live_ports)


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


def apply_rules(
    nodes: list[dict],
    cp_ip: str,
    escape_enabled: bool = False,
) -> dict:
    """
    Apply DNAT + SNAT rules safely using flush + add (NOT iptables-restore).

    iptables-restore replaces the ENTIRE nat table which destroys other
    chains (INPUT/OUTPUT) and any non-balancer rules. Instead we only
    flush PREROUTING and POSTROUTING, then add our rules back.

    Steps:
    1. Flush PREROUTING chain (removes old DNAT rules).
    2. Add new DNAT rules.
    3. Flush POSTROUTING chain (removes old SNAT rules).
    4. Add SNAT rules with -d filter (ONLY for traffic to nodes).
    5. Persist with netfilter-persistent save.
    6. Return current state.

    ``cp_ip`` is the control-plane's own IP for SNAT source.
    ``escape_enabled`` toggles the two escape-mode ports (500 / 53443).
    """
    ports = get_active_ports(escape_enabled)
    dnat_rules = generate_iptables_rules(nodes, ports=ports)
    enabled_ips = {n["ip"] for n in nodes if n.get("enabled")}

    # 1. Flush PREROUTING
    _run(["iptables", "-t", "nat", "-F", "PREROUTING"])

    # 2. Add DNAT rules
    for rule in dnat_rules:
        # rule is like "-A PREROUTING -p udp --dport 51443 ... -j DNAT --to-destination IP:PORT"
        args = rule.split()
        # Remove leading "-A PREROUTING" — we'll use iptables -t nat -A PREROUTING
        if args[0] == "-A" and args[1] == "PREROUTING":
            args = args[2:]
        _run(["iptables", "-t", "nat", "-A", "PREROUTING"] + args)

    # 3. Flush POSTROUTING
    _run(["iptables", "-t", "nat", "-F", "POSTROUTING"])

    # 4. Add SNAT rules — one per node IP, with -d filter
    for ip in sorted(enabled_ips):
        _run([
            "iptables", "-t", "nat", "-A", "POSTROUTING",
            "-d", ip, "-j", "SNAT", "--to-source", cp_ip,
        ])

    # 5. Persist
    try:
        _run(["netfilter-persistent", "save"])
    except (subprocess.CalledProcessError, FileNotFoundError) as exc:
        logger.warning("netfilter-persistent save failed (non-fatal): %s", exc)

    return read_current_state()


def ensure_ports_reconciled(db) -> bool:
    """
    Self-heal entry point called from app startup.

    If live iptables is missing any ``DEFAULT_PORTS`` and the DB has at
    least one node, re-apply all DNAT/SNAT rules. Returns True if a
    reconcile was performed, False if no-op.

    This covers the case where ``DEFAULT_PORTS`` was extended in a code
    upgrade (e.g. adding WireGuard backup ports 540/580) — without it,
    the operator would have to click "Save" in the UI for the new ports
    to appear in iptables.
    """
    from app.db.models import Node, SystemSettings

    try:
        current = read_current_state()
    except Exception as exc:
        logger.warning("ensure_ports_reconciled: read_current_state failed: %s", exc)
        return False

    nodes = db.query(Node).all()
    settings = db.query(SystemSettings).filter(SystemSettings.id == 1).first()
    escape_enabled = bool(settings and getattr(settings, "escape_enabled", False))

    if not needs_reconcile(
        live_ports=_live_ports_from_state(current),
        has_nodes=bool(nodes),
        escape_enabled=escape_enabled,
    ):
        return False

    cp_ip = settings.cp_ip if settings else None
    if not cp_ip:
        logger.warning("ensure_ports_reconciled: cp_ip not set, skipping")
        return False

    payload = []
    for n in nodes:
        live = current.get(str(n.private_ip))
        payload.append({
            "ip": str(n.private_ip),
            "weight": live["weight"] if live else 50,
            "enabled": live["enabled"] if live else True,
        })

    active = get_active_ports(escape_enabled)
    logger.info(
        "ensure_ports_reconciled: reapplying DNAT (escape_enabled=%s, ports=%s)",
        escape_enabled, active,
    )
    apply_rules(payload, cp_ip, escape_enabled=escape_enabled)
    return True


def _live_ports_from_state(state: dict) -> set[int]:
    """Re-read iptables just to collect the set of dports currently in use."""
    try:
        result = _run(["iptables", "-t", "nat", "-L", "PREROUTING", "-n"])
    except Exception:
        return set()
    ports: set[int] = set()
    for line in result.stdout.splitlines():
        m = re.search(r"udp\s+dpt:(\d+)", line)
        if m:
            ports.add(int(m.group(1)))
    return ports
