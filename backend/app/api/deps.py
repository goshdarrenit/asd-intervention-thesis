"""Dependency injection for database sessions and Redis."""
from typing import Annotated, AsyncGenerator

from fastapi import Depends
from sqlalchemy.ext.asyncio import AsyncSession
import redis.asyncio as redis

from app.core.database import AsyncSessionLocal
from app.core.lifespan import app_state


async def get_db() -> AsyncGenerator[AsyncSession, None]:
    """Dependency for database sessions with automatic transaction management."""
    async with AsyncSessionLocal() as session:
        try:
            yield session
            await session.commit()
        except Exception:
            await session.rollback()
            raise
        finally:
            await session.close()


async def get_redis() -> redis.Redis:
    """Dependency for Redis client."""
    return app_state["redis"]


# Type aliases for dependency injection
DbSession = Annotated[AsyncSession, Depends(get_db)]
RedisClient = Annotated[redis.Redis, Depends(get_redis)]
