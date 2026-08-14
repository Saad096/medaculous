import hashlib
import secrets
from datetime import datetime, timedelta, timezone
from typing import Any, Literal

import jwt
from passlib.context import CryptContext

from app.core.config import settings

pwd_context = CryptContext(schemes=["bcrypt"], deprecated="auto")

TokenType = Literal["access", "refresh"]


def hash_password(password: str) -> str:
    return pwd_context.hash(password)


def verify_password(password: str, password_hash: str) -> bool:
    return pwd_context.verify(password, password_hash)


def _secret_for(token_type: TokenType) -> str:
    return settings.JWT_SECRET if token_type == "access" else settings.JWT_REFRESH_SECRET


def create_token(subject: str, token_type: TokenType, extra_claims: dict[str, Any] | None = None) -> str:
    now = datetime.now(timezone.utc)
    if token_type == "access":
        expires_at = now + timedelta(minutes=settings.ACCESS_TOKEN_EXPIRE_MINUTES)
    else:
        expires_at = now + timedelta(days=settings.REFRESH_TOKEN_EXPIRE_DAYS)

    payload: dict[str, Any] = {
        "sub": subject,
        "type": token_type,
        "iat": now,
        "exp": expires_at,
        "jti": secrets.token_urlsafe(16),
    }
    if extra_claims:
        payload.update(extra_claims)

    return jwt.encode(payload, _secret_for(token_type), algorithm=settings.JWT_ALGORITHM)


def decode_token(token: str, token_type: TokenType) -> dict[str, Any]:
    payload = jwt.decode(token, _secret_for(token_type), algorithms=[settings.JWT_ALGORITHM])
    if payload.get("type") != token_type:
        raise jwt.InvalidTokenError("Unexpected token type")
    return payload


def hash_opaque_token(token: str) -> str:
    """Refresh tokens are stored hashed so a leaked DB doesn't equal valid sessions."""
    return hashlib.sha256(token.encode("utf-8")).hexdigest()


def generate_otp_code(length: int) -> str:
    return "".join(secrets.choice("0123456789") for _ in range(length))


def hash_otp_code(code: str) -> str:
    return hashlib.sha256(code.encode("utf-8")).hexdigest()
