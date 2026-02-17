"""
Test configuration and fixtures.
Uses SQLite with type overrides for PostgreSQL-specific types (UUID, JSONB).
"""
import os
import uuid
import pytest
from datetime import datetime
from unittest.mock import patch

# Override settings BEFORE importing app modules
os.environ.update({
    "DATABASE_URL": "sqlite:///./test.db",
    "SECRET_KEY": "test-secret-key-for-testing-only-64chars-long-xxxxxxxxxxxxxxxxx",
    "JWT_ALGORITHM": "HS256",
    "GOOGLE_CLIENT_ID": "test-client-id",
    "GOOGLE_CLIENT_SECRET": "test-client-secret",
    "GOOGLE_OAUTH_DOMAIN": "testcompany.com",
    "FRONTEND_URL": "http://localhost:3000",
    "BACKEND_URL": "http://localhost:8000/api",
    "CORS_ORIGINS": "http://localhost:3000",
    "VPN_CLIENT_SCRIPT": "/dev/null",
    "VPN_CLIENT_DIR": "/tmp/test-vpn-client",
    "OPENVPN_STATUS_LOG_DIR": "/tmp/test-openvpn-logs",
})

from sqlalchemy import create_engine, event, String, Text, types
from sqlalchemy.pool import NullPool
from sqlalchemy.orm import sessionmaker
from fastapi.testclient import TestClient

from app.db.base import Base
from app.db.session import get_db
from app.db.models import User, SystemSettings
from app.core.security import get_password_hash, create_access_token

# ── SQLite compatibility: override PostgreSQL-specific column types ──
from sqlalchemy.dialects.postgresql import UUID as PG_UUID, JSONB as PG_JSONB


class SQLiteUUID(types.TypeDecorator):
    """Store UUID as string(36) in SQLite"""
    impl = String(36)
    cache_ok = True

    def process_bind_param(self, value, dialect):
        if value is not None:
            return str(value)
        return value

    def process_result_value(self, value, dialect):
        if value is not None:
            return uuid.UUID(value)
        return value


class SQLiteJSON(types.TypeDecorator):
    """Store JSONB as TEXT in SQLite"""
    impl = Text
    cache_ok = True


# Replace PG types in all registered model columns
for table in Base.metadata.tables.values():
    for column in table.columns:
        if isinstance(column.type, PG_UUID):
            column.type = SQLiteUUID()
        elif isinstance(column.type, PG_JSONB):
            column.type = SQLiteJSON()


# ── SQLite engine ──
# NullPool prevents stale connections surviving between tests when test.db is deleted
engine = create_engine(
    "sqlite:///./test.db",
    connect_args={"check_same_thread": False},
    poolclass=NullPool,
)


@event.listens_for(engine, "connect")
def set_sqlite_pragma(dbapi_connection, connection_record):
    cursor = dbapi_connection.cursor()
    cursor.execute("PRAGMA foreign_keys=ON")
    cursor.close()


TestSessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)


# ── Import app AFTER env override (so settings read test values) ──
# Patch scheduler and init_db to prevent side effects during tests
_start_patcher = patch("app.services.scheduler.start_scheduler")
_stop_patcher = patch("app.services.scheduler.stop_scheduler")
_init_db_patcher = patch("app.db.init_db.init_db")
_start_patcher.start()
_stop_patcher.start()
_init_db_patcher.start()

from app.main import app  # noqa: E402 — must import after env + patches


# ── Fixtures ──

@pytest.fixture(autouse=True)
def setup_db():
    """Create tables before each test, drop after"""
    Base.metadata.create_all(bind=engine)
    yield
    Base.metadata.drop_all(bind=engine)
    # Dispose app engine connections so file can be cleanly deleted
    from app.db.session import engine as app_engine
    app_engine.dispose()
    engine.dispose()
    try:
        os.remove("test.db")
    except OSError:
        pass


@pytest.fixture
def db():
    """Get a test database session"""
    session = TestSessionLocal()
    try:
        yield session
    finally:
        session.close()


@pytest.fixture
def client(db):
    """FastAPI TestClient with overridden database"""
    def override_get_db():
        try:
            yield db
        finally:
            pass

    app.dependency_overrides[get_db] = override_get_db
    with TestClient(app, raise_server_exceptions=False) as c:
        yield c
    app.dependency_overrides.clear()


@pytest.fixture
def admin_user(db) -> User:
    """Create an admin user"""
    user = User(
        id=uuid.uuid4(),
        email="admin@test.com",
        username="admin",
        password_hash=get_password_hash("adminpass"),
        role="admin",
        auth_provider="local",
        is_active=True,
        created_at=datetime.utcnow(),
        updated_at=datetime.utcnow(),
    )
    db.add(user)
    db.commit()
    db.refresh(user)
    return user


@pytest.fixture
def regular_user(db) -> User:
    """Create a regular user"""
    user = User(
        id=uuid.uuid4(),
        email="user@test.com",
        username="testuser",
        password_hash=get_password_hash("userpass"),
        role="user",
        auth_provider="local",
        is_active=True,
        created_at=datetime.utcnow(),
        updated_at=datetime.utcnow(),
    )
    db.add(user)
    db.commit()
    db.refresh(user)
    return user


@pytest.fixture
def system_settings(db) -> SystemSettings:
    """Create default system settings"""
    s = SystemSettings(
        id=1,
        max_configs_per_user=2,
        updated_at=datetime.utcnow(),
    )
    db.add(s)
    db.commit()
    db.refresh(s)
    return s


@pytest.fixture
def admin_token(admin_user) -> str:
    return create_access_token(data={"sub": str(admin_user.id), "role": "admin"})


@pytest.fixture
def user_token(regular_user) -> str:
    return create_access_token(data={"sub": str(regular_user.id), "role": "user"})


def auth_header(token: str) -> dict:
    return {"Authorization": f"Bearer {token}"}
