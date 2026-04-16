"""
Apply-status API — called by the admin frontend to check WireGuard config sync.

GET /apply-status?path=P      — JSON: are all live nodes synced?
GET /apply-status/stream?path=P — SSE: waits until synced or 30s timeout
"""
import asyncio
import json
import logging
import os
from typing import AsyncGenerator

from fastapi import APIRouter, Depends, Query
from fastapi.responses import StreamingResponse
from sqlalchemy.orm import Session

from app.api.deps import get_current_user, get_db
from app.db.models import Node, User

logger = logging.getLogger(__name__)
router = APIRouter()


# ---------------------------------------------------------------------------
# Helper
# ---------------------------------------------------------------------------

def _check_applied(db: Session, path: str) -> dict:
    """Return sync status for a given config path.

    Returns dict with keys: applied (bool), live_nodes (int), synced_nodes (int).
    """
    from app.services.wg_blob_store import WgBlobStore

    store = WgBlobStore(db)
    paths = store.get_all_paths()
    current_sha = paths.get(path)

    live_nodes = db.query(Node).filter(Node.health.in_(["ok", "degraded"])).all()

    if not live_nodes or not current_sha:
        return {
            "applied": True,
            "live_nodes": len(live_nodes),
            "synced_nodes": len(live_nodes),
        }

    synced = sum(
        1 for n in live_nodes
        if (n.applied_sha or {}).get(path) == current_sha
    )
    return {
        "applied": synced == len(live_nodes),
        "live_nodes": len(live_nodes),
        "synced_nodes": synced,
    }


# ---------------------------------------------------------------------------
# Endpoints
# ---------------------------------------------------------------------------

@router.get("")
def get_apply_status(
    path: str = Query(...),
    db: Session = Depends(get_db),
    _: User = Depends(get_current_user),
) -> dict:
    """JSON check: are all live nodes synced to the current SHA for *path*?"""
    return _check_applied(db, path)


@router.get("/stream")
async def stream_apply_status(
    path: str = Query(...),
    db: Session = Depends(get_db),
    _: User = Depends(get_current_user),
):
    """SSE stream: emits {status: ready} once all live nodes are synced (or on timeout)."""

    async def _generate() -> AsyncGenerator[str, None]:
        database_url = os.environ.get("DATABASE_URL", "")

        # Quick check — already applied?
        status = _check_applied(db, path)
        if status["applied"]:
            yield f'data: {json.dumps({"status": "ready"})}\n\n'
            return

        # SQLite (test mode): no LISTEN/NOTIFY support — return immediately
        if not database_url.startswith("postgresql"):
            yield f'data: {json.dumps({"status": "ready"})}\n\n'
            return

        # PostgreSQL: listen on node_applied channel, poll every 3s, 30s timeout
        try:
            import asyncpg

            queue: asyncio.Queue = asyncio.Queue()
            conn = await asyncpg.connect(database_url)

            def _on_notify(conn, pid, channel, payload):
                queue.put_nowait(payload)

            await conn.add_listener("node_applied", _on_notify)
            deadline = asyncio.get_event_loop().time() + 30.0
            try:
                while True:
                    remaining = deadline - asyncio.get_event_loop().time()
                    if remaining <= 0:
                        # Timeout — send ready with warning anyway
                        yield f'data: {json.dumps({"status": "ready", "warning": "timeout: not all nodes synced"})}\n\n'
                        return

                    try:
                        await asyncio.wait_for(queue.get(), timeout=min(3.0, remaining))
                    except asyncio.TimeoutError:
                        pass

                    # Re-check after notification or 3s poll
                    status = _check_applied(db, path)
                    if status["applied"]:
                        yield f'data: {json.dumps({"status": "ready"})}\n\n'
                        return

            finally:
                await conn.remove_listener("node_applied", _on_notify)
                await conn.close()

        except Exception as exc:
            logger.error("apply-status SSE error: %s", exc)
            # Emit ready anyway so the UI doesn't hang
            yield f'data: {json.dumps({"status": "ready", "warning": str(exc)})}\n\n'

    return StreamingResponse(
        _generate(),
        media_type="text/event-stream",
        headers={
            "Cache-Control": "no-cache",
            "X-Accel-Buffering": "no",
        },
    )
