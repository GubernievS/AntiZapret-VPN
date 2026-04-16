"""
Tests for wg_templates — pure WireGuard config functions (no I/O, no DB).
"""
import base64
import pytest

from app.services.wg_templates import (
    Peer,
    reverse_key,
    reverse_peer_keys,
    parse_peers,
    render_server_conf,
    render_client_conf,
    next_free_ip,
)


# ---------------------------------------------------------------------------
# Sample data
# ---------------------------------------------------------------------------

# A valid WireGuard key (32 random bytes, base64-encoded)
_SAMPLE_KEY = base64.b64encode(bytes(range(32))).decode()  # deterministic

# Proper 32-byte base64 keys that survive encode/decode round-trips.
# Generated deterministically so tests are reproducible.
def _make_key(seed: int) -> str:
    return base64.b64encode(bytes([(seed + i) % 256 for i in range(32)])).decode()

_ALICE_PUB = _make_key(10)
_ALICE_PSK = _make_key(50)
_BOB_PUB = _make_key(90)
_BOB_PSK = _make_key(130)
_SERVER_PRIV = _make_key(170)

_SERVER_CONF = (
    f"[Interface]\n"
    f"PrivateKey = {_SERVER_PRIV}\n"
    f"Address = 10.29.8.1/21\n"
    f"ListenPort = 51443\n"
    f"\n"
    f"# Client = alice-1\n"
    f"[Peer]\n"
    f"PublicKey = {_ALICE_PUB}\n"
    f"PresharedKey = {_ALICE_PSK}\n"
    f"AllowedIPs = 10.29.8.2/32\n"
    f"\n"
    f"# Client = bob-2\n"
    f"[Peer]\n"
    f"PublicKey = {_BOB_PUB}\n"
    f"PresharedKey = {_BOB_PSK}\n"
    f"AllowedIPs = 10.29.8.3/32\n"
)

_SERVER_CONF_WITH_PRIVKEY_COMMENT = (
    f"[Interface]\n"
    f"PrivateKey = {_SERVER_PRIV}\n"
    f"Address = 10.29.8.1/21\n"
    f"ListenPort = 51443\n"
    f"\n"
    f"# Client = alice-1\n"
    f"# PrivateKey = alicepriv==\n"
    f"[Peer]\n"
    f"PublicKey = {_ALICE_PUB}\n"
    f"PresharedKey = {_ALICE_PSK}\n"
    f"AllowedIPs = 10.29.8.2/32\n"
)


# ---------------------------------------------------------------------------
# reverse_key
# ---------------------------------------------------------------------------

class TestReverseKey:
    def test_roundtrip_is_identity(self):
        """reverse_key(reverse_key(x)) == x — self-inverse property."""
        assert reverse_key(reverse_key(_SAMPLE_KEY)) == _SAMPLE_KEY

    def test_produces_valid_base64(self):
        result = reverse_key(_SAMPLE_KEY)
        # Must decode without error
        decoded = base64.b64decode(result)
        assert len(decoded) == 32  # same length as original

    def test_reversed_bytes_match(self):
        original_bytes = base64.b64decode(_SAMPLE_KEY)
        reversed_result = reverse_key(_SAMPLE_KEY)
        result_bytes = base64.b64decode(reversed_result)
        assert result_bytes == original_bytes[::-1]

    def test_different_from_input(self):
        """For a non-palindromic key, output differs from input."""
        assert reverse_key(_SAMPLE_KEY) != _SAMPLE_KEY

    def test_real_wg_key_roundtrip(self):
        """Test with an actual WG-style 44-char base64 key."""
        # Generate a realistic 32-byte key
        key_bytes = bytes([i ^ 0xAB for i in range(32)])
        key = base64.b64encode(key_bytes).decode()
        assert reverse_key(reverse_key(key)) == key


# ---------------------------------------------------------------------------
# reverse_peer_keys
# ---------------------------------------------------------------------------

