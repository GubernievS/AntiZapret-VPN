"""
Pure WireGuard config functions — no I/O, no DB, no subprocess.

All functions are deterministic transformations on WireGuard config text.
Used by WgBlobStore (Task 3) and vpn_manager refactor (Task 4).
"""
from __future__ import annotations

import base64
import ipaddress
from dataclasses import dataclass
from typing import List


# ---------------------------------------------------------------------------
# Data model
# ---------------------------------------------------------------------------

@dataclass
class Peer:
    name: str
    public_key: str
    preshared_key: str
    allowed_ips: str


# ---------------------------------------------------------------------------
# Port mapping
# ---------------------------------------------------------------------------

_PORT_MAP = {
    ("antizapret", "wg"):  51443,
    ("antizapret", "awg"): 52443,
    ("vpn", "wg"):         51080,
    ("vpn", "awg"):        52080,
    # Escape ifaces — awg-only, single port each.
    ("antizapret_escape", "awg"): 53443,
    ("vpn_escape", "awg"):        500,
}

_BACKUP_PORT_MAP = {
    "antizapret": 540,
    "vpn": 580,
}

# Escape port map (convenience lookup, same values as _PORT_MAP for "awg").
_ESCAPE_PORT_MAP = {
    "antizapret_escape": 53443,
    "vpn_escape": 500,
}


# ---------------------------------------------------------------------------
# AWG obfuscation constants
# ---------------------------------------------------------------------------

_AWG_OBFUSCATION = """\
Jc = 100
Jmin = 20
Jmax = 100
S1 = 0
S2 = 0
H1 = 1
H2 = 2
H3 = 3
H4 = 4"""

_AWG_I1 = (
    "<b 0xcc0000000108f2b74ee971b3056f088b3ae6000a58de5a004204815a27b9b61e"
    "68aeb17cd4575dc3c20de4f759f54827dae8ee806368fa5f77edd8723df36d83c607"
    "f0604901aa880869003dcfe7ea037f938192cd60cf254e0ff7a1a7adf1b88353afab"
    "896b617e30c2127af3ed035d586a1ea1d012a59e75539f7bf57f0b2639597415b4b9"
    "8c0a20814d6c94b72eb7c5f56e94b82ab05a31cdae3d84b82c3294d6bc5f872c809a"
    "1b44222511b4ac8cb5f3f6ab41ce5275ed440e6ef95fb2362bb7ce9840b9c4174bcbc"
    "420983bb6721249a32f59ebc5be129007b15101eeb6dfa094fb8966b83817ec8f494f"
    "30eb547a620e04d4d378fdec8f2df1313538d2d12ddb4d7cd7ab0bcc7931f3cfd0bfa"
    "3e663ec1f614e2292119bd5d3bf49813aad947e3f09703b0d9f9c214f408a55ffabe94"
    "120b78fa6ccad53960732c41732d4f7aadd85ab7bec6d5ed544f33feaef8ef52adf337"
    "c5d6dbdcbb3d619830d3480e4eaeff48d8984cfdc0606ab215f75babd5555a78d7a890"
    "a8a6f0dd1c06d6e0bb822e6fb3db59e6c981e67539f3251be0c803eb6b48473a5e2e50"
    "ea6e1d714979d4244f92d4a0231616b78c43242fee7e6761fe1df167e3c876fff9ffde"
    "223c36542bd4c52dd2dcc08bb7c9012efb9fdd82e78815fac3fa718e901910a3fba0516"
    "e4eae2cf79b8e090d5a5fae4099247fa6ac19617ae44f1350a72f06aeace0a68ea0f335"
    "ed02af771058f2ae957c725dfa3d6a609c96729764d611697>"
)


# ---------------------------------------------------------------------------
# Key operations
# ---------------------------------------------------------------------------

def reverse_key(key: str) -> str:
    """
    Reverse a WireGuard base64 key at the byte level.

    Decodes base64 -> reverses raw bytes -> re-encodes.
    Always produces valid base64 of the correct length.
    The operation is its own inverse: reverse_key(reverse_key(x)) == x.
    """
    try:
        raw = base64.b64decode(key)
        return base64.b64encode(raw[::-1]).decode()
    except Exception:
        # Fallback for keys reversed with old char-level method (invalid base64)
        stripped = key.rstrip("=")
        padding = key[len(stripped):]
        return stripped[::-1] + padding


