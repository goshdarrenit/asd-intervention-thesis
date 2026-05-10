"""Session management endpoints.

Provides session lifecycle operations (start/end) with Redis caching.
"""
from uuid import UUID

from fastapi import APIRouter, status

from app.api.deps import DbSession, RedisClient
from app.core.dependencies import CurrentUser
from app.domains.sessions.schemas import SessionStartRequest, SessionResponse, SessionEndResponse
from app.domains.sessions import service

router = APIRouter(prefix="/api/sessions", tags=["sessions"])


@router.post("/start", status_code=status.HTTP_200_OK)
async def start_session(
    request: SessionStartRequest,
    db: DbSession,
    redis: RedisClient,
    _current_user: CurrentUser,
) -> SessionResponse:
    """Start a new session.

    Creates session in PostgreSQL, caches user profile in Redis with 30-min TTL,
    and caches session metadata for quick access.

    Args:
        request: Session start request with user_id
        db: Database session (injected)
        redis: Redis client (injected)

    Returns:
        SessionResponse with session_id, started_at, and initial metrics

    Raises:
        404: User not found (USER_NOT_FOUND)
    """
    return await service.start_session(
        db=db,
        redis_client=redis,
        user_id=request.user_id,
        platform=request.platform,
    )


@router.post("/{session_id}/end", status_code=status.HTTP_200_OK)
async def end_session(
    session_id: UUID,
    db: DbSession,
    redis: RedisClient,
    _current_user: CurrentUser,
) -> SessionEndResponse:
    """End an existing session.

    Finalizes session in PostgreSQL with aggregate metrics (scenarios_completed,
    total_reward, average_frustration), applies EMA profile updates,
    and clears Redis session cache.

    Args:
        session_id: Session UUID (path parameter)
        db: Database session (injected)
        redis: Redis client (injected)

    Returns:
        SessionEndResponse with ended_at, scenarios_completed, and success message

    Raises:
        404: Session not found (SESSION_NOT_FOUND)
        400: Session already ended (SESSION_ALREADY_ENDED)
    """
    return await service.end_session(db=db, redis_client=redis, session_id=session_id)
