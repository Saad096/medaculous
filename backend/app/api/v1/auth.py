import uuid
from datetime import datetime, timedelta, timezone
from pathlib import Path

import jwt
from fastapi import APIRouter, Depends, HTTPException, Request, UploadFile, status
from fastapi.responses import FileResponse
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.deps import get_current_user
from app.core.config import settings
from app.core.security import (
    create_token,
    decode_token,
    hash_opaque_token,
    hash_password,
    verify_password,
)
from app.db.session import get_db
from app.models.audit_log import AuditLog
from app.models.otp import OTPPurpose
from app.models.refresh_token import RefreshToken
from app.models.user import User
from app.schemas.auth import (
    AppleSignInRequest,
    ForgotPasswordRequest,
    GoogleSignInRequest,
    LoginRequest,
    LogoutRequest,
    OTPResendRequest,
    OTPVerifyRequest,
    RefreshRequest,
    RegisterRequest,
    ResetPasswordRequest,
    TokenPair,
    UserOut,
)
from app.services.apple_oauth import verify_apple_identity_token
from app.services.google_oauth import verify_google_id_token
from app.services.otp_service import request_otp, verify_otp

router = APIRouter(prefix="/auth", tags=["auth"])


async def _log(db: AsyncSession, *, user_id: uuid.UUID | None, event: str, ip: str | None) -> None:
    db.add(AuditLog(user_id=user_id, event_type=event, ip_address=ip))
    await db.commit()


async def _issue_token_pair(db: AsyncSession, user: User, *, request: Request, family_id: uuid.UUID | None = None) -> TokenPair:
    """A fresh login starts a new session family; a refresh reuses the caller's family_id."""
    family_id = family_id or uuid.uuid4()
    access = create_token(str(user.id), "access")
    refresh = create_token(str(user.id), "refresh", extra_claims={"family": str(family_id)})

    refresh_payload = decode_token(refresh, "refresh")
    db.add(
        RefreshToken(
            user_id=user.id,
            family_id=family_id,
            token_hash=hash_opaque_token(refresh),
            user_agent=request.headers.get("user-agent"),
            ip_address=request.client.host if request.client else None,
            expires_at=datetime.fromtimestamp(refresh_payload["exp"], tz=timezone.utc),
        )
    )
    await db.commit()
    return TokenPair(access_token=access, refresh_token=refresh)


@router.post("/register", response_model=UserOut, status_code=status.HTTP_201_CREATED)
async def register(payload: RegisterRequest, request: Request, db: AsyncSession = Depends(get_db)) -> User:
    existing = await db.scalar(select(User).where(User.email == payload.email))
    if existing is not None:
        # Same response whether the account exists verified or not — don't leak account existence.
        raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail="An account with this email already exists.")

    user = User(email=payload.email, hashed_password=hash_password(payload.password), display_name=payload.display_name)
    db.add(user)
    await db.commit()
    await db.refresh(user)

    await request_otp(
        db, email=user.email, purpose=OTPPurpose.EMAIL_VERIFICATION, request_ip=request.client.host if request.client else None
    )
    await _log(db, user_id=user.id, event="register", ip=request.client.host if request.client else None)
    return user


@router.post("/verify-email", response_model=TokenPair)
async def verify_email(payload: OTPVerifyRequest, request: Request, db: AsyncSession = Depends(get_db)) -> TokenPair:
    await verify_otp(db, email=payload.email, purpose=OTPPurpose.EMAIL_VERIFICATION, code=payload.code)

    user = await db.scalar(select(User).where(User.email == payload.email))
    if user is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="User not found.")

    user.is_verified = True
    await db.commit()
    await _log(db, user_id=user.id, event="email_verified", ip=request.client.host if request.client else None)
    return await _issue_token_pair(db, user, request=request)


@router.post("/resend-otp", status_code=status.HTTP_204_NO_CONTENT)
async def resend_otp(payload: OTPResendRequest, request: Request, db: AsyncSession = Depends(get_db)) -> None:
    # Same no-enumeration pattern as forgot-password: always 204, but only actually
    # send when there's a real, still-unverified account behind the email — otherwise
    # this endpoint would happily email-bomb arbitrary addresses or re-verify
    # accounts that are already verified.
    user = await db.scalar(select(User).where(User.email == payload.email))
    if user is not None and not user.is_verified:
        await request_otp(
            db,
            email=payload.email,
            purpose=OTPPurpose.EMAIL_VERIFICATION,
            request_ip=request.client.host if request.client else None,
        )


