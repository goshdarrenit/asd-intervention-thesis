"""Session service orchestrating lifecycle and cache-aside pattern.

Coordinates session creation/termination with profile caching and EMA updates.
"""
from uuid import UUID

import redis.asyncio as redis
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.exceptions import SessionAlreadyEndedException, SessionNotFoundException, UserNotFoundException
from app.domains.sessions import repository
from app.domains.sessions.models import ScenarioResult
from app.domains.sessions.profile_updater import ProfileUpdater
from app.domains.sessions.schemas import SessionEndResponse, SessionResponse
from app.domains.users import repository as user_repository
from app.domains.users.schemas import UserProfileResponse


async def start_session(
    db: AsyncSession,
    redis_client: redis.Redis,
    user_id: UUID,
    platform: str | None = None,
) -> SessionResponse:
    """Start a new session with profile caching.

    Args:
        db: Async database session
        redis_client: Async Redis client
        user_id: User UUID

    Returns:
        SessionResponse with session details

    Raises:
        UserNotFoundException: If user does not exist
    """
    # Verify user exists
    user = await user_repository.get_user_by_id(db, user_id)
    if user is None:
        raise UserNotFoundException(str(user_id))

    # Create session
    session = await repository.create_session(db, user_id, platform=platform)

    # Load profile for caching
    profile = await user_repository.get_user_profile(db, user_id)
    if profile is not None:
        # Serialize profile using Pydantic schema
        profile_response = UserProfileResponse.model_validate(profile)
        profile_json = profile_response.model_dump_json()

        # Cache in Redis with 30-min TTL
        await repository.cache_profile(redis_client, user_id, profile_json)

    # Cache session metadata
    await repository.cache_session_data(redis_client, session.session_id, user_id)

    return SessionResponse.model_validate(session)


async def end_session(
    db: AsyncSession,
    redis_client: redis.Redis,
    session_id: UUID,
) -> SessionEndResponse:
    """End session with profile updates and cache invalidation.

    Updates session with ended_at timestamp and aggregate metrics.
    Applies EMA profile updates for all scenario results.
    Invalidates profile cache after writes.

    Args:
        db: Async database session
        redis_client: Async Redis client
        session_id: Session UUID

    Returns:
        SessionEndResponse with final metrics

    Raises:
        SessionNotFoundException: If session does not exist
        SessionAlreadyEndedException: If session already ended
    """
    # Load session
    session = await repository.get_session(db, session_id)
    if session is None:
        raise SessionNotFoundException(str(session_id))

    # Check if already ended
    if session.ended_at is not None:
        raise SessionAlreadyEndedException(str(session_id))

    # Query all scenario results for this session
    result = await db.execute(
        select(ScenarioResult).where(ScenarioResult.session_id == session_id)
    )
    scenario_results = result.scalars().all()

    # Calculate aggregate metrics
    scenarios_completed = len(scenario_results)
    total_reward = sum(r.reward or 0.0 for r in scenario_results)

    # Calculate average frustration from emotions
    frustrations = [
        r.emotions.get("frustration", 0.0)
        for r in scenario_results
        if r.emotions is not None
    ]
    average_frustration = sum(frustrations) / len(frustrations) if frustrations else None

    # Apply EMA profile updates for each scenario result
    if scenario_results:
        profile_updater = ProfileUpdater()
        for result in scenario_results:
            await profile_updater.update_profile_after_scenario(
                db,
                redis_client,
                session.user_id,
                result,
            )

    # Update session with end timestamp and metrics
    updated_session = await repository.end_session(
        db,
        session,
        scenarios_completed,
        total_reward,
        average_frustration,
    )

    # Clean up session cache
    await repository.delete_session_cache(redis_client, session_id)

    # Invalidate profile cache (EMA updates wrote new data)
    await repository.invalidate_profile_cache(redis_client, session.user_id)

    return SessionEndResponse.model_validate(updated_session)
