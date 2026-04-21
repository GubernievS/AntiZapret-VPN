"""
Tests for security module (JWT, passwords)
"""
from app.core.security import (
    get_password_hash,
    verify_password,
    create_access_token,
    create_refresh_token,
    decode_token,
    create_config_share_token,
    verify_config_share_token,
)


class TestPasswordHashing:
    def test_hash_and_verify(self):
        password = "mysecretpassword"
        hashed = get_password_hash(password)
        assert hashed != password
        assert verify_password(password, hashed) is True

    def test_wrong_password(self):
        hashed = get_password_hash("correct")
        assert verify_password("wrong", hashed) is False

    def test_different_hashes(self):
        h1 = get_password_hash("same")
        h2 = get_password_hash("same")
        # Bcrypt generates different salts
        assert h1 != h2
        # But both verify
        assert verify_password("same", h1)
        assert verify_password("same", h2)


class TestJWT:
    def test_create_and_decode_access_token(self):
        token = create_access_token(data={"sub": "user-123", "role": "admin"})
        payload = decode_token(token)
        assert payload is not None
        assert payload["sub"] == "user-123"
        assert payload["role"] == "admin"
        assert payload["type"] == "access"

    def test_create_and_decode_refresh_token(self):
        token = create_refresh_token(data={"sub": "user-456"})
        payload = decode_token(token)
        assert payload is not None
        assert payload["sub"] == "user-456"
        assert payload["type"] == "refresh"

    def test_invalid_token(self):
        payload = decode_token("invalid.token.here")
        assert payload is None

    def test_access_token_has_expiry(self):
        token = create_access_token(data={"sub": "user-1"})
        payload = decode_token(token)
        assert "exp" in payload

    def test_refresh_token_has_expiry(self):
        token = create_refresh_token(data={"sub": "user-1"})
        payload = decode_token(token)
        assert "exp" in payload


class TestConfigShareToken:
    """Share token used for QR code download-links — must carry bypass/backup flags."""

    def test_verify_returns_dict_with_config_id(self):
        token = create_config_share_token("cfg-123")
        result = verify_config_share_token(token)
        assert result is not None
        assert result["config_id"] == "cfg-123"
        assert result["bypass"] is False
        assert result["backup"] is False

    def test_token_encodes_bypass_flag(self):
        token = create_config_share_token("cfg-42", bypass=True)
        result = verify_config_share_token(token)
        assert result["config_id"] == "cfg-42"
        assert result["bypass"] is True
        assert result["backup"] is False

    def test_token_encodes_backup_flag(self):
        token = create_config_share_token("cfg-43", backup=True)
        result = verify_config_share_token(token)
        assert result["config_id"] == "cfg-43"
        assert result["bypass"] is False
        assert result["backup"] is True

    def test_invalid_token_returns_none(self):
        assert verify_config_share_token("not-a-jwt") is None

    def test_legacy_token_without_flags_defaults_both_false(self):
        """Tokens minted before the flags existed (just `sub` + `type`)
        must still verify — defaulting bypass/backup to False."""
        from jose import jwt
        from datetime import datetime, timedelta
        from app.config import settings
        legacy = jwt.encode(
            {
                "sub": "cfg-legacy",
                "type": "config_share",
                "exp": datetime.utcnow() + timedelta(minutes=5),
            },
            settings.SECRET_KEY,
            algorithm=settings.JWT_ALGORITHM,
        )
        result = verify_config_share_token(legacy)
        assert result is not None
        assert result["config_id"] == "cfg-legacy"
        assert result["bypass"] is False
        assert result["backup"] is False
