"""
Monitoring CRUD operations - connection logs
"""
from datetime import datetime, timedelta
from typing import Optional
import uuid
from sqlalchemy.orm import Session
from sqlalchemy import func, and_

from app.db.models import ConnectionLog, VPNConfig


def get_active_connections(db: Session) -> list[ConnectionLog]:
    """Get all currently active connections"""
    return db.query(ConnectionLog).filter(
        ConnectionLog.status == 'connected'
    ).order_by(ConnectionLog.connected_at.desc()).all()


def get_connection_count(db: Session) -> int:
    """Count active connections"""
    return db.query(ConnectionLog).filter(
        ConnectionLog.status == 'connected'
    ).count()


def get_by_config(
    db: Session, config_id: uuid.UUID, days: int = 7
) -> list[ConnectionLog]:
    """Get connection history for a specific config"""
    since = datetime.utcnow() - timedelta(days=days)
    return db.query(ConnectionLog).filter(
        ConnectionLog.config_id == config_id,
        ConnectionLog.connected_at >= since
    ).order_by(ConnectionLog.connected_at.desc()).all()


def get_history(
    db: Session, days: int = 7, skip: int = 0, limit: int = 100
) -> list[ConnectionLog]:
    """Get connection history for a period"""
    since = datetime.utcnow() - timedelta(days=days)
    return db.query(ConnectionLog).filter(
        ConnectionLog.connected_at >= since
    ).order_by(ConnectionLog.connected_at.desc()).offset(skip).limit(limit).all()


def get_stats(db: Session) -> dict:
    """Get aggregate connection statistics"""
    active = db.query(ConnectionLog).filter(
        ConnectionLog.status == 'connected'
    ).count()

    total_bytes = db.query(
        func.coalesce(func.sum(ConnectionLog.bytes_sent), 0),
        func.coalesce(func.sum(ConnectionLog.bytes_received), 0)
    ).first()

    return {
        'active_connections': active,
        'total_bytes_sent': total_bytes[0] if total_bytes else 0,
        'total_bytes_received': total_bytes[1] if total_bytes else 0,
    }


def upsert_connection(
    db: Session,
    client_name: str,
    client_ip: Optional[str],
    bytes_sent: int,
    bytes_received: int,
    connected_at: Optional[datetime],
    config_id: Optional[uuid.UUID] = None,
) -> ConnectionLog:
    """Create or update a connection log entry.
    If an active connection for this client_name exists, update it.
    Otherwise, create a new entry.
    """
    existing = db.query(ConnectionLog).filter(
        ConnectionLog.client_name == client_name,
        ConnectionLog.status == 'connected'
    ).first()

    if existing:
        existing.client_ip = client_ip
        existing.bytes_sent = bytes_sent
        existing.bytes_received = bytes_received
        db.commit()
        db.refresh(existing)
        return existing

    log = ConnectionLog(
        config_id=config_id,
        client_name=client_name,
        client_ip=client_ip,
        bytes_sent=bytes_sent,
        bytes_received=bytes_received,
        connected_at=connected_at or datetime.utcnow(),
        status='connected'
    )
    db.add(log)
    db.commit()
    db.refresh(log)
    return log


def mark_disconnected(db: Session, client_name: str) -> None:
    """Mark all active connections for a client as disconnected"""
    db.query(ConnectionLog).filter(
        ConnectionLog.client_name == client_name,
        ConnectionLog.status == 'connected'
    ).update({
        'status': 'disconnected',
        'disconnected_at': datetime.utcnow()
    })
    db.commit()


def mark_all_disconnected_except(db: Session, active_client_names: list[str]) -> None:
    """Mark connections as disconnected if their client_name is not in active list"""
    if active_client_names:
        db.query(ConnectionLog).filter(
            ConnectionLog.status == 'connected',
            ~ConnectionLog.client_name.in_(active_client_names)
        ).update({
            'status': 'disconnected',
            'disconnected_at': datetime.utcnow()
        }, synchronize_session='fetch')
    else:
        # No active connections - mark all as disconnected
        db.query(ConnectionLog).filter(
            ConnectionLog.status == 'connected'
        ).update({
            'status': 'disconnected',
            'disconnected_at': datetime.utcnow()
        })
    db.commit()


def get_daily_traffic(db: Session, days: int = 7) -> list[dict]:
    """Get daily traffic aggregates for the last N days"""
    since = datetime.utcnow() - timedelta(days=days)

    results = db.query(
        func.date(ConnectionLog.connected_at).label('date'),
        func.sum(ConnectionLog.bytes_sent).label('bytes_sent'),
        func.sum(ConnectionLog.bytes_received).label('bytes_received'),
        func.count(ConnectionLog.id).label('connections')
    ).filter(
        ConnectionLog.connected_at >= since
    ).group_by(
        func.date(ConnectionLog.connected_at)
    ).order_by(
        func.date(ConnectionLog.connected_at)
    ).all()

    return [
        {
            'date': str(r.date),
            'bytes_sent': r.bytes_sent or 0,
            'bytes_received': r.bytes_received or 0,
            'connections': r.connections
        }
        for r in results
    ]
