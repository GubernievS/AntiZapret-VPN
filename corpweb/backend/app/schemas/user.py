"""
User schemas
"""
import uuid
from datetime import datetime
from pydantic import BaseModel, Field
from typing import Optional


class UserBase(BaseModel):
    """Common user fields"""
    email: str = Field(..., max_length=255)
    username: str = Field(..., min_length=2, max_length=50, pattern=r'^[a-zA-Z0-9._-]+$')


class UserCreate(UserBase):
    """Admin creates a user with password"""
    password: str = Field(..., min_length=6, max_length=128)


class UserUpdate(BaseModel):
    """Admin updates user fields"""
    email: Optional[str] = Field(None, max_length=255)
    username: Optional[str] = Field(None, min_length=2, max_length=50, pattern=r'^[a-zA-Z0-9._-]+$')
    is_active: Optional[bool] = None


class UserResponse(BaseModel):
    """User data returned in API responses"""
    id: uuid.UUID
    email: str
    username: str
    role: str
    auth_provider: str
    is_active: bool
    created_at: datetime
    last_login: Optional[datetime] = None
    config_count: int = 0

    model_config = {"from_attributes": True}


class UserListResponse(BaseModel):
    """Paginated list of users"""
    items: list[UserResponse]
    total: int


class MeResponse(BaseModel):
    """Current user info (includes config limit)"""
    id: uuid.UUID
    email: str
    username: str
    role: str
    auth_provider: str
    is_active: bool
    created_at: datetime
    last_login: Optional[datetime] = None
    config_count: int = 0
    max_configs: int = 2

    model_config = {"from_attributes": True}
