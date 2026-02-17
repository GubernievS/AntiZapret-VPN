"""
Monitoring API endpoints
"""
import re
import uuid
from pathlib import Path
from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session

from app.api.deps import get_current_user, require_admin
from app.db.session import get_db
from app.db.models import User, VPNConfig
from app.crud import monitoring as crud_monitoring
from app.crud import config as crud_config
from app.services.monitoring import MonitoringService
from app.schemas.monitoring import (
    MonitoringStatsResponse,
    LiveConnectionResponse,
    DailyTrafficResponse,
    MonitoringOverviewResponse,
    ConnectionLogResponse,
)

# Pattern to extract client_name from filename:
# antizapret-{client_name}-({server_ip})-am.conf  OR  antizapret-{client_name}-am.conf
_CONF_NAME_RE = re.compile(r'^(?:antizapret|vpn)-(.+?)(?:-\([^)]+\))?-am\.conf$')


def _parse_address_from_file(path: Path) -> str | None:
    """Extract client VPN IP from [Interface] Address = ... line."""
    try:
        for line in path.read_text().splitlines():
            line = line.strip()
            if line.lower().startswith('address'):
                ip_part = line.split('=', 1)[1].strip()
                return ip_part.split('/')[0].strip()
    except OSError:
        pass
    return None


def _build_ip_to_name_map_from_files(client_dir: Path) -> dict:
    """
    Scan antizapret/vpn config directories and build IP -> client_name mapping.
    Extracts client_name from filename, VPN IP from file content.
    Works for all existing configs regardless of how they were created.
    """
    ip_map: dict = {}
    for subdir in ('antizapret', 'vpn'):
        dir_path = client_dir / 'amneziawg' / subdir
        if not dir_path.exists():
            continue
        for conf_file in dir_path.glob('*.conf'):
            m = _CONF_NAME_RE.match(conf_file.name)
            if not m:
                continue
            client_name = m.group(1)
            ip = _parse_address_from_file(conf_file)
            if ip and client_name:
                ip_map[ip] = client_name
    return ip_map


def _build_ip_to_name_map(db: Session) -> dict:
    """
    Build a mapping of VPN IP -> client_name.
    Priority:
      1. vpn_ip stored in config_metadata (new configs)
      2. Scan actual config files on disk (covers all existing configs)
    """
    from app.config import settings as app_settings
    client_dir = Path(app_settings.VPN_CLIENT_DIR)

    # Start with full file-scan (covers existing configs too)
    ip_map = _build_ip_to_name_map_from_files(client_dir)

    # Override/add entries from DB metadata (most authoritative for new configs)
    configs = db.query(VPNConfig).filter(VPNConfig.is_active == True).all()
    for cfg in configs:
        meta = cfg.config_metadata or {}
        vpn_ip = meta.get("vpn_ip")
        if vpn_ip:
            ip_map[vpn_ip] = cfg.client_name

    return ip_map


def _resolve_client_name(conn: dict, ip_map: dict) -> str | None:
    """
    Resolve a human-readable client_name for a live connection.
    - WireGuard: match allowed_ips (e.g. '10.8.0.2/32') against ip_map
    - OpenVPN: use common_name directly (it matches client_name)
    """
    if conn.get("protocol") == "openvpn":
        return conn.get("common_name")

    allowed_ips = conn.get("allowed_ips", "") or ""
    # allowed_ips may be comma-separated; each entry like '10.8.0.2/32'
    for entry in allowed_ips.split(","):
        ip = entry.strip().split("/")[0]
        if ip in ip_map:
            return ip_map[ip]
    return None

router = APIRouter()


@router.get("/stats", response_model=MonitoringStatsResponse)
def get_stats(
    db: Session = Depends(get_db),
    _user: User = Depends(require_admin),
):
    """Get aggregate monitoring statistics (admin only)"""
    return crud_monitoring.get_stats(db)


@router.get("/connections", response_model=list[LiveConnectionResponse])
def get_live_connections(
    db: Session = Depends(get_db),
    _user: User = Depends(require_admin),
):
    """Get live connections from wg show + OpenVPN status (admin only)"""
    ip_map = _build_ip_to_name_map(db)
    raw = MonitoringService.get_all_connections()
    result = []
    for conn in raw:
        conn = dict(conn)
        if not conn.get("client_name"):
            conn["client_name"] = _resolve_client_name(conn, ip_map)
        result.append(LiveConnectionResponse(**conn))
    return result


@router.get("/history", response_model=list[ConnectionLogResponse])
def get_history(
    days: int = 7,
    skip: int = 0,
    limit: int = 100,
    db: Session = Depends(get_db),
    _user: User = Depends(require_admin),
):
    """Get connection history (admin only)"""
    logs = crud_monitoring.get_history(db, days=days, skip=skip, limit=limit)
    return [ConnectionLogResponse.model_validate(log) for log in logs]


@router.get("/traffic", response_model=list[DailyTrafficResponse])
def get_daily_traffic(
    days: int = 7,
    db: Session = Depends(get_db),
    _user: User = Depends(require_admin),
):
    """Get daily traffic statistics (admin only)"""
    return crud_monitoring.get_daily_traffic(db, days=days)


@router.get("/overview", response_model=MonitoringOverviewResponse)
def get_overview(
    db: Session = Depends(get_db),
    _user: User = Depends(require_admin),
):
    """Get full monitoring overview: stats + live connections + traffic (admin only)"""
    ip_map = _build_ip_to_name_map(db)
    stats = crud_monitoring.get_stats(db)
    live_raw = MonitoringService.get_all_connections()
    live = []
    for conn in live_raw:
        conn = dict(conn)
        if not conn.get("client_name"):
            conn["client_name"] = _resolve_client_name(conn, ip_map)
        live.append(LiveConnectionResponse(**conn))
    traffic = crud_monitoring.get_daily_traffic(db, days=7)

    return MonitoringOverviewResponse(
        stats=MonitoringStatsResponse(**stats),
        live_connections=live,
        daily_traffic=[DailyTrafficResponse(**t) for t in traffic],
    )


@router.get("/config/{config_id}", response_model=list[ConnectionLogResponse])
def get_config_history(
    config_id: str,
    days: int = 7,
    db: Session = Depends(get_db),
    user: User = Depends(get_current_user),
):
    """Get connection history for a specific config.
    Users can see their own configs, admins can see all.
    """
    config = crud_config.get_by_id(db, uuid.UUID(config_id))
    if not config:
        raise HTTPException(404, "Config not found")

    if user.role != 'admin' and config.user_id != user.id:
        raise HTTPException(403, "Access denied")

    logs = crud_monitoring.get_by_config(db, uuid.UUID(config_id), days=days)
    return [ConnectionLogResponse.model_validate(log) for log in logs]
