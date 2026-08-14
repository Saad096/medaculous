import uuid
from datetime import datetime

from sqlalchemy import Boolean, DateTime, Integer, String, func
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import Mapped, mapped_column

from app.db.base import Base


class User(Base):
    __tablename__ = "users"

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    email: Mapped[str] = mapped_column(String(255), unique=True, index=True, nullable=False)
    hashed_password: Mapped[str | None] = mapped_column(String(255), nullable=True)
    display_name: Mapped[str | None] = mapped_column(String(255), nullable=True)

    is_verified: Mapped[bool] = mapped_column(Boolean, default=False, nullable=False)
    is_active: Mapped[bool] = mapped_column(Boolean, default=True, nullable=False)

    # Set when the account was created/linked via that provider. A user can have
    # a password AND an oauth sub if they later link a second sign-in method to
    # the same email (see OPEN_QUESTIONS.md re: account-linking UX).
    google_sub: Mapped[str | None] = mapped_column(String(255), unique=True, nullable=True)
    apple_sub: Mapped[str | None] = mapped_column(String(255), unique=True, nullable=True)

    # Relative path under AVATAR_STORAGE_DIR (e.g. "<user_id>.jpg"), not a public URL —
    # served through the authenticated GET /auth/me/avatar endpoint, same ownership-gated
    # pattern as Knowledge Hub PDFs, so a profile photo never becomes a guessable public
    # file. Null means "no avatar uploaded, show initials instead" (see UserOut.has_avatar).
    avatar_path: Mapped[str | None] = mapped_column(String(255), nullable=True)

    # talk2saadalam@gmail.com is seeded as admin on migration (owner request,
    # 2026-08-14) — grants access to /admin/* (usage dashboard, per-user AI
    # limits, account deletion) and exempts the account from AI usage limits.
    is_admin: Mapped[bool] = mapped_column(Boolean, default=False, nullable=False)

    # Per-user override for the AI message quota (see settings.AI_USAGE_LIMIT_DEFAULT
    # and api.deps.enforce_ai_usage_limit). Null means "use the plan default", so an
    # admin only needs to write a row when actually overriding someone.
    ai_monthly_limit: Mapped[int | None] = mapped_column(Integer, nullable=True)
    ai_messages_used: Mapped[int] = mapped_column(Integer, default=0, nullable=False)
    # Rolling window start for ai_messages_used — reset lazily (on the next AI
    # request after 30 days have elapsed) rather than via a cron job.
    usage_period_start: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), nullable=False
    )

    # Cosmetic until a real payment processor is wired up (see PaywallScreen /
    # CheckoutScreen "coming soon" step + OPEN_QUESTIONS.md) — lets the UI show
    # "Pro (Annual)" etc. once a plan is nominally selected, and gives the admin
    # dashboard something real to filter/report on.
    subscription_tier: Mapped[str] = mapped_column(String(20), default="trial", nullable=False)

    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), onupdate=func.now()
    )
