"""
Monitoring service: parses wg show and OpenVPN status logs
to collect active connection data.
"""
import re
import subprocess
from datetime import datetime, timedelta
from pathlib import Path
from typing import Optional
from dataclasses import dataclass

from app.config import settings


@dataclass
class PeerInfo:
    """Parsed WireGuard/AmneziaWG peer info"""
    interface: str
    public_key: str
    endpoint: Optional[str] = None
    latest_handshake: Optional[datetime] = None
    transfer_rx: int = 0  # bytes received by peer
    transfer_tx: int = 0  # bytes sent by peer
    allowed_ips: Optional[str] = None


@dataclass
class OpenVPNClient:
    """Parsed OpenVPN client info"""
    common_name: str
    real_address: str
    bytes_received: int = 0
    bytes_sent: int = 0
    connected_since: Optional[datetime] = None


class MonitoringService:
    """Collects VPN connection data from WireGuard and OpenVPN"""

    @staticmethod
    def parse_wg_show() -> list[PeerInfo]:
        """
        Parse output of `wg show all` to get peer connection info.
        Returns list of PeerInfo for all connected peers.
        """
        try:
            result = subprocess.run(
                ["wg", "show", "all"],
                capture_output=True,
                text=True,
                timeout=10
            )
            if result.returncode != 0:
                return []
        except (subprocess.TimeoutExpired, FileNotFoundError):
            return []

        peers: list[PeerInfo] = []
        current_interface = ""
        current_peer: Optional[PeerInfo] = None

        for line in result.stdout.split('\n'):
            line = line.strip()
            if not line:
                continue

            # Interface line: "interface: antizapret"
            if line.startswith('interface:'):
                current_interface = line.split(':', 1)[1].strip()
                continue

            # Peer line: "peer: <public_key>"
            if line.startswith('peer:'):
                if current_peer:
                    peers.append(current_peer)
                current_peer = PeerInfo(
                    interface=current_interface,
                    public_key=line.split(':', 1)[1].strip()
                )
                continue

            if not current_peer:
                continue

            # Endpoint
            if line.startswith('endpoint:'):
                current_peer.endpoint = line.split(':', 1)[1].strip()

            # Latest handshake
            elif line.startswith('latest handshake:'):
                hs_str = line.split(':', 1)[1].strip()
                current_peer.latest_handshake = MonitoringService._parse_handshake_time(hs_str)

            # Transfer: "transfer: 1.23 MiB received, 4.56 MiB sent"
            elif line.startswith('transfer:'):
                transfer_str = line.split(':', 1)[1].strip()
                rx, tx = MonitoringService._parse_transfer(transfer_str)
                current_peer.transfer_rx = rx
                current_peer.transfer_tx = tx

            # Allowed IPs
            elif line.startswith('allowed ips:'):
                current_peer.allowed_ips = line.split(':', 1)[1].strip()

        if current_peer:
            peers.append(current_peer)

        return peers

    @staticmethod
    def _parse_handshake_time(hs_str: str) -> Optional[datetime]:
        """Parse WireGuard handshake time string into datetime.
        Examples: '1 minute, 23 seconds ago', '2 hours, 5 minutes, 10 seconds ago'
        """
        if not hs_str or hs_str == 'never':
            return None

        total_seconds = 0
        parts = re.findall(r'(\d+)\s+(second|minute|hour|day)s?', hs_str)
        multipliers = {'second': 1, 'minute': 60, 'hour': 3600, 'day': 86400}

        for value, unit in parts:
            total_seconds += int(value) * multipliers.get(unit, 0)

        if total_seconds == 0:
            return None

        return datetime.utcnow().replace(microsecond=0) - timedelta(seconds=total_seconds)

    @staticmethod
    def _parse_transfer(transfer_str: str) -> tuple[int, int]:
        """Parse WireGuard transfer string into bytes (rx, tx).
        Example: '1.23 MiB received, 4.56 GiB sent'
        """
        multipliers = {'B': 1, 'KiB': 1024, 'MiB': 1048576, 'GiB': 1073741824, 'TiB': 1099511627776}

        rx = 0
        tx = 0

        rx_match = re.search(r'([\d.]+)\s+(B|KiB|MiB|GiB|TiB)\s+received', transfer_str)
        tx_match = re.search(r'([\d.]+)\s+(B|KiB|MiB|GiB|TiB)\s+sent', transfer_str)

        if rx_match:
            rx = int(float(rx_match.group(1)) * multipliers.get(rx_match.group(2), 1))
        if tx_match:
            tx = int(float(tx_match.group(1)) * multipliers.get(tx_match.group(2), 1))

        return rx, tx

    @staticmethod
    def parse_openvpn_status() -> list[OpenVPNClient]:
        """
        Parse OpenVPN status log files from OPENVPN_STATUS_LOG_DIR.
        Status files contain lines like:
            CLIENT_LIST,common_name,real_address,virtual_address,...,bytes_received,bytes_sent,connected_since,...
        """
        log_dir = Path(settings.OPENVPN_STATUS_LOG_DIR)
        clients: list[OpenVPNClient] = []

        if not log_dir.exists():
            return clients

        for status_file in log_dir.glob("*-status.log"):
            try:
                content = status_file.read_text()
                for line in content.split('\n'):
                    if not line.startswith('CLIENT_LIST,'):
                        continue

                    parts = line.split(',')
                    if len(parts) < 8:
                        continue

                    common_name = parts[1]
                    real_address = parts[2]

                    # Skip header line
                    if common_name == 'Common Name':
                        continue

                    try:
                        bytes_received = int(parts[5])
                        bytes_sent = int(parts[6])
                    except (ValueError, IndexError):
                        bytes_received = 0
                        bytes_sent = 0

                    connected_since = None
                    try:
                        connected_since = datetime.strptime(parts[7], '%Y-%m-%d %H:%M:%S')
                    except (ValueError, IndexError):
                        pass

                    clients.append(OpenVPNClient(
                        common_name=common_name,
                        real_address=real_address,
                        bytes_received=bytes_received,
                        bytes_sent=bytes_sent,
                        connected_since=connected_since
                    ))
            except OSError:
                continue

        return clients

    @staticmethod
    def get_all_connections() -> list[dict]:
        """
        Combine WireGuard and OpenVPN connections into a unified list.
        Returns list of dicts with client info.
        """
        connections: list[dict] = []

        # WireGuard peers (considered "connected" if handshake within last 3 minutes)
        for peer in MonitoringService.parse_wg_show():
            is_active = False
            if peer.latest_handshake:
                age = (datetime.utcnow() - peer.latest_handshake).total_seconds()
                is_active = age < 180  # 3 minutes

            connections.append({
                'protocol': 'wireguard',
                'interface': peer.interface,
                'public_key': peer.public_key,
                'endpoint': peer.endpoint,
                'latest_handshake': peer.latest_handshake.isoformat() if peer.latest_handshake else None,
                'bytes_received': peer.transfer_rx,
                'bytes_sent': peer.transfer_tx,
                'allowed_ips': peer.allowed_ips,
                'is_active': is_active,
            })

        # OpenVPN clients
        for client in MonitoringService.parse_openvpn_status():
            connections.append({
                'protocol': 'openvpn',
                'interface': 'openvpn',
                'common_name': client.common_name,
                'endpoint': client.real_address,
                'latest_handshake': None,
                'bytes_received': client.bytes_received,
                'bytes_sent': client.bytes_sent,
                'connected_since': client.connected_since.isoformat() if client.connected_since else None,
                'is_active': True,
            })

        return connections

    @staticmethod
    def format_bytes(b: int) -> str:
        """Format bytes to human-readable string"""
        for unit in ['B', 'KiB', 'MiB', 'GiB', 'TiB']:
            if b < 1024:
                return f"{b:.1f} {unit}"
            b /= 1024
        return f"{b:.1f} PiB"
