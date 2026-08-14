import hmac
from datetime import datetime, timedelta, timezone

from fastapi import HTTPException, status
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import settings
from app.core.security import generate_otp_code, hash_otp_code
from app.models.otp import OTPCode, OTPPurpose
from app.services.email import send_otp_email

# In-memory only, never persisted or hashed — exists purely so Patrol/E2E automation
# can retrieve a real code without IMAP access to a real inbox. Only populated when
# TEST_MODE_OTP_BACKDOOR is explicitly enabled (see api/v1/auth.py — the retrieval
# route itself doesn't exist unless the flag is on), which must never be true in any
# environment a real user's data passes through.
_test_otp_store: dict[tuple[str, OTPPurpose], str] = {}


def get_test_otp(email: str, purpose: OTPPurpose) -> str | None:
    return _test_otp_store.get((email, purpose))


async def request_otp(db: AsyncSession, *, email: str, purpose: OTPPurpose, request_ip: str | None) -> None:
    """
    Generates and (dev: logs / prod: emails) a new OTP for `email`, enforcing:
    - resend cooldown (last code for this email+purpose must be older than the cooldown)
    - per-email and per-IP hourly request caps (independent limits — see security_spec
      carried over from the legacy app's threat model)
    """
    now = datetime.now(timezone.utc)
    one_hour_ago = now - timedelta(hours=1)

    last_code = await db.scalar(
        select(OTPCode)
        .where(OTPCode.email == email, OTPCode.purpose == purpose)
        .order_by(OTPCode.created_at.desc())
        .limit(1)
    )
    if last_code and (now - last_code.created_at) < timedelta(seconds=settings.OTP_RESEND_COOLDOWN_SECONDS):
        retry_after = settings.OTP_RESEND_COOLDOWN_SECONDS - int((now - last_code.created_at).total_seconds())
        raise HTTPException(
            status_code=status.HTTP_429_TOO_MANY_REQUESTS,
            detail=f"Please wait {retry_after}s before requesting another code.",
        )

    email_count = await db.scalar(
        select(func.count()).select_from(OTPCode).where(
            OTPCode.email == email, OTPCode.purpose == purpose, OTPCode.created_at >= one_hour_ago
        )
    )
    if email_count >= settings.OTP_MAX_REQUESTS_PER_EMAIL_PER_HOUR:
        raise HTTPException(status_code=status.HTTP_429_TOO_MANY_REQUESTS, detail="Too many codes requested. Try again later.")

    if request_ip:
        ip_count = await db.scalar(
            select(func.count()).select_from(OTPCode).where(
                OTPCode.request_ip == request_ip, OTPCode.created_at >= one_hour_ago
            )
        )
        if ip_count >= settings.OTP_MAX_REQUESTS_PER_IP_PER_HOUR:
            raise HTTPException(status_code=status.HTTP_429_TOO_MANY_REQUESTS, detail="Too many requests from this network. Try again later.")

    code = generate_otp_code(settings.OTP_LENGTH)
    otp = OTPCode(
        email=email,
        purpose=purpose,
        code_hash=hash_otp_code(code),
        request_ip=request_ip,
        expires_at=now + timedelta(minutes=settings.OTP_TTL_MINUTES),
    )
    db.add(otp)
    await db.commit()

    if settings.TEST_MODE_OTP_BACKDOOR:
        _test_otp_store[(email, purpose)] = code

    send_otp_email(email, code, purpose.value)


async def verify_otp(db: AsyncSession, *, email: str, purpose: OTPPurpose, code: str) -> bool:
    """Consumes the most recent unconsumed OTP for email+purpose if `code` matches and it hasn't expired."""
    now = datetime.now(timezone.utc)

    otp = await db.scalar(
        select(OTPCode)
        .where(OTPCode.email == email, OTPCode.purpose == purpose, OTPCode.consumed_at.is_(None))
        .order_by(OTPCode.created_at.desc())
        .limit(1)
    )
    if otp is None:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="No pending verification code. Request a new one.")

    if otp.expires_at < now:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Code expired. Request a new one.")

    if otp.attempts >= settings.OTP_MAX_ATTEMPTS_PER_CODE:
        raise HTTPException(status_code=status.HTTP_429_TOO_MANY_REQUESTS, detail="Too many incorrect attempts. Request a new code.")

    if not hmac.compare_digest(hash_otp_code(code), otp.code_hash):
        otp.attempts += 1
        await db.commit()
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Incorrect code.")

    otp.consumed_at = now
    await db.commit()
    return True
