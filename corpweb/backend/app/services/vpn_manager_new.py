"""
DB-backed VPN manager — replaces file/subprocess vpn_manager with WgBlobStore.

All WireGuard config state lives in the database (wg_file_state, wg_server_keys).
No filesystem access, no subprocess calls.
"""
from __future__ import annotations

import base64
import logging
import os
import re
from typing import List

from cryptography.hazmat.primitives.asymmetric.x25519 import X25519PrivateKey
from sqlalchemy import text
from sqlalchemy.orm import Session

from app.db.models import WgServerKeys
from app.services.wg_blob_store import WgBlobStore
from app.services.wg_templates import (
    Peer,
    next_free_ip,
    parse_peers,
    render_client_conf,
    render_server_conf,
    reverse_peer_keys,
)

logger = logging.getLogger(__name__)

# ---------------------------------------------------------------------------
# Interface definitions
# ---------------------------------------------------------------------------

_IFACE_CONFIG = {
    "antizapret": {
        "address": "10.29.8.1/21",
        "subnet": "10.29.8.0/21",
        "conf_path": "/etc/wireguard/antizapret.conf",
    },
    "vpn": {
        "address": "10.28.8.1/21",
        "subnet": "10.28.8.0/21",
        "conf_path": "/etc/wireguard/vpn.conf",
    },
}

# Advisory lock ID — arbitrary but unique within the application
_ADVISORY_LOCK_ID = 8675309


# ---------------------------------------------------------------------------
# Advisory lock helpers (no-op on SQLite)
# ---------------------------------------------------------------------------

def _advisory_lock(db: Session) -> None:
    try:
        db.execute(text("SELECT pg_try_advisory_lock(:id)"), {"id": _ADVISORY_LOCK_ID})
    except Exception:
        pass  # SQLite — no-op


def _advisory_unlock(db: Session) -> None:
    try:
        db.execute(text("SELECT pg_advisory_unlock(:id)"), {"id": _ADVISORY_LOCK_ID})
    except Exception:
        pass


# ---------------------------------------------------------------------------
# Key generation
# ---------------------------------------------------------------------------

def _generate_keypair() -> tuple[str, str]:
    """Generate an X25519 keypair. Returns (private_key_b64, public_key_b64)."""
    priv = X25519PrivateKey.generate()
    priv_b64 = base64.b64encode(priv.private_bytes_raw()).decode()
    pub_b64 = base64.b64encode(priv.public_key().public_bytes_raw()).decode()
    return priv_b64, pub_b64


def _generate_preshared_key() -> str:
    """Generate a 32-byte random preshared key, base64-encoded."""
    return base64.b64encode(os.urandom(32)).decode()


# ---------------------------------------------------------------------------
# Standalone helpers
# ---------------------------------------------------------------------------

def generate_client_name(username: str, existing_names: list[str]) -> str:
    """
    Generate unique client name: username-1, username-2, etc.

    Takes the part before @ (if email), replaces disallowed chars with
    underscore, then appends the next available number.
    """
    base_name = re.sub(r"[^a-zA-Z0-9_-]", "_", username.split("@")[0])

    max_number = 0
    pattern = re.compile(rf"^{re.escape(base_name)}-(\d+)$")
    for name in existing_names:
        match = pattern.match(name)
        if match:
            max_number = max(max_number, int(match.group(1)))

    return f"{base_name}-{max_number + 1}"


# ---------------------------------------------------------------------------
# VpnManager
# ---------------------------------------------------------------------------

