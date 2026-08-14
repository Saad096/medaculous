import uuid
from datetime import datetime, timedelta, timezone

import jwt
from fastapi import Depends, HTTPException, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import settings
from app.core.security import decode_token
from app.db.session import get_db
from app.models.user import User

bearer_scheme = HTTPBearer(auto_error=False)


async def get_current_user(
    credentials: HTTPAuthorizationCredentials | None = Depends(bearer_scheme),
    db: AsyncSession = Depends(get_db),
) -> User:
    unauthorized = HTTPException(
        status_code=status.HTTP_401_UNAUTHORIZED,
        detail="Could not validate credentials",
        headers={"WWW-Authenticate": "Bearer"},
    )
    if credentials is None:
        raise unauthorized

    try:
        payload = decode_token(credentials.credentials, "access")
    except jwt.ExpiredSignatureError:
        # Distinct from a bad token: the client should silently refresh and retry,
        # not force a full re-login.
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Token expired") from None
    except jwt.PyJWTError:
        raise unauthorized from None

    user = await db.get(User, uuid.UUID(payload["sub"]))
    if user is None or not user.is_active:
        raise unauthorized
    return user


async def require_admin(user: User = Depends(get_current_user)) -> User:
    if not user.is_admin:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Admin access required.")
    return user


_USAGE_RESET_PERIOD = timedelta(days=30)


async def enforce_ai_usage_limit(
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> User:
    """Drop-in replacement for get_current_user on any endpoint that calls the
    LLM — counts the request against the user's rolling 30-day quota and 429s
    once it's exhausted. Admin accounts are exempt. Reset happens lazily here
    rather than via a cron job, since the only thing that matters is the count
    being right the next time this user actually makes a request."""
    if user.is_admin:
        return user

    now = datetime.now(timezone.utc)
    period_start = user.usage_period_start
    if period_start.tzinfo is None:
        period_start = period_start.replace(tzinfo=timezone.utc)
    if now - period_start >= _USAGE_RESET_PERIOD:
        user.ai_messages_used = 0
        user.usage_period_start = now

    limit = user.ai_monthly_limit if user.ai_monthly_limit is not None else settings.AI_USAGE_LIMIT_DEFAULT
    if user.ai_messages_used >= limit:
        await db.commit()
        raise HTTPException(
            status_code=status.HTTP_429_TOO_MANY_REQUESTS,
            detail="ai_usage_limit_reached",
        )

    user.ai_messages_used += 1
    await db.commit()
    await db.refresh(user)
    return user
