"""
System settings schemas
"""
from datetime import datetime
from pydantic import BaseModel, Field
from typing import Optional


class SystemSettingsResponse(BaseModel):
    """Current system settings"""
    max_configs_per_user: int
    updated_at: datetime
    updated_by: Optional[str] = None

    model_config = {"from_attributes": True}


class SystemSettingsUpdate(BaseModel):
    """Admin update to system settings"""
    max_configs_per_user: int = Field(..., ge=1, le=10, description="Max configs per user (1-10)")
