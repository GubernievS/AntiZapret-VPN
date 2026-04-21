"""
Admin API endpoints
Users management, system settings, dashboard
"""
import base64
import uuid
import logging
from typing import Optional
from fastapi import APIRouter, Depends, File, HTTPException, UploadFile, status
from fastapi.responses import JSONResponse
from sqlalchemy.orm import Session

from app.db.session import get_db
from app.db.models import User, VPNConfig, ConnectionLog, SystemSettings
from app.crud import user as crud_user
from app.crud import config as crud_config
from app.schemas.user import UserCreate, UserUpdate, UserResponse, UserListResponse
from app.schemas.config import ConfigResponse, ConfigListResponse
from app.schemas.settings import SystemSettingsResponse, SystemSettingsUpdate
from app.api.deps import require_admin
from app.services.vpn_manager_new import vpn_manager
from app.services.wg_blob_store import WgBlobStore
from app.services import balancer
from app.db.models import WgServerKeys, Node

logger = logging.getLogger(__name__)

router = APIRouter()


# ============================================
# Users Management
# ============================================

def _build_user_response(db: Session, user: User) -> UserResponse:
    """Build UserResponse with active and blocked config counts."""
    active = db.query(VPNConfig).filter(
        VPNConfig.user_id == user.id,
        VPNConfig.is_active == True
    ).count()
    blocked = db.query(VPNConfig).filter(
        VPNConfig.user_id == user.id,
        VPNConfig.is_active == False
    ).count()
    return UserResponse(
        id=user.id,
        email=user.email,
        username=user.username,
        role=user.role,
        auth_provider=user.auth_provider,
        is_active=user.is_active,
        created_at=user.created_at,
        last_login=user.last_login,
        config_count=active,
        blocked_config_count=blocked,
    )


@router.get("/users", response_model=UserListResponse)
async def list_users(
    skip: int = 0,
    limit: int = 100,
    search: Optional[str] = None,
    admin: User = Depends(require_admin),
    db: Session = Depends(get_db)
):
    """List all users with config counts, optionally filtered by search"""
    users = crud_user.get_all_filtered(db, skip=skip, limit=limit, search=search)
    total = crud_user.get_filtered_count(db, search=search)

    items = [_build_user_response(db, u) for u in users]
    return UserListResponse(items=items, total=total)


@router.post("/users", response_model=UserResponse, status_code=status.HTTP_201_CREATED)
async def create_user(
    data: UserCreate,
    admin: User = Depends(require_admin),
    db: Session = Depends(get_db)
):
    """Create a local user (admin only)"""
    # Check uniqueness
    if crud_user.get_by_email(db, data.email):
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="Email already registered"
        )
    if crud_user.get_by_username(db, data.username):
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="Username already taken"
        )

    user = crud_user.create_local_user(
        db,
        email=data.email,
        username=data.username,
        password=data.password,
        role="user"
    )

    return _build_user_response(db, user)


@router.put("/users/{user_id}", response_model=UserResponse)
async def update_user(
    user_id: uuid.UUID,
    data: UserUpdate,
    admin: User = Depends(require_admin),
    db: Session = Depends(get_db)
):
    """Update user fields (admin only)"""
    user = crud_user.get_by_id(db, user_id)
    if not user:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="User not found"
        )

    # Prevent modifying the admin user's critical fields
    if user.username == "admin" and data.username and data.username != "admin":
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Cannot change admin username"
        )

    # Check uniqueness for new email/username
    if data.email and data.email != user.email:
        if crud_user.get_by_email(db, data.email):
            raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail="Email already registered")

    if data.username and data.username != user.username:
        if crud_user.get_by_username(db, data.username):
            raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail="Username already taken")

    user = crud_user.update_user(
        db, user,
        email=data.email,
        username=data.username,
        is_active=data.is_active
    )

    return _build_user_response(db, user)


