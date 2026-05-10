"""FastAPI route for the CrewAI validation framework.

POST /api/validation/run — No authentication required (research tool).
"""
import logging
import traceback
from uuid import UUID
from fastapi import APIRouter, HTTPException
from fastapi.responses import JSONResponse
from pydantic import BaseModel
from typing import Any
from sqlalchemy import select

logger = logging.getLogger(__name__)

from app.api.deps import get_db
from app.domains.users.models import UserProfile, User
from fastapi import Depends
from sqlalchemy.ext.asyncio import AsyncSession
from validation.runner import run_trial, run_session_trial, run_phase1, run_phase2, run_phase3
from validation.scenarios import SCENARIOS, FULL_SESSION_SCENARIO
from validation.results_schema import SupervisorReport

router = APIRouter(prefix="/api/validation", tags=["validation"])


class ValidationRunRequest(BaseModel):
    scenario_id: str
    phase: int | None = None  # 1, 2, or 3; None runs all phases


class ResetProfileRequest(BaseModel):
    user_id: str
    starting_difficulty: int = 3


@router.post("/reset-profile")
async def reset_validation_profile(
    request: ResetProfileRequest,
    db: AsyncSession = Depends(get_db),
) -> Any:
    """Reset a validation test user's profile to clean defaults at a given starting difficulty.

    Clears accumulated session history so each validation run starts from a known state.
    Only intended for validation test users (validation.*@asd-thesis.test).
    """
    user_id = UUID(request.user_id)

    # Guard: only allow resetting validation test accounts
    user = await db.get(User, user_id)
    if user is None or not (user.email or "").endswith("@asd-thesis.test"):
        raise HTTPException(status_code=403, detail="Only validation test users can be reset.")

    profile = await db.get(UserProfile, user_id)
    if profile is None:
        raise HTTPException(status_code=404, detail="Profile not found.")

    # Rebuild initial state_vector: age + severity in first two dims, rest zeroed
    age_norm = (user.age - 5) / 10.0
    severity_norm = (user.severity_level - 1) / 2.0
    state_vector = [age_norm, severity_norm] + [0.0] * 58

    profile.current_difficulty = request.starting_difficulty
    profile.overall_success_rate = 0.5
    profile.scenarios_completed = 0
    profile.total_session_time = 0
    profile.last_5_scenarios = []
    profile.last_5_success_rates = []
    profile.emotional_history = {
        "frustration_mean": 0.3,
        "engagement_mean": 0.7,
        "confidence_mean": 0.5,
    }
    profile.state_vector = state_vector

    await db.commit()
    return JSONResponse({"status": "ok", "user_id": str(user_id), "starting_difficulty": request.starting_difficulty})


@router.post("/run")
async def run_validation(request: ValidationRunRequest) -> Any:
    """
    Trigger a CrewAI validation trial for a single scenario.

    Runs 5 ASD child persona agents + supervisor sequentially.
    Response time: ~60-180 seconds (LLM calls, not cached).
    No authentication required — this is a research/thesis tool.

    For full_session_validation, use `phase` (1, 2, or 3) to run a single phase.
    Phases 2 and 3 load their input from the previous phase's cache when run standalone.
    Phase 1 and 2 return {"status": "ok", ...}; phase 3 returns a SupervisorReport.
    """
    # Full live-session mode: drives real API sessions for all 5 personas
    if request.scenario_id == FULL_SESSION_SCENARIO["id"]:
        try:
            if request.phase == 1:
                user_ids = await run_phase1()
                return JSONResponse({"status": "ok", "phase": 1, "user_ids": user_ids})
            if request.phase == 2:
                await run_phase2()
                return JSONResponse({"status": "ok", "phase": 2, "message": "persona_results cached"})
            if request.phase == 3:
                report = await run_phase3()
                return JSONResponse(report.model_dump())
            return JSONResponse((await run_session_trial()).model_dump())
        except RuntimeError as exc:
            raise HTTPException(status_code=503, detail=str(exc))
        except Exception as exc:
            logger.error("Session validation trial failed:\n%s", traceback.format_exc())
            raise HTTPException(
                status_code=500,
                detail=f"Session validation trial failed: {str(exc)}",
            )

    # Static scenario mode (original behaviour — backward compatible)
    scenario = next(
        (s for s in SCENARIOS if s["id"] == request.scenario_id), None
    )
    if scenario is None:
        raise HTTPException(
            status_code=404,
            detail=f"Scenario '{request.scenario_id}' not found. "
                   f"Valid IDs: {[s['id'] for s in SCENARIOS] + [FULL_SESSION_SCENARIO['id']]}",
        )
    try:
        return await run_trial(scenario)
    except Exception as exc:
        raise HTTPException(
            status_code=500,
            detail=f"Validation trial failed: {str(exc)}",
        )
