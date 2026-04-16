"""
Application configuration using Pydantic Settings
"""
from urllib.parse import urlparse
from pydantic_settings import BaseSettings, SettingsConfigDict
from typing import Optional
from functools import lru_cache


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", case_sensitive=True)

    # Application
    APP_NAME: str = "CorpWeb"
    APP_VERSION: str = "0.1.0"
    DEBUG: bool = False

    # Database
    DATABASE_URL: str

    # Security
    SECRET_KEY: str
    JWT_ALGORITHM: str = "HS256"
    ACCESS_TOKEN_EXPIRE_MINUTES: int = 60
    REFRESH_TOKEN_EXPIRE_DAYS: int = 30

    # Google OAuth
    GOOGLE_CLIENT_ID: str
    GOOGLE_CLIENT_SECRET: str
    GOOGLE_OAUTH_DOMAIN: str

    # URLs
    FRONTEND_URL: str
    BACKEND_URL: str
    CORS_ORIGINS: str = "https://vpn-admin.yourcompany.com"

    # VPN Client Script Paths
    VPN_CLIENT_SCRIPT: str = "/root/antizapret/client.sh"
    VPN_CLIENT_DIR: str = "/root/antizapret/client"

    # Load balancer endpoint host (used when generating client configs)
    LB_ENDPOINT_HOST: str = ""

    # Logging
    LOG_LEVEL: str = "INFO"

    # Rate Limiting
    RATE_LIMIT_PER_MINUTE: int = 60

    # Monitoring
    MONITORING_UPDATE_INTERVAL: int = 30  # seconds
    OPENVPN_STATUS_LOG_DIR: str = "/etc/openvpn/server/logs"

    def get_cors_origins(self) -> list[str]:
        """Parse CORS origins from comma-separated string"""
        return [origin.strip() for origin in self.CORS_ORIGINS.split(",")]

    def get_short_server_name(self) -> str:
        """
        Extract subdomain from FRONTEND_URL for short config filenames.
        e.g. 'https://wgfi2.p4i.ru' -> 'wgfi2'
        Tunnel names in AmneziaWG are limited to 15 chars (IFNAMSIZ).
        """
        hostname = urlparse(self.FRONTEND_URL).hostname or "server"
        return hostname.split(".")[0]


@lru_cache()
def get_settings() -> Settings:
    """Cached settings instance"""
    return Settings()


# Export settings instance
settings = get_settings()
