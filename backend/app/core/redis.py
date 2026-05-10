"""Async Redis connection pool configuration."""
import redis.asyncio as redis

from app.core.config import settings


async def get_redis_pool() -> redis.Redis:
    """Create and return async Redis connection pool."""
    return await redis.from_url(
        settings.REDIS_URL,
        decode_responses=True,
        max_connections=50,
        socket_timeout=5,
        socket_connect_timeout=5,
        health_check_interval=30,
    )
