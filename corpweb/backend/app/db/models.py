"""
SQLAlchemy database models
"""
import uuid
from datetime import datetime
from sqlalchemy import Column, String, Boolean, DateTime, ForeignKey, BigInteger, Text, Integer, LargeBinary, func
from sqlalchemy.dialects.postgresql import UUID, JSONB
from sqlalchemy.orm import relationship
from app.db.base import Base


class User(Base):
    __tablename__ = "users"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    email = Column(String(255), unique=True, nullable=False, index=True)
    username = Column(String(50), unique=True, nullable=False, index=True)
    password_hash = Column(String(255), nullable=True)  # NULL for OAuth users
    role = Column(String(20), nullable=False, default="user")  # 'admin' | 'user'
    auth_provider = Column(String(20), default="local")  # 'local' | 'google'
    google_id = Column(String(255), unique=True, nullable=True)
    is_active = Column(Boolean, default=True, nullable=False)
    created_at = Column(DateTime, default=datetime.utcnow, nullable=False)
    updated_at = Column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow, nullable=False)
    last_login = Column(DateTime, nullable=True)

    # Relationships
    configs = relationship("VPNConfig", back_populates="user", cascade="all, delete-orphan")

    def __repr__(self):
        return f"<User {self.username}>"


class VPNConfig(Base):
    __tablename__ = "vpn_configs"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    user_id = Column(UUID(as_uuid=True), ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True)

    # Internal name for client.sh (e.g., ivan.ivanov-1)
    client_name = Column(String(32), unique=True, nullable=False, index=True)

    # Config type: 'awg_antizapret' (selective routing) | 'awg_vpn' (all traffic)
    config_type = Column(String(20), nullable=False)

    # Metadata (IP, keys, paths)
    config_metadata = Column(JSONB, nullable=True)

    # Path to .conf file
    config_file_path = Column(String(500), nullable=True)

    # Status
    is_active = Column(Boolean, default=True, nullable=False)
    created_at = Column(DateTime, default=datetime.utcnow, nullable=False)
    updated_at = Column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow, nullable=False)

    # Relationships
    user = relationship("User", back_populates="configs")
    connection_logs = relationship("ConnectionLog", back_populates="config", cascade="all, delete-orphan")

    def __repr__(self):
        return f"<VPNConfig {self.client_name}>"


class ConnectionLog(Base):
    __tablename__ = "connection_logs"

    id = Column(BigInteger, primary_key=True, autoincrement=True)
    config_id = Column(UUID(as_uuid=True), ForeignKey("vpn_configs.id", ondelete="CASCADE"), nullable=True, index=True)
    client_name = Column(String(32), nullable=True)
    client_ip = Column(String(50), nullable=True)
    bytes_sent = Column(BigInteger, default=0)
    bytes_received = Column(BigInteger, default=0)
    connected_at = Column(DateTime, nullable=True)
    disconnected_at = Column(DateTime, nullable=True)
    status = Column(String(20), nullable=True, index=True)  # 'connected' | 'disconnected'

    # Relationships
    config = relationship("VPNConfig", back_populates="connection_logs")

    def __repr__(self):
        return f"<ConnectionLog {self.client_name} - {self.status}>"


class SystemSettings(Base):
    """
    Global system settings
    Singleton table - should only have one row with id=1
    """
    __tablename__ = "system_settings"

    id = Column(Integer, primary_key=True, default=1)

    # Maximum number of configs per user (configurable by admin, default: 2)
    max_configs_per_user = Column(Integer, nullable=False, default=2)

    # Client download links (shown to users on dashboard)
    google_play_url = Column(String(500), nullable=True)
    app_store_url = Column(String(500), nullable=True)
    apk_url = Column(String(500), nullable=True)
    windows_url = Column(String(500), nullable=True)

    # Control-plane IP for DNAT balancer SNAT rules
    cp_ip = Column(String(50), nullable=True)

    # When True, escape-mode (obfuscation) DNAT rules are applied on CP and
    # "Обход блокировки" toggle becomes visible in LK.
    escape_enabled = Column(Boolean, nullable=False, default=False, server_default="false")

    updated_at = Column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow, nullable=False)
    updated_by = Column(String(50), nullable=True)  # Username who made the change

    def __repr__(self):
        return f"<SystemSettings max_configs={self.max_configs_per_user}>"


class WgFileState(Base):
    """WireGuard config files stored as blobs for HA synchronisation."""
    __tablename__ = "wg_file_state"

    path = Column(String(500), primary_key=True)
    content = Column(LargeBinary, nullable=False)
    sha256 = Column(String(64), nullable=False)
    size_bytes = Column(Integer, nullable=False)
    updated_at = Column(DateTime, nullable=False, default=datetime.utcnow)
    updated_by = Column(String(100), nullable=False)

    def __repr__(self):
        return f"<WgFileState {self.path}>"


class WgServerKeys(Base):
    """Server WireGuard keypairs per interface."""
    __tablename__ = "wg_server_keys"

    iface = Column(String(50), primary_key=True)
    private_key = Column(Text, nullable=False)
    public_key = Column(Text, nullable=False)
    created_at = Column(DateTime, nullable=False, default=datetime.utcnow)

    def __repr__(self):
        return f"<WgServerKeys {self.iface}>"


class WgObfuscationParams(Base):
    """
    Per-iface AmneziaWG obfuscation parameters (S1/S2/H1-H4/Jc/Jmin/Jmax/I1).

    One row per escape iface (antizapret_escape, vpn_escape). Values are
    generated randomly per-installation and only regenerated manually via
    an admin button — regeneration invalidates all existing escape clients.
    """
    __tablename__ = "wg_obfuscation_params"

    iface = Column(String(64), primary_key=True)
    jc = Column(Integer, nullable=False)
    jmin = Column(Integer, nullable=False)
    jmax = Column(Integer, nullable=False)
    s1 = Column(Integer, nullable=False)
    s2 = Column(Integer, nullable=False)
    h1 = Column(BigInteger, nullable=False)
    h2 = Column(BigInteger, nullable=False)
    h3 = Column(BigInteger, nullable=False)
    h4 = Column(BigInteger, nullable=False)
    i1 = Column(Text, nullable=False)
    created_at = Column(DateTime, server_default=func.now(), nullable=False)
    updated_at = Column(DateTime, server_default=func.now(), onupdate=func.now(), nullable=False)

    def __repr__(self):
        return f"<WgObfuscationParams {self.iface}>"


class Node(Base):
    """Data-plane node registry with health and metrics."""
    __tablename__ = "nodes"

    id = Column(Integer, primary_key=True, autoincrement=True)
    hostname = Column(String(255), unique=True, nullable=False)
    private_ip = Column(String(50), nullable=False)
    enroll_token = Column(String(255), unique=True, nullable=False)
    last_seen = Column(DateTime, nullable=True)
    health = Column(String(20), nullable=True)
    applied_sha = Column(JSONB, nullable=True)
    metrics = Column(JSONB, nullable=True)
    peers_snapshot = Column(JSONB, nullable=True)
    created_at = Column(DateTime, nullable=False, default=datetime.utcnow)

    def __repr__(self):
        return f"<Node {self.hostname}>"
