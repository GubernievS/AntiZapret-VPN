"""
Public (unauthenticated) endpoints.
Currently used for temporary config file download links
shared via QR codes.
"""
import io
import uuid
import logging
import zipfile

from fastapi import APIRouter, HTTPException, status
from fastapi.responses import Response
from sqlalchemy.orm import Session
from fastapi import Depends

from app.db.session import get_db
from app.crud import config as crud_config
from app.core.security import verify_config_share_token
from app.services.vpn_manager import vpn_manager, VPNManagerError

logger = logging.getLogger(__name__)

router = APIRouter()


@router.get("/config/{token}")
async def download_shared_config(
    token: str,
    db: Session = Depends(get_db),
):
    """
    Download a config file as ZIP using a temporary share token.
    No authentication required — the signed JWT token serves as proof.
    Used when antizapret configs are too large for a direct QR code.

    Returns a ZIP archive containing the .conf file.
    ZIP format is used because mobile browsers (Chrome) rename
    plain .conf downloads to .conf.txt, breaking import into AmneziaWG.
    AmneziaWG natively supports importing .zip archives with .conf files inside.
    """
    config_id_str = verify_config_share_token(token)
    if config_id_str is None:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid or expired download link",
        )

    try:
        config_id = uuid.UUID(config_id_str)
    except ValueError:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid download link",
        )

    config = crud_config.get_by_id(db, config_id)
    if not config:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Config not found",
        )

    if not config.config_file_path:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Config file path not set",
        )

    try:
        content = vpn_manager.read_config_file(config.config_file_path)
    except VPNManagerError as e:
        logger.error(f"Failed to read config file for share link: {e}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to read config file",
        )

    if content is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Config file not found on server",
        )

    # Short filename for AmneziaWG (tunnel name <= 15 chars / IFNAMSIZ)
    from app.config import settings
    server = settings.get_short_server_name()
    suffix = "az" if config.config_type == "awg_antizapret" else "vpn"
    short_name = f"{server}-{suffix}"
    conf_filename = f"{short_name}.conf"
    zip_filename = f"{short_name}.zip"

    buf = io.BytesIO()
    with zipfile.ZipFile(buf, "w", zipfile.ZIP_DEFLATED) as zf:
        zf.writestr(conf_filename, content)
    buf.seek(0)

    return Response(
        content=buf.getvalue(),
        media_type="application/zip",
        headers={
            "Content-Disposition": f'attachment; filename="{zip_filename}"',
        },
    )
