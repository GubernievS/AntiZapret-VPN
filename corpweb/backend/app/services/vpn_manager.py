"""
VPN Manager Service
Interface with /root/antizapret/client.sh for config management
"""
import re
import subprocess
import logging
import tempfile
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
    # Key management: parsing, derivation, peer swap for block/unblock
    # ------------------------------------------------------------------

    def _parse_config_key(self, config_content: str, key_name: str) -> Optional[str]:
        """Parse a key = value field from WireGuard/AmneziaWG config text."""
        for line in config_content.splitlines():
            stripped = line.strip()
            if stripped.lower().startswith(key_name.lower()):
                parts = stripped.split('=', 1)
                if len(parts) == 2:
                    return parts[1].strip()
        return None

    def derive_public_key(self, private_key: str) -> str:
        """Derive WireGuard public key from private key using `wg pubkey`."""
        try:
            result = subprocess.run(
                ['wg', 'pubkey'],
                input=private_key,
                capture_output=True,
                text=True,
                timeout=5,
            )
            if result.returncode != 0:
                raise VPNManagerError(f"wg pubkey failed: {result.stderr.strip()}")
            return result.stdout.strip()
        except FileNotFoundError:
            raise VPNManagerError("wg command not found")
        except subprocess.TimeoutExpired:
            raise VPNManagerError("wg pubkey timed out")

    def _get_wg_interfaces(self) -> List[str]:
        """Get list of active WireGuard/AmneziaWG interfaces."""
        try:
            result = subprocess.run(
                ['wg', 'show', 'interfaces'],
                capture_output=True, text=True, timeout=5,
            )
            if result.returncode != 0:
                return []
            return result.stdout.strip().split()
        except Exception:
            return []

    def _swap_wg_peer(
        self,
        new_pubkey: str,
        old_pubkey: str,
        old_psk: Optional[str],
        fallback_allowed_ips: Optional[str],
    ) -> None:
        """
        Replace the NEW peer with the OLD peer on every WG interface
        where the new peer is present (runtime — does not touch config files).
        """
        for iface in self._get_wg_interfaces():
            # wg show <iface> dump: first line = interface, rest = peers
            # peer columns: pubkey  psk  endpoint  allowed-ips  handshake  rx  tx  keepalive
            try:
                dump = subprocess.run(
                    ['wg', 'show', iface, 'dump'],
                    capture_output=True, text=True, timeout=5,
                )
            except Exception:
                continue

            peer_allowed_ips = None
            for line in dump.stdout.strip().splitlines()[1:]:
                cols = line.split('\t')
                if cols[0] == new_pubkey:
                    peer_allowed_ips = cols[3] if len(cols) > 3 else None
                    break

            if peer_allowed_ips is None:
                continue  # new peer not on this interface

            # Remove new peer
            subprocess.run(
                ['wg', 'set', iface, 'peer', new_pubkey, 'remove'],
                capture_output=True, text=True, timeout=5,
            )

            # Build command to add old peer
            allowed = peer_allowed_ips or fallback_allowed_ips or '0.0.0.0/0'
            cmd = ['wg', 'set', iface, 'peer', old_pubkey,
                   'allowed-ips', allowed]

            if old_psk:
                psk_path = None
                try:
                    with tempfile.NamedTemporaryFile(
                        mode='w', suffix='.psk', delete=False
                    ) as f:
                        f.write(old_psk)
                        psk_path = f.name
                    cmd.extend(['preshared-key', psk_path])
                    subprocess.run(
                        cmd, capture_output=True, text=True, timeout=5,
                    )
                finally:
                    if psk_path:
                        Path(psk_path).unlink(missing_ok=True)
            else:
                subprocess.run(
                    cmd, capture_output=True, text=True, timeout=5,
                )

            logger.info(f"Swapped peer on {iface}: {new_pubkey[:8]}… → {old_pubkey[:8]}…")

    def _update_server_configs(
        self,
        new_pubkey: str,
        old_pubkey: str,
        new_psk: Optional[str],
        old_psk: Optional[str],
    ) -> None:
        """
        Replace new pubkey/psk with old ones in server config files
        so the change persists across WG restarts.
        """
        search_dirs = [
            Path('/etc/amnezia/amneziawg'),
            Path('/etc/amnezia'),
            Path('/etc/wireguard'),
        ]

        for search_dir in search_dirs:
            if not search_dir.exists():
                continue
            for conf_file in search_dir.rglob('*.conf'):
                try:
                    content = conf_file.read_text()
                    if new_pubkey not in content:
                        continue

                    content = content.replace(new_pubkey, old_pubkey)
                    if new_psk and old_psk and new_psk != old_psk:
                        content = content.replace(new_psk, old_psk)

                    conf_file.write_text(content)
                    logger.info(f"Updated server config: {conf_file}")
                except OSError as e:
                    logger.warning(f"Failed to update {conf_file}: {e}")

    def restore_client(
        self,
        client_name: str,
        saved_configs: Dict[str, Optional[str]],
    ) -> Dict[str, str]:
        """
        Restore a previously blocked client with its original keys.

        1. client.sh 4  — create fresh peer (new keys, correct server-side setup)
        2. Parse new & old configs to extract keys
        3. Overwrite client config files with saved content (old keys)
        4. Swap peers on running WG interfaces
        5. Update server config files for persistence

        If saved content is missing for a config type, that file keeps
        its new keys (fallback for pre-feature configs).
        """
        # Safety: remove leftover peer if somehow still present
        try:
            self.delete_client(client_name)
        except VPNManagerError:
            pass

        # Step 1: create fresh client
        result = self.add_client(client_name)

        swapped_pubkeys: set = set()

        config_pairs = [
            (result.get('antizapret_path'), saved_configs.get('antizapret_content')),
            (result.get('vpn_path'), saved_configs.get('vpn_content')),
        ]

        for new_path, saved_content in config_pairs:
            if not new_path or not saved_content:
                continue

            try:
                new_content = Path(new_path).read_text()
            except OSError:
                continue

            new_privkey = self._parse_config_key(new_content, 'PrivateKey')
            old_privkey = self._parse_config_key(saved_content, 'PrivateKey')

            if not new_privkey or not old_privkey:
                # Can't parse keys — just overwrite file
                Path(new_path).write_text(saved_content)
                continue

            if new_privkey == old_privkey:
                # Keys identical — overwrite for other fields (AllowedIPs etc.)
                Path(new_path).write_text(saved_content)
                continue

            new_pubkey = self.derive_public_key(new_privkey)
            old_pubkey = self.derive_public_key(old_privkey)

            # Overwrite client config file with saved content
            Path(new_path).write_text(saved_content)

            # Swap peer on WG interfaces (once per unique key pair)
            if new_pubkey not in swapped_pubkeys:
                swapped_pubkeys.add(new_pubkey)

                old_psk = self._parse_config_key(saved_content, 'PresharedKey')
                new_psk = self._parse_config_key(new_content, 'PresharedKey')
                old_address = self._parse_config_key(saved_content, 'Address')

                try:
                    self._swap_wg_peer(
                        new_pubkey, old_pubkey, old_psk, old_address,
                    )
                    self._update_server_configs(
                        new_pubkey, old_pubkey, new_psk, old_psk,
                    )
                except Exception as e:
                    logger.error(f"Key swap failed for {client_name}: {e}")
                    # Peer was created successfully by add_client,
                    # but with new keys — user will need to re-download

        # Re-extract VPN IP from restored config
        vpn_ip = None
        for path_key in ('antizapret_path', 'vpn_path'):
            p = result.get(path_key)
            if p:
                vpn_ip = self._extract_address(Path(p))
                if vpn_ip:
                    break
        result['vpn_ip'] = vpn_ip

        return result


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
