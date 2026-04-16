"""
One-time file→DB migration script for wgfi2.

Reads WireGuard config files from disk and stores them in the database.
Run with:  python3 -m app.migrate

The `root` parameter prefixes every absolute path, making the script
testable with a tmpdir without touching the real filesystem.

All operations are idempotent — safe to run multiple times.
"""
from __future__ import annotations

import glob
import logging
import os
import re
from typing import Optional

from sqlalchemy.orm import Session

from app.db.models import VPNConfig, WgServerKeys
from app.services.wg_blob_store import WgBlobStore

logger = logging.getLogger(__name__)

# ---------------------------------------------------------------------------
# Managed files that are stored verbatim into wg_file_state
# ---------------------------------------------------------------------------

# Paths are absolute (as they exist on the server).  The `root` prefix lets
# tests redirect them to a tmpdir without changing the path keys stored in DB.
_MANAGED_FILES: list[str] = [
    "/etc/wireguard/antizapret.conf",
    "/etc/wireguard/vpn.conf",
    "/root/antizapret/setup",
    "/root/antizapret/config/include-hosts.txt",
    "/root/antizapret/config/exclude-hosts.txt",
    "/root/antizapret/config/include-ips.txt",
    "/root/antizapret/config/exclude-ips.txt",
    "/root/antizapret/config/allow-ips.txt",
    "/root/antizapret/config/forward-ips.txt",
    "/root/antizapret/config/include-adblock-hosts.txt",
    "/root/antizapret/config/exclude-adblock-hosts.txt",
    "/root/antizapret/config/remove-hosts.txt",
]

# Glob pattern for client antizapret conf files (used to extract AllowedIPs)
_CLIENT_CONF_GLOB = "/root/antizapret/client/amneziawg/antizapret/antizapret-*-am.conf"

# Path to the server keypair file
_KEY_FILE = "/etc/wireguard/key"

# Blob path for the AllowedIPs template
_ALLOWED_IPS_BLOB_PATH = "antizapret:allowed_ips"

# Interfaces that share the same server keypair
_IFACES = ("antizapret", "vpn")


# ---------------------------------------------------------------------------
# Pure parsing helpers
# ---------------------------------------------------------------------------

def extract_client_private_keys(server_conf: str) -> dict[str, str]:
    """
    Parse ``# PrivateKey = ...`` comments from a WireGuard server conf.

    Returns a mapping of {client_name: private_key_b64} for every peer
    block that has a ``# PrivateKey = ...`` comment between its
    ``# Client = ...`` marker and the ``[Peer]`` line.

    Example peer block::

        # Client = alice-1
        # PrivateKey = SLqNefHfHeFRkEm51kl4PlVEsKn20/+PmOsNOfIbcEU=
        [Peer]
        PublicKey = y5NLYcmC3YgIQWQq33IIv5c/B6tOCRPGN30YRr7UQnA=
    """
    result: dict[str, str] = {}
    pending_name: Optional[str] = None
    pending_privkey: Optional[str] = None

    for line in server_conf.splitlines():
        stripped = line.strip()

        if stripped.startswith("# Client") and "=" in stripped:
            pending_name = stripped.split("=", 1)[1].strip()
            pending_privkey = None
            continue

        if stripped.startswith("# PrivateKey") and "=" in stripped:
            pending_privkey = stripped.split("=", 1)[1].strip()
            continue

        if stripped == "[Peer]":
            if pending_name is not None and pending_privkey is not None:
                result[pending_name] = pending_privkey
            pending_name = None
            pending_privkey = None
            continue

        # Any non-comment, non-[Peer] line resets pending state when outside a
        # comment block (i.e. after a [Peer] header has been seen)
        if stripped and not stripped.startswith("#"):
            # Reset only if we haven't entered a peer block yet
            pass  # keep accumulating comment lines

    return result


def _parse_key_file(content: str) -> tuple[str, str]:
    """
    Parse ``/etc/wireguard/key`` and return (private_key, public_key).

    Expected format::

        PRIVATE_KEY=<base64>
        PUBLIC_KEY=<base64>
    """
    pairs: dict[str, str] = {}
    for line in content.splitlines():
        line = line.strip()
        if "=" in line:
            k, _, v = line.partition("=")
            pairs[k.strip()] = v.strip()
    return pairs["PRIVATE_KEY"], pairs["PUBLIC_KEY"]


