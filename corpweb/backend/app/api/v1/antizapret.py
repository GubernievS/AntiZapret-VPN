"""
Antizapret admin API endpoints.
File editing and setup settings management.
All endpoints require admin role.
"""
from fastapi import APIRouter, Depends, HTTPException, status
from app.db.models import User
from app.api.deps import require_admin
from app.services.antizapret import antizapret_service, AntizapretServiceError, EDITABLE_FILES
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
    try:
        content = antizapret_service.get_file_content(file_type)
    except AntizapretServiceError as e:
        raise HTTPException(status_code=status.HTTP_500_INTERNAL_SERVER_ERROR, detail=str(e))
    return FileContentResponse(file_type=file_type, content=content)


@router.put("/files/{file_type}", response_model=FileContentResponse)
async def save_file(
    file_type: str,
    data: FileContentUpdate,
    _admin: User = Depends(require_admin),
):
    """
    Save one of the editable config files.
    Does NOT run doall.sh automatically — call POST /doall separately.
    """
    if file_type not in EDITABLE_FILES:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"Unknown file type '{file_type}'. Valid: {list(EDITABLE_FILES.keys())}",
        )
    try:
        antizapret_service.save_file_content(file_type, data.content)
    except AntizapretServiceError as e:
        raise HTTPException(status_code=status.HTTP_500_INTERNAL_SERVER_ERROR, detail=str(e))
    return FileContentResponse(file_type=file_type, content=data.content)


# ── Setup settings ────────────────────────────────────────────────────────────

@router.get("/settings", response_model=AntizapretSettingsResponse)
async def get_settings(
    _admin: User = Depends(require_admin),
):
    """Read current values from /root/antizapret/setup"""
    try:
        raw = antizapret_service.get_settings()
    except AntizapretServiceError as e:
        raise HTTPException(status_code=status.HTTP_500_INTERNAL_SERVER_ERROR, detail=str(e))
    return AntizapretSettingsResponse(**raw)


@router.patch("/settings", response_model=DoallResponse)
async def update_settings(
    data: AntizapretSettingsUpdate,
    _admin: User = Depends(require_admin),
):
    """
    Update /root/antizapret/setup with provided key-value pairs.
    Returns count of changed parameters. Does NOT apply changes automatically.
    """
    try:
        changed = antizapret_service.update_settings(data.settings)
    except AntizapretServiceError as e:
        raise HTTPException(status_code=status.HTTP_500_INTERNAL_SERVER_ERROR, detail=str(e))
    return DoallResponse(status="saved", output="", changed=changed)


# ── Apply changes ─────────────────────────────────────────────────────────────

@router.post("/doall", response_model=DoallResponse)
async def run_doall(
    _admin: User = Depends(require_admin),
):
    """
    Execute /root/antizapret/doall.sh to apply all pending changes.
    This rebuilds routing tables and DNS lists (may take 1-5 min).
    """
    try:
        output = antizapret_service.run_doall()
    except AntizapretServiceError as e:
        raise HTTPException(status_code=status.HTTP_500_INTERNAL_SERVER_ERROR, detail=str(e))
    return DoallResponse(status="applied", output=output)