def reverse_peer_keys(content: str, name: str) -> str:
    """
    Reverse PublicKey and PresharedKey values in the [Peer] block for *name*.

    Uses split('\\n') (not splitlines()) to preserve trailing newlines.
    The operation is its own inverse (involution).
    """
    lines = content.split("\n")
    result_lines: list[str] = []
    in_target_peer = False

    for line in lines:
        stripped = line.strip()

        # Detect "# Client = <name>" comment
        if stripped.startswith("# Client") and "=" in stripped:
            peer_name = stripped.split("=", 1)[1].strip()
            in_target_peer = peer_name == name

        # Detect start of a different peer block (reset flag)
        if stripped == "[Peer]" and not in_target_peer:
            in_target_peer = False

        # Reverse key values in the target peer block
        if in_target_peer and not stripped.startswith("#"):
            lower = stripped.lower()
            if lower.startswith("publickey") or lower.startswith("presharedkey"):
                key_part, sep, value = line.partition("=")
                if sep and value.strip():
                    reversed_val = reverse_key(value.strip())
                    result_lines.append(f"{key_part}= {reversed_val}")
                    continue

        result_lines.append(line)

    return "\n".join(result_lines)


# ---------------------------------------------------------------------------
# Parsing
# ---------------------------------------------------------------------------

def parse_peers(content: str) -> List[Peer]:
    """
    Parse all [Peer] blocks from a WireGuard server config.

    Each peer is preceded by a ``# Client = <name>`` comment.
    An optional ``# PrivateKey = ...`` comment may appear between the
    client comment and the ``[Peer]`` line.
    """
    peers: list[Peer] = []
    lines = content.split("\n")

    # pending_name: the name from the most recent "# Client = ..." comment,
    # not yet assigned to a [Peer] block.
    pending_name: str | None = None
    # active_name: the name of the [Peer] block currently being parsed.
    active_name: str | None = None
    current_pub: str | None = None
    current_psk: str | None = None
    current_ips: str | None = None
    in_peer = False

    def _flush() -> None:
        """Append the current peer to the list if valid."""
        nonlocal in_peer
        if in_peer and active_name is not None:
            peers.append(Peer(
                name=active_name,
                public_key=current_pub or "",
                preshared_key=current_psk or "",
                allowed_ips=current_ips or "",
            ))

    for line in lines:
        stripped = line.strip()

        # Detect "# Client = <name>" comment
        if stripped.startswith("# Client") and "=" in stripped:
            pending_name = stripped.split("=", 1)[1].strip()
            continue

        # Start of [Peer] block
        if stripped == "[Peer]":
            # Flush any previous peer
            _flush()
            # Begin new peer — assign pending name
            in_peer = True
            active_name = pending_name
            pending_name = None
            current_pub = None
            current_psk = None
            current_ips = None
            continue

        if not in_peer:
            continue

        # Skip comments inside peer block (e.g. # PrivateKey = ...)
        if stripped.startswith("#"):
            continue

        lower = stripped.lower()
        if lower.startswith("publickey") and "=" in stripped:
            current_pub = stripped.split("=", 1)[1].strip()
        elif lower.startswith("presharedkey") and "=" in stripped:
            current_psk = stripped.split("=", 1)[1].strip()
        elif lower.startswith("allowedips") and "=" in stripped:
            current_ips = stripped.split("=", 1)[1].strip()

    # Flush last peer
    _flush()

    return peers


# ---------------------------------------------------------------------------
# IP allocation
# ---------------------------------------------------------------------------

def next_free_ip(peers: List[Peer], subnet: str) -> str:
    """
    Return the first available client IP in *subnet*.

    .1 is reserved for the server; clients start at .2.
    Fills gaps (e.g. if .3 is unused, returns .3 before .5).
    """
    network = ipaddress.ip_network(subnet, strict=False)

    # Collect IPs already allocated to peers
    used: set[ipaddress.IPv4Address] = set()
    for peer in peers:
        ip_str = peer.allowed_ips.split("/")[0]
        try:
            used.add(ipaddress.IPv4Address(ip_str))
        except ValueError:
            continue

    # .0 is network, .1 is server — start at .2
    for addr in network.hosts():
        if addr == network.network_address + 1:
            continue  # skip .1 (server)
        if addr not in used:
            return str(addr)

    raise ValueError(f"No free IPs in {subnet}")


# ---------------------------------------------------------------------------
# Rendering
# ---------------------------------------------------------------------------

def render_server_conf(
    iface: str,
    peers: List[Peer],
    server_privkey: str,
    address: str,
    *,
    awg_params: dict | None = None,
) -> str:
    """
    Render a full WireGuard server config file.

    Args:
        iface: interface name ("antizapret", "vpn", "antizapret_escape", "vpn_escape").
        peers: list of Peer objects.
        server_privkey: server private key.
        address: server address with CIDR (e.g. "10.29.8.1/21").
        awg_params: optional dict with AmneziaWG obfuscation params
            (keys: jc, jmin, jmax, s1, s2, h1..h4, i1). When provided,
            an obfuscation block is appended to [Interface].
    """
    # Escape ifaces are awg-only; base ifaces use the legacy "wg" port in
    # the server config (the port that wg-quick actually binds).
    if iface in _ESCAPE_PORT_MAP:
        port = _ESCAPE_PORT_MAP[iface]
    else:
        port = _PORT_MAP[(iface, "wg")]

    lines = [
        "[Interface]",
        f"PrivateKey = {server_privkey}",
        f"Address = {address}",
        f"ListenPort = {port}",
    ]

    if awg_params:
        lines.append(f"Jc = {awg_params['jc']}")
        lines.append(f"Jmin = {awg_params['jmin']}")
        lines.append(f"Jmax = {awg_params['jmax']}")
        lines.append(f"S1 = {awg_params['s1']}")
        lines.append(f"S2 = {awg_params['s2']}")
        lines.append(f"H1 = {awg_params['h1']}")
        lines.append(f"H2 = {awg_params['h2']}")
        lines.append(f"H3 = {awg_params['h3']}")
        lines.append(f"H4 = {awg_params['h4']}")
        if awg_params.get("i1"):
            lines.append(f"I1 = {awg_params['i1']}")

    for peer in peers:
        lines.append("")
        lines.append(f"# Client = {peer.name}")
        lines.append("[Peer]")
        lines.append(f"PublicKey = {peer.public_key}")
        lines.append(f"PresharedKey = {peer.preshared_key}")
        lines.append(f"AllowedIPs = {peer.allowed_ips}")

    lines.append("")  # trailing newline
    return "\n".join(lines)


