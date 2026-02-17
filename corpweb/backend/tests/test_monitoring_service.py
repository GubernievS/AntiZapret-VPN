"""
Tests for monitoring service (parsing logic)
"""
from app.services.monitoring import MonitoringService


class TestParseTransfer:
    def test_parse_mib(self):
        rx, tx = MonitoringService._parse_transfer("1.5 MiB received, 2.3 MiB sent")
        assert rx == int(1.5 * 1048576)
        assert tx == int(2.3 * 1048576)

    def test_parse_gib(self):
        rx, tx = MonitoringService._parse_transfer("1.0 GiB received, 0.5 GiB sent")
        assert rx == 1073741824
        assert tx == int(0.5 * 1073741824)

    def test_parse_kib(self):
        rx, tx = MonitoringService._parse_transfer("512.0 KiB received, 256.0 KiB sent")
        assert rx == 512 * 1024
        assert tx == 256 * 1024

    def test_parse_bytes(self):
        rx, tx = MonitoringService._parse_transfer("100 B received, 200 B sent")
        assert rx == 100
        assert tx == 200

    def test_parse_empty(self):
        rx, tx = MonitoringService._parse_transfer("")
        assert rx == 0
        assert tx == 0


class TestParseHandshakeTime:
    def test_seconds_ago(self):
        result = MonitoringService._parse_handshake_time("30 seconds ago")
        assert result is not None

    def test_minutes_ago(self):
        result = MonitoringService._parse_handshake_time("2 minutes, 15 seconds ago")
        assert result is not None

    def test_hours_ago(self):
        result = MonitoringService._parse_handshake_time("1 hour, 5 minutes, 10 seconds ago")
        assert result is not None

    def test_never(self):
        result = MonitoringService._parse_handshake_time("never")
        assert result is None

    def test_empty(self):
        result = MonitoringService._parse_handshake_time("")
        assert result is None


class TestFormatBytes:
    def test_bytes(self):
        assert "100.0 B" == MonitoringService.format_bytes(100)

    def test_kib(self):
        result = MonitoringService.format_bytes(2048)
        assert "KiB" in result

    def test_mib(self):
        result = MonitoringService.format_bytes(5 * 1048576)
        assert "MiB" in result

    def test_gib(self):
        result = MonitoringService.format_bytes(2 * 1073741824)
        assert "GiB" in result

    def test_zero(self):
        assert "0.0 B" == MonitoringService.format_bytes(0)
