"""
Background scheduler for periodic monitoring updates.
Uses APScheduler to run monitoring tasks every N seconds.
"""
import logging
from apscheduler.schedulers.background import BackgroundScheduler

from app.config import settings
from app.db.session import SessionLocal
from app.services.monitoring import MonitoringService
from app.crud import monitoring as crud_monitoring
from app.crud import config as crud_config

logger = logging.getLogger(__name__)

scheduler = BackgroundScheduler()


def update_connection_logs():
    """
    Periodic task: collect live connections and update connection_logs table.
    Runs every MONITORING_UPDATE_INTERVAL seconds.
    """
    db = SessionLocal()
    try:
        active_client_names: list[str] = []

        # WireGuard connections
        for peer in MonitoringService.parse_wg_show():
            if not peer.latest_handshake:
                continue
            from datetime import datetime
            age = (datetime.utcnow() - peer.latest_handshake).total_seconds()
            if age > 180:  # Not active if handshake > 3 min ago
                continue

            # Try to find config by matching allowed_ips or public_key
            # For now, we store with client_name = None since WG doesn't expose client names
            # TODO: match peer public_key to config_metadata when available
            endpoint_ip = peer.endpoint.split(':')[0] if peer.endpoint else None

            crud_monitoring.upsert_connection(
                db=db,
                client_name=peer.public_key[:16],  # Use truncated public key as identifier
                client_ip=endpoint_ip,
                bytes_sent=peer.transfer_tx,
                bytes_received=peer.transfer_rx,
                connected_at=peer.latest_handshake,
            )
            active_client_names.append(peer.public_key[:16])

        # OpenVPN connections
        for client in MonitoringService.parse_openvpn_status():
            # Try to find config by client_name
            config = crud_config.get_by_client_name(db, client.common_name)
            config_id = config.id if config else None

            crud_monitoring.upsert_connection(
                db=db,
                client_name=client.common_name,
                client_ip=client.real_address,
                bytes_sent=client.bytes_sent,
                bytes_received=client.bytes_received,
                connected_at=client.connected_since,
                config_id=config_id,
            )
            active_client_names.append(client.common_name)

        # Mark stale connections as disconnected
        crud_monitoring.mark_all_disconnected_except(db, active_client_names)

    except Exception as e:
        logger.error(f"Error updating connection logs: {e}")
    finally:
        db.close()


def start_scheduler():
    """Start the background monitoring scheduler"""
    scheduler.add_job(
        update_connection_logs,
        'interval',
        seconds=settings.MONITORING_UPDATE_INTERVAL,
        id='update_connections',
        replace_existing=True,
    )
    scheduler.start()
    logger.info(f"Monitoring scheduler started (interval: {settings.MONITORING_UPDATE_INTERVAL}s)")


def stop_scheduler():
    """Stop the background scheduler"""
    if scheduler.running:
        scheduler.shutdown(wait=False)
        logger.info("Monitoring scheduler stopped")
