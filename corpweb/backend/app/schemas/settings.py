"""
System settings schemas
"""
from datetime import datetime
from pydantic import BaseModel, Field
from typing import Optional


class SystemSettingsResponse(BaseModel):
    """Current system settings"""
    max_configs_per_user: int
    google_play_url: Optional[str] = None
    app_store_url: Optional[str] = None
    apk_url: Optional[str] = None
    windows_url: Optional[str] = None
    updated_at: datetime
    updated_by: Optional[str] = None

    model_config = {"from_attributes": True}


class SystemSettingsUpdate(BaseModel):
    """Admin update to system settings"""
    max_configs_per_user: int = Field(..., ge=1, le=10, description="Max configs per user (1-10)")
    google_play_url: Optional[str] = Field(None, max_length=500)
    app_store_url: Optional[str] = Field(None, max_length=500)
    apk_url: Optional[str] = Field(None, max_length=500)
    windows_url: Optional[str] = Field(None, max_length=500)
