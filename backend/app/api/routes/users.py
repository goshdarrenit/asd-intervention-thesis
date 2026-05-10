"""User management endpoints.

Provides user registration and profile retrieval with Redis caching.
"""
from uuid import UUID

from fastapi import APIRouter, status

from app.api.deps import DbSession, RedisClient
from app.core.dependencies import CurrentUser
from app.domains.users.schemas import UserCreate, UserResponse, UserProfileResponse
from app.domains.users import service

router = APIRouter(prefix="/api/users", tags=["users"])


@router.post("/register", status_code=status.HTTP_201_CREATED)
async def register_user(
    user_data: UserCreate,
    db: DbSession,
) -> UserResponse:
    """Register a new user.

    Creates user and profile with initialized state vector.

    Args:
        user_data: User registration data (age, severity_level, optional guardian_email)
        db: Database session (injected)

    Returns:
        UserResponse with user_id

    Raises:
        422: Validation error (age not 4-18, severity not 1-3)
    """
    return await service.register_user(db=db, user_data=user_data)


@router.get("/{user_id}/profile")
async def get_user_profile(
    user_id: UUID,
    db: DbSession,
    redis: RedisClient,
    _current_user: CurrentUser,
) -> UserProfileResponse:
    """Get user profile with cache-aside pattern.

    Implements cache-aside:
    1. Check Redis cache
    2. If miss, query PostgreSQL
    3. Populate cache with 5min TTL
    4. Return profile data

    Args:
        user_id: User UUID
        db: Database session (injected)
        redis: Redis client (injected)

    Returns:
        UserProfileResponse with profile data

    Raises:
        404: User not found
    """
    return await service.get_user_profile(db=db, redis_client=redis, user_id=user_id)
