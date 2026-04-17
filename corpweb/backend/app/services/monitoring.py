"""Monitoring service — reads from nodes.peers_snapshot (agent heartbeats)."""
import time
from sqlalchemy.orm import Session
from app.db.models import Node, VPNConfig

ACTIVE_HANDSHAKE_MAX_AGE = 180  # 3 minutes — matches WG convention for "active" peer


class MonitoringService:
    def __init__(self, db: Session):
        self._db = db

    def get_active_connections(self, node_filter=None) -> list[dict]:
        query = self._db.query(Node).filter(Node.health.in_(["ok", "degraded"]))
        if node_filter:
            query = query.filter(Node.hostname == node_filter)
        nodes = query.all()
        ip_to_name = self._build_ip_map()
        now = int(time.time())
        result = []
        for node in nodes:
            for peer in (node.peers_snapshot or []):
                hs = peer.get("latest_handshake", 0)
                if hs == 0 or (now - hs) > ACTIVE_HANDSHAKE_MAX_AGE:
                    continue
                ip = (peer.get("allowed_ips") or "").split("/")[0]
                result.append({
                    "node": node.hostname,
                    "interface": peer.get("interface", ""),
                    "public_key": peer.get("public_key", ""),
                    "client_name": ip_to_name.get(ip),
                    "endpoint": peer.get("endpoint"),
                    "allowed_ips": peer.get("allowed_ips"),
                    "handshake_age": now - hs,
                    "rx_bytes": peer.get("rx_bytes", 0),
                    "tx_bytes": peer.get("tx_bytes", 0),
                })
        return result

    def get_traffic_stats(self) -> dict:
        nodes = self._db.query(Node).filter(Node.health.in_(["ok", "degraded"])).all()
        total_rx = total_tx = 0
        per_node = []
        for n in nodes:
            m = n.metrics or {}
            rx = m.get("rx_bytes_per_sec", 0)
            tx = m.get("tx_bytes_per_sec", 0)
            total_rx += rx
            total_tx += tx
            per_node.append({"hostname": n.hostname, "rx_bytes_per_sec": rx, "tx_bytes_per_sec": tx})
        return {"total_rx_bytes_per_sec": total_rx, "total_tx_bytes_per_sec": total_tx, "per_node": per_node}

    def get_overview(self) -> dict:
        return {"connections": self.get_active_connections(), "traffic": self.get_traffic_stats()}

    def _build_ip_map(self) -> dict[str, str]:
        configs = self._db.query(VPNConfig).filter(VPNConfig.is_active == True).all()
        return {
            (cfg.config_metadata or {}).get("vpn_ip", ""): cfg.client_name
            for cfg in configs
            if (cfg.config_metadata or {}).get("vpn_ip")
        }
