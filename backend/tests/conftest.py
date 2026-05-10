"""Test fixtures and configuration.

Provides test database, Redis client, and HTTP client fixtures.
"""
import os
from typing import AsyncGenerator

import pytest
import pytest_asyncio
from httpx import AsyncClient, ASGITransport
from sqlalchemy.ext.asyncio import create_async_engine, AsyncSession, async_sessionmaker
import redis.asyncio as redis

from app.main import app
from app.core.database import Base
from app.api.deps import get_db, get_redis


# Use test database URL
TEST_DATABASE_URL = os.getenv(
    "TEST_DATABASE_URL",
    "postgresql+asyncpg://postgres:postgres@localhost:5432/asd_intervention_test"
)


@pytest_asyncio.fixture(scope="function")
async def test_db() -> AsyncGenerator[AsyncSession, None]:
    """Create test database session with tables created/dropped per test.

    Uses a separate test database to avoid affecting dev data.
    """
    # Create async engine for test database
    engine = create_async_engine(TEST_DATABASE_URL, echo=False)

    # Create all tables
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)

    # Create session factory
    TestSessionLocal = async_sessionmaker(
        engine,
        class_=AsyncSession,
        expire_on_commit=False,
    )

    # Create session
    async with TestSessionLocal() as session:
        try:
            yield session
            await session.commit()
        except Exception:
            await session.rollback()
            raise
        finally:
            await session.close()

    # Drop all tables
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.drop_all)

    # Dispose engine
    await engine.dispose()


@pytest_asyncio.fixture(scope="function")
async def test_redis() -> AsyncGenerator[redis.Redis, None]:
    """Create test Redis client."""
    redis_url = os.getenv("REDIS_URL", "redis://localhost:6379/0")
    client = redis.from_url(redis_url, decode_responses=True)

    yield client

    await client.aclose()


@pytest_asyncio.fixture(scope="function")
async def test_auth_token(test_db: AsyncSession) -> str:
    """Create a test user with email/password and return a JWT token."""
    from app.core.security import create_access_token, hash_password
    from app.domains.users.models import User, UserProfile

    user = User(
        age=8,
        severity_level=2,
        email="testuser@test.com",
        hashed_password=hash_password("testpass123"),
    )
    test_db.add(user)
    await test_db.flush()

    profile = UserProfile(user_id=user.user_id, state_vector=[0.0] * 60)
    test_db.add(profile)
    await test_db.flush()

    token = create_access_token(sub=f"user:{user.user_id}")
    return token


@pytest_asyncio.fixture(scope="function")
async def test_client(
    test_db: AsyncSession,
    test_redis: redis.Redis,
    test_auth_token: str,
) -> AsyncGenerator[AsyncClient, None]:
    """Create test HTTP client with dependency overrides and auth token.

    Overrides:
    - get_db: Use test database session
    - get_redis: Use test Redis client
    """
    # Override dependencies
    async def override_get_db():
        yield test_db

    async def override_get_redis():
        return test_redis

    app.dependency_overrides[get_db] = override_get_db
    app.dependency_overrides[get_redis] = override_get_redis

    # Create test client with auth header
    async with AsyncClient(
        transport=ASGITransport(app=app),
        base_url="http://test",
        headers={"Authorization": f"Bearer {test_auth_token}"},
    ) as client:
        yield client

    # Clear overrides
    app.dependency_overrides.clear()