class TestReversePeerKeys:
    def test_changes_target_peer(self):
        result = reverse_peer_keys(_SERVER_CONF, "alice-1")
        # alice's keys should change
        assert _ALICE_PUB not in result
        assert _ALICE_PSK not in result

    def test_leaves_other_peers_alone(self):
        result = reverse_peer_keys(_SERVER_CONF, "alice-1")
        # bob's keys should be untouched
        assert _BOB_PUB in result
        assert _BOB_PSK in result

    def test_self_inverse(self):
        """Applying twice returns original content — involution."""
        once = reverse_peer_keys(_SERVER_CONF, "alice-1")
        twice = reverse_peer_keys(once, "alice-1")
        assert twice == _SERVER_CONF

    def test_preserves_trailing_newline(self):
        """split('\\n') preserves trailing newline unlike splitlines()."""
        text = _SERVER_CONF
        assert text.endswith("\n")
        result = reverse_peer_keys(text, "alice-1")
        assert result.endswith("\n")

    def test_no_match_returns_unchanged(self):
        result = reverse_peer_keys(_SERVER_CONF, "nonexistent")
        assert result == _SERVER_CONF

    def test_tolerates_private_key_comment(self):
        """A # PrivateKey = ... comment line between Client and [Peer] is tolerated."""
        result = reverse_peer_keys(_SERVER_CONF_WITH_PRIVKEY_COMMENT, "alice-1")
        # The comment should remain, keys should be reversed
        assert "# PrivateKey = alicepriv==" in result
        assert _ALICE_PUB not in result
        # And it's self-inverse
        twice = reverse_peer_keys(result, "alice-1")
        assert twice == _SERVER_CONF_WITH_PRIVKEY_COMMENT


# ---------------------------------------------------------------------------
# parse_peers
# ---------------------------------------------------------------------------

class TestParsePeers:
    def test_correct_count(self):
        peers = parse_peers(_SERVER_CONF)
        assert len(peers) == 2

    def test_all_fields_extracted(self):
        peers = parse_peers(_SERVER_CONF)
        alice = peers[0]
        assert alice.name == "alice-1"
        assert alice.public_key == _ALICE_PUB
        assert alice.preshared_key == _ALICE_PSK
        assert alice.allowed_ips == "10.29.8.2/32"

    def test_second_peer(self):
        peers = parse_peers(_SERVER_CONF)
        bob = peers[1]
        assert bob.name == "bob-2"
        assert bob.public_key == _BOB_PUB
        assert bob.preshared_key == _BOB_PSK
        assert bob.allowed_ips == "10.29.8.3/32"

    def test_empty_config(self):
        conf = "[Interface]\nPrivateKey = x\nAddress = 10.0.0.1/24\nListenPort = 51443\n"
        peers = parse_peers(conf)
        assert peers == []

    def test_tolerates_private_key_comment(self):
        peers = parse_peers(_SERVER_CONF_WITH_PRIVKEY_COMMENT)
        assert len(peers) == 1
        assert peers[0].name == "alice-1"
        assert peers[0].public_key == _ALICE_PUB

    def test_single_peer(self):
        conf = """\
[Interface]
PrivateKey = x
Address = 10.29.8.1/21
ListenPort = 51443

# Client = solo-1
[Peer]
PublicKey = solopub==
PresharedKey = solopsk==
AllowedIPs = 10.29.8.2/32
"""
        peers = parse_peers(conf)
        assert len(peers) == 1
        assert peers[0].name == "solo-1"


# ---------------------------------------------------------------------------
# next_free_ip
# ---------------------------------------------------------------------------

