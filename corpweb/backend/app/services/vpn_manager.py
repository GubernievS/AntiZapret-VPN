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
