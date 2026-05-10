"""Data access layer for sessions and Redis cache operations.

Repository pattern for database operations on Session models and Redis caching.
"""
import json
from datetime import datetime, timezone
from typing import Optional
from uuid import UUID

import redis.asyncio as redis
from sqlalchemy.ext.asyncio import AsyncSession

from app.domains.sessions.models import Session


async def create_session(
    db: AsyncSession,
    user_id: UUID,
    platform: Optional[str] = None,
) -> Session:
    """Create a new session row.

    Args:
        db: Async database session
        user_id: User UUID reference

    Returns:
        Session: Created session with server-generated ID and timestamp
    """
    session = Session(user_id=user_id, platform=platform)
    db.add(session)
    await db.flush()
    await db.refresh(session)
    return session


async def get_session(db: AsyncSession, session_id: UUID) -> Optional[Session]:
    """Fetch session by primary key.

    Args:
        db: Async database session
        session_id: Session UUID

    Returns:
        Session if found, None otherwise
    """
    return await db.get(Session, session_id)


async def end_session(
    db: AsyncSession,
    session: Session,
    scenarios_completed: int,
    total_reward: float,
    average_frustration: Optional[float],
    ended_reason: str = "completed",
) -> Session:
    """Update session with end timestamp and aggregate metrics.

    Args:
        db: Async database session
        session: Session object to update
        scenarios_completed: Count of scenarios completed in session
        total_reward: Sum of rewards across all scenarios
        average_frustration: Mean frustration across scenarios
        ended_reason: Reason for session end (completed, timeout, user_quit, intervention)

    Returns:
        Session: Updated session object
    """
    session.ended_at = datetime.now(timezone.utc).replace(tzinfo=None)
    session.scenarios_completed = scenarios_completed
    session.total_reward = total_reward
    session.average_frustration = average_frustration
    session.ended_reason = ended_reason
    await db.flush()
    await db.refresh(session)
    return session


async def cache_profile(
    redis_client: redis.Redis,
    user_id: UUID,
    profile_data: str,
    ttl: int = 1800,
) -> None:
    """Store serialized profile JSON in Redis with TTL.

    30-minute TTL (1800s) for profile cache.

    Args:
        redis_client: Async Redis client
        user_id: User UUID
        profile_data: Serialized profile JSON string
        ttl: Time-to-live in seconds (default: 1800 = 30 minutes)
    """
    cache_key = f"profile:{user_id}"
    await redis_client.setex(cache_key, ttl, profile_data)


async def get_cached_profile(
    redis_client: redis.Redis,
    user_id: UUID,
) -> Optional[str]:
    """Get cached profile from Redis with sliding TTL.

    Implements sliding expiration by extending TTL on access.

    Args:
        redis_client: Async Redis client
        user_id: User UUID

    Returns:
        Cached profile JSON string if found, None otherwise
    """
    cache_key = f"profile:{user_id}"
    cached_data = await redis_client.get(cache_key)

    if cached_data is not None:
        # Implement sliding TTL: extend expiration on access
        await redis_client.expire(cache_key, 1800)
        return cached_data

    return None


async def cache_session_data(
    redis_client: redis.Redis,
    session_id: UUID,
    user_id: UUID,
) -> None:
    """Store session metadata in Redis.

    Args:
        redis_client: Async Redis client
        session_id: Session UUID
        user_id: User UUID
    """
    cache_key = f"session:{session_id}"
    session_data = {
        "user_id": str(user_id),
        "scenarios_completed": 0,
    }
    await redis_client.setex(cache_key, 1800, json.dumps(session_data))


async def get_cached_session_data(
    redis_client: redis.Redis,
    session_id: UUID,
) -> Optional[dict]:
    """Get cached session data with sliding TTL.

    Args:
        redis_client: Async Redis client
        session_id: Session UUID

    Returns:
        Parsed session data dict if found, None otherwise
    """
    cache_key = f"session:{session_id}"
    cached_data = await redis_client.get(cache_key)

    if cached_data is not None:
        # Extend TTL on access (sliding expiration)
        await redis_client.expire(cache_key, 1800)
        return json.loads(cached_data)

    return None


async def delete_session_cache(
    redis_client: redis.Redis,
    session_id: UUID,
) -> None:
    """Delete session cache from Redis.

    Args:
        redis_client: Async Redis client
        session_id: Session UUID
    """
    cache_key = f"session:{session_id}"
    await redis_client.delete(cache_key)


async def invalidate_profile_cache(
    redis_client: redis.Redis,
    user_id: UUID,
) -> None:
    """Invalidate profile cache after write operations.

    Args:
        redis_client: Async Redis client
        user_id: User UUID
    """
    cache_key = f"profile:{user_id}"
    await redis_client.delete(cache_key)
