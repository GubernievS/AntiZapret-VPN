"""
Nodes CRUD API — called by admin panel.
"""
import secrets

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel
from sqlalchemy.orm import Session

from app.db.session import get_db
from app.db.models import Node
from app.api.deps import require_admin

router = APIRouter()


@router.get("")
def list_nodes(db: Session = Depends(get_db), _=Depends(require_admin)):
    nodes = db.query(Node).order_by(Node.created_at).all()
    return [
        {
            "id": n.id,
            "hostname": n.hostname,
            "private_ip": n.private_ip,
            "health": n.health,
            "last_seen": n.last_seen.isoformat() if n.last_seen else None,
            "metrics": n.metrics,
            "applied_sha": n.applied_sha,
        }
        for n in nodes
    ]


class CreateNodeRequest(BaseModel):
    hostname: str
    private_ip: str


@router.post("", status_code=201)
def create_node(
    req: CreateNodeRequest,
    db: Session = Depends(get_db),
    _=Depends(require_admin),
):
    if db.query(Node).filter_by(hostname=req.hostname).first():
        raise HTTPException(status_code=409, detail="Hostname already exists")
    token = secrets.token_urlsafe(32)
    node = Node(hostname=req.hostname, private_ip=req.private_ip, enroll_token=token)
    db.add(node)
    db.commit()
    db.refresh(node)
    return {"id": node.id, "hostname": node.hostname, "enroll_token": token}


@router.get("/{node_id}")
def get_node(
    node_id: int,
    db: Session = Depends(get_db),
    _=Depends(require_admin),
):
    node = db.get(Node, node_id)
    if not node:
        raise HTTPException(status_code=404, detail="Node not found")
    return {
        "id": node.id,
        "hostname": node.hostname,
        "private_ip": node.private_ip,
        "health": node.health,
        "last_seen": node.last_seen.isoformat() if node.last_seen else None,
        "metrics": node.metrics,
        "applied_sha": node.applied_sha,
        "enroll_token": node.enroll_token,
    }


@router.delete("/{node_id}")
def delete_node(
    node_id: int,
    db: Session = Depends(get_db),
    _=Depends(require_admin),
):
    node = db.get(Node, node_id)
    if not node:
        raise HTTPException(status_code=404, detail="Node not found")
    db.delete(node)
    db.commit()
    return {"ok": True}