@router.post("/login", response_model=TokenPair)
async def login(payload: LoginRequest, request: Request, db: AsyncSession = Depends(get_db)) -> TokenPair:
    ip = request.client.host if request.client else None
    user = await db.scalar(select(User).where(User.email == payload.email))

    # Lockout check happens before password verification so a locked-out attacker
    # can't keep guessing right up to the exact moment the window resets, and so
    # the response is identical (429) regardless of whether the password would
    # have been correct.
    window_start = datetime.now(timezone.utc) - timedelta(minutes=settings.LOGIN_LOCKOUT_WINDOW_MINUTES)
    if user is not None:
        recent_failures = await db.scalar(
            select(func.count()).select_from(AuditLog).where(
                AuditLog.user_id == user.id,
                AuditLog.event_type == "login_failed",
                AuditLog.created_at >= window_start,
            )
        )
        if recent_failures >= settings.LOGIN_MAX_FAILED_ATTEMPTS:
            raise HTTPException(
                status_code=status.HTTP_429_TOO_MANY_REQUESTS,
                detail="Too many failed login attempts. Please try again later or reset your password.",
            )

    if user is None or user.hashed_password is None or not verify_password(payload.password, user.hashed_password):
        await _log(db, user_id=user.id if user else None, event="login_failed", ip=ip)
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Incorrect email or password.")

    if not user.is_active:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Account is disabled.")

    if not user.is_verified:
        # Correct credentials, but the account never completed OTP verification —
        # distinct machine-readable code so the client can route straight to the
        # verify-email screen instead of showing a generic auth error.
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail={"code": "email_not_verified", "message": "Please verify your email before signing in."},
        )

    await _log(db, user_id=user.id, event="login_success", ip=ip)
    return await _issue_token_pair(db, user, request=request)


@router.post("/refresh", response_model=TokenPair)
async def refresh_token(payload: RefreshRequest, request: Request, db: AsyncSession = Depends(get_db)) -> TokenPair:
    try:
        claims = decode_token(payload.refresh_token, "refresh")
    except jwt.PyJWTError:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid refresh token.") from None

    token_hash = hash_opaque_token(payload.refresh_token)
    stored = await db.scalar(select(RefreshToken).where(RefreshToken.token_hash == token_hash))

    if stored is None:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid refresh token.")

    if stored.revoked:
        # Reuse of an already-rotated-away token: treat as a stolen token and kill the
        # whole session family, not just this one token.
        await db.execute(
            RefreshToken.__table__.update()
            .where(RefreshToken.family_id == stored.family_id, RefreshToken.revoked.is_(False))
            .values(revoked=True, revoked_at=datetime.now(timezone.utc))
        )
        await db.commit()
        await _log(db, user_id=stored.user_id, event="refresh_reuse_detected", ip=request.client.host if request.client else None)
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Session invalidated. Please log in again.")

    user = await db.get(User, uuid.UUID(claims["sub"]))
    if user is None or not user.is_active:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid refresh token.")

    stored.revoked = True
    stored.revoked_at = datetime.now(timezone.utc)
    new_pair = await _issue_token_pair(db, user, request=request, family_id=stored.family_id)

    new_token_hash = hash_opaque_token(new_pair.refresh_token)
    new_row = await db.scalar(select(RefreshToken).where(RefreshToken.token_hash == new_token_hash))
    stored.replaced_by_id = new_row.id if new_row else None
    await db.commit()

    return new_pair


@router.post("/logout", status_code=status.HTTP_204_NO_CONTENT)
async def logout(payload: LogoutRequest, db: AsyncSession = Depends(get_db)) -> None:
    token_hash = hash_opaque_token(payload.refresh_token)
    stored = await db.scalar(select(RefreshToken).where(RefreshToken.token_hash == token_hash))
    if stored is not None and not stored.revoked:
        stored.revoked = True
        stored.revoked_at = datetime.now(timezone.utc)
        await db.commit()
    # Idempotent by design: logging out an already-invalid token is a no-op, not an error —
    # the client's goal (no valid session left) is already satisfied either way.


@router.post("/forgot-password", status_code=status.HTTP_204_NO_CONTENT)
async def forgot_password(payload: ForgotPasswordRequest, request: Request, db: AsyncSession = Depends(get_db)) -> None:
    user = await db.scalar(select(User).where(User.email == payload.email))
    if user is not None:
        await request_otp(
            db,
            email=payload.email,
            purpose=OTPPurpose.PASSWORD_RESET,
            request_ip=request.client.host if request.client else None,
        )
    # Always 204 regardless of whether the account exists — don't leak account existence.


@router.post("/reset-password", status_code=status.HTTP_204_NO_CONTENT)
async def reset_password(payload: ResetPasswordRequest, request: Request, db: AsyncSession = Depends(get_db)) -> None:
    await verify_otp(db, email=payload.email, purpose=OTPPurpose.PASSWORD_RESET, code=payload.code)

    user = await db.scalar(select(User).where(User.email == payload.email))
    if user is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="User not found.")

    user.hashed_password = hash_password(payload.new_password)

    # Password change invalidates every other active session.
    await db.execute(
        RefreshToken.__table__.update()
        .where(RefreshToken.user_id == user.id, RefreshToken.revoked.is_(False))
        .values(revoked=True, revoked_at=datetime.now(timezone.utc))
    )
    await db.commit()
    await _log(db, user_id=user.id, event="password_reset", ip=request.client.host if request.client else None)


