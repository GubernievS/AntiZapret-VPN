"""
Agent API — called by sync-agent running on each data-plane node.
All endpoints require Authorization: Bearer <enroll_token>.
"""
import asyncio
import base64
import logging
import os
from datetime import datetime
from typing import AsyncGenerator

from fastapi import APIRouter, Depends, Header, HTTPException, Query
from fastapi.responses import StreamingResponse
from pydantic import BaseModel
from sqlalchemy.orm import Session

from app.db.session import get_db
from app.db.models import Node, WgServerKeys
from app.services.wg_blob_store import WgBlobStore

logger = logging.getLogger(__name__)
router = APIRouter()


# ---------------------------------------------------------------------------
# Auth helpers
# ---------------------------------------------------------------------------

def _extract_token(authorization: str = Header(default="")) -> str:
    if authorization.startswith("Bearer "):
        return authorization[7:]
    return ""


def _require_node(
    db: Session = Depends(get_db),
    token: str = Depends(_extract_token),
) -> Node:
    if not token:
        raise HTTPException(status_code=401, detail="Missing token")
    node = db.query(Node).filter_by(enroll_token=token).first()
    if not node:
        raise HTTPException(status_code=401, detail="Invalid enroll token")
    return node


# ---------------------------------------------------------------------------
# Endpoints
# ---------------------------------------------------------------------------

class RegisterRequest(BaseModel):
    hostname: str
    private_ip: str


@router.post("/register")
def register(
    req: RegisterRequest,
    db: Session = Depends(get_db),
    node: Node = Depends(_require_node),
):
    node.private_ip = req.private_ip
    node.last_seen = datetime.utcnow()
    db.commit()

    keys = {
        row.iface: {"private_key": row.private_key, "public_key": row.public_key}
        for row in db.query(WgServerKeys).all()
    }
    return {"node_id": node.id, "wg_server_keys": keys}


@router.get("/file")
def get_file(
    path: str = Query(...),
    db: Session = Depends(get_db),
    node: Node = Depends(_require_node),
):
    store = WgBlobStore(db)
    content = store.get(path)
    if content is None:
        raise HTTPException(status_code=404, detail="File not found")
    paths = store.get_all_paths()
    return {
        "content": base64.b64encode(content).decode(),
        "sha256": paths.get(path, ""),
    }


class HeartbeatRequest(BaseModel):
    applied_sha: dict
    health: str
    metrics: dict = {}


@router.post("/heartbeat")
def heartbeat(
    req: HeartbeatRequest,
    db: Session = Depends(get_db),
    node: Node = Depends(_require_node),
):
    node.health = req.health
    node.applied_sha = req.applied_sha
    node.metrics = req.metrics
    node.last_seen = datetime.utcnow()
    db.commit()
    return {"ok": True}


@router.get("/events")
async def events(
    db: Session = Depends(get_db),
    node: Node = Depends(_require_node),
):
    async def stream() -> AsyncGenerator[str, None]:
        database_url = os.environ.get("DATABASE_URL", "")

        # In test/SQLite mode, just send a keepalive and close
        if not database_url.startswith("postgresql"):
            yield ": keepalive\n\n"
            return

        try:
            import asyncpg
            queue: asyncio.Queue = asyncio.Queue()

            conn = await asyncpg.connect(database_url)

            def on_notify(conn, pid, channel, payload):
                queue.put_nowait(payload)

            await conn.add_listener("wg_file_state_changed", on_notify)
            try:
                while True:
                    try:
                        path = await asyncio.wait_for(queue.get(), timeout=15.0)
                        yield f'data: {{"path": "{path}"}}\n\n'
                    except asyncio.TimeoutError:
                        yield ": keepalive\n\n"
            finally:
                await conn.remove_listener("wg_file_state_changed", on_notify)
                await conn.close()
        except Exception as e:
            logger.error("SSE error: %s", e)
            yield 'data: {"error": "stream closed"}\n\n'

    return StreamingResponse(
        stream(),
        media_type="text/event-stream",
        headers={"Cache-Control": "no-cache", "X-Accel-Buffering": "no"},
    )


@router.post("/drain")
def drain(
    db: Session = Depends(get_db),
    node: Node = Depends(_require_node),
):
    node.health = "draining"
    db.commit()
    return {"ok": True, "ttl_minutes": 10}
