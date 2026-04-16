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


# ---------------------------------------------------------------------------
# Install script (no auth — token passed as query param)
# ---------------------------------------------------------------------------

from fastapi import Request
from fastapi.responses import PlainTextResponse
from pathlib import Path

_AGENT_DIR = Path(os.environ.get("AGENT_DIR", Path(__file__).resolve().parent.parent.parent.parent / "agent"))


@router.get("/install.sh")
def install_script(
    token: str = Query(...),
    request: Request = None,
    db: Session = Depends(get_db),
):
    """
    Render a self-contained install script with the CP URL and token baked in.
    No auth required — the token itself is the secret.
    Usage: curl https://panel/api/v1/agent/install.sh?token=T | bash
    """
    # Verify token is valid
    node = db.query(Node).filter_by(enroll_token=token).first()
    if not node:
        raise HTTPException(status_code=404, detail="Invalid token")

    cp_url = str(request.base_url).rstrip("/")
    # Use X-Forwarded-Proto if behind nginx
    if request.headers.get("x-forwarded-proto") == "https":
        cp_url = cp_url.replace("http://", "https://")

    script = _render_install_script(cp_url, token, node.hostname)
    return PlainTextResponse(script, media_type="text/plain")


@router.get("/sync-agent.py")
def agent_source(
    token: str = Query(...),
    db: Session = Depends(get_db),
):
    """Serve the sync-agent Python source. Token required to prevent scraping."""
    node = db.query(Node).filter_by(enroll_token=token).first()
    if not node:
        raise HTTPException(status_code=404, detail="Invalid token")
    agent_py = _AGENT_DIR / "corpweb_sync_agent.py"
    if not agent_py.exists():
        raise HTTPException(status_code=500, detail="Agent source not found on server")
    return PlainTextResponse(agent_py.read_text(), media_type="text/plain")


@router.get("/sync-agent.service")
def agent_service(
    token: str = Query(...),
    db: Session = Depends(get_db),
):
    """Serve the systemd unit file."""
    node = db.query(Node).filter_by(enroll_token=token).first()
    if not node:
        raise HTTPException(status_code=404, detail="Invalid token")
    service_file = _AGENT_DIR / "corpweb-sync-agent.service"
    if not service_file.exists():
        raise HTTPException(status_code=500, detail="Service file not found on server")
    return PlainTextResponse(service_file.read_text(), media_type="text/plain")


def _render_install_script(cp_url: str, token: str, hostname: str) -> str:
    return f'''#!/usr/bin/env bash
set -euo pipefail

# CorpWeb Sync Agent installer
# Generated for node: {hostname}
# CP: {cp_url}

CONTROL_PLANE_URL="{cp_url}"
AGENT_TOKEN="{token}"
AGENT_HOSTNAME="{hostname}"

echo "==> Installing CorpWeb Sync Agent on $AGENT_HOSTNAME"
echo "==> Control plane: $CONTROL_PLANE_URL"

# Install Python requests if missing
python3 -c "import requests" 2>/dev/null || pip3 install requests

# Download agent
curl -fsSL "$CONTROL_PLANE_URL/api/v1/agent/sync-agent.py?token=$AGENT_TOKEN" \\
    -o /usr/local/bin/corpweb-sync-agent.py
chmod +x /usr/local/bin/corpweb-sync-agent.py

# Create wrapper
cat > /usr/local/bin/corpweb-sync-agent << 'WRAPPER'
#!/bin/bash
exec python3 /usr/local/bin/corpweb-sync-agent.py "$@"
WRAPPER
chmod +x /usr/local/bin/corpweb-sync-agent

# Write env file
cat > /etc/corpweb-sync-agent.env << ENVEOF
CONTROL_PLANE_URL=$CONTROL_PLANE_URL
AGENT_TOKEN=$AGENT_TOKEN
AGENT_HOSTNAME=$AGENT_HOSTNAME
ENVEOF
chmod 600 /etc/corpweb-sync-agent.env

# Install systemd service
curl -fsSL "$CONTROL_PLANE_URL/api/v1/agent/sync-agent.service?token=$AGENT_TOKEN" \\
    -o /etc/systemd/system/corpweb-sync-agent.service

systemctl daemon-reload
systemctl enable --now corpweb-sync-agent

echo "==> Agent installed. Status:"
systemctl status corpweb-sync-agent --no-pager || true
echo ""
echo "==> Check logs: journalctl -u corpweb-sync-agent -f"
'''
