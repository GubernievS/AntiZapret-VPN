"""
Pydantic schemas for Antizapret configuration API
"""
from pydantic import BaseModel
from typing import Dict, Optional


class FileContentResponse(BaseModel):
    file_type: str
    content: str


class FileContentUpdate(BaseModel):
    content: str


class AntizapretSettingsResponse(BaseModel):
    """Current values from /root/antizapret/setup"""
    # Routing
    ROUTE_ALL: Optional[str] = None
    # CDN / services
    DISCORD_INCLUDE: Optional[str] = None
    CLOUDFLARE_INCLUDE: Optional[str] = None
    AMAZON_INCLUDE: Optional[str] = None
    GOOGLE_INCLUDE: Optional[str] = None
    WHATSAPP_INCLUDE: Optional[str] = None
    TELEGRAM_INCLUDE: Optional[str] = None
    HETZNER_INCLUDE: Optional[str] = None
    DIGITALOCEAN_INCLUDE: Optional[str] = None
    OVH_INCLUDE: Optional[str] = None
    AKAMAI_INCLUDE: Optional[str] = None
    ROBLOX_INCLUDE: Optional[str] = None
    # Features
    BLOCK_ADS: Optional[str] = None
    CLEAR_HOSTS: Optional[str] = None
    # WireGuard
    WIREGUARD_HOST: Optional[str] = None
    # Security
    SSH_PROTECTION: Optional[str] = None
    ATTACK_PROTECTION: Optional[str] = None
    TORRENT_GUARD: Optional[str] = None
    RESTRICT_FORWARD: Optional[str] = None
    # DNS
    ANTIZAPRET_DNS: Optional[str] = None
    VPN_DNS: Optional[str] = None
    # Clients
    ALTERNATIVE_CLIENT_IP: Optional[str] = None
    ALTERNATIVE_FAKE_IP: Optional[str] = None
    CLIENT_ISOLATION: Optional[str] = None
    # WARP
    WARP_OUTBOUND: Optional[str] = None


class AntizapretSettingsUpdate(BaseModel):
    """Dict of setting key → value to update"""
    settings: Dict[str, str]


class DoallResponse(BaseModel):
    status: str
    output: str
    changed: Optional[int] = None