@router.patch("/users/{user_id}/block")
async def toggle_user_block(
    user_id: uuid.UUID,
    admin: User = Depends(require_admin),
    db: Session = Depends(get_db)
):
    """
    Toggle user block/unblock (admin only).

    Block:   comments out PublicKey/PresharedKey in server WG configs,
             marks configs inactive. IP reservation preserved.
    Unblock: uncomments keys, marks configs active. No re-download needed.
    """
    user = crud_user.get_by_id(db, user_id)
    if not user:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="User not found"
        )

    if user.username == "admin":
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Cannot block the admin user"
        )

    is_blocking = user.is_active  # currently active → about to block
    vpn_errors: list[str] = []

    # Collect unique client_names (a user may have multiple configs
    # sharing the same client_name but different config_type)
    if is_blocking:
        configs = crud_config.get_active_by_user(db, user.id)
    else:
        configs = crud_config.get_inactive_by_user(db, user.id)

    processed_clients: set[str] = set()

    for config in configs:
        client_name = config.client_name
        try:
            # Each client_name appears in server configs once per interface.
            # disable_peer/enable_peer processes ALL interfaces at once,
            # so we only need to call it once per unique client_name.
            if client_name not in processed_clients:
                processed_clients.add(client_name)
                if is_blocking:
                    vpn_manager.disable_peer(db, client_name)
                else:
                    vpn_manager.enable_peer(db, client_name)
        except Exception as e:
            logger.error(f"Failed to {'disable' if is_blocking else 'enable'} "
                         f"peer {client_name}: {e}")
            vpn_errors.append(client_name)

        # Always update DB status
        if is_blocking:
            crud_config.deactivate(db, config)
        else:
            crud_config.activate(db, config)

    # Toggle user active status in DB
    user = crud_user.toggle_active(db, user)

    response_data = _build_user_response(db, user)

    if vpn_errors:
        return JSONResponse(
            status_code=207,
            content={
                **response_data.model_dump(mode="json"),
                "vpn_warnings": [
                    f"Ошибка обработки VPN конфига: {name}"
                    for name in vpn_errors
                ],
            },
        )

    return response_data


@router.delete("/users/{user_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_user(
    user_id: uuid.UUID,
    admin: User = Depends(require_admin),
    db: Session = Depends(get_db)
):
    """Delete a user and all their configs (admin only)"""
    user = crud_user.get_by_id(db, user_id)
    if not user:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="User not found"
        )

    if user.username == "admin":
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Cannot delete the admin user"
        )

    # Delete all VPN peers from WG server before DB cascade.
    # Only delete active configs — inactive ones were already removed
    # from WG when the user was blocked.
    all_configs = crud_config.get_by_user(db, user.id)
    for config in all_configs:
        if config.is_active:
            try:
                vpn_manager.delete_peer(db, config.client_name)
            except Exception as e:
                logger.error(
                    f"Failed to delete VPN client {config.client_name}: {e}"
                )
                # Best-effort: continue with remaining configs and DB cleanup

    # DB cascade handles config records + connection logs
    crud_user.delete_user(db, user)


@router.get("/users/{user_id}", response_model=UserResponse)
async def get_user(
    user_id: uuid.UUID,
    admin: User = Depends(require_admin),
    db: Session = Depends(get_db)
):
    """Get single user details (admin only)"""
    user = crud_user.get_by_id(db, user_id)
    if not user:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="User not found"
        )
    return _build_user_response(db, user)


@router.get("/users/{user_id}/configs", response_model=ConfigListResponse)
async def list_user_configs(
    user_id: uuid.UUID,
    admin: User = Depends(require_admin),
    db: Session = Depends(get_db)
):
    """List all VPN configs for a specific user (admin only)"""
    user = crud_user.get_by_id(db, user_id)
    if not user:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="User not found"
        )

    configs = crud_config.get_by_user(db, user_id)
    items = [ConfigResponse.model_validate(c) for c in configs]
    return ConfigListResponse(items=items, total=len(items))


# ============================================
# System Settings
# ============================================

@router.get("/settings", response_model=SystemSettingsResponse)
async def get_settings(
    admin: User = Depends(require_admin),
    db: Session = Depends(get_db)
):
    """Get current system settings"""
    settings = db.query(SystemSettings).filter(SystemSettings.id == 1).first()
    if not settings:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="System settings not initialized"
        )
    return settings


@router.patch("/settings", response_model=SystemSettingsResponse)
async def update_settings(
    data: SystemSettingsUpdate,
    admin: User = Depends(require_admin),
    db: Session = Depends(get_db)
):
    """
    Update system settings (admin only).

    Partial PATCH: fields that aren't present in the request body are left
    untouched. When ``escape_enabled`` changes, iptables DNAT rules are
    re-applied via :func:`app.services.balancer.apply_rules` so the new
    port set (500/53443) takes effect immediately.
    """
    settings = db.query(SystemSettings).filter(SystemSettings.id == 1).first()
    if not settings:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="System settings not initialized"
        )

    payload = data.model_dump(exclude_unset=True)
    previous_escape = bool(getattr(settings, "escape_enabled", False))

    for field, value in payload.items():
        setattr(settings, field, value)
    settings.updated_by = admin.username
    db.commit()
    db.refresh(settings)

    # If escape_enabled actually changed, kick the balancer so iptables
    # picks up (or drops) the escape-mode ports immediately.
    if "escape_enabled" in payload and bool(payload["escape_enabled"]) != previous_escape:
        try:
            _rebalance_on_escape_change(db, escape_enabled=bool(settings.escape_enabled))
        except Exception as exc:
            logger.warning("rebalance after escape_enabled change failed: %s", exc)

    return settings