class TestNextFreeIp:
    def test_empty_list_returns_dot_2(self):
        ip = next_free_ip([], "10.29.8.0/21")
        assert ip == "10.29.8.2"

    def test_with_existing_peers(self):
        peers = [
            Peer(name="a", public_key="", preshared_key="", allowed_ips="10.29.8.2/32"),
            Peer(name="b", public_key="", preshared_key="", allowed_ips="10.29.8.3/32"),
        ]
        ip = next_free_ip(peers, "10.29.8.0/21")
        assert ip == "10.29.8.4"

    def test_gap_in_allocation(self):
        """If .3 is missing, .3 should be returned (first gap)."""
        peers = [
            Peer(name="a", public_key="", preshared_key="", allowed_ips="10.29.8.2/32"),
            Peer(name="c", public_key="", preshared_key="", allowed_ips="10.29.8.4/32"),
        ]
        ip = next_free_ip(peers, "10.29.8.0/21")
        assert ip == "10.29.8.3"

    def test_respects_subnet(self):
        """Works with different subnets."""
        ip = next_free_ip([], "10.0.0.0/24")
        assert ip == "10.0.0.2"


# ---------------------------------------------------------------------------
# render_server_conf
# ---------------------------------------------------------------------------

class TestRenderServerConf:
    def _make_iface(self):
        """Return iface params dict."""
        return {"listen_port": 51443, "address": "10.29.8.1/21"}

    def test_contains_interface_section(self):
        conf = render_server_conf(
            iface=self._make_iface(),
            peers=[],
            server_privkey="servpriv==",
            address="10.29.8.1/21",
        )
        assert "[Interface]" in conf

    def test_correct_listen_port(self):
        conf = render_server_conf(
            iface={"listen_port": 52443, "address": "10.29.8.1/21"},
            peers=[],
            server_privkey="servpriv==",
            address="10.29.8.1/21",
        )
        assert "ListenPort = 52443" in conf

    def test_includes_all_peers(self):
        peers = [
            Peer(name="alice-1", public_key="apub==", preshared_key="apsk==", allowed_ips="10.29.8.2/32"),
            Peer(name="bob-2", public_key="bpub==", preshared_key="bpsk==", allowed_ips="10.29.8.3/32"),
        ]
        conf = render_server_conf(
            iface=self._make_iface(),
            peers=peers,
            server_privkey="servpriv==",
            address="10.29.8.1/21",
        )
        assert "# Client = alice-1" in conf
        assert "# Client = bob-2" in conf
        assert "[Peer]" in conf
        assert "PublicKey = apub==" in conf
        assert "PresharedKey = bpsk==" in conf
        assert "AllowedIPs = 10.29.8.2/32" in conf
        assert "AllowedIPs = 10.29.8.3/32" in conf

    def test_private_key_in_output(self):
        conf = render_server_conf(
            iface=self._make_iface(),
            peers=[],
            server_privkey="MY_SECRET_KEY==",
            address="10.29.8.1/21",
        )
        assert "PrivateKey = MY_SECRET_KEY==" in conf


# ---------------------------------------------------------------------------
# render_client_conf
# ---------------------------------------------------------------------------

