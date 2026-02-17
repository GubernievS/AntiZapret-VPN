"""
Tests for VPN Manager (validation logic, not subprocess calls)
"""
import pytest
from app.services.vpn_manager import VPNManager, VPNManagerError, generate_client_name, CLIENT_NAME_PATTERN


class TestClientNameValidation:
    def setup_method(self):
        self.mgr = VPNManager()

    def test_valid_names(self):
        # Should not raise
        self.mgr._validate_client_name("user-1")
        self.mgr._validate_client_name("john.doe-2")
        self.mgr._validate_client_name("test_user")
        self.mgr._validate_client_name("Admin123")

    def test_invalid_special_chars(self):
        for bad_name in ["user;rm", "user|cat", "user&bg", "user$(cmd)", "user`cmd`"]:
            with pytest.raises(VPNManagerError):
                self.mgr._validate_client_name(bad_name)

    def test_empty_name(self):
        with pytest.raises(VPNManagerError):
            self.mgr._validate_client_name("")

    def test_too_long_name(self):
        with pytest.raises(VPNManagerError):
            self.mgr._validate_client_name("a" * 33)

    def test_name_pattern_no_spaces(self):
        assert CLIENT_NAME_PATTERN.match("user name") is None


class TestGenerateClientName:
    def test_first_config(self):
        name = generate_client_name("testuser", [])
        assert name == "testuser-1"

    def test_second_config(self):
        name = generate_client_name("testuser", ["testuser-1"])
        assert name == "testuser-2"

    def test_gap_in_numbering(self):
        name = generate_client_name("user", ["user-1", "user-3"])
        assert name == "user-4"

    def test_email_username(self):
        name = generate_client_name("john@company.com", [])
        assert name == "john-1"

    def test_no_matching_existing(self):
        name = generate_client_name("alice", ["bob-1", "charlie-2"])
        assert name == "alice-1"


class TestGetConfigFilePath:
    def setup_method(self):
        self.mgr = VPNManager()

    def test_antizapret_returns_none_for_missing_file(self):
        result = self.mgr.get_config_file_path("user-1", "awg_antizapret")
        assert result is None  # File doesn't exist in test env

    def test_vpn_returns_none_for_missing_file(self):
        result = self.mgr.get_config_file_path("user-1", "awg_vpn")
        assert result is None

    def test_invalid_type_returns_none(self):
        result = self.mgr.get_config_file_path("user-1", "invalid_type")
        assert result is None
