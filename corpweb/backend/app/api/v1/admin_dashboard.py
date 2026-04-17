"""Admin Dashboard — aggregate data from nodes, configs, users."""
from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session

from app.db.session import get_db
from app.db.models import Node, VPNConfig, User
from app.api.deps import require_admin
from app.services.wg_blob_store import WgBlobStore

router = APIRouter()


@router.get("")
def get_dashboard(
    db: Session = Depends(get_db),
    _=Depends(require_admin),
):
    nodes = db.query(Node).order_by(Node.id).all()
    store = WgBlobStore(db)
    all_paths = store.get_all_paths()

    total_active = 0
    node_data = []
    for n in nodes:
        m = n.metrics or {}
        az = m.get("active_peers_antizapret", 0)
        vpn = m.get("active_peers_vpn", 0)
        total_active += az + vpn

        applied = n.applied_sha or {}
        synced = all(
            applied.get(p) == all_paths.get(p)
            for p in all_paths
            if p.startswith("/")
        )

        node_data.append({
            "id": n.id,
            "hostname": n.hostname,
            "health": n.health,
            "active_peers_antizapret": az,
            "active_peers_vpn": vpn,
            "rx_bytes_per_sec": m.get("rx_bytes_per_sec", 0),
            "tx_bytes_per_sec": m.get("tx_bytes_per_sec", 0),
            "synced": synced,
            "last_seen": n.last_seen.isoformat() if n.last_seen else None,
        })

    total_configs = db.query(VPNConfig).count()
    total_users = db.query(User).count()

    return {
        "nodes": node_data,
        "totals": {
            "active_clients": total_active,
            "total_configs": total_configs,
            "total_users": total_users,
        },
    }