def render_client_conf(
    peer: Peer,
    iface: str,
    server_pubkey: str,
    endpoint_host: str,
    flavor: str,
    *,
    allowed_ips: str | None = None,
    client_private_key: str | None = None,
    use_backup_port: bool = False,
    awg_params: dict | None = None,
) -> str:
    """
    Render a WireGuard / AmneziaWG client config.

    Args:
        peer: Peer dataclass with client info.
        iface: "antizapret", "vpn", "antizapret_escape", or "vpn_escape".
        server_pubkey: server public key.
        endpoint_host: server hostname or IP.
        flavor: "wg" or "awg". Escape ifaces are always awg.
        allowed_ips: override AllowedIPs for antizapret (default: "10.29.8.0/24").
        client_private_key: if provided, embed the real key; otherwise use placeholder.
        use_backup_port: route via UDP 540/580 — only valid for base ifaces.
        awg_params: per-iface obfuscation dict (jc/jmin/jmax/s1/s2/h1..h4/i1).
            When provided, replaces the hardcoded legacy _AWG_OBFUSCATION /
            _AWG_I1 block with values rendered from the dict. Required in
            practice for escape ifaces (where they must match the server).
    """
    # Port lookup: escape ifaces have dedicated single ports, base ifaces
    # pick between flavored primary port and backup port.
    if iface in _ESCAPE_PORT_MAP:
        port = _ESCAPE_PORT_MAP[iface]
    elif use_backup_port:
        port = _BACKUP_PORT_MAP[iface]
    else:
        port = _PORT_MAP[(iface, flavor)]

    # Extract bare IP from allowed_ips (e.g. "10.29.8.2/32" -> "10.29.8.2")
    client_ip = peer.allowed_ips.split("/")[0]

    # PrivateKey line
    private_key_line = (
        f"PrivateKey = {client_private_key}"
        if client_private_key is not None
        else "PrivateKey = ${CLIENT_PRIVATE_KEY}"
    )

    # [Interface] section
    lines = [
        "[Interface]",
        private_key_line,
        f"Address = {client_ip}/32",
        "DNS = 10.29.8.1",
    ]

    # AWG obfuscation fields
    if flavor == "awg":
        if awg_params is not None:
            lines.append(f"Jc = {awg_params['jc']}")
            lines.append(f"Jmin = {awg_params['jmin']}")
            lines.append(f"Jmax = {awg_params['jmax']}")
            lines.append(f"S1 = {awg_params['s1']}")
            lines.append(f"S2 = {awg_params['s2']}")
            lines.append(f"H1 = {awg_params['h1']}")
            lines.append(f"H2 = {awg_params['h2']}")
            lines.append(f"H3 = {awg_params['h3']}")
            lines.append(f"H4 = {awg_params['h4']}")
            if awg_params.get("i1"):
                lines.append(f"I1 = {awg_params['i1']}")
        else:
            lines.append(_AWG_OBFUSCATION)
            lines.append(f"I1 = {_AWG_I1}")

    # [Peer] section
    lines.append("")
    lines.append("[Peer]")
    lines.append(f"PublicKey = {server_pubkey}")
    lines.append(f"PresharedKey = {peer.preshared_key}")
    lines.append(f"Endpoint = {endpoint_host}:{port}")

    # AllowedIPs: full-VPN for vpn/vpn_escape; split-tunnel for antizapret/antizapret_escape.
    if iface in ("vpn", "vpn_escape"):
        lines.append("AllowedIPs = 0.0.0.0/0, ::/0")
    else:
        # antizapret / antizapret_escape: subnet-based split routing
        effective_allowed_ips = allowed_ips if allowed_ips is not None else "10.29.8.0/24"
        lines.append(f"AllowedIPs = {effective_allowed_ips}")

    lines.append("PersistentKeepalive = 15")
    lines.append("")  # trailing newline
    return "\n".join(lines)
