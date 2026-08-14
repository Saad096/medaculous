import os
import uuid
from collections.abc import AsyncGenerator

# Settings() is instantiated at import time (app.core.config module level) and has
# no defaults for these — must be set before any `app.*` import happens anywhere.
# medaculous_test is a real local Postgres database (see README/DISCOVERY_REPORT for
# setup) with the same alembic migrations applied as the dev `medaculous` database —
# not a mock, so these tests exercise real ownership/authz queries end-to-end.
os.environ.setdefault("DATABASE_URL", "postgresql+asyncpg://saad:123@localhost:5432/medaculous_test")
os.environ.setdefault("JWT_SECRET", "test-access-secret")
os.environ.setdefault("JWT_REFRESH_SECRET", "test-refresh-secret")
os.environ.setdefault("ENV", "dev")

import pytest
import pytest_asyncio
from httpx import ASGITransport, AsyncClient
from sqlalchemy import text

from app.core.security import create_token, hash_password
from app.db.session import AsyncSessionLocal, engine
from app.main import app
from app.models.user import User


@pytest_asyncio.fixture
async def db_session() -> AsyncGenerator:
    async with AsyncSessionLocal() as session:
        yield session


@pytest_asyncio.fixture
async def client() -> AsyncGenerator[AsyncClient, None]:
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test/api/v1") as ac:
        yield ac


async def _make_user(db, *, email: str) -> User:
    user = User(
        id=uuid.uuid4(),
        email=email,
        hashed_password=hash_password("Test-Password-123!"),
        is_active=True,
        is_verified=True,
    )
    db.add(user)
    await db.commit()
    await db.refresh(user)
    return user


@pytest_asyncio.fixture
async def user_a(db_session):
    return await _make_user(db_session, email=f"user-a-{uuid.uuid4().hex[:8]}@test.com")


@pytest_asyncio.fixture
async def user_b(db_session):
    return await _make_user(db_session, email=f"user-b-{uuid.uuid4().hex[:8]}@test.com")


@pytest_asyncio.fixture
def auth_headers():
    """Returns a factory: auth_headers(user) -> {"Authorization": "Bearer ..."} for that user."""

    def _make(user: User) -> dict[str, str]:
        token = create_token(str(user.id), "access")
        return {"Authorization": f"Bearer {token}"}

    return _make


@pytest_asyncio.fixture(autouse=True)
async def _cleanup_after_test():
    """Each test creates its own users via user_a/user_b; truncating users CASCADE
    after every test clears all owned rows too, keeping tests independent without
    needing a transaction-rollback sandbox."""
    yield
    async with engine.begin() as conn:
        await conn.execute(text("TRUNCATE TABLE users CASCADE"))
