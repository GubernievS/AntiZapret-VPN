"""
Tests for security module (JWT, passwords)
"""
from app.core.security import (
    get_password_hash,
    verify_password,
    create_access_token,
    create_refresh_token,
    decode_token,
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
