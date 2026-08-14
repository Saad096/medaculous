import uuid
from datetime import datetime, timedelta, timezone

from pydantic import BaseModel, EmailStr, Field, computed_field

from app.core.config import settings


class RegisterRequest(BaseModel):
    email: EmailStr
    password: str = Field(min_length=8, max_length=128)
    display_name: str | None = None


class LoginRequest(BaseModel):
    email: EmailStr
    password: str


class OTPVerifyRequest(BaseModel):
    email: EmailStr
    code: str = Field(min_length=4, max_length=8)


class OTPResendRequest(BaseModel):
    email: EmailStr


class ForgotPasswordRequest(BaseModel):
    email: EmailStr


class ResetPasswordRequest(BaseModel):
    email: EmailStr
    code: str
    new_password: str = Field(min_length=8, max_length=128)


class RefreshRequest(BaseModel):
    refresh_token: str


class LogoutRequest(BaseModel):
    refresh_token: str


class GoogleSignInRequest(BaseModel):
    id_token: str


class AppleSignInRequest(BaseModel):
    identity_token: str
    # Apple only sends the user's name on the very first authorization; the client
    # must capture and forward it that one time since it can't be recovered later.
    full_name: str | None = None


class TokenPair(BaseModel):
    access_token: str
    refresh_token: str
    token_type: str = "bearer"


class UserOut(BaseModel):
    id: uuid.UUID
    email: EmailStr
    display_name: str | None
    is_verified: bool
    is_admin: bool
    subscription_tier: str
    ai_messages_used: int
    ai_monthly_limit: int | None = Field(default=None, exclude=True)
    created_at: datetime
    google_sub: str | None = Field(default=None, exclude=True)
    apple_sub: str | None = Field(default=None, exclude=True)
    avatar_path: str | None = Field(default=None, exclude=True)

    model_config = {"from_attributes": True}

    @computed_field
    @property
    def sign_in_method(self) -> str:
        if self.google_sub:
            return "google"
        if self.apple_sub:
            return "apple"
        return "email"

    @computed_field
    @property
    def has_avatar(self) -> bool:
        return self.avatar_path is not None

    # Trial scaffolding (see OPEN_QUESTIONS.md + config.TRIAL_DURATION_DAYS) —
    # computed from created_at rather than a stored column, since "trial starts
    # at signup" needs no extra state. Not enforced server-side yet; the client
    # can use this to show trial status without the backend blocking access.
    @computed_field
    @property
    def trial_expires_at(self) -> datetime:
        return self.created_at + timedelta(days=settings.TRIAL_DURATION_DAYS)

    @computed_field
    @property
    def is_trial_active(self) -> bool:
        return datetime.now(timezone.utc) < self.trial_expires_at

    @computed_field
    @property
    def ai_usage_limit(self) -> int:
        return self.ai_monthly_limit if self.ai_monthly_limit is not None else settings.AI_USAGE_LIMIT_DEFAULT
