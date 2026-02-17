"""
Admin API endpoints
Users management, system settings, dashboard
"""
import uuid
from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session

from app.db.session import get_db
from app.db.models import User, VPNConfig, ConnectionLog, SystemSettings
from app.crud import user as crud_user
from app.schemas.user import UserCreate, UserUpdate, UserResponse, UserListResponse
from app.schemas.settings import SystemSettingsResponse, SystemSettingsUpdate
from app.api.deps import require_admin

router = APIRouter()


# ============================================
# Users Management
# ============================================

@router.get("/users", response_model=UserListResponse)
async def list_users(
    skip: int = 0,
    limit: int = 100,
    admin: User = Depends(require_admin),
    db: Session = Depends(get_db)
):
    """List all users with config counts"""
    users = crud_user.get_all(db, skip=skip, limit=limit)
    total = crud_user.get_total_count(db)

    items = []
    for user in users:
        config_count = db.query(VPNConfig).filter(
            VPNConfig.user_id == user.id,
            VPNConfig.is_active == True
        ).count()
        items.append(UserResponse(
            id=user.id,
            email=user.email,
            username=user.username,
            role=user.role,
            auth_provider=user.auth_provider,
            is_active=user.is_active,
            created_at=user.created_at,
            last_login=user.last_login,
            config_count=config_count
        ))

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

    return UserResponse(
        id=user.id,
        email=user.email,
        username=user.username,
        role=user.role,
        auth_provider=user.auth_provider,
        is_active=user.is_active,
        created_at=user.created_at,
        last_login=user.last_login,
        config_count=0
    )


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

    config_count = db.query(VPNConfig).filter(
        VPNConfig.user_id == user.id,
        VPNConfig.is_active == True
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
        config_count=config_count
    )


@router.patch("/users/{user_id}/block", response_model=UserResponse)
async def toggle_user_block(
    user_id: uuid.UUID,
    admin: User = Depends(require_admin),
    db: Session = Depends(get_db)
):
    """Toggle user block/unblock (admin only)"""
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

    user = crud_user.toggle_active(db, user)

    config_count = db.query(VPNConfig).filter(
        VPNConfig.user_id == user.id,
        VPNConfig.is_active == True
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
        config_count=config_count
    )


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

    # TODO: Also delete VPN configs on the server via VPNManager
    crud_user.delete_user(db, user)


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
    """Update system settings (admin only)"""
    settings = db.query(SystemSettings).filter(SystemSettings.id == 1).first()
    if not settings:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="System settings not initialized"
        )

    settings.max_configs_per_user = data.max_configs_per_user
    settings.updated_by = admin.username
    db.commit()
    db.refresh(settings)
    return settings


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
