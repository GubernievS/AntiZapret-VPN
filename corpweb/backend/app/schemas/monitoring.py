"""
Monitoring Pydantic schemas
"""
from pydantic import BaseModel
from typing import Optional
from datetime import datetime


class ConnectionLogResponse(BaseModel):
    id: int
    config_id: Optional[str] = None
    client_name: Optional[str] = None
    client_ip: Optional[str] = None
    bytes_sent: int = 0
    bytes_received: int = 0
    connected_at: Optional[datetime] = None
    disconnected_at: Optional[datetime] = None
    status: Optional[str] = None

    model_config = {"from_attributes": True}


class LiveConnectionResponse(BaseModel):
    """Live connection data from wg show / OpenVPN status"""
    protocol: str  # 'wireguard' | 'openvpn'
    interface: str
    client_name: Optional[str] = None
    public_key: Optional[str] = None
    endpoint: Optional[str] = None
    latest_handshake: Optional[str] = None
    connected_since: Optional[str] = None
    bytes_sent: int = 0
    bytes_received: int = 0
    is_active: bool = False
    allowed_ips: Optional[str] = None


class MonitoringStatsResponse(BaseModel):
    active_connections: int = 0
    total_bytes_sent: int = 0
    total_bytes_received: int = 0


class DailyTrafficResponse(BaseModel):
    date: str
    bytes_sent: int = 0
    bytes_received: int = 0
    connections: int = 0


class MonitoringOverviewResponse(BaseModel):
    stats: MonitoringStatsResponse
    live_connections: list[LiveConnectionResponse]
    daily_traffic: list[DailyTrafficResponse]
