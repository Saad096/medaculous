"""
Deletes refresh tokens that are both revoked and past expiry — nothing can ever
validate them again, so keeping the rows around only serves audit history that
belongs in audit_log instead. Run on a schedule:

    python -m app.workers.token_pruning
"""

import asyncio
from datetime import datetime, timezone

from sqlalchemy import delete, or_

from app.db.session import AsyncSessionLocal
from app.models.refresh_token import RefreshToken


async def prune_dead_refresh_tokens() -> int:
    now = datetime.now(timezone.utc)
    async with AsyncSessionLocal() as db:
        result = await db.execute(
            delete(RefreshToken).where(or_(RefreshToken.revoked.is_(True), RefreshToken.expires_at < now))
        )
        await db.commit()
        return result.rowcount or 0


if __name__ == "__main__":
    deleted = asyncio.run(prune_dead_refresh_tokens())
    print(f"Deleted {deleted} dead refresh tokens.")
