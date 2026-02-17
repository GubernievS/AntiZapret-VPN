"""
Authentication API endpoints
"""
from datetime import timedelta
from fastapi import APIRouter, Depends, HTTPException, status, Response, Request
from sqlalchemy.orm import Session

from app.db.session import get_db
from app.db.models import User, SystemSettings, VPNConfig
from app.core.security import (
    create_access_token,
    create_refresh_token,
    decode_token,
    verify_password,
)
from app.crud import user as crud_user
from app.schemas.auth import LoginRequest, TokenResponse, RefreshRequest, ChangePasswordRequest
from app.schemas.user import MeResponse
from app.api.deps import get_current_user
from app.config import settings

router = APIRouter()


@router.post("/login", response_model=TokenResponse)
async def login(
    data: LoginRequest,
    response: Response,
    db: Session = Depends(get_db)
):
    """
    Login with username/email and password.
    Returns JWT access token. Sets refresh token in HttpOnly cookie.
    """
    user = crud_user.authenticate(db, data.login, data.password)

    if not user:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid credentials"
        )

    if not user.is_active:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="User account is blocked"
        )

    # Update last login
    crud_user.update_last_login(db, user)

    # Create tokens
    access_token = create_access_token(
        data={"sub": str(user.id), "role": user.role},
        expires_delta=timedelta(minutes=settings.ACCESS_TOKEN_EXPIRE_MINUTES)
    )
    refresh_token = create_refresh_token(
        data={"sub": str(user.id)},
        expires_delta=timedelta(days=settings.REFRESH_TOKEN_EXPIRE_DAYS)
    )

    # Set refresh token in HttpOnly cookie
    response.set_cookie(
        key="refresh_token",
        value=refresh_token,
        httponly=True,
        secure=True,
        samesite="lax",
        max_age=settings.REFRESH_TOKEN_EXPIRE_DAYS * 24 * 3600,
        path="/api/v1/auth"
    )

    return TokenResponse(
        access_token=access_token,
        expires_in=settings.ACCESS_TOKEN_EXPIRE_MINUTES * 60
    )


@router.post("/refresh", response_model=TokenResponse)
async def refresh_token(
    request: Request,
    response: Response,
    db: Session = Depends(get_db)
):
    """
    Refresh access token using refresh token from cookie.
    """
    token = request.cookies.get("refresh_token")
    if not token:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Refresh token not found"
        )

    payload = decode_token(token)
    if payload is None or payload.get("type") != "refresh":
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid refresh token"
        )

    user_id = payload.get("sub")
    user = crud_user.get_by_id(db, user_id)

    if not user or not user.is_active:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="User not found or blocked"
        )

    # Create new tokens
    access_token = create_access_token(
        data={"sub": str(user.id), "role": user.role},
        expires_delta=timedelta(minutes=settings.ACCESS_TOKEN_EXPIRE_MINUTES)
    )
    new_refresh_token = create_refresh_token(
        data={"sub": str(user.id)},
        expires_delta=timedelta(days=settings.REFRESH_TOKEN_EXPIRE_DAYS)
    )

    response.set_cookie(
        key="refresh_token",
        value=new_refresh_token,
        httponly=True,
        secure=True,
        samesite="lax",
        max_age=settings.REFRESH_TOKEN_EXPIRE_DAYS * 24 * 3600,
        path="/api/v1/auth"
    )

    return TokenResponse(
        access_token=access_token,
        expires_in=settings.ACCESS_TOKEN_EXPIRE_MINUTES * 60
    )


@router.post("/logout")
async def logout(response: Response):
    """
    Logout: clear refresh token cookie.
    """
    response.delete_cookie(
        key="refresh_token",
        path="/api/v1/auth"
    )
    return {"detail": "Logged out"}


