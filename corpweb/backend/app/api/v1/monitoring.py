"""
Monitoring API endpoints
"""
import uuid
from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session

from app.api.deps import get_current_user, require_admin
from app.db.session import get_db
from app.db.models import User
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
    _user: User = Depends(require_admin),
):
    """Get live connections from wg show + OpenVPN status (admin only)"""
    raw = MonitoringService.get_all_connections()
    return [LiveConnectionResponse(**conn) for conn in raw]


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
    stats = crud_monitoring.get_stats(db)
    live_raw = MonitoringService.get_all_connections()
    live = [LiveConnectionResponse(**conn) for conn in live_raw]
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