class VpnManager:
    """
    DB-backed WireGuard peer management.

    All config state is stored in wg_file_state (via WgBlobStore) and
    wg_server_keys. Methods are transaction-safe and use advisory locks
    to prevent concurrent IP allocation.
    """

    # ------------------------------------------------------------------
    # bootstrap
    # ------------------------------------------------------------------

    def bootstrap(self, db: Session) -> None:
        """
        Idempotent initialisation: create server keypairs and empty conf blobs.

        Safe to call on every startup.
        """
        store = WgBlobStore(db)

        for iface, cfg in _IFACE_CONFIG.items():
            # Create server keypair if it doesn't exist
            existing = db.get(WgServerKeys, iface)
            if existing is None:
                priv, pub = _generate_keypair()
                row = WgServerKeys(iface=iface, private_key=priv, public_key=pub)
                db.add(row)
                db.commit()
                logger.info("Created server keypair for %s", iface)
            else:
                priv = existing.private_key

            # Create empty server conf blob if it doesn't exist
            if store.get(cfg["conf_path"]) is None:
                conf = render_server_conf(
                    iface=iface,
                    peers=[],
                    server_privkey=priv,
                    address=cfg["address"],
                )
                store.put(cfg["conf_path"], conf.encode(), by="bootstrap")
                logger.info("Created initial conf blob for %s", iface)

    # ------------------------------------------------------------------
    # add_peer
    # ------------------------------------------------------------------

    def add_peer(self, db: Session, name: str) -> dict:
        """
        Add a peer to both antizapret and vpn server configs.

        Uses an advisory lock to prevent concurrent IP allocation.

        Returns:
            dict with client_name, vpn_ip, private_key,
            public_key_antizapret, preshared_key.
        """
        _advisory_lock(db)
        try:
            return self._add_peer_impl(db, name)
        finally:
            _advisory_unlock(db)

    def _add_peer_impl(self, db: Session, name: str) -> dict:
        store = WgBlobStore(db)

        # Generate client keypair and preshared key
        client_priv, client_pub = _generate_keypair()
        psk = _generate_preshared_key()

        # Determine free IP from antizapret subnet (both ifaces share same IP)
        az_cfg = _IFACE_CONFIG["antizapret"]
        az_blob = store.get(az_cfg["conf_path"])
        az_content = az_blob.decode() if az_blob else ""
        az_peers = parse_peers(az_content)
        free_ip = next_free_ip(az_peers, az_cfg["subnet"])

        new_peer = Peer(
            name=name,
            public_key=client_pub,
            preshared_key=psk,
            allowed_ips=f"{free_ip}/32",
        )

        # Update both interface configs
        for iface, cfg in _IFACE_CONFIG.items():
            blob = store.get(cfg["conf_path"])
            content = blob.decode() if blob else ""
            existing_peers = parse_peers(content)

            server_keys = db.get(WgServerKeys, iface)
            all_peers = existing_peers + [new_peer]
            new_conf = render_server_conf(
                iface=iface,
                peers=all_peers,
                server_privkey=server_keys.private_key,
                address=cfg["address"],
            )
            store.put(cfg["conf_path"], new_conf.encode(), by="add_peer")

        return {
            "client_name": name,
            "vpn_ip": free_ip,
            "private_key": client_priv,
            "public_key_antizapret": client_pub,
            "preshared_key": psk,
        }

    # ------------------------------------------------------------------
    # delete_peer
    # ------------------------------------------------------------------

    def delete_peer(self, db: Session, name: str) -> None:
        """Remove a peer from both antizapret and vpn server configs."""
        store = WgBlobStore(db)

        for iface, cfg in _IFACE_CONFIG.items():
            blob = store.get(cfg["conf_path"])
            if blob is None:
                continue
            content = blob.decode()
            peers = parse_peers(content)
            filtered = [p for p in peers if p.name != name]

            if len(filtered) == len(peers):
                continue  # peer not in this conf

            server_keys = db.get(WgServerKeys, iface)
            new_conf = render_server_conf(
                iface=iface,
                peers=filtered,
                server_privkey=server_keys.private_key,
                address=cfg["address"],
            )
            store.put(cfg["conf_path"], new_conf.encode(), by="delete_peer")

    # ------------------------------------------------------------------
    # disable_peer / enable_peer
    # ------------------------------------------------------------------

    def disable_peer(self, db: Session, name: str) -> None:
        """Disable a peer by reversing its keys in both server configs."""
        self._toggle_peer(db, name)

    def enable_peer(self, db: Session, name: str) -> None:
        """Re-enable a previously disabled peer (reverse_peer_keys is self-inverse)."""
        self._toggle_peer(db, name)

    def _toggle_peer(self, db: Session, name: str) -> None:
        store = WgBlobStore(db)
        for _iface, cfg in _IFACE_CONFIG.items():
            blob = store.get(cfg["conf_path"])
            if blob is None:
                continue
            content = blob.decode()
            if f"# Client = {name}" not in content:
                continue
            new_content = reverse_peer_keys(content, name)
            if new_content != content:
                store.put(cfg["conf_path"], new_content.encode(), by="toggle_peer")

    # ------------------------------------------------------------------
    # list_peers
    # ------------------------------------------------------------------

    def list_peers(self, db: Session) -> list[dict]:
        """
        Parse peers from the antizapret server conf blob.

        Returns list of dicts: [{name, public_key, allowed_ips}, ...]
        """
        store = WgBlobStore(db)
        az_cfg = _IFACE_CONFIG["antizapret"]
        blob = store.get(az_cfg["conf_path"])
        if blob is None:
            return []
        content = blob.decode()
        peers = parse_peers(content)
        return [
            {
                "name": p.name,
                "public_key": p.public_key,
                "allowed_ips": p.allowed_ips,
            }
            for p in peers
        ]

    # ------------------------------------------------------------------
    # get_client_conf
    # ------------------------------------------------------------------

    def get_client_conf(
        self,
        db: Session,
        name: str,
        flavor: str,
        endpoint_host: str,
        iface: str = "antizapret",
        *,
        client_private_key: str | None = None,
        allowed_ips: str | None = None,
    ) -> str:
        """
        Render a client config in-memory from the server conf blob.

        Args:
            name: client name (must exist in the conf).
            flavor: "wg" or "awg".
            endpoint_host: server hostname or IP.
            iface: "antizapret" or "vpn".
            client_private_key: if provided, embed the real key instead of placeholder.
            allowed_ips: override AllowedIPs for antizapret.

        Returns:
            Rendered client config string.

        Raises:
            ValueError: if the peer is not found.
        """
        store = WgBlobStore(db)
        cfg = _IFACE_CONFIG[iface]
        blob = store.get(cfg["conf_path"])
        if blob is None:
            raise ValueError(f"Peer '{name}' not found: no conf for {iface}")

        content = blob.decode()
        peers = parse_peers(content)
        target = None
        for p in peers:
            if p.name == name:
                target = p
                break

        if target is None:
            raise ValueError(f"Peer '{name}' not found in {iface} config")

        server_keys = db.get(WgServerKeys, iface)
        return render_client_conf(
            peer=target,
            iface=iface,
            server_pubkey=server_keys.public_key,
            endpoint_host=endpoint_host,
            flavor=flavor,
            client_private_key=client_private_key,
            allowed_ips=allowed_ips,
        )

    # ------------------------------------------------------------------
    # get_antizapret_allowed_ips
    # ------------------------------------------------------------------

    def get_antizapret_allowed_ips(self, db: Session) -> str | None:
        """Return the antizapret allowed IPs blob, or None if not set."""
        store = WgBlobStore(db)
        blob = store.get("antizapret:allowed_ips")
        return blob.decode() if blob else None

    # ------------------------------------------------------------------
    # check_all_nodes_applied
    # ------------------------------------------------------------------

    def check_all_nodes_applied(self, db: Session, path: str) -> bool:
        """
        Return True if all live nodes have applied the current blob at *path*.

        Returns True if there is no current blob or no live nodes.
        """
        from app.db.models import Node
        store = WgBlobStore(db)
        paths = store.get_all_paths()
        current_sha = paths.get(path)
        if not current_sha:
            return True
        live_nodes = db.query(Node).filter(Node.health.in_(["ok", "degraded"])).all()
        if not live_nodes:
            return True
        for node in live_nodes:
            if (node.applied_sha or {}).get(path) != current_sha:
                return False
        return True


# Module-level singleton (mirrors old vpn_manager pattern)
vpn_manager = VpnManager()
