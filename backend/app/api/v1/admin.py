import uuid
from datetime import datetime, timedelta, timezone

from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.deps import require_admin
from app.core.config import settings
from app.db.session import get_db
from app.models.user import User
from app.schemas.admin import (
    AdminStatsResponse,
    AdminUserListResponse,
    AdminUserOut,
    DailyCount,
    SetUsageLimitRequest,
)

router = APIRouter(prefix="/admin", tags=["admin"])


def _to_admin_user_out(user: User) -> AdminUserOut:
    limit = user.ai_monthly_limit if user.ai_monthly_limit is not None else settings.AI_USAGE_LIMIT_DEFAULT
    return AdminUserOut(
        id=user.id,
        email=user.email,
        display_name=user.display_name,
        is_verified=user.is_verified,
        is_active=user.is_active,
        is_admin=user.is_admin,
        subscription_tier=user.subscription_tier,
        ai_messages_used=user.ai_messages_used,
        ai_monthly_limit=user.ai_monthly_limit,
        ai_usage_limit=limit,
        created_at=user.created_at,
    )


@router.get("/users", response_model=AdminUserListResponse)
async def list_users(
    search: str | None = Query(default=None, description="Filter by email or display name"),
    page: int = Query(default=1, ge=1),
    page_size: int = Query(default=50, ge=1, le=200),
    admin: User = Depends(require_admin),
    db: AsyncSession = Depends(get_db),
) -> AdminUserListResponse:
    stmt = select(User)
    count_stmt = select(func.count()).select_from(User)
    if search:
        pattern = f"%{search.strip()}%"
        stmt = stmt.where((User.email.ilike(pattern)) | (User.display_name.ilike(pattern)))
        count_stmt = count_stmt.where((User.email.ilike(pattern)) | (User.display_name.ilike(pattern)))

    total = (await db.execute(count_stmt)).scalar_one()
    result = await db.execute(
        stmt.order_by(User.created_at.desc()).offset((page - 1) * page_size).limit(page_size)
    )
    users = result.scalars().all()
    return AdminUserListResponse(
        users=[_to_admin_user_out(u) for u in users], total=total, page=page, page_size=page_size
    )


@router.patch("/users/{user_id}/limit", response_model=AdminUserOut)
async def set_usage_limit(
    user_id: uuid.UUID,
    body: SetUsageLimitRequest,
    admin: User = Depends(require_admin),
    db: AsyncSession = Depends(get_db),
) -> AdminUserOut:
    user = await db.get(User, user_id)
    if user is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="User not found.")
    user.ai_monthly_limit = body.ai_monthly_limit
    await db.commit()
    await db.refresh(user)
    return _to_admin_user_out(user)


@router.delete("/users/{user_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_user(
    user_id: uuid.UUID,
    admin: User = Depends(require_admin),
    db: AsyncSession = Depends(get_db),
) -> None:
    if user_id == admin.id:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="You cannot delete your own account.")
    user = await db.get(User, user_id)
    if user is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="User not found.")
    # Every table that references users.id has ON DELETE CASCADE (see migration
    # a1b2c3d4e5f6) — Postgres removes the user's notes, conversations, ward
    # data, exam plans, etc. in the same transaction as this delete.
    await db.delete(user)
    await db.commit()


@router.get("/stats", response_model=AdminStatsResponse)
async def get_stats(
    admin: User = Depends(require_admin),
    db: AsyncSession = Depends(get_db),
) -> AdminStatsResponse:
    total_users = (await db.execute(select(func.count()).select_from(User))).scalar_one()
    verified_users = (
        await db.execute(select(func.count()).select_from(User).where(User.is_verified.is_(True)))
    ).scalar_one()
    admin_users = (
        await db.execute(select(func.count()).select_from(User).where(User.is_admin.is_(True)))
    ).scalar_one()
    total_ai_messages_used = (
        await db.execute(select(func.coalesce(func.sum(User.ai_messages_used), 0)))
    ).scalar_one()

    trial_cutoff = datetime.now(timezone.utc) - timedelta(days=settings.TRIAL_DURATION_DAYS)
    active_trial_users = (
        await db.execute(select(func.count()).select_from(User).where(User.created_at > trial_cutoff))
    ).scalar_one()

    since = datetime.now(timezone.utc) - timedelta(days=14)
    daily_result = await db.execute(
        select(func.date(User.created_at), func.count())
        .where(User.created_at >= since)
        .group_by(func.date(User.created_at))
        .order_by(func.date(User.created_at))
    )
    signups_last_14_days = [DailyCount(date=str(d), count=c) for d, c in daily_result.all()]

    top_result = await db.execute(
        select(User).where(User.ai_messages_used > 0).order_by(User.ai_messages_used.desc()).limit(5)
    )
    top_ai_users = [_to_admin_user_out(u) for u in top_result.scalars().all()]

    return AdminStatsResponse(
        total_users=total_users,
        verified_users=verified_users,
        active_trial_users=active_trial_users,
        admin_users=admin_users,
        total_ai_messages_used=total_ai_messages_used,
        signups_last_14_days=signups_last_14_days,
        top_ai_users=top_ai_users,
    )
