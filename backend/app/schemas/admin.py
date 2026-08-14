import uuid
from datetime import datetime

from pydantic import BaseModel, EmailStr


class AdminUserOut(BaseModel):
    id: uuid.UUID
    email: EmailStr
    display_name: str | None
    is_verified: bool
    is_active: bool
    is_admin: bool
    subscription_tier: str
    ai_messages_used: int
    ai_monthly_limit: int | None
    ai_usage_limit: int
    created_at: datetime

    model_config = {"from_attributes": True}


class AdminUserListResponse(BaseModel):
    users: list[AdminUserOut]
    total: int
    page: int
    page_size: int


class SetUsageLimitRequest(BaseModel):
    # Null clears the override so the user falls back to the plan default.
    ai_monthly_limit: int | None = None


class AdminStatsResponse(BaseModel):
    total_users: int
    verified_users: int
    active_trial_users: int
    admin_users: int
    total_ai_messages_used: int
    signups_last_14_days: list["DailyCount"]
    top_ai_users: list[AdminUserOut]


class DailyCount(BaseModel):
    date: str
    count: int


AdminStatsResponse.model_rebuild()
