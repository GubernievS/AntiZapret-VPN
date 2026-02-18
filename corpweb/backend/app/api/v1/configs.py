"""
VPN Config API endpoints
"""
import io
import uuid
import logging
import qrcode
import qrcode.constants
from fastapi import APIRouter, Depends, HTTPException, status
from fastapi.responses import PlainTextResponse, Response
from sqlalchemy.orm import Session

from app.db.session import get_db
from app.db.models import User, VPNConfig, SystemSettings
from app.crud import config as crud_config
from app.schemas.config import ConfigCreate, ConfigResponse, ConfigDetailResponse, ConfigListResponse
from app.api.deps import get_current_user, require_admin
from app.services.vpn_manager import vpn_manager, generate_client_name, VPNManagerError

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
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    """
    List configs for current user.
    Admin sees all configs; regular users see only their own.
    """
    if current_user.role == "admin":
        configs = crud_config.get_all(db)
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

    # Create config on VPN server via client.sh
    try:
        result = vpn_manager.add_client(client_name)
    except VPNManagerError as e:
        logger.error(f"Failed to create VPN config: {e}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Failed to create VPN config: {str(e)}"
        )

    # Determine config file path based on type
    if data.config_type == "awg_antizapret":
        config_file_path = result.get("antizapret_path")
    else:  # awg_vpn
        config_file_path = result.get("vpn_path")

    # Save to database
    config = crud_config.create(
        db,
        user_id=current_user.id,
        client_name=client_name,
        config_type=data.config_type,
        config_file_path=config_file_path,
        config_metadata={
            "antizapret_path": result.get("antizapret_path"),
            "vpn_path": result.get("vpn_path"),
            "vpn_ip": result.get("vpn_ip"),
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
    Download .conf file for a config.
    Returns the raw config text as a file download.
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

    if not config.config_file_path:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Config file path not set"
        )

    try:
        content = vpn_manager.read_config_file(config.config_file_path)
    except VPNManagerError as e:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail=str(e)
        )

    if content is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Config file not found on server"
        )

    # Return file with a user-friendly name: username-N.conf
    filename = f"{config.client_name}.conf"

    return PlainTextResponse(
        content=content,
        headers={
            "Content-Disposition": f'attachment; filename="{filename}"'
        }
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

    if not config.config_file_path:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Config file path not set"
        )

    try:
        content = vpn_manager.read_config_file(config.config_file_path)
    except VPNManagerError as e:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail=str(e)
        )

    if content is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Config file not found on server"
        )

    qr = qrcode.QRCode(
        version=None,
        error_correction=qrcode.constants.ERROR_CORRECT_L,
        box_size=10,
        border=4,
    )
    qr.add_data(content)
    qr.make(fit=True)

    img = qr.make_image(fill_color="black", back_color="white")
    buf = io.BytesIO()
    img.save(buf, format="PNG")
    buf.seek(0)

    return Response(
        content=buf.getvalue(),
        media_type="image/png",
        headers={"Cache-Control": "no-store"},
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

    # Delete from VPN server
    try:
        vpn_manager.delete_client(config.client_name)
    except VPNManagerError as e:
        logger.error(f"Failed to delete VPN client {config.client_name}: {e}")
        # Continue with DB deletion even if server deletion fails
        # The config file may have been already removed manually

    # Delete from database
    crud_config.delete_config(db, config)
