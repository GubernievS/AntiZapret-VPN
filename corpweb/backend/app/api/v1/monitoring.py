"""Monitoring API — reads from node agent heartbeats."""
from fastapi import APIRouter, Depends, Query
from sqlalchemy.orm import Session
from app.api.deps import require_admin
from app.db.session import get_db
from app.services.monitoring import MonitoringService

router = APIRouter()


@router.get("/connections")
def get_connections(node: str = Query(None), db: Session = Depends(get_db), _=Depends(require_admin)):
    return MonitoringService(db).get_active_connections(node_filter=node)


@router.get("/traffic")
def get_traffic(db: Session = Depends(get_db), _=Depends(require_admin)):
    return MonitoringService(db).get_traffic_stats()


@router.get("/overview")
def get_overview(db: Session = Depends(get_db), _=Depends(require_admin)):
    return MonitoringService(db).get_overview()