@router.get("/me", response_model=MeResponse)
async def get_me(
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    """
    Get current user info including config count and max limit.
    """
    config_count = db.query(VPNConfig).filter(
        VPNConfig.user_id == current_user.id,
        VPNConfig.is_active == True
    ).count()

    sys_settings = db.query(SystemSettings).filter(SystemSettings.id == 1).first()
    max_configs = sys_settings.max_configs_per_user if sys_settings else 2

    return MeResponse(
        id=current_user.id,
        email=current_user.email,
        username=current_user.username,
        role=current_user.role,
        auth_provider=current_user.auth_provider,
        is_active=current_user.is_active,
        created_at=current_user.created_at,
        last_login=current_user.last_login,
        config_count=config_count,
        max_configs=max_configs
    )


@router.post("/change-password")
async def change_password(
    data: ChangePasswordRequest,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    """
    Change own password (for local auth users only).
    """
    if current_user.auth_provider != "local":
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Cannot change password for Google OAuth users"
        )

    if not current_user.password_hash:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="No password set"
        )

    if not verify_password(data.current_password, current_user.password_hash):
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Current password is incorrect"
        )

    crud_user.update_password(db, current_user, data.new_password)
    return {"detail": "Password changed successfully"}


# ============================================
# Google OAuth endpoints
# ============================================

@router.get("/google")
async def google_login(request: Request):
    """
    Redirect to Google OAuth consent screen.
    """
    from app.core.oauth import get_google_client
    google = get_google_client()
    redirect_uri = f"{settings.BACKEND_URL}/v1/auth/google/callback"
    return await google.authorize_redirect(request, redirect_uri)


@router.get("/google/callback")
async def google_callback(
    request: Request,
    response: Response,
    db: Session = Depends(get_db)
):
    """
    Google OAuth callback.
    Auto-creates user on first login if domain matches.
    """
    from app.core.oauth import get_google_client
    google = get_google_client()

    try:
        token = await google.authorize_access_token(request)
    except Exception:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Failed to authorize with Google"
        )

    userinfo = token.get("userinfo")
    if not userinfo:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Failed to get user info from Google"
        )

    email = userinfo.get("email", "")
    google_id = userinfo.get("sub", "")

    if not email or not google_id:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Invalid Google account data"
        )

    # Check domain restriction
    email_domain = email.split("@")[-1]
    if email_domain != settings.GOOGLE_OAUTH_DOMAIN:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail=f"Domain @{email_domain} is not allowed. Only @{settings.GOOGLE_OAUTH_DOMAIN} users can login."
        )

    # Find or create user
    user = crud_user.get_by_google_id(db, google_id)

    if not user:
        # Check if email already exists (local user with same email)
        existing = crud_user.get_by_email(db, email)
        if existing:
            # Link Google account to existing user
            existing.google_id = google_id
            existing.auth_provider = "google"
            db.commit()
            user = existing
        else:
            # Auto-create new user
            user = crud_user.create_google_user(db, email, google_id)

    if not user.is_active:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="User account is blocked by administrator"
        )

    # Update last login
    crud_user.update_last_login(db, user)

    # Create tokens
    access_token = create_access_token(
        data={"sub": str(user.id), "role": user.role},
        expires_delta=timedelta(minutes=settings.ACCESS_TOKEN_EXPIRE_MINUTES)
    )
    refresh_token_value = create_refresh_token(
        data={"sub": str(user.id)},
        expires_delta=timedelta(days=settings.REFRESH_TOKEN_EXPIRE_DAYS)
    )

    # Set refresh token cookie
    response.set_cookie(
        key="refresh_token",
        value=refresh_token_value,
        httponly=True,
        secure=True,
        samesite="lax",
        max_age=settings.REFRESH_TOKEN_EXPIRE_DAYS * 24 * 3600,
        path="/api/v1/auth"
    )

    # Redirect to frontend with access token
    from fastapi.responses import RedirectResponse
    redirect_url = f"{settings.FRONTEND_URL}/auth/callback?token={access_token}"
    return RedirectResponse(url=redirect_url)