def _rebalance_on_escape_change(db: Session, *, escape_enabled: bool) -> None:
    """Re-apply iptables DNAT rules so the escape-mode ports match DB state."""
    nodes = db.query(Node).order_by(Node.created_at).all()
    if not nodes:
        return  # nothing to balance against

    ss = db.query(SystemSettings).filter(SystemSettings.id == 1).first()
    cp_ip = ss.cp_ip if ss and ss.cp_ip else None
    if not cp_ip:
        logger.warning("rebalance skipped: cp_ip not configured")
        return

    # Preserve current weight / enabled state for each node. We read the
    # live iptables state and fall back to a neutral weight only if a node
    # has no existing DNAT rules. Otherwise toggling escape_enabled would
    # silently reset the operator's tuned weights to 50/50.
    try:
        current = balancer.read_current_state()
    except Exception as exc:
        logger.warning("could not read live iptables state: %s", exc)
        current = {}

    payload = []
    for n in nodes:
        ip = str(n.private_ip)
        cur = current.get(ip)
        payload.append({
            "ip": ip,
            "weight": cur["weight"] if cur else 50,
            "enabled": cur["enabled"] if cur else True,
        })
    balancer.apply_rules(payload, cp_ip, escape_enabled=escape_enabled)


# ============================================
# Dashboard Stats
# ============================================

@router.get("/dashboard")
async def admin_dashboard(
    admin: User = Depends(require_admin),
    db: Session = Depends(get_db)
):
    """Admin dashboard statistics"""
    total_users = db.query(User).count()
    active_users = db.query(User).filter(User.is_active == True).count()
    google_users = db.query(User).filter(User.auth_provider == "google").count()
    local_users = db.query(User).filter(User.auth_provider == "local").count()

    total_configs = db.query(VPNConfig).count()
    active_configs = db.query(VPNConfig).filter(VPNConfig.is_active == True).count()
    antizapret_configs = db.query(VPNConfig).filter(VPNConfig.config_type == "awg_antizapret").count()
    vpn_configs = db.query(VPNConfig).filter(VPNConfig.config_type == "awg_vpn").count()

    active_connections = db.query(ConnectionLog).filter(
        ConnectionLog.status == "connected"
    ).count()

    sys_settings = db.query(SystemSettings).filter(SystemSettings.id == 1).first()

    return {
        "users": {
            "total": total_users,
            "active": active_users,
            "blocked": total_users - active_users,
            "google": google_users,
            "local": local_users
        },
        "configs": {
            "total": total_configs,
            "active": active_configs,
            "awg_antizapret": antizapret_configs,
            "awg_vpn": vpn_configs
        },
        "connections": {
            "active": active_connections
        },
        "settings": {
            "max_configs_per_user": sys_settings.max_configs_per_user if sys_settings else 2
        }
    }


# ============================================
# Import WireGuard files (migration from single node)
# ============================================

@router.post("/import-wgfiles")
async def import_wgfiles(
    antizapret_conf: Optional[UploadFile] = File(None),
    vpn_conf: Optional[UploadFile] = File(None),
    wg_key: Optional[UploadFile] = File(None),
    db: Session = Depends(get_db),
    admin: User = Depends(require_admin),
):
    """
    Import WireGuard configs from existing node into DB.
    One-time migration endpoint: upload confs + server key.
    """
    store = WgBlobStore(db)
    imported = []

    file_map = {
        "antizapret.conf": (antizapret_conf, "/etc/wireguard/antizapret.conf"),
        "vpn.conf": (vpn_conf, "/etc/wireguard/vpn.conf"),
    }

    for label, (upload, path) in file_map.items():
        if upload:
            content = await upload.read()
            store.put(path, content, by=f"import:{admin.username}")
            imported.append(label)

    if wg_key:
        from cryptography.hazmat.primitives.asymmetric.x25519 import X25519PrivateKey

        key_content = await wg_key.read()
        priv_b64 = key_content.decode().strip()
        priv_raw = base64.b64decode(priv_b64)
        priv_obj = X25519PrivateKey.from_private_bytes(priv_raw)
        pub_b64 = base64.b64encode(priv_obj.public_key().public_bytes_raw()).decode()

        for iface in ("antizapret", "vpn"):
            existing = db.get(WgServerKeys, iface)
            if existing:
                existing.private_key = priv_b64
                existing.public_key = pub_b64
            else:
                db.add(WgServerKeys(iface=iface, private_key=priv_b64, public_key=pub_b64))
        db.commit()
        imported.append("wg_key")

    return {"imported": imported, "count": len(imported)}