def _parse_allowed_ips_from_client_conf(content: str) -> Optional[str]:
    """
    Extract the AllowedIPs value from a WireGuard client config.

    Returns the raw value string (e.g. ``"10.29.8.0/21, 100.64.0.0/10"``),
    or None if not found.
    """
    for line in content.splitlines():
        stripped = line.strip()
        lower = stripped.lower()
        if lower.startswith("allowedips") and "=" in stripped:
            return stripped.split("=", 1)[1].strip()
    return None


# ---------------------------------------------------------------------------
# Migration steps
# ---------------------------------------------------------------------------

def _migrate_file_state(db: Session, root: str) -> None:
    """Store the 12 managed files into wg_file_state."""
    store = WgBlobStore(db)
    for abs_path in _MANAGED_FILES:
        disk_path = root + abs_path
        if not os.path.exists(disk_path):
            logger.warning("Managed file not found, skipping: %s", disk_path)
            continue
        with open(disk_path, "rb") as fh:
            content = fh.read()
        store.put(abs_path, content, by="migrate")
        logger.info("Migrated file: %s (%d bytes)", abs_path, len(content))


def _migrate_server_keys(db: Session, root: str) -> None:
    """
    Read /etc/wireguard/key and store the keypair for both ifaces.

    Idempotent: upserts existing rows.
    """
    key_path = root + _KEY_FILE
    if not os.path.exists(key_path):
        logger.warning("Key file not found, skipping server key migration: %s", key_path)
        return

    with open(key_path) as fh:
        content = fh.read()

    private_key, public_key = _parse_key_file(content)

    for iface in _IFACES:
        existing = db.get(WgServerKeys, iface)
        if existing is None:
            row = WgServerKeys(
                iface=iface,
                private_key=private_key,
                public_key=public_key,
            )
            db.add(row)
        else:
            existing.private_key = private_key
            existing.public_key = public_key
        logger.info("Upserted server keys for iface: %s", iface)

    db.commit()


def _migrate_client_private_keys(db: Session, root: str) -> None:
    """
    Parse ``# PrivateKey = ...`` comments from the antizapret server conf
    and write the private key into config_metadata for matching VPNConfig rows.
    """
    conf_path = root + "/etc/wireguard/antizapret.conf"
    if not os.path.exists(conf_path):
        logger.warning("antizapret.conf not found, skipping client private key migration")
        return

    with open(conf_path) as fh:
        server_conf = fh.read()

    keys_by_name = extract_client_private_keys(server_conf)
    if not keys_by_name:
        logger.info("No client private keys found in server conf")
        return

    configs = db.query(VPNConfig).filter(
        VPNConfig.client_name.in_(keys_by_name.keys())
    ).all()

    for config in configs:
        private_key = keys_by_name[config.client_name]
        metadata = dict(config.config_metadata or {})
        metadata["private_key"] = private_key
        config.config_metadata = metadata
        logger.info("Updated private key in config_metadata for: %s", config.client_name)

    db.commit()


def _migrate_allowed_ips(db: Session, root: str) -> None:
    """
    Extract AllowedIPs from any existing antizapret client config file and
    store it as a blob at path ``antizapret:allowed_ips``.
    """
    pattern = root + _CLIENT_CONF_GLOB
    matches = glob.glob(pattern)
    if not matches:
        logger.info("No antizapret client conf found at %s, skipping AllowedIPs migration", pattern)
        return

    # Use the first match (there should typically be only one template file)
    client_conf_path = matches[0]
    with open(client_conf_path) as fh:
        content = fh.read()

    allowed_ips = _parse_allowed_ips_from_client_conf(content)
    if allowed_ips is None:
        logger.warning("AllowedIPs not found in %s", client_conf_path)
        return

    store = WgBlobStore(db)
    store.put(_ALLOWED_IPS_BLOB_PATH, allowed_ips.encode(), by="migrate")
    logger.info("Stored AllowedIPs template: %s", allowed_ips)


# ---------------------------------------------------------------------------
# Main entry point
# ---------------------------------------------------------------------------

def run(db: Session, root: str = "") -> None:
    """
    Run all migration steps.

    Args:
        db: SQLAlchemy session.
        root: Filesystem prefix for all paths (empty in production,
              tmpdir path in tests).  Must NOT end with a slash.
    """
    logger.info("=== Starting file→DB migration (root=%r) ===", root or "/")
    _migrate_file_state(db, root)
    _migrate_server_keys(db, root)
    _migrate_client_private_keys(db, root)
    _migrate_allowed_ips(db, root)
    logger.info("=== Migration complete ===")


if __name__ == "__main__":
    import sys

    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s %(levelname)s %(name)s: %(message)s",
        stream=sys.stdout,
    )

    from app.db.session import SessionLocal

    db = SessionLocal()
    try:
        run(db, root="")
    finally:
        db.close()
