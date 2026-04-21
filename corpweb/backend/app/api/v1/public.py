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
from app.services.vpn_manager_new import vpn_manager

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
    payload = verify_config_share_token(token)
    if payload is None:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid or expired download link",
        )

    try:
        config_id = uuid.UUID(payload["config_id"])
    except ValueError:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid download link",
        )

    bypass = payload["bypass"]
    backup = payload["backup"]

    config = crud_config.get_by_id(db, config_id)
    if not config:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Config not found",
        )

    # Render config from DB
    from urllib.parse import urlparse
    from app.config import settings as app_settings

    if config.config_type == "awg_antizapret":
        iface, flavor = "antizapret", "awg"
    else:
        iface, flavor = "vpn", "awg"

    endpoint_host = app_settings.LB_ENDPOINT_HOST or urlparse(app_settings.FRONTEND_URL).hostname
    allowed_ips = vpn_manager.get_antizapret_allowed_ips(db) if iface == "antizapret" else None
    private_key = config.config_metadata.get("private_key") if config.config_metadata else None

    if private_key is None:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail="Config missing private key (pre-migration config). Please recreate.",
        )

    try:
        content = vpn_manager.get_client_conf(
            db, config.client_name, flavor, endpoint_host, iface,
            client_private_key=private_key,
            allowed_ips=allowed_ips,
            use_backup_port=backup,
            bypass=bypass,
        )
    except ValueError as e:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=str(e),
        )

    # Short filename for AmneziaWG (tunnel name <= 15 chars / IFNAMSIZ).
    # Must match /configs/{id}/download naming so QR-link and direct
    # download produce the same filename (and don't collide in the client).
    server = app_settings.get_short_server_name()
    suffix = "az" if config.config_type == "awg_antizapret" else "vpn"
    if bypass:
        suffix = f"{suffix}B"
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
