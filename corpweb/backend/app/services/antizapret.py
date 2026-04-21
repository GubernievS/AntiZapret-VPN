"""
Antizapret configuration service.
Manages /root/antizapret/setup settings and editable config files
via WgBlobStore (stored in DB, not filesystem).
"""
import re
import logging
from typing import Dict, Optional

from sqlalchemy.orm import Session

from app.services.wg_blob_store import WgBlobStore

logger = logging.getLogger(__name__)

ANTIZAPRET_SETUP_FILE = "/root/antizapret/setup"

EDITABLE_FILES: Dict[str, str] = {
    "include_hosts":         "/root/antizapret/config/include-hosts.txt",
    "exclude_hosts":         "/root/antizapret/config/exclude-hosts.txt",
    "include_ips":           "/root/antizapret/config/include-ips.txt",
    "exclude_ips":           "/root/antizapret/config/exclude-ips.txt",
    "allow_ips":             "/root/antizapret/config/allow-ips.txt",
    "forward_ips":           "/root/antizapret/config/forward-ips.txt",
    "include_adblock_hosts": "/root/antizapret/config/include-adblock-hosts.txt",
    "exclude_adblock_hosts": "/root/antizapret/config/exclude-adblock-hosts.txt",
    "remove_hosts":          "/root/antizapret/config/remove-hosts.txt",
}

# Settings stored as y/n
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
    "SSH_PROTECTION",
    "ATTACK_PROTECTION",
    "TORRENT_GUARD",
    "RESTRICT_FORWARD",
    "ALTERNATIVE_CLIENT_IP",
    "ALTERNATIVE_FAKE_IP",
    "CLIENT_ISOLATION",
    "WIREGUARD_BACKUP",
]

# Settings stored as 1/0 (shown as toggle in UI)
NUMERIC_BOOLEAN_SETTINGS = [
    "ANTIZAPRET_DNS",
    "VPN_DNS",
]

STRING_SETTINGS = [
    "WIREGUARD_HOST",
    "WARP_OUTBOUND",
]

ALL_KNOWN_SETTINGS = BOOLEAN_SETTINGS + NUMERIC_BOOLEAN_SETTINGS + STRING_SETTINGS


class AntizapretServiceError(Exception):
    pass


class AntizapretService:

    def __init__(self, db: Session):
        self._store = WgBlobStore(db)

    def get_file_content(self, file_type: str) -> str:
        """Read one of the editable config files from the blob store."""
        if file_type not in EDITABLE_FILES:
            raise AntizapretServiceError(f"Unknown file type: {file_type}")
        path = EDITABLE_FILES[file_type]
        data = self._store.get(path)
        if data is None:
            return ""
        return data.decode("utf-8")

    def save_file_content(self, file_type: str, content: str) -> None:
        """Write one of the editable config files to the blob store."""
        if file_type not in EDITABLE_FILES:
            raise AntizapretServiceError(f"Unknown file type: {file_type}")
        path = EDITABLE_FILES[file_type]
        self._store.put(path, content.encode("utf-8"), by="admin")
        logger.info(f"Saved antizapret file: {path}")

    def get_settings(self) -> Dict[str, Optional[str]]:
        """
        Read /root/antizapret/setup from blob store and return known settings.
        Returns dict where missing keys have value None.
        """
        result: Dict[str, Optional[str]] = {k: None for k in ALL_KNOWN_SETTINGS}
        data = self._store.get(ANTIZAPRET_SETUP_FILE)
        if data is None:
            return result

        content = data.decode("utf-8")
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
        Update /root/antizapret/setup in blob store with provided key-value pairs.
        Only keys in ALL_KNOWN_SETTINGS are accepted.
        Preserves comments and unknown lines.
        Returns count of changed parameters.
        """
        data = self._store.get(ANTIZAPRET_SETUP_FILE)
        if data is None:
            raise AntizapretServiceError(f"Setup file not found: {ANTIZAPRET_SETUP_FILE}")

        content = data.decode("utf-8")
        changed = 0

        for key, value in new_settings.items():
            if key not in ALL_KNOWN_SETTINGS:
                continue
            # Sanitize boolean values
            if key in BOOLEAN_SETTINGS:
                value = "y" if value.lower() in ("y", "yes", "true", "1") else "n"
            elif key in NUMERIC_BOOLEAN_SETTINGS:
                value = "1" if value.lower() in ("1", "y", "yes", "true") else "0"

            line_pattern = re.compile(rf'^{re.escape(key)}=.*$', re.MULTILINE)
            new_line = f"{key}={value}"
            if line_pattern.search(content):
                content = line_pattern.sub(new_line, content)
            else:
                content = content.rstrip("\n") + f"\n{new_line}\n"
            changed += 1

        self._store.put(ANTIZAPRET_SETUP_FILE, content.encode("utf-8"), by="admin")
        logger.info(f"Updated {changed} antizapret settings")
        return changed
