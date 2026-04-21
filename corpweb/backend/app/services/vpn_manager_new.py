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
from app.services.obfuscation_service import ensure_initialized, get_params
from app.services.wg_blob_store import WgBlobStore
from app.services.wg_templates import (
    Peer,
    next_free_ip,
    parse_peers,
    render_client_conf,
    render_server_conf,
    reverse_peer_keys,
)

_ESCAPE_IFACES = ("antizapret_escape", "vpn_escape")

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
    "antizapret_escape": {
        "address": "10.27.8.1/21",
        "subnet": "10.27.8.0/21",
        "conf_path": "/etc/wireguard/antizapret_escape.conf",
    },
    "vpn_escape": {
        "address": "10.26.8.1/21",
        "subnet": "10.26.8.0/21",
        "conf_path": "/etc/wireguard/vpn_escape.conf",
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

        For escape ifaces (``*_escape``), also ensures ``wg_obfuscation_params``
        rows exist and bakes those params into the freshly-rendered
        server conf.

        Safe to call on every startup.
        """
        # Ensure obfuscation params exist for escape ifaces before we render
        # their server confs.
        ensure_initialized(db, ifaces=list(_ESCAPE_IFACES))

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
                awg = get_params(db, iface) if iface in _ESCAPE_IFACES else None
                conf = render_server_conf(
                    iface=iface,
                    peers=[],
                    server_privkey=priv,
                    address=cfg["address"],
                    awg_params=awg,
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

        # Determine free IP from antizapret subnet (canonical source)
        # VPN peer gets IP with same host part in 10.28.x.x subnet
        az_cfg = _IFACE_CONFIG["antizapret"]
        az_blob = store.get(az_cfg["conf_path"])
        az_content = az_blob.decode() if az_blob else ""
        az_peers = parse_peers(az_content)
        free_ip = next_free_ip(az_peers, az_cfg["subnet"])

        # Per-iface IP: each iface gets the same host part in its own /21:
        #   antizapret        = 10.29.x.x
        #   vpn               = 10.28.x.x
        #   antizapret_escape = 10.27.x.x
        #   vpn_escape        = 10.26.x.x
        host_parts = free_ip.split(".")[2:]  # last 2 octets
        iface_ip = {
            "antizapret":        free_ip,
            "vpn":               f"10.28.{host_parts[0]}.{host_parts[1]}",
            "antizapret_escape": f"10.27.{host_parts[0]}.{host_parts[1]}",
            "vpn_escape":        f"10.26.{host_parts[0]}.{host_parts[1]}",
        }

        # Update all four interface configs (2 base + 2 escape).
        for iface, cfg in _IFACE_CONFIG.items():
            blob = store.get(cfg["conf_path"])
            content = blob.decode() if blob else ""
            existing_peers = parse_peers(content)

            new_peer = Peer(
                name=name,
                public_key=client_pub,
                preshared_key=psk,
                allowed_ips=f"{iface_ip[iface]}/32",
            )

            server_keys = db.get(WgServerKeys, iface)
            all_peers = existing_peers + [new_peer]
            awg = get_params(db, iface) if iface in _ESCAPE_IFACES else None
            new_conf = render_server_conf(
                iface=iface,
                peers=all_peers,
                server_privkey=server_keys.private_key,
                address=cfg["address"],
                awg_params=awg,
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
        """Remove a peer from all four server configs (base + escape)."""
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
            awg = get_params(db, iface) if iface in _ESCAPE_IFACES else None
            new_conf = render_server_conf(
                iface=iface,
                peers=filtered,
                server_privkey=server_keys.private_key,
                address=cfg["address"],
                awg_params=awg,
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
        use_backup_port: bool = False,
        bypass: bool = False,
    ) -> str:
        """
        Render a client config in-memory from the server conf blob.

        Args:
            name: client name (must exist in the conf).
            flavor: "wg" or "awg".
            endpoint_host: server hostname or IP.
            iface: "antizapret" or "vpn" — the *logical* iface choice.
            client_private_key: if provided, embed the real key instead of placeholder.
            allowed_ips: override AllowedIPs for antizapret.
            use_backup_port: route through UDP 540/580 (base ifaces only).
            bypass: if True, serve the peer from the corresponding
                ``{iface}_escape`` interface and inject per-iface obfuscation
                params. Mutually exclusive with ``use_backup_port``.

        Returns:
            Rendered client config string.

        Raises:
            ValueError: if the peer is not found, or if ``bypass`` is combined
                with ``use_backup_port``, or if bypass obfuscation params are
                missing from the DB.
        """
        if bypass and use_backup_port:
            raise ValueError(
                "bypass and backup_port are mutually exclusive"
            )

        effective_iface = f"{iface}_escape" if bypass else iface

        store = WgBlobStore(db)
        cfg = _IFACE_CONFIG[effective_iface]
        blob = store.get(cfg["conf_path"])
        if blob is None:
            raise ValueError(
                f"Peer '{name}' not found: no conf for {effective_iface}"
            )

        content = blob.decode()
        peers = parse_peers(content)
        target = None
        for p in peers:
            if p.name == name:
                target = p
                break

        if target is None:
            raise ValueError(
                f"Peer '{name}' not found in {effective_iface} config"
            )

        server_keys = db.get(WgServerKeys, effective_iface)

        awg = None
        if bypass:
            awg = get_params(db, effective_iface)
            if awg is None:
                raise ValueError(
                    f"bypass requested for '{effective_iface}' but no "
                    "obfuscation params exist; run bootstrap() first"
                )

        return render_client_conf(
            peer=target,
            iface=effective_iface,
            server_pubkey=server_keys.public_key,
            endpoint_host=endpoint_host,
            flavor=flavor,
            client_private_key=client_private_key,
            allowed_ips=allowed_ips,
            use_backup_port=use_backup_port,
            awg_params=awg,
        )

    # ------------------------------------------------------------------
    # rerender_escape_server_confs
    # ------------------------------------------------------------------

    def rerender_escape_server_confs(self, db: Session) -> None:
        """
        Re-render the two escape server .conf blobs with whatever obfuscation
        params are currently stored in the DB.

        Preserves existing peers. Used after ``obfuscation_service.regenerate``
        so agents pick up the new params via the wg_file_state SSE stream.
        """
        store = WgBlobStore(db)
        for iface in _ESCAPE_IFACES:
            cfg = _IFACE_CONFIG[iface]
            blob = store.get(cfg["conf_path"])
            peers = parse_peers(blob.decode()) if blob else []
            server_keys = db.get(WgServerKeys, iface)
            if server_keys is None:
                continue  # bootstrap hasn't run yet — skip quietly
            awg = get_params(db, iface)
            new_conf = render_server_conf(
                iface=iface,
                peers=peers,
                server_privkey=server_keys.private_key,
                address=cfg["address"],
                awg_params=awg,
            )
            store.put(cfg["conf_path"], new_conf.encode(), by="regenerate")

    # ------------------------------------------------------------------
    # backfill_escape_peers
    # ------------------------------------------------------------------

    def backfill_escape_peers(self, db: Session) -> None:
        """
        Copy peers from the antizapret server conf into the two escape server
        confs, preserving ``public_key`` + ``preshared_key`` and rewriting
        ``allowed_ips`` to the corresponding escape subnet.

        Meaningful for deployments upgraded across the Phase-2 cutover:
        peers added BEFORE Phase 2 only exist in antizapret/vpn confs,
        so the escape ifaces lack them. New peers (added after Phase 2)
        already land in all four ifaces via :meth:`add_peer`, so this
        helper is a no-op for them.

        Idempotent — peers already present in an escape conf (matched by
        name OR public_key) are left untouched.

        Requires :meth:`bootstrap` to have run (keypairs + obfuscation
        params must exist for escape ifaces).
        """
        store = WgBlobStore(db)

        az_cfg = _IFACE_CONFIG["antizapret"]
        az_blob = store.get(az_cfg["conf_path"])
        if az_blob is None:
            return  # no base peers to backfill from
        az_peers = parse_peers(az_blob.decode())
        if not az_peers:
            return

        # Mapping: iface -> subnet prefix for escape IP rewrite.
        _ESCAPE_PREFIX = {
            "antizapret_escape": "10.27",
            "vpn_escape": "10.26",
        }

        for iface in _ESCAPE_IFACES:
            cfg = _IFACE_CONFIG[iface]
            blob = store.get(cfg["conf_path"])
            existing_peers = parse_peers(blob.decode()) if blob else []
            existing_names = {p.name for p in existing_peers}
            existing_pubkeys = {p.public_key for p in existing_peers}

            added_any = False
            for az_peer in az_peers:
                if az_peer.name in existing_names:
                    continue
                if az_peer.public_key in existing_pubkeys:
                    continue

                # Rewrite host part into the escape subnet, preserving
                # the last two octets (matches _add_peer_impl convention).
                az_ip = az_peer.allowed_ips.split("/", 1)[0]
                host_parts = az_ip.split(".")[2:]  # ["x", "y"]
                new_ip = f"{_ESCAPE_PREFIX[iface]}.{host_parts[0]}.{host_parts[1]}"

                existing_peers.append(
                    Peer(
                        name=az_peer.name,
                        public_key=az_peer.public_key,
                        preshared_key=az_peer.preshared_key,
                        allowed_ips=f"{new_ip}/32",
                    )
                )
                existing_names.add(az_peer.name)
                existing_pubkeys.add(az_peer.public_key)
                added_any = True

            if not added_any:
                continue  # nothing changed — skip re-render for idempotency

            server_keys = db.get(WgServerKeys, iface)
            if server_keys is None:
                # bootstrap() must run first; bail quietly rather than crash
                # (migration wraps this in try/except anyway).
                logger.warning(
                    "backfill_escape_peers: no server keys for %s — skipping",
                    iface,
                )
                continue

            awg = get_params(db, iface)
            new_conf = render_server_conf(
                iface=iface,
                peers=existing_peers,
                server_privkey=server_keys.private_key,
                address=cfg["address"],
                awg_params=awg,
            )
            store.put(cfg["conf_path"], new_conf.encode(), by="backfill_escape_peers")
            logger.info("backfill_escape_peers: re-rendered %s", iface)

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
