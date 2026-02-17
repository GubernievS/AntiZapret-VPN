"""
VPN config schemas
"""
import uuid
from datetime import datetime
from pydantic import BaseModel, Field
from typing import Optional, Any


class ConfigCreate(BaseModel):
    """Create a new VPN config"""
    config_type: str = Field(
        ...,
        pattern=r'^(awg_antizapret|awg_vpn)$',
        description="Config type: 'awg_antizapret' or 'awg_vpn'"
    )


class ConfigResponse(BaseModel):
    """VPN config returned in API responses"""
    id: uuid.UUID
    user_id: uuid.UUID
    client_name: str
    config_type: str
    is_active: bool
    created_at: datetime
    updated_at: datetime
    # Connection status (populated from monitoring)
    connection_status: Optional[str] = None  # 'connected' | 'disconnected' | None

    model_config = {"from_attributes": True}


class ConfigDetailResponse(ConfigResponse):
    """Detailed config info (includes metadata)"""
    config_metadata: Optional[dict[str, Any]] = None
    config_file_path: Optional[str] = None
    # Owner info (for admin view)
    owner_username: Optional[str] = None
    owner_email: Optional[str] = None


class ConfigListResponse(BaseModel):
    """List of configs"""
    items: list[ConfigResponse]
    total: int
