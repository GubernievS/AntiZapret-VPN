"""
Antizapret admin API endpoints.
File editing and setup settings management via WgBlobStore.
All endpoints require admin role.
"""
from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session

from app.db.models import User
from app.db.session import get_db
from app.api.deps import require_admin
from app.services.antizapret import AntizapretService, AntizapretServiceError, EDITABLE_FILES
from app.schemas.antizapret import (
    FileContentResponse,
    FileContentUpdate,
    AntizapretSettingsResponse,
    AntizapretSettingsUpdate,
    DoallResponse,
)

router = APIRouter()


# ── File editing ──────────────────────────────────────────────────────────────

@router.get("/files/{file_type}", response_model=FileContentResponse)
async def get_file(
    file_type: str,
    db: Session = Depends(get_db),
    _admin: User = Depends(require_admin),
):
    """
    Read one of the editable config files.
    file_type: include_hosts | exclude_hosts | include_ips
    """
    if file_type not in EDITABLE_FILES:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"Unknown file type '{file_type}'. Valid: {list(EDITABLE_FILES.keys())}",
        )
    svc = AntizapretService(db)
    try:
        content = svc.get_file_content(file_type)
    except AntizapretServiceError as e:
        raise HTTPException(status_code=status.HTTP_500_INTERNAL_SERVER_ERROR, detail=str(e))
    return FileContentResponse(file_type=file_type, content=content)


@router.put("/files/{file_type}", response_model=FileContentResponse)
async def save_file(
    file_type: str,
    data: FileContentUpdate,
    db: Session = Depends(get_db),
    _admin: User = Depends(require_admin),
):
    """
    Save one of the editable config files.
    Agents auto-apply via debounced doall.sh.
    """
    if file_type not in EDITABLE_FILES:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"Unknown file type '{file_type}'. Valid: {list(EDITABLE_FILES.keys())}",
        )
    svc = AntizapretService(db)
    try:
        svc.save_file_content(file_type, data.content)
    except AntizapretServiceError as e:
        raise HTTPException(status_code=status.HTTP_500_INTERNAL_SERVER_ERROR, detail=str(e))
    return FileContentResponse(file_type=file_type, content=data.content)


# ── Setup settings ────────────────────────────────────────────────────────────

@router.get("/settings", response_model=AntizapretSettingsResponse)
async def get_settings(
    db: Session = Depends(get_db),
    _admin: User = Depends(require_admin),
):
    """Read current values from /root/antizapret/setup (via blob store)."""
    svc = AntizapretService(db)
    try:
        raw = svc.get_settings()
    except AntizapretServiceError as e:
        raise HTTPException(status_code=status.HTTP_500_INTERNAL_SERVER_ERROR, detail=str(e))
    return AntizapretSettingsResponse(**raw)


@router.patch("/settings", response_model=DoallResponse)
async def update_settings(
    data: AntizapretSettingsUpdate,
    db: Session = Depends(get_db),
    _admin: User = Depends(require_admin),
):
    """
    Update /root/antizapret/setup with provided key-value pairs.
    Returns count of changed parameters. Agents auto-apply changes.
    """
    svc = AntizapretService(db)
    try:
        changed = svc.update_settings(data.settings)
    except AntizapretServiceError as e:
        raise HTTPException(status_code=status.HTTP_500_INTERNAL_SERVER_ERROR, detail=str(e))
    return DoallResponse(status="saved", output="", changed=changed)


# ── Obfuscation (escape mode) ─────────────────────────────────────────────────

@router.post("/obfuscation/regenerate")
async def regenerate_obfuscation(
    db: Session = Depends(get_db),
    _admin: User = Depends(require_admin),
):
    """
    Regenerate AmneziaWG obfuscation parameters for escape ifaces.

    Invalidates existing bypass client configs — users must re-download.
    Re-renders the server ``*_escape.conf`` blobs so agents pick up the
    new params via SSE.
    """
    from app.services.obfuscation_service import regenerate
    from app.services.vpn_manager_new import vpn_manager

    regenerate(db, ifaces=["az_escape", "vpn_escape"])
    vpn_manager.rerender_escape_server_confs(db)
    return {"status": "ok"}
