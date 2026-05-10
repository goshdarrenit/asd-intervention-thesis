"""Business logic for user management with Redis cache-aside pattern.

Service layer implementing:
- User registration
- Profile retrieval with cache-aside pattern
"""
import json
from uuid import UUID

import redis.asyncio as redis
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.exceptions import UserNotFoundException
from app.domains.users import repository
from app.domains.users.schemas import UserCreate, UserResponse, UserProfileResponse


async def register_user(
    db: AsyncSession,
    user_data: UserCreate,
) -> UserResponse:
    """Register a new user.

    Creates user and profile in PostgreSQL.

    Args:
        db: Database session
        user_data: User registration data

    Returns:
        UserResponse with user_id
    """
    user = await repository.create_user(
        db=db,
        age=user_data.age,
        severity_level=user_data.severity_level,
        guardian_email=user_data.guardian_email,
    )

    return UserResponse(user_id=user.user_id)


async def get_user_profile(
    db: AsyncSession,
    redis_client: redis.Redis,
    user_id: UUID,
) -> UserProfileResponse:
    """Fetch user profile with cache-aside pattern.

    Implements cache-aside pattern:
    1. Check Redis cache first (key: profile:{user_id})
    2. If cache hit: return cached data
    3. If cache miss: query PostgreSQL
    4. If not found in DB: raise UserNotFoundException
    5. If found: store in Redis with 300s TTL, return data

    Args:
        db: Database session
        redis_client: Redis client
        user_id: User UUID

    Returns:
        UserProfileResponse with profile data

    Raises:
        UserNotFoundException: If user_id doesn't exist
    """
    # Cache key
    cache_key = f"profile:{user_id}"

    # Step 1: Try Redis cache
    cached_data = await redis_client.get(cache_key)
    if cached_data:
        # Cache hit - deserialize and return
        profile_dict = json.loads(cached_data)
        return UserProfileResponse(**profile_dict)

    # Step 2: Cache miss - query PostgreSQL
    profile = await repository.get_user_profile(db=db, user_id=user_id)

    if not profile:
        # Step 3: Not found in DB
        raise UserNotFoundException(user_id=str(user_id))

    # Step 4: Found - create response object
    profile_response = UserProfileResponse(
        user_id=profile.user_id,
        overall_success_rate=profile.overall_success_rate,
        scenarios_completed=profile.scenarios_completed,
        current_difficulty=profile.current_difficulty,
        learning_rate=profile.learning_rate,
        frustration_tolerance=profile.frustration_tolerance,
        preferred_scenarios=profile.preferred_scenarios,
        emotional_history=profile.emotional_history,
    )

    # Step 5: Populate cache with 300s TTL
    # Serialize to JSON (convert UUID to string for JSON serialization)
    cache_data = profile_response.model_dump(mode="json")
    cache_data["user_id"] = str(cache_data["user_id"])  # UUID -> string
    await redis_client.setex(
        cache_key,
        300,  # 5 minutes TTL
        json.dumps(cache_data),
    )

    return profile_response
