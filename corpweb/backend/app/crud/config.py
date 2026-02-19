"""
VPN Config CRUD operations
"""
import uuid
from datetime import datetime
from typing import Optional
from sqlalchemy.orm import Session

from app.db.models import VPNConfig


def get_by_id(db: Session, config_id: uuid.UUID) -> Optional[VPNConfig]:
    return db.query(VPNConfig).filter(VPNConfig.id == config_id).first()


def get_by_client_name(db: Session, client_name: str) -> Optional[VPNConfig]:
    return db.query(VPNConfig).filter(VPNConfig.client_name == client_name).first()


def get_by_user(db: Session, user_id: uuid.UUID) -> list[VPNConfig]:
    """Get all configs for a user"""
    return db.query(VPNConfig).filter(
        VPNConfig.user_id == user_id
    ).order_by(VPNConfig.created_at.desc()).all()


def get_active_by_user(db: Session, user_id: uuid.UUID) -> list[VPNConfig]:
    """Get active configs for a user"""
    return db.query(VPNConfig).filter(
        VPNConfig.user_id == user_id,
        VPNConfig.is_active == True
    ).order_by(VPNConfig.created_at.desc()).all()


def count_active_by_user(db: Session, user_id: uuid.UUID) -> int:
    """Count active configs for a user"""
    return db.query(VPNConfig).filter(
        VPNConfig.user_id == user_id,
        VPNConfig.is_active == True
    ).count()


def get_client_names_by_user(db: Session, user_id: uuid.UUID) -> list[str]:
    """Get list of client_name strings for a user"""
    configs = db.query(VPNConfig.client_name).filter(
        VPNConfig.user_id == user_id
    ).all()
    return [c[0] for c in configs]


def get_all(db: Session, skip: int = 0, limit: int = 100) -> list[VPNConfig]:
    """Get all configs (admin view)"""
    return db.query(VPNConfig).order_by(
        VPNConfig.created_at.desc()
    ).offset(skip).limit(limit).all()


def get_total_count(db: Session) -> int:
    return db.query(VPNConfig).count()


def create(
    db: Session,
    user_id: uuid.UUID,
    client_name: str,
    config_type: str,
    config_file_path: Optional[str] = None,
    config_metadata: Optional[dict] = None
) -> VPNConfig:
    """Create a new VPN config record"""
    config = VPNConfig(
        id=uuid.uuid4(),
        user_id=user_id,
        client_name=client_name,
        config_type=config_type,
        config_file_path=config_file_path,
        config_metadata=config_metadata,
        is_active=True,
        created_at=datetime.utcnow(),
        updated_at=datetime.utcnow()
    )
    db.add(config)
    db.commit()
    db.refresh(config)
    return config


def delete_config(db: Session, config: VPNConfig) -> None:
    """Delete a config record"""
    db.delete(config)
    db.commit()


def deactivate(db: Session, config: VPNConfig) -> VPNConfig:
    """Mark config as inactive"""
    config.is_active = False
    config.updated_at = datetime.utcnow()
    db.commit()
    db.refresh(config)
    return config


def get_inactive_by_user(db: Session, user_id: uuid.UUID) -> list[VPNConfig]:
    """Get inactive (blocked) configs for a user"""
    return db.query(VPNConfig).filter(
        VPNConfig.user_id == user_id,
        VPNConfig.is_active == False
    ).order_by(VPNConfig.created_at.desc()).all()


def update_after_restore(
    db: Session,
    config: VPNConfig,
    config_file_path: Optional[str],
    config_metadata: Optional[dict],
) -> VPNConfig:
    """Update config record after VPN client restoration (possibly new paths)."""
    config.config_file_path = config_file_path
    if config_metadata is not None:
        config.config_metadata = config_metadata
    config.is_active = True
    config.updated_at = datetime.utcnow()
    db.commit()
    db.refresh(config)
    return config