async def _find_or_link_oauth_user(db: AsyncSession, *, email: str, provider_field: str, sub: str) -> User:
    """
    Links by verified email if an account already exists (e.g. user signed up with
    email/password, then taps "Continue with Google" using the same address) — see
    OPEN_QUESTIONS.md for confirming this is the intended account-linking behavior.
    """
    user = await db.scalar(select(User).where(getattr(User, provider_field) == sub))
    if user is not None:
        return user

    user = await db.scalar(select(User).where(User.email == email))
    if user is not None:
        setattr(user, provider_field, sub)
        await db.commit()
        return user

    user = User(email=email, is_verified=True)
    setattr(user, provider_field, sub)
    db.add(user)
    await db.commit()
    await db.refresh(user)
    return user


@router.post("/google", response_model=TokenPair)
async def google_sign_in(payload: GoogleSignInRequest, request: Request, db: AsyncSession = Depends(get_db)) -> TokenPair:
    profile = verify_google_id_token(payload.id_token)
    if not profile.email_verified:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Google account email is not verified.")

    user = await _find_or_link_oauth_user(db, email=profile.email, provider_field="google_sub", sub=profile.sub)
    await _log(db, user_id=user.id, event="login_google", ip=request.client.host if request.client else None)
    return await _issue_token_pair(db, user, request=request)


@router.post("/apple", response_model=TokenPair)
async def apple_sign_in(payload: AppleSignInRequest, request: Request, db: AsyncSession = Depends(get_db)) -> TokenPair:
    profile = verify_apple_identity_token(payload.identity_token)

    # First-login-only email: if Apple didn't send one (subsequent logins), fall back
    # to whatever we already have on file for this apple_sub.
    existing = await db.scalar(select(User).where(User.apple_sub == profile.sub))
    email = profile.email or (existing.email if existing else None)
    if email is None:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="No email available for this Apple account.")

    user = await _find_or_link_oauth_user(db, email=email, provider_field="apple_sub", sub=profile.sub)
    if payload.full_name and not user.display_name:
        user.display_name = payload.full_name
        await db.commit()

    await _log(db, user_id=user.id, event="login_apple", ip=request.client.host if request.client else None)
    return await _issue_token_pair(db, user, request=request)


@router.get("/me", response_model=UserOut)
async def read_current_user(current_user: User = Depends(get_current_user)) -> User:
    return current_user


def _avatar_path(user_id: uuid.UUID) -> Path:
    root = Path(settings.AVATAR_STORAGE_DIR)
    root.mkdir(parents=True, exist_ok=True)
    return root / f"{user_id}.jpg"


@router.put("/me/avatar", response_model=UserOut)
async def upload_avatar(
    file: UploadFile,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> User:
    if not (file.content_type or "").startswith("image/"):
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Only image files are supported.")
    content = await file.read()
    max_bytes = settings.AVATAR_MAX_UPLOAD_MB * 1024 * 1024
    if len(content) > max_bytes:
        raise HTTPException(
            status_code=status.HTTP_413_REQUEST_ENTITY_TOO_LARGE,
            detail=f"Image exceeds the {settings.AVATAR_MAX_UPLOAD_MB}MB upload limit.",
        )
    # Always the same fixed filename per user (re-upload overwrites) — the frontend
    # cache-busts with a query param on the request URL since the path never changes.
    _avatar_path(user.id).write_bytes(content)
    user.avatar_path = f"{user.id}.jpg"
    await db.commit()
    await db.refresh(user)
    return user


@router.get("/me/avatar")
async def get_avatar(user: User = Depends(get_current_user)) -> FileResponse:
    if not user.avatar_path:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="No avatar uploaded.")
    path = _avatar_path(user.id)
    if not path.exists():
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Avatar file missing from storage.")
    return FileResponse(path, media_type="image/jpeg")


@router.delete("/me/avatar", response_model=UserOut, status_code=status.HTTP_200_OK)
async def delete_avatar(user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)) -> User:
    path = _avatar_path(user.id)
    if path.exists():
        path.unlink()
    user.avatar_path = None
    await db.commit()
    await db.refresh(user)
    return user


if settings.TEST_MODE_OTP_BACKDOOR:
    # Registered only when the flag is on — this route does not exist in any build
    # where TEST_MODE_OTP_BACKDOOR isn't explicitly set, not even as a 403. See
    # services/otp_service.py for the in-memory store this reads from.
    from app.services.otp_service import get_test_otp

    @router.get("/_test/last-otp")
    async def get_last_otp_for_testing(email: str, purpose: OTPPurpose = OTPPurpose.EMAIL_VERIFICATION) -> dict:
        code = get_test_otp(email, purpose)
        if code is None:
            raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="No OTP on record for this email/purpose.")
        return {"code": code}