class TestRenderClientConf:
    _PEER = Peer(
        name="alice-1",
        public_key="alicepub==",
        preshared_key="alicepsk==",
        allowed_ips="10.29.8.2/32",
    )

    def test_awg_has_obfuscation_fields(self):
        conf = render_client_conf(
            peer=self._PEER,
            iface="antizapret",
            server_pubkey="servpub==",
            endpoint_host="vpn.example.com",
            flavor="awg",
        )
        assert "Jc = 100" in conf
        assert "Jmin = 20" in conf
        assert "Jmax = 100" in conf
        assert "S1 = 0" in conf
        assert "S2 = 0" in conf
        assert "H1 = 1" in conf
        assert "H2 = 2" in conf
        assert "H3 = 3" in conf
        assert "H4 = 4" in conf
        assert "I1 = " in conf

    def test_wg_has_no_obfuscation_fields(self):
        conf = render_client_conf(
            peer=self._PEER,
            iface="antizapret",
            server_pubkey="servpub==",
            endpoint_host="vpn.example.com",
            flavor="wg",
        )
        assert "Jc" not in conf
        assert "Jmin" not in conf
        assert "I1" not in conf

    def test_awg_antizapret_port(self):
        conf = render_client_conf(
            peer=self._PEER,
            iface="antizapret",
            server_pubkey="servpub==",
            endpoint_host="vpn.example.com",
            flavor="awg",
        )
        assert ":52443" in conf

    def test_wg_antizapret_port(self):
        conf = render_client_conf(
            peer=self._PEER,
            iface="antizapret",
            server_pubkey="servpub==",
            endpoint_host="vpn.example.com",
            flavor="wg",
        )
        assert ":51443" in conf

    def test_awg_vpn_port(self):
        conf = render_client_conf(
            peer=self._PEER,
            iface="vpn",
            server_pubkey="servpub==",
            endpoint_host="vpn.example.com",
            flavor="awg",
        )
        assert ":52080" in conf

    def test_wg_vpn_port(self):
        conf = render_client_conf(
            peer=self._PEER,
            iface="vpn",
            server_pubkey="servpub==",
            endpoint_host="vpn.example.com",
            flavor="wg",
        )
        assert ":51080" in conf

    def test_antizapret_allowed_ips(self):
        conf = render_client_conf(
            peer=self._PEER,
            iface="antizapret",
            server_pubkey="servpub==",
            endpoint_host="vpn.example.com",
            flavor="wg",
        )
        # antizapret uses subnet-based routing
        assert "10.29.8.0/24" in conf
        assert "0.0.0.0/0" not in conf

    def test_vpn_allowed_ips(self):
        conf = render_client_conf(
            peer=self._PEER,
            iface="vpn",
            server_pubkey="servpub==",
            endpoint_host="vpn.example.com",
            flavor="wg",
        )
        assert "0.0.0.0/0" in conf
        assert "::/0" in conf

    def test_client_address_from_peer(self):
        conf = render_client_conf(
            peer=self._PEER,
            iface="antizapret",
            server_pubkey="servpub==",
            endpoint_host="vpn.example.com",
            flavor="wg",
        )
        # Address should contain the peer's IP
        assert "10.29.8.2/32" in conf

    def test_preshared_key_present(self):
        conf = render_client_conf(
            peer=self._PEER,
            iface="antizapret",
            server_pubkey="servpub==",
            endpoint_host="vpn.example.com",
            flavor="wg",
        )
        assert "PresharedKey = alicepsk==" in conf

    def test_server_pubkey_present(self):
        conf = render_client_conf(
            peer=self._PEER,
            iface="antizapret",
            server_pubkey="servpub==",
            endpoint_host="vpn.example.com",
            flavor="wg",
        )
        assert "PublicKey = servpub==" in conf

    def test_endpoint_host(self):
        conf = render_client_conf(
            peer=self._PEER,
            iface="antizapret",
            server_pubkey="servpub==",
            endpoint_host="vpn.example.com",
            flavor="wg",
        )
        assert "Endpoint = vpn.example.com:" in conf

    def test_persistent_keepalive(self):
        conf = render_client_conf(
            peer=self._PEER,
            iface="antizapret",
            server_pubkey="servpub==",
            endpoint_host="vpn.example.com",
            flavor="wg",
        )
        assert "PersistentKeepalive = 15" in conf

    def test_private_key_placeholder(self):
        conf = render_client_conf(
            peer=self._PEER,
            iface="antizapret",
            server_pubkey="servpub==",
            endpoint_host="vpn.example.com",
            flavor="wg",
        )
        assert "PrivateKey = ${CLIENT_PRIVATE_KEY}" in conf

    def test_dns_server(self):
        conf = render_client_conf(
            peer=self._PEER,
            iface="antizapret",
            server_pubkey="servpub==",
            endpoint_host="vpn.example.com",
            flavor="wg",
        )
        assert "DNS = 10.29.8.1" in conf
