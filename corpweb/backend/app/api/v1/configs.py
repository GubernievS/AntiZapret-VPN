"""
VPN Config API endpoints
"""
import io
import uuid
import logging
import zipfile
import qrcode
import qrcode.constants
from fastapi import APIRouter, Depends, HTTPException, status
from fastapi.responses import Response
from sqlalchemy.orm import Session

from app.db.session import get_db
from app.db.models import User, VPNConfig, SystemSettings
from app.crud import config as crud_config
from app.schemas.config import ConfigCreate, ConfigResponse, ConfigDetailResponse, ConfigListResponse
from app.api.deps import get_current_user, require_admin
from app.services.vpn_manager_new import vpn_manager, generate_client_name
from app.core.security import create_config_share_token
from app.config import settings as app_settings

logger = logging.getLogger(__name__)

router = APIRouter()


@router.get("/client-links")
async def get_client_links(
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    """
    Get client app download links from system settings.
    Accessible to all authenticated users.
    """
    sys_settings = db.query(SystemSettings).filter(SystemSettings.id == 1).first()
    if not sys_settings:
        return {}
    return {
        "google_play_url": sys_settings.google_play_url,
        "app_store_url": sys_settings.app_store_url,
        "apk_url": sys_settings.apk_url,
        "windows_url": sys_settings.windows_url,
    }


@router.get("", response_model=ConfigListResponse)
async def list_configs(
    skip: int = 0,
    limit: int = 100,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    """
    List configs for current user.
    Admin sees all configs (paginated); regular users see only their own.
    """
    if current_user.role == "admin":
        configs = crud_config.get_all(db, skip=skip, limit=limit)
        total = crud_config.get_total_count(db)
    else:
        configs = crud_config.get_by_user(db, current_user.id)
        total = len(configs)

    items = [ConfigResponse.model_validate(c) for c in configs]
    return ConfigListResponse(items=items, total=total)


@router.post("", response_model=ConfigResponse, status_code=status.HTTP_201_CREATED)
async def create_config(
    data: ConfigCreate,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    """
    Create a new VPN config.
    Checks the configurable limit from SystemSettings.
    """
    # Check config limit
    sys_settings = db.query(SystemSettings).filter(SystemSettings.id == 1).first()
    max_configs = sys_settings.max_configs_per_user if sys_settings else 2

    active_count = crud_config.count_active_by_user(db, current_user.id)
    if active_count >= max_configs:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"Maximum {max_configs} active configs allowed. Delete an existing config first."
        )

    # Generate client name
    existing_names = crud_config.get_client_names_by_user(db, current_user.id)
    client_name = generate_client_name(current_user.username, existing_names)

    # Create config in DB via vpn_manager_new
    try:
        result = vpn_manager.add_peer(db, client_name)
    except Exception as e:
        logger.error(f"Failed to create VPN config: {e}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Failed to create VPN config: {str(e)}"
        )

    # Save to database (lightweight metadata — keys and IP only)
    config = crud_config.create(
        db,
        user_id=current_user.id,
        client_name=client_name,
        config_type=data.config_type,
        config_file_path=None,
        config_metadata={
            "vpn_ip": result.get("vpn_ip"),
            "private_key": result.get("private_key"),
            "preshared_key": result.get("preshared_key"),
        }
    )

    return ConfigResponse.model_validate(config)


@router.get("/{config_id}", response_model=ConfigDetailResponse)
async def get_config(
    config_id: uuid.UUID,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    """Get config details"""
    config = crud_config.get_by_id(db, config_id)
    if not config:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Config not found"
        )

    # Check ownership (admin can see any)
    if current_user.role != "admin" and config.user_id != current_user.id:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Access denied"
        )

    response = ConfigDetailResponse.model_validate(config)

    # Add owner info for admin
    if current_user.role == "admin":
        response.owner_username = config.user.username
        response.owner_email = config.user.email

    return response


@router.get("/{config_id}/download")
async def download_config(
    config_id: uuid.UUID,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    """
    Download config as a ZIP archive containing the .conf file.
    ZIP format is used because mobile browsers (Chrome) rename
    plain .conf downloads to .conf.txt, breaking import into AmneziaWG.
    AmneziaWG natively supports importing .zip archives.
    """
    config = crud_config.get_by_id(db, config_id)
    if not config:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Config not found"
        )

    # Check ownership
    if current_user.role != "admin" and config.user_id != current_user.id:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Access denied"
        )

    # Render config from DB
    from urllib.parse import urlparse

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
        )
    except ValueError as e:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=str(e),
        )

    # Short filename for AmneziaWG (tunnel name <= 15 chars / IFNAMSIZ)
    server = app_settings.get_short_server_name()
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


