"""Health check endpoint.

Provides detailed health status for database, Redis, and RL model.
"""
from fastapi import APIRouter, status
from fastapi.responses import JSONResponse
from sqlalchemy import text

from app.api.deps import DbSession, RedisClient
from app.core.lifespan import app_state

router = APIRouter(tags=["health"])


@router.get("/health")
async def health_check(
    db: DbSession,
    redis: RedisClient,
) -> JSONResponse:
    """Detailed health check for all dependencies.

    Checks:
    - Database: Executes SELECT 1 query
    - Redis: Pings Redis server
    - RL Model: Checks model_loaded state 

    Returns:
        JSONResponse with status and individual checks

    Status codes:
        200: All critical services (DB, Redis) are healthy
        503: One or more critical services are unhealthy

    """
    checks = {}
    all_healthy = True

    # Check database
    try:
        await db.execute(text("SELECT 1"))
        checks["database"] = "healthy"
    except Exception as e:
        checks["database"] = f"error: {str(e)}"
        all_healthy = False

    # Check Redis
    try:
        await redis.ping()
        checks["redis"] = "healthy"
    except Exception as e:
        checks["redis"] = f"error: {str(e)}"
        all_healthy = False

    model_loaded = app_state.get("model_loaded", False)
    checks["rl_model"] = "loaded" if model_loaded else "not_loaded"

    # Overall status
    overall_status = "healthy" if all_healthy else "unhealthy"
    status_code = status.HTTP_200_OK if all_healthy else status.HTTP_503_SERVICE_UNAVAILABLE

    return JSONResponse(
        status_code=status_code,
        content={
            "status": overall_status,
            "checks": checks,
        },
    )
