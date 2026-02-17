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

# Allowed characters in client names (security: prevent command injection)
CLIENT_NAME_PATTERN = re.compile(r'^[a-zA-Z0-9._-]+$')


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

    def add_client(self, client_name: str) -> Dict[str, str]:
        """
        Create an AmneziaWG client config.
        Option 4 = WireGuard/AmneziaWG - Add client

        Returns paths to created config files.
        """
        self._validate_client_name(client_name)

        result = self._run_script(["4", client_name])

        # Expected config file paths
        antizapret_path = self.client_dir / "amneziawg" / "antizapret" / f"antizapret-{client_name}-am.conf"
        vpn_path = self.client_dir / "amneziawg" / "vpn" / f"vpn-{client_name}-am.conf"

        return {
            "client_name": client_name,
            "antizapret_path": str(antizapret_path) if antizapret_path.exists() else None,
            "vpn_path": str(vpn_path) if vpn_path.exists() else None,
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
            path = self.client_dir / "amneziawg" / "antizapret" / f"antizapret-{client_name}-am.conf"
        elif config_type == "awg_vpn":
            path = self.client_dir / "amneziawg" / "vpn" / f"vpn-{client_name}-am.conf"
        else:
            return None

        return str(path) if path.exists() else None

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
    # Clean username: take part before @ if email
    base_name = username.split("@")[0]

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
