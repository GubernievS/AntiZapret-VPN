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

    return {"nodes": result}


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

    # Determine control-plane IP from DB (first node, or fallback)
    # In practice the CP IP is the host running this service.
    # We pass it through for the SNAT rule; derive from first enabled node's
    # registered IP if not explicitly configured.
    from app.config import settings
    cp_ip = getattr(settings, "CP_IP", None) or enabled_nodes[0].ip

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

    return {"nodes": result}
