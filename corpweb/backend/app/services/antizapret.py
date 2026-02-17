"""
Antizapret configuration service.
Manages /root/antizapret/setup settings and editable config files.
"""
import re
import subprocess
import logging
from pathlib import Path
from typing import Dict, Optional

logger = logging.getLogger(__name__)

ANTIZAPRET_SETUP_FILE = "/root/antizapret/setup"
ANTIZAPRET_DOALL_SCRIPT = "/root/antizapret/doall.sh"

EDITABLE_FILES: Dict[str, str] = {
    "include_hosts": "/root/antizapret/config/include-hosts.txt",
    "exclude_hosts": "/root/antizapret/config/exclude-hosts.txt",
    "include_ips": "/root/antizapret/config/include-ips.txt",
}

BOOLEAN_SETTINGS = [
    "ROUTE_ALL",
    "DISCORD_INCLUDE",
    "CLOUDFLARE_INCLUDE",
    "AMAZON_INCLUDE",
    "GOOGLE_INCLUDE",
    "WHATSAPP_INCLUDE",
    "TELEGRAM_INCLUDE",
    "HETZNER_INCLUDE",
    "DIGITALOCEAN_INCLUDE",
    "OVH_INCLUDE",
    "AKAMAI_INCLUDE",
    "ROBLOX_INCLUDE",
    "BLOCK_ADS",
    "CLEAR_HOSTS",
    "OPENVPN_80_443_TCP",
    "OPENVPN_80_443_UDP",
    "SSH_PROTECTION",
    "ATTACK_PROTECTION",
    "TORRENT_GUARD",
    "RESTRICT_FORWARD",
]

STRING_SETTINGS = [
    "OPENVPN_HOST",
    "WIREGUARD_HOST",
]

ALL_KNOWN_SETTINGS = BOOLEAN_SETTINGS + STRING_SETTINGS


class AntizapretServiceError(Exception):
    pass


class AntizapretService:

    def get_file_content(self, file_type: str) -> str:
        """Read one of the editable config files."""
        if file_type not in EDITABLE_FILES:
            raise AntizapretServiceError(f"Unknown file type: {file_type}")
        path = Path(EDITABLE_FILES[file_type])
        if not path.exists():
            return ""
        return path.read_text(encoding="utf-8")

    def save_file_content(self, file_type: str, content: str) -> None:
        """Write one of the editable config files."""
        if file_type not in EDITABLE_FILES:
            raise AntizapretServiceError(f"Unknown file type: {file_type}")
        path = Path(EDITABLE_FILES[file_type])
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(content, encoding="utf-8")
        logger.info(f"Saved antizapret file: {path}")

    def get_settings(self) -> Dict[str, Optional[str]]:
        """
        Read /root/antizapret/setup and return known settings.
        Returns dict where missing keys have value None.
        """
        path = Path(ANTIZAPRET_SETUP_FILE)
        result: Dict[str, Optional[str]] = {k: None for k in ALL_KNOWN_SETTINGS}
        if not path.exists():
            return result

        content = path.read_text(encoding="utf-8")
        # Match lines like: KEY=value or KEY="value" or KEY='value'
        pattern = re.compile(r'^([A-Z0-9_]+)=["\']?([^"\'#\n]*)["\']?\s*(?:#.*)?$', re.MULTILINE)
        for match in pattern.finditer(content):
            key = match.group(1)
            value = match.group(2).strip()
            if key in result:
                result[key] = value
        return result

    def update_settings(self, new_settings: Dict[str, str]) -> int:
        """
        Update /root/antizapret/setup with provided key-value pairs.
        Only keys in ALL_KNOWN_SETTINGS are accepted.
        Preserves comments and unknown lines.
        Returns count of changed parameters.
        """
        path = Path(ANTIZAPRET_SETUP_FILE)
        if not path.exists():
            raise AntizapretServiceError(f"Setup file not found: {ANTIZAPRET_SETUP_FILE}")

        content = path.read_text(encoding="utf-8")
        changed = 0

        for key, value in new_settings.items():
            if key not in ALL_KNOWN_SETTINGS:
                continue
            # Sanitize boolean values
            if key in BOOLEAN_SETTINGS:
                value = "y" if value.lower() in ("y", "yes", "true", "1") else "n"

            line_pattern = re.compile(rf'^{re.escape(key)}=.*$', re.MULTILINE)
            new_line = f"{key}={value}"
            if line_pattern.search(content):
                content = line_pattern.sub(new_line, content)
            else:
                content = content.rstrip("\n") + f"\n{new_line}\n"
            changed += 1

        path.write_text(content, encoding="utf-8")
        logger.info(f"Updated {changed} antizapret settings")
        return changed

    def run_doall(self, timeout: int = 300) -> str:
        """Execute /root/antizapret/doall.sh to apply changes."""
        script = Path(ANTIZAPRET_DOALL_SCRIPT)
        if not script.exists():
            raise AntizapretServiceError(f"Script not found: {ANTIZAPRET_DOALL_SCRIPT}")

        try:
            result = subprocess.run(
                [str(script)],
                capture_output=True,
                text=True,
                timeout=timeout,
                check=False,
            )
            if result.returncode != 0:
                raise AntizapretServiceError(
                    f"doall.sh failed (exit {result.returncode}): {result.stderr.strip()}"
                )
            logger.info("doall.sh completed successfully")
            return result.stdout
        except subprocess.TimeoutExpired:
            raise AntizapretServiceError("doall.sh timed out (limit: 5 min)")
        except FileNotFoundError:
            raise AntizapretServiceError(f"Script not executable: {ANTIZAPRET_DOALL_SCRIPT}")


antizapret_service = AntizapretService()
