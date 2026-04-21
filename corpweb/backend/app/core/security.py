"""
Security utilities: password hashing, JWT tokens
"""
from datetime import datetime, timedelta
from typing import Optional, Dict, Any
from jose import jwt, JWTError
from passlib.context import CryptContext
from app.config import settings

# Password hashing context (bcrypt with cost=12)
pwd_context = CryptContext(schemes=["bcrypt"], deprecated="auto")


def get_password_hash(password: str) -> str:
    """
    Hash a password using bcrypt

    Args:
        password: Plain text password

    Returns:
        Hashed password
    """
    return pwd_context.hash(password)


def verify_password(plain_password: str, hashed_password: str) -> bool:
    """
    Verify a password against its hash

    Args:
        plain_password: Plain text password to verify
        hashed_password: Bcrypt hashed password

    Returns:
        True if password matches, False otherwise
    """
    return pwd_context.verify(plain_password, hashed_password)


def create_access_token(
    data: Dict[str, Any],
    expires_delta: Optional[timedelta] = None
) -> str:
    """
    Create a JWT access token

    Args:
        data: Payload data (should include 'sub' for user ID)
        expires_delta: Token expiration time (default: 1 hour)

    Returns:
        Encoded JWT token
    """
    to_encode = data.copy()

    if expires_delta:
        expire = datetime.utcnow() + expires_delta
    else:
        expire = datetime.utcnow() + timedelta(hours=1)

    to_encode.update({
        "exp": expire,
        "type": "access"
    })

    encoded_jwt = jwt.encode(
        to_encode,
        settings.SECRET_KEY,
        algorithm=settings.JWT_ALGORITHM
    )

    return encoded_jwt


def create_refresh_token(
    data: Dict[str, Any],
    expires_delta: Optional[timedelta] = None
) -> str:
    """
    Create a JWT refresh token

    Args:
        data: Payload data (should include 'sub' for user ID)
        expires_delta: Token expiration time (default: 30 days)

    Returns:
        Encoded JWT token
    """
    to_encode = data.copy()

    if expires_delta:
        expire = datetime.utcnow() + expires_delta
    else:
        expire = datetime.utcnow() + timedelta(days=30)

    to_encode.update({
        "exp": expire,
        "type": "refresh"
    })

    encoded_jwt = jwt.encode(
        to_encode,
        settings.SECRET_KEY,
        algorithm=settings.JWT_ALGORITHM
    )

    return encoded_jwt


def decode_token(token: str) -> Optional[Dict[str, Any]]:
    """
    Decode and verify a JWT token

    Args:
        token: JWT token string

    Returns:
        Token payload if valid, None otherwise
    """
    try:
        payload = jwt.decode(
            token,
            settings.SECRET_KEY,
            algorithms=[settings.JWT_ALGORITHM]
        )
        return payload
    except JWTError:
        return None


def create_config_share_token(
    config_id: str,
    *,
    bypass: bool = False,
    backup: bool = False,
    expires_minutes: int = 10,
) -> str:
    """
    Create a short-lived JWT token for public config file download.
    Used when config is too large for a QR code.

    The token carries the per-download flags (bypass / backup) so the
    public endpoint can render the same conf the authenticated user
    would have received from ``/configs/{id}/download``.
    """
    expire = datetime.utcnow() + timedelta(minutes=expires_minutes)
    payload = {
        "sub": config_id,
        "type": "config_share",
        "bypass": bool(bypass),
        "backup": bool(backup),
        "exp": expire,
    }
    return jwt.encode(payload, settings.SECRET_KEY, algorithm=settings.JWT_ALGORITHM)


def verify_config_share_token(token: str) -> Optional[dict]:
    """
    Verify a config share token and return its payload fields.

    Returns ``None`` if the token is invalid or expired; otherwise a dict
    with ``config_id``, ``bypass``, and ``backup``. Legacy tokens that
    predate the flags default both to ``False``.
    """
    payload = decode_token(token)
    if payload is None or payload.get("type") != "config_share":
        return None
    config_id = payload.get("sub")
    if not config_id:
        return None
    return {
        "config_id": config_id,
        "bypass": bool(payload.get("bypass", False)),
        "backup": bool(payload.get("backup", False)),
    }