@router.get("/{config_id}/qr")
async def get_config_qr(
    config_id: uuid.UUID,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    """
    Generate QR code PNG image for a config.
    The QR contains the raw awg-quick config text — compatible with AmneziaWG mobile clients.
    """
    config = crud_config.get_by_id(db, config_id)
    if not config:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Config not found"
        )

    # Check ownership
    if current_user.role != "admin" and config.user_id != current_user.id:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Access denied"
        )

    # Render config from DB
    from urllib.parse import urlparse as _urlparse_qr

    if config.config_type == "awg_antizapret":
        iface_qr, flavor_qr = "antizapret", "awg"
    else:
        iface_qr, flavor_qr = "vpn", "awg"

    endpoint_host_qr = app_settings.LB_ENDPOINT_HOST or _urlparse_qr(app_settings.FRONTEND_URL).hostname
    allowed_ips_qr = vpn_manager.get_antizapret_allowed_ips(db) if iface_qr == "antizapret" else None
    private_key_qr = config.config_metadata.get("private_key") if config.config_metadata else None

    if private_key_qr is None:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail="Config missing private key (pre-migration config). Please recreate.",
        )

    try:
        content = vpn_manager.get_client_conf(
            db, config.client_name, flavor_qr, endpoint_host_qr, iface_qr,
            client_private_key=private_key_qr,
            allowed_ips=allowed_ips_qr,
        )
    except ValueError as e:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=str(e),
        )

    # QR Code version 40 with ERROR_CORRECT_L supports max 2953 bytes.
    # Antizapret configs contain thousands of AllowedIPs entries and
    # easily exceed this limit — use a temporary download link instead.
    MAX_QR_BYTES = 2953
    content_size = len(content.encode("utf-8"))

    if content_size <= MAX_QR_BYTES:
        qr_data = content
        qr_type = "config"
    else:
        token = create_config_share_token(str(config_id))
        download_url = f"{app_settings.FRONTEND_URL}/api/v1/public/config/{token}"
        qr_data = download_url
        qr_type = "download-link"

    try:
        qr = qrcode.QRCode(
            version=None,
            error_correction=qrcode.constants.ERROR_CORRECT_L,
            box_size=10,
            border=4,
        )
        qr.add_data(qr_data)
        qr.make(fit=True)

        img = qr.make_image(fill_color="black", back_color="white")
        buf = io.BytesIO()
        img.save(buf, format="PNG")
        buf.seek(0)
    except Exception as e:
        logger.error(f"QR generation failed for config {config_id}: {e}")
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail="Не удалось сгенерировать QR-код. Используйте скачивание файла.",
        )

    return Response(
        content=buf.getvalue(),
        media_type="image/png",
        headers={
            "Cache-Control": "no-store",
            "X-QR-Type": qr_type,
        },
    )


@router.delete("/{config_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_config(
    config_id: uuid.UUID,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    """
    Delete a VPN config.
    Removes from both database and VPN server.
    """
    config = crud_config.get_by_id(db, config_id)
    if not config:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Config not found"
        )

    # Check ownership
    if current_user.role != "admin" and config.user_id != current_user.id:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Access denied"
        )

    # Delete from VPN server (DB blobs)
    try:
        vpn_manager.delete_peer(db, config.client_name)
    except Exception as e:
        logger.error(f"Failed to delete VPN client {config.client_name}: {e}")
        # Continue with DB deletion even if server deletion fails

    # Delete from database
    crud_config.delete_config(db, config)
