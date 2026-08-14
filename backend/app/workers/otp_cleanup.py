"""
Deletes expired/consumed OTP codes so the table doesn't grow unbounded.
Run on a schedule (cron, k8s CronJob, or APScheduler in a long-lived process):

    python -m app.workers.otp_cleanup
"""

import asyncio
from datetime import datetime, timedelta, timezone

from sqlalchemy import delete

from app.db.session import AsyncSessionLocal
from app.models.otp import OTPCode

RETENTION_AFTER_EXPIRY = timedelta(days=1)


async def cleanup_expired_otps() -> int:
    cutoff = datetime.now(timezone.utc) - RETENTION_AFTER_EXPIRY
    async with AsyncSessionLocal() as db:
        result = await db.execute(delete(OTPCode).where(OTPCode.expires_at < cutoff))
        await db.commit()
        return result.rowcount or 0


if __name__ == "__main__":
    deleted = asyncio.run(cleanup_expired_otps())
    print(f"Deleted {deleted} expired OTP codes.")
