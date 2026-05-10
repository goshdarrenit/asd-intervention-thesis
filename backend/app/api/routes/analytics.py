"""Analytics endpoints for user learning curves and RL agent performance."""
from typing import Annotated
from uuid import UUID

from fastapi import APIRouter, Depends
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.deps import get_db
from app.core.dependencies import CurrentUser
from app.domains.analytics.queries import get_model_metadata, get_user_scenario_history

DbSession = Annotated[AsyncSession, Depends(get_db)]

router = APIRouter(prefix="/api/analytics", tags=["analytics"])


@router.get("/user/{user_id}")
async def get_user_analytics(user_id: UUID, db: DbSession, current_user: CurrentUser):
    """Learning curve, scenario performance, emotional trends."""
    scenarios = await get_user_scenario_history(db, user_id)

    # Compute rolling 5-scenario window success rate
    completed = [s["completed"] for s in scenarios]
    window_5 = []
    for i in range(len(completed)):
        start = max(0, i - 4)
        window = completed[start : i + 1]
        window_5.append(sum(window) / len(window) if window else 0.0)

    # Emotional trends: raw frustration + engagement per scenario
    emotional_trends = [
        {
            "frustration": s["emotions"].get("frustration", 0.0),
            "engagement": s["emotions"].get("engagement", 0.0),
            "timestamp": s["timestamp"],
        }
        for s in scenarios
    ]

    return {
        "user_id": str(user_id),
        "scenarios": scenarios,
        "window_5_success_rate": window_5,
        "emotional_trends": emotional_trends,
    }


@router.get("/rl_agent/performance")
async def get_rl_performance(current_user: CurrentUser):
    """Model version, training metrics, evaluation results."""
    return get_model_metadata()
