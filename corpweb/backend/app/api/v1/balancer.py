"""
Balancer API — iptables DNAT load-balancer management.

GET  /nodes/balancer  — read actual iptables state, merge with DB nodes
PUT  /nodes/balancer  — validate + apply new weights, return live state
"""
import logging
from typing import List

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel
from sqlalchemy.orm import Session

from app.api.deps import require_admin
from app.db.session import get_db
from app.db.models import Node
from app.services.balancer import apply_rules, read_current_state

logger = logging.getLogger(__name__)
router = APIRouter()


def _detect_cp_ip(db: Session) -> str:
    """
    Determine control-plane IP for SNAT rules.
    Priority: system_settings.cp_ip from DB → auto-detect from default route.
    """
    from app.db.models import SystemSettings
    ss = db.query(SystemSettings).filter(SystemSettings.id == 1).first()
    if ss and ss.cp_ip:
        return ss.cp_ip

    # Auto-detect: IP of the default-route interface
    import subprocess
    try:
        result = subprocess.run(
            ["ip", "-4", "route", "get", "8.8.8.8"],
            capture_output=True, text=True, timeout=5,
        )
        parts = result.stdout.split()
        if "src" in parts:
            return parts[parts.index("src") + 1]
    except Exception:
        pass

    raise ValueError("Cannot determine CP IP. Set it in Settings → Nodes")


# ── Schemas ───────────────────────────────────────────────────────────────────

class NodeBalancerEntry(BaseModel):
    ip: str
    weight: int
    enabled: bool


class BalancerUpdateRequest(BaseModel):
    nodes: List[NodeBalancerEntry]


# ── Endpoints ─────────────────────────────────────────────────────────────────

@router.get("")
def get_balancer_state(
    db: Session = Depends(get_db),
    _=Depends(require_admin),
):
    """
    Read actual iptables DNAT state and merge with known nodes from DB.

    Returns:
        {
            "nodes": [
                {
                    "id": 1,
                    "hostname": "node1",
                    "ip": "1.2.3.4",
                    "health": "ok",
                    "weight": 50,
                    "enabled": true
                },
                ...
            ]
        }
    """
    try:
        iptables_state = read_current_state()
    except Exception as exc:
        logger.warning("Could not read iptables state: %s", exc)
        iptables_state = {}

    db_nodes = db.query(Node).order_by(Node.created_at).all()

    result = []
    for node in db_nodes:
        ip = node.private_ip
        state = iptables_state.get(ip, {})
        result.append({
            "id": node.id,
            "hostname": node.hostname,
            "ip": ip,
            "health": node.health,
            "weight": state.get("weight", 0),
            "enabled": state.get("enabled", False),
        })

    try:
        cp_ip = _detect_cp_ip(db)
    except ValueError:
        cp_ip = ""

    return {"nodes": result, "cp_ip": cp_ip}


@router.put("")
def update_balancer(
    req: BalancerUpdateRequest,
    db: Session = Depends(get_db),
    _=Depends(require_admin),
):
    """
    Apply new load-balancer weights.

    Validates:
    - At least one node must be enabled.
    - Sum of weights for enabled nodes must equal 100.

    Applies via iptables-restore and returns actual state after apply.
    """
    enabled_nodes = [n for n in req.nodes if n.enabled]

    if not enabled_nodes:
        raise HTTPException(
            status_code=422,
            detail="At least one node must be enabled",
        )

    weight_sum = sum(n.weight for n in enabled_nodes)
    if weight_sum != 100:
        raise HTTPException(
            status_code=422,
            detail=f"Sum of enabled node weights must be 100, got {weight_sum}",
        )

    cp_ip = _detect_cp_ip(db)

    nodes_payload = [
        {"ip": n.ip, "weight": n.weight, "enabled": n.enabled}
        for n in req.nodes
    ]

    try:
        new_state = apply_rules(nodes_payload, cp_ip=cp_ip)
    except Exception as exc:
        logger.error("Failed to apply iptables rules: %s", exc)
        raise HTTPException(
            status_code=500,
            detail=f"Failed to apply iptables rules: {exc}",
        )

    # Merge with DB for richer response
    db_nodes = db.query(Node).order_by(Node.created_at).all()
    result = []
    for node in db_nodes:
        ip = node.private_ip
        state = new_state.get(ip, {})
        result.append({
            "id": node.id,
            "hostname": node.hostname,
            "ip": ip,
            "health": node.health,
            "weight": state.get("weight", 0),
            "enabled": state.get("enabled", False),
        })

    return {"nodes": result, "cp_ip": cp_ip}


class CpIpUpdate(BaseModel):
    cp_ip: str


@router.put("/cp-ip")
def update_cp_ip(
    req: CpIpUpdate,
    db: Session = Depends(get_db),
    _=Depends(require_admin),
):
    """Update the control-plane IP stored in system_settings."""
    from app.db.models import SystemSettings
    ss = db.query(SystemSettings).filter(SystemSettings.id == 1).first()
    if not ss:
        raise HTTPException(404, "System settings not found")
    ss.cp_ip = req.cp_ip.strip()
    db.commit()
    return {"cp_ip": ss.cp_ip}
