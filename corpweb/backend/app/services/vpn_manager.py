"""
VPN Manager Service
Interface with /root/antizapret/client.sh for config management
"""
import re
import subprocess
import logging
from pathlib import Path
from typing import Dict, List, Optional

from app.config import settings

logger = logging.getLogger(__name__)

# Allowed characters in client names — matches client.sh: alphanumeric, underscore, dash only (no dots)
CLIENT_NAME_PATTERN = re.compile(r'^[a-zA-Z0-9_-]+$')


class VPNManagerError(Exception):
    """Custom exception for VPN manager errors"""
    pass


class VPNManager:
    """
    Manages VPN client configs through client.sh script.

    client.sh options:
        4 = WireGuard/AmneziaWG - Add client
        5 = WireGuard/AmneziaWG - Delete client
        6 = WireGuard/AmneziaWG - List clients
    """

    def __init__(self):
        self.client_script = settings.VPN_CLIENT_SCRIPT
        self.client_dir = Path(settings.VPN_CLIENT_DIR)

    def _validate_client_name(self, client_name: str) -> None:
        """Validate client name to prevent command injection"""
        if not CLIENT_NAME_PATTERN.match(client_name):
            raise VPNManagerError(
                f"Invalid client name: '{client_name}'. "
                "Only letters, numbers, dots, hyphens and underscores are allowed."
            )
        if len(client_name) > 32:
            raise VPNManagerError("Client name too long (max 32 characters)")

    def _run_script(self, args: List[str], timeout: int = 60) -> subprocess.CompletedProcess:
        """
        Run client.sh with given arguments.
        Uses subprocess with security precautions.
        """
        cmd = [self.client_script] + args

        logger.info(f"Running: {' '.join(cmd)}")

        try:
            result = subprocess.run(
                cmd,
                capture_output=True,
                text=True,
                timeout=timeout,
                check=False  # We'll check returncode manually
            )

            if result.returncode != 0:
                logger.error(f"Script failed (exit code {result.returncode}): {result.stderr}")
                raise VPNManagerError(
                    f"client.sh failed: {result.stderr.strip() or result.stdout.strip()}"
                )

            logger.info(f"Script output: {result.stdout[:200]}")
            return result

        except subprocess.TimeoutExpired:
            raise VPNManagerError("Operation timed out")
        except FileNotFoundError:
            raise VPNManagerError(f"Script not found: {self.client_script}")
        except PermissionError:
            raise VPNManagerError(f"No permission to execute: {self.client_script}")

    def _find_config_file(self, directory: Path, prefix: str, client_name: str) -> Optional[Path]:
        """
        Find actual config file using glob pattern.
        Antizapret script may append server IP to filename:
        e.g., antizapret-ivan-1-(213.148.6.245)-am.conf
        Tries exact match first, then glob pattern.
        """
        exact = directory / f"{prefix}-{client_name}-am.conf"
        if exact.exists():
            return exact

        matches = list(directory.glob(f"{prefix}-{client_name}-*-am.conf"))
        if matches:
            return matches[0]

        return None

    def _extract_address(self, file_path: Path) -> Optional[str]:
        """Extract client VPN IP from [Interface] Address field in config file."""
        try:
            for line in file_path.read_text().splitlines():
                line = line.strip()
                if line.lower().startswith('address'):
                    ip_part = line.split('=', 1)[1].strip()
                    return ip_part.split('/')[0].strip()
        except OSError:
            pass
        return None

    def add_client(self, client_name: str) -> Dict[str, str]:
        """
        Create an AmneziaWG client config.
        Option 4 = WireGuard/AmneziaWG - Add client

        Returns paths to created config files.
        """
        self._validate_client_name(client_name)

        result = self._run_script(["4", client_name])

        # Find actual config files (script may include server IP in filename)
        antizapret_dir = self.client_dir / "amneziawg" / "antizapret"
        vpn_dir = self.client_dir / "amneziawg" / "vpn"

        antizapret_file = self._find_config_file(antizapret_dir, "antizapret", client_name)
        vpn_file = self._find_config_file(vpn_dir, "vpn", client_name)

        # Extract client VPN IP to enable monitoring name resolution
        vpn_ip = None
        for f in (antizapret_file, vpn_file):
            if f:
                vpn_ip = self._extract_address(f)
                if vpn_ip:
                    break

        return {
            "client_name": client_name,
            "antizapret_path": str(antizapret_file) if antizapret_file else None,
            "vpn_path": str(vpn_file) if vpn_file else None,
            "vpn_ip": vpn_ip,
            "output": result.stdout
        }

    def delete_client(self, client_name: str) -> None:
        """
        Delete an AmneziaWG client.
        Option 5 = WireGuard/AmneziaWG - Delete client
        """
        self._validate_client_name(client_name)
        self._run_script(["5", client_name])
        logger.info(f"Deleted client: {client_name}")

    def list_clients(self) -> List[str]:
        """
        Get list of existing AWG clients.
        Option 6 = WireGuard/AmneziaWG - List clients
        """
        result = self._run_script(["6"], timeout=15)

        # Parse output: skip header lines, extract client names
        lines = result.stdout.strip().split('\n')
        clients = []
        for line in lines:
            line = line.strip()
            # Skip empty lines and header lines
            if not line or line.startswith('=') or line.startswith('-') or 'client' in line.lower():
                continue
            # Take the first word as client name
            name = line.split()[0] if line.split() else None
            if name and CLIENT_NAME_PATTERN.match(name):
                clients.append(name)

        return clients

    def get_config_file_path(self, client_name: str, config_type: str) -> Optional[str]:
        """
        Get path to config file for a specific client and type.

        Args:
            client_name: Client name (e.g., "user-1")
            config_type: "awg_antizapret" or "awg_vpn"

        Returns:
            Path to .conf file or None if not found
        """
        self._validate_client_name(client_name)

        if config_type == "awg_antizapret":
            directory = self.client_dir / "amneziawg" / "antizapret"
            found = self._find_config_file(directory, "antizapret", client_name)
        elif config_type == "awg_vpn":
            directory = self.client_dir / "amneziawg" / "vpn"
            found = self._find_config_file(directory, "vpn", client_name)
        else:
            return None

        return str(found) if found else None

    def read_config_file(self, file_path: str) -> Optional[str]:
        """
        Read config file content for download.
        Validates path is within allowed directory.
        """
        path = Path(file_path)

        # Security: ensure path is within client directory
        try:
            path.resolve().relative_to(self.client_dir.resolve())
        except ValueError:
            logger.warning(f"Path traversal attempt: {file_path}")
            raise VPNManagerError("Access denied: invalid file path")

        if not path.exists():
            return None

        return path.read_text()

    # ------------------------------------------------------------------
    # Peer disable/enable via key reversal in server config files.
    #
    # Server config format (/etc/wireguard/vpn.conf, antizapret.conf):
    #
    #   # Client = ivan-1
    #   # PrivateKey = ...
    #   [Peer]
    #   PublicKey = abc123...XYZ=
    #   PresharedKey = def456...UVW=
    #   AllowedIPs = 10.28.8.5/32
    #
    # To disable: reverse PublicKey and PresharedKey values (preserving
    # trailing '=' base64 padding). The [Peer] block stays syntactically
    # valid — WireGuard parses it without errors — but the reversed key
    # won't match any client, so the peer can't connect.
    #
    # To re-enable: reverse again (the operation is its own inverse).
    # AllowedIPs (IP reservation) is always preserved.
    # ------------------------------------------------------------------

    _SERVER_CONFIG_DIR = Path('/etc/wireguard')

    def _find_server_configs(self) -> List[Path]:
        """Find all WireGuard server config files."""
        if not self._SERVER_CONFIG_DIR.exists():
            return []
        return list(self._SERVER_CONFIG_DIR.glob('*.conf'))

    def _extract_peer_public_key(self, content: str, client_name: str) -> Optional[str]:
        """
        Extract PublicKey for a specific client from server config content.
        Returns the current value (which may be reversed if the peer is blocked).
        """
        lines = content.split('\n')
        in_target_peer = False

        for line in lines:
            stripped = line.strip()

            if stripped.startswith('# Client') and '=' in stripped:
                peer_name = stripped.split('=', 1)[1].strip()
                in_target_peer = (peer_name == client_name)

            if in_target_peer and not stripped.startswith('#'):
                if stripped.lower().startswith('publickey') and '=' in stripped:
                    return stripped.split('=', 1)[1].strip()

        return None

    @staticmethod
    def _reverse_key(key: str) -> str:
        """
        Reverse a WireGuard base64 key while preserving trailing '='
        padding.  The operation is its own inverse:
        _reverse_key(_reverse_key(x)) == x.

        Example: 'aBcDeFgH12345=' -> '54321HgFeDcBa='
        """
        stripped = key.rstrip('=')
        padding = key[len(stripped):]
        return stripped[::-1] + padding

    def _reverse_peer_keys(self, content: str, client_name: str) -> str:
        """
        Reverse PublicKey and PresharedKey values in a [Peer] block
        belonging to client_name.

        Before:
            # Client = ivan-1
            # PrivateKey = ...
            [Peer]
            PublicKey = abc123XYZ=
            PresharedKey = def456UVW=
            AllowedIPs = 10.28.8.5/32

        After:
            # Client = ivan-1
            # PrivateKey = ...
            [Peer]
            PublicKey = ZYX321cba=
            PresharedKey = WVU654fed=
            AllowedIPs = 10.28.8.5/32

        The [Peer] block stays syntactically valid.  Calling this method
        again on the same client reverses the keys back to the originals.
        """
        # split('\n') preserves trailing newline (as empty last element),
        # unlike splitlines() which drops it — critical for file integrity.
        lines = content.split('\n')
        result_lines = []
        in_target_peer = False

        for line in lines:
            stripped = line.strip()

            # Detect "# Client = <name>" comment
            if stripped.startswith('# Client') and '=' in stripped:
                peer_name = stripped.split('=', 1)[1].strip()
                in_target_peer = (peer_name == client_name)

            # Detect start of a different peer block (reset flag)
            if stripped == '[Peer]' and not in_target_peer:
                in_target_peer = False

            # Reverse key values in the target peer block
            if in_target_peer and not stripped.startswith('#'):
                lower = stripped.lower()
                if lower.startswith('publickey') or lower.startswith('presharedkey'):
                    key_part, sep, value = line.partition('=')
                    if sep and value.strip():
                        reversed_val = self._reverse_key(value.strip())
                        result_lines.append(f"{key_part}= {reversed_val}")
                        continue

            result_lines.append(line)

        return '\n'.join(result_lines)

    def _remove_wg_peer(self, iface: str, public_key: str) -> None:
        """
        Remove a specific peer from a running WireGuard interface.
        Uses `wg set <iface> peer <pubkey> remove`.
        """
        try:
            result = subprocess.run(
                ['wg', 'set', iface, 'peer', public_key, 'remove'],
                capture_output=True, text=True, timeout=10,
            )
            if result.returncode != 0:
                logger.warning(
                    f"wg set {iface} peer remove failed: {result.stderr.strip()}"
                )
            else:
                logger.info(f"Removed peer {public_key[:8]}... from {iface}")
        except Exception as e:
            logger.warning(f"Failed to remove peer from {iface}: {e}")

    def _apply_wg_config(self, conf_path: Path) -> None:
        """
        Apply config changes to the running WireGuard interface
        without restarting it (no disconnects for other peers).

        Uses `wg syncconf <iface> <(wg-quick strip <iface>)` pattern.
        Only safe when ALL [Peer] blocks have a valid PublicKey
        (i.e. after uncommenting / enabling peers).
        """
        iface = conf_path.stem  # e.g. /etc/wireguard/vpn.conf → "vpn"
        try:
            result = subprocess.run(
                ['bash', '-c', f'wg syncconf {iface} <(wg-quick strip {iface})'],
                capture_output=True, text=True, timeout=10,
            )
            if result.returncode != 0:
                logger.warning(
                    f"wg syncconf {iface} failed: {result.stderr.strip()}"
                )
            else:
                logger.info(f"Applied config for interface {iface}")
        except Exception as e:
            logger.warning(f"Failed to apply config for {iface}: {e}")

    def disable_peer(self, client_name: str) -> None:
        """
        Disable a peer by reversing its PublicKey/PresharedKey values
        in all server config files, then removing it from running WG.

        The reversed keys keep the [Peer] block syntactically valid
        (no wg config parse errors) but won't match any client.

        Uses `wg set <iface> peer <pubkey> remove` to drop the peer
        from the running interface immediately.

        The peer's IP reservation (AllowedIPs) is preserved, preventing
        IP conflicts if new clients are created while this one is blocked.
        Client config files on disk are untouched.
        """
        self._validate_client_name(client_name)

        for conf_path in self._find_server_configs():
            try:
                content = conf_path.read_text()
                if f'# Client = {client_name}' not in content:
                    continue

                # Extract PublicKey BEFORE reversing it
                pubkey = self._extract_peer_public_key(content, client_name)

                new_content = self._reverse_peer_keys(content, client_name)
                if new_content != content:
                    conf_path.write_text(new_content)
                    logger.info(f"Disabled peer {client_name} in {conf_path}")

                    # Remove peer from running WG interface by its original PublicKey
                    if pubkey:
                        iface = conf_path.stem
                        self._remove_wg_peer(iface, pubkey)
                    else:
                        logger.warning(
                            f"No PublicKey found for {client_name} in {conf_path}"
                        )
            except OSError as e:
                raise VPNManagerError(f"Failed to modify {conf_path}: {e}")

    def enable_peer(self, client_name: str) -> None:
        """
        Re-enable a previously disabled peer by reversing its keys back
        to the originals (_reverse_peer_keys is its own inverse), then
        applying via wg syncconf (safe because all [Peer] blocks have
        valid PublicKey).
        """
        self._validate_client_name(client_name)
        modified_configs = []

        for conf_path in self._find_server_configs():
            try:
                content = conf_path.read_text()
                if f'# Client = {client_name}' not in content:
                    continue

                new_content = self._reverse_peer_keys(content, client_name)
                if new_content != content:
                    conf_path.write_text(new_content)
                    modified_configs.append(conf_path)
                    logger.info(f"Enabled peer {client_name} in {conf_path}")
            except OSError as e:
                raise VPNManagerError(f"Failed to modify {conf_path}: {e}")

        if not modified_configs:
            logger.warning(f"Peer {client_name} not found in server configs")

        # wg syncconf is safe — all [Peer] blocks have valid PublicKey
        for conf_path in modified_configs:
            self._apply_wg_config(conf_path)

    def _parse_config_key(self, config_content: str, key_name: str) -> Optional[str]:
        """Parse a key = value field from WireGuard/AmneziaWG config text."""
        for line in config_content.splitlines():
            stripped = line.strip()
            if stripped.lower().startswith(key_name.lower()):
                parts = stripped.split('=', 1)
                if len(parts) == 2:
                    return parts[1].strip()
        return None


def generate_client_name(username: str, existing_names: List[str]) -> str:
    """
    Generate unique client name: username-1, username-2, etc.

    Args:
        username: User's username (without @domain)
        existing_names: List of existing client names for this user
    """
    # Clean username: take part before @ if email, then replace disallowed chars with underscore
    base_name = re.sub(r'[^a-zA-Z0-9_-]', '_', username.split("@")[0])

    # Find max number among existing names
    max_number = 0
    pattern = re.compile(rf'^{re.escape(base_name)}-(\d+)$')
    for name in existing_names:
        match = pattern.match(name)
        if match:
            max_number = max(max_number, int(match.group(1)))

    return f"{base_name}-{max_number + 1}"


# Singleton instance
vpn_manager = VPNManager()
