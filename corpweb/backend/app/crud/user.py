"""
User CRUD operations
"""
import uuid
from datetime import datetime
from typing import Optional
from sqlalchemy.orm import Session
from sqlalchemy import or_

from app.db.models import User
from app.core.security import get_password_hash, verify_password


def get_by_id(db: Session, user_id: uuid.UUID) -> Optional[User]:
    return db.query(User).filter(User.id == user_id).first()


def get_by_email(db: Session, email: str) -> Optional[User]:
    return db.query(User).filter(User.email == email).first()


def get_by_username(db: Session, username: str) -> Optional[User]:
    return db.query(User).filter(User.username == username).first()


def get_by_login(db: Session, login: str) -> Optional[User]:
    """Find user by username or email"""
    return db.query(User).filter(
        or_(User.username == login, User.email == login)
    ).first()


def get_by_google_id(db: Session, google_id: str) -> Optional[User]:
    return db.query(User).filter(User.google_id == google_id).first()


def get_all(db: Session, skip: int = 0, limit: int = 100) -> list[User]:
    return db.query(User).order_by(User.created_at.desc()).offset(skip).limit(limit).all()


def get_total_count(db: Session) -> int:
    return db.query(User).count()


def get_all_filtered(
    db: Session,
    skip: int = 0,
    limit: int = 100,
    search: Optional[str] = None
) -> list[User]:
    """Get users with optional ILIKE search on username/email."""
    query = db.query(User)
    if search:
        pattern = f"%{search}%"
        query = query.filter(
            or_(
                User.username.ilike(pattern),
                User.email.ilike(pattern)
            )
        )
    return query.order_by(User.created_at.desc()).offset(skip).limit(limit).all()


def get_filtered_count(db: Session, search: Optional[str] = None) -> int:
    """Count users matching optional search filter."""
    query = db.query(User)
    if search:
        pattern = f"%{search}%"
        query = query.filter(
            or_(
                User.username.ilike(pattern),
                User.email.ilike(pattern)
            )
        )
    return query.count()


def create_local_user(
    db: Session,
    email: str,
    username: str,
    password: str,
    role: str = "user"
) -> User:
    """Create a user with local authentication"""
    user = User(
        id=uuid.uuid4(),
        email=email,
        username=username,
        password_hash=get_password_hash(password),
        role=role,
        auth_provider="local",
        is_active=True,
        created_at=datetime.utcnow(),
        updated_at=datetime.utcnow()
    )
    db.add(user)
    db.commit()
    db.refresh(user)
    return user


def create_google_user(
    db: Session,
    email: str,
    google_id: str
) -> User:
    """Create a user from Google OAuth (auto-registration)"""
    # Generate username from email (before @)
    username = email.split("@")[0]

    # Ensure unique username
    base_username = username
    counter = 1
    while get_by_username(db, username):
        username = f"{base_username}{counter}"
        counter += 1

    user = User(
        id=uuid.uuid4(),
        email=email,
        username=username,
        password_hash=None,
        role="user",
        auth_provider="google",
        google_id=google_id,
        is_active=True,
        created_at=datetime.utcnow(),
        updated_at=datetime.utcnow()
    )
    db.add(user)
    db.commit()
    db.refresh(user)
    return user


def update_user(
    db: Session,
    user: User,
    email: Optional[str] = None,
    username: Optional[str] = None,
    is_active: Optional[bool] = None
) -> User:
    """Update user fields"""
    if email is not None:
        user.email = email
    if username is not None:
        user.username = username
    if is_active is not None:
        user.is_active = is_active
    db.commit()
    db.refresh(user)
    return user


def update_password(db: Session, user: User, new_password: str) -> User:
    """Update user password"""
    user.password_hash = get_password_hash(new_password)
    db.commit()
    db.refresh(user)
    return user


def update_last_login(db: Session, user: User) -> None:
    """Update last login timestamp"""
    user.last_login = datetime.utcnow()
    db.commit()


def toggle_active(db: Session, user: User) -> User:
    """Toggle user is_active status"""
    user.is_active = not user.is_active
    db.commit()
    db.refresh(user)
    return user


def delete_user(db: Session, user: User) -> None:
    """Delete user (cascades to configs and logs)"""
    db.delete(user)
    db.commit()


def authenticate(db: Session, login: str, password: str) -> Optional[User]:
    """Authenticate user by login (username or email) and password"""
    user = get_by_login(db, login)
    if not user:
        return None
    if not user.password_hash:
        return None  # OAuth-only user
    if not verify_password(password, user.password_hash):
        return None
    return user
