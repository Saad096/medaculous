from datetime import datetime, timedelta, timezone

import jwt
import pytest

from app.core.config import settings
from app.core.security import (
    create_token,
    decode_token,
    generate_otp_code,
    hash_opaque_token,
    hash_otp_code,
    hash_password,
    verify_password,
)


def test_password_hash_roundtrip():
    hashed = hash_password("correct horse battery staple")
    assert verify_password("correct horse battery staple", hashed)
    assert not verify_password("wrong password", hashed)


def test_password_hash_is_salted():
    # Two hashes of the same password must differ (bcrypt salt) — otherwise a leaked
    # DB lets an attacker spot repeated passwords across accounts.
    assert hash_password("same-password") != hash_password("same-password")


def test_access_and_refresh_tokens_use_different_secrets():
    access = create_token("user-1", "access")
    refresh = create_token("user-1", "refresh")

    assert decode_token(access, "access")["sub"] == "user-1"
    assert decode_token(refresh, "refresh")["sub"] == "user-1"

    # An access token must never be usable as a refresh token and vice versa.
    with pytest.raises(jwt.PyJWTError):
        decode_token(access, "refresh")
    with pytest.raises(jwt.PyJWTError):
        decode_token(refresh, "access")


def test_expired_access_token_is_rejected():
    now = datetime.now(timezone.utc)
    expired_payload = {
        "sub": "user-1",
        "type": "access",
        "iat": now - timedelta(minutes=20),
        "exp": now - timedelta(minutes=5),
    }
    expired_token = jwt.encode(expired_payload, settings.JWT_SECRET, algorithm=settings.JWT_ALGORITHM)

    with pytest.raises(jwt.ExpiredSignatureError):
        decode_token(expired_token, "access")


def test_refresh_token_hash_is_deterministic_and_one_way():
    token = create_token("user-1", "refresh")
    assert hash_opaque_token(token) == hash_opaque_token(token)
    assert hash_opaque_token(token) != token


def test_otp_code_is_numeric_and_correct_length():
    code = generate_otp_code(6)
    assert len(code) == 6
    assert code.isdigit()


def test_otp_hash_matches_only_the_original_code():
    code = generate_otp_code(6)
    hashed = hash_otp_code(code)
    assert hash_otp_code(code) == hashed
    assert hash_otp_code("000000" if code != "000000" else "111111") != hashed
