"""Scenario selection and submission endpoints.

/next: Get next scenario from RL model
/submit: Submit scenario results with telemetry, get emotion feedback
"""
import random
from datetime import datetime, timezone
from typing import Literal
from uuid import UUID

_CONSEC_FAIL_KEY = "safety:consec_fails:{session_id}"
_CONSEC_FAIL_TTL = 7200  # 2 hours

# Redis key for shuffle-bag scenario type selection (per session)
_SCENARIO_BAG_KEY = "scenario:bag:{session_id}"
_SCENARIO_BAG_TTL = 7200  # 2 hours

import numpy as np
from fastapi import APIRouter, HTTPException, status
from pydantic import BaseModel, Field

from app.api.deps import DbSession, RedisClient
from app.core.dependencies import CurrentUser
from app.core.lifespan import app_state
from app.domains.scenarios.difficulty_config import (
    calculate_difficulty,
    calculate_reward,
    generate_encouragement,
)
from app.domains.sessions.models import ScenarioResult, Session
from app.domains.sessions.profile_updater import ProfileUpdater
from app.domains.users import repository as user_repository
from app.rl.action_space import ACTION_SPACE_CONFIG, decode_action
from app.rl.emotion_inference import BehavioralTelemetry, infer_emotion

# Create router
router = APIRouter(prefix="/api/v1/scenarios", tags=["scenarios"])


# Request/Response schemas
class NextScenarioRequest(BaseModel):
    """Request for next scenario selection."""

    user_id: str = Field(..., description="User UUID")
    session_id: str = Field(..., description="Session UUID")


class NextScenarioResponse(BaseModel):
    """Response with next scenario configuration."""

    scenario_type: Literal[
        "sharing", "patience", "emotion_recognition", "turn_taking", "conflict_resolution"
    ] = Field(..., description="Scenario type")
    difficulty: int = Field(..., ge=1, le=5, description="Difficulty level (1-5)")
    complexity: Literal["low", "medium", "high"] = Field(..., description="Complexity level")
    reinforcement_mode: Literal["positive", "neutral", "corrective"] = Field(
        ..., description="Reinforcement strategy"
    )
    session_id: str = Field(..., description="Session UUID")


class SubmitScenarioRequest(BaseModel):
    """Request to submit scenario results with telemetry."""

    user_id: str = Field(..., description="User UUID")
    session_id: str = Field(..., description="Session UUID")
    scenario_type: str = Field(..., description="Scenario type played")
    difficulty: int = Field(..., ge=1, le=5, description="Difficulty level (1-5)")
    complexity: str = Field(..., description="Complexity level")
    reinforcement_mode: str = Field(..., description="Reinforcement strategy used")
    success: bool = Field(..., description="Whether scenario was completed successfully")
    completion_time_ms: int = Field(..., description="Time taken in milliseconds")
    telemetry: dict = Field(
        default_factory=dict, description="Behavioral telemetry from mobile"
    )


class SubmitScenarioResponse(BaseModel):
    """Response with emotion feedback and reward."""

    emotions: dict[str, float] = Field(
        ..., description="Inferred emotions (frustration, engagement, confidence)"
    )
    reward: float = Field(..., ge=0.0, le=1.0, description="Reward value")
    updated_difficulty: int = Field(..., ge=1, le=5, description="Updated difficulty level")
    message: str = Field(..., description="Encouragement message")
    force_ended: bool = Field(
        default=False,
        description="True if session was force-ended due to 3 consecutive failures",
    )


async def _validate_active_session(
    db: DbSession,
    *,
    session_id: str,
    user_id: str,
) -> Session:
    """Ensure session exists, belongs to user, and is still active."""
    session_uuid = UUID(session_id)
    session_obj = await db.get(Session, session_uuid)
    if session_obj is None or str(session_obj.user_id) != user_id:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail={
                "error": {
                    "message": f"Session not found: {session_id}",
                    "code": "SESSION_NOT_FOUND",
                }
            },
        )

    if session_obj.ended_at is not None:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail={
                "error": {
                    "message": "Session already ended",
                    "code": "SESSION_ALREADY_ENDED",
                }
            },
        )

    return session_obj


async def _next_scenario_type_from_bag(redis, session_id: str) -> str:
    """Shuffle-bag scenario type selection for even distribution.

    Maintains a per-session bag in Redis containing all 5 scenario types in a
    random order. Pops one type per call; when the bag empties it is refilled
    and reshuffled. This guarantees exactly one of each type per five scenarios,
    eliminating the skew caused by the RL model repeatedly outputting the same
    type for out-of-distribution (near-zero) state vectors.
    """
    bag_key = _SCENARIO_BAG_KEY.format(session_id=session_id)
    raw = await redis.rpop(bag_key)

    if raw is None:
        # Bag exhausted — refill with all 5 types in a new random order
        types = list(ACTION_SPACE_CONFIG["action_types"])
        random.shuffle(types)
        await redis.rpush(bag_key, *types)
        await redis.expire(bag_key, _SCENARIO_BAG_TTL)
        raw = await redis.rpop(bag_key)

    return raw.decode() if isinstance(raw, bytes) else raw


def _rule_based_delta(last_5_success_rates: list[float] | None) -> int:
    """Compute a simple difficulty delta from recent success rates.

    Used when the RL model is not loaded or returns delta=0.
    Keeps difficulty adaptive so children always experience progression.

    Rules (based on last-5 rolling success rate):
      >= 0.8  -> increase by +1  (consistently succeeding, ready for more)
      <= 0.3  -> decrease by -1  (consistently struggling, need easier tasks)
      else    -> no change        (in the zone of proximal development)
    """
    rates = last_5_success_rates or []
    if not rates:
        return 0
    rolling = sum(rates) / len(rates)
    if rolling >= 0.8:
        return 1
    if rolling <= 0.3:
        return -1
    return 0


@router.post("/next", response_model=NextScenarioResponse)
async def get_next_scenario(
    request: NextScenarioRequest,
    db: DbSession,
    redis: RedisClient,
    _current_user: CurrentUser,
) -> NextScenarioResponse:
    """Get next scenario from RL model.

    Queries RL predictor with user's current state vector to get optimal
    scenario selection. Falls back to random selection if model not loaded.

    Args:
        request: NextScenarioRequest with user_id and session_id
        db: Database session (injected)
        redis: Redis client (injected)

    Returns:
        NextScenarioResponse with scenario configuration

    Raises:
        404: User not found (USER_NOT_FOUND)
    """
    # Validate session so clients don't continue with stale/local-only IDs.
    await _validate_active_session(
        db,
        session_id=request.session_id,
        user_id=request.user_id,
    )

    # Get user profile
    user_id = UUID(request.user_id)
    profile = await user_repository.get_user_profile(db, user_id)

    if profile is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail={
                "error": {
                    "message": f"User not found: {request.user_id}",
                    "code": "USER_NOT_FOUND",
                }
            },
        )

    # Get current difficulty (default to 2 matching DB default)
    current_difficulty = profile.current_difficulty or 2

    # Check if RL model is loaded
    model_loaded = app_state.get("model_loaded", False)

    # Rule-based reinforcement mode from emotional state.
    # The trained model outputs "corrective" for nearly all real-user inputs
    # because real users have near-zero state vectors that are out-of-distribution
    # relative to synthetic training data.  Override with a clinically sensible rule.
    emotional_history = profile.emotional_history or {}
    frustration_mean = emotional_history.get("frustration_mean", 0.3)
    if frustration_mean > 0.7:
        reinforcement_mode = "corrective"
    elif frustration_mean > 0.4:
        reinforcement_mode = "neutral"
    else:
        reinforcement_mode = "positive"

    # Debug: log profile state for difficulty diagnosis
    import sys
    print(f"[/next] user={request.user_id[:8]} current_diff={current_difficulty} last_5_success={profile.last_5_success_rates} frustration={frustration_mean:.2f}", flush=True, file=sys.stderr)

    # Rule-based difficulty delta: always derived from recent success rates.
    # The model's difficulty delta is unreliable for real users (out-of-distribution
    # state vectors produce unstable predictions). Rule-based gives reliable
    # adaptive progression that the thesis evaluation can reason about clearly.
    difficulty_delta = _rule_based_delta(profile.last_5_success_rates)

    if model_loaded:
        # Use RL model for complexity only — the model's scenario_type output is
        # unreliable for real users whose near-zero state vectors are out-of-distribution
        # relative to synthetic training data (same issue as reinforcement_mode, fixed above).
        predictor = app_state["rl_predictor"]
        state_vector = profile.state_vector or [0.0] * 60
        state_array = np.array(state_vector, dtype=np.float32)
        result = predictor.predict(state_array, deterministic=True)
        decoded = result["decoded_action"]
        complexity = decoded["complexity_level"]
    else:
        complexity = random.choice(ACTION_SPACE_CONFIG["complexity_levels"])

    # Always use shuffle bag for scenario type — guarantees each of the 5 types
    # appears exactly once per 5 scenarios, regardless of RL model output.
    scenario_type = await _next_scenario_type_from_bag(redis, request.session_id)

    # Calculate absolute difficulty from rule-based delta
    difficulty = calculate_difficulty(current_difficulty, difficulty_delta)
    print(f"[/next] type={scenario_type} delta={difficulty_delta} new_diff={difficulty} reinf={reinforcement_mode}", flush=True, file=sys.stderr)

    # Persist computed difficulty so submit handler and next call see it
    profile.current_difficulty = difficulty
    await db.flush()
    await db.commit()

    return NextScenarioResponse(
        scenario_type=scenario_type,
        difficulty=difficulty,
        complexity=complexity,
        reinforcement_mode=reinforcement_mode,
        session_id=request.session_id,
    )


@router.post("/submit", response_model=SubmitScenarioResponse)
async def submit_scenario_result(
    request: SubmitScenarioRequest,
    db: DbSession,
    redis: RedisClient,
    _current_user: CurrentUser,
) -> SubmitScenarioResponse:
    """Submit scenario results with telemetry.

    Processes behavioral telemetry through emotion inference, calculates reward,
    persists ScenarioResult to database, and updates user profile via EMA.

    Args:
        request: SubmitScenarioRequest with scenario data and telemetry
        db: Database session (injected)
        redis: Redis client (injected)

    Returns:
        SubmitScenarioResponse with emotion feedback and reward

    Raises:
        404: User not found (USER_NOT_FOUND)
    """
    # Validate session before attempting inserts into scenario_results.
    await _validate_active_session(
        db,
        session_id=request.session_id,
        user_id=request.user_id,
    )

    # Convert telemetry dict to BehavioralTelemetry dataclass
    telemetry = request.telemetry
    behavioral_telemetry = BehavioralTelemetry(
        decision_time=telemetry.get("hesitation_pattern", 5000) / 1000.0,  # ms to seconds
        num_pauses=telemetry.get("pause_count", 0),
        num_retries=telemetry.get("retry_count", 0),
        quit_early=telemetry.get("quit_attempts", 0) > 0,
        completion_time=request.completion_time_ms / 1000.0,  # ms to seconds
    )

    # Infer emotions from telemetry
    emotional_state = infer_emotion(behavioral_telemetry)

    # Build emotions dict
    emotions = {
        "frustration": emotional_state.frustration,
        "engagement": emotional_state.engagement,
        "confidence": emotional_state.confidence,
    }

    # Calculate reward
    reward = calculate_reward(
        success=request.success,
        completion_time_ms=request.completion_time_ms,
        difficulty=request.difficulty,
        emotions=emotions,
    )

    # On the 3rd consecutive failure, force-end the session (set ended_reason='intervention').
    redis_key = _CONSEC_FAIL_KEY.format(session_id=request.session_id)
    force_ended = False

    if request.success:
        # Reset counter on any success
        await redis.delete(redis_key)
        consecutive_failures = 0
    else:
        # Increment counter and refresh TTL
        consecutive_failures = await redis.incr(redis_key)
        await redis.expire(redis_key, _CONSEC_FAIL_TTL)

        if consecutive_failures >= 3:
            # Force-end the session in the DB
            force_ended = True
            session_obj = await db.get(Session, UUID(request.session_id))
            if session_obj and session_obj.ended_at is None:
                session_obj.ended_reason = "intervention"
                session_obj.ended_at = datetime.now(timezone.utc).replace(tzinfo=None)
                await db.flush()
            # Clean up Redis key immediately so it doesn't affect future sessions
            await redis.delete(redis_key)

    # Capture pre-scenario state vector for RL telemetry (before EMA update)
    user_id = UUID(request.user_id)
    session_id = UUID(request.session_id)

    pre_profile = await user_repository.get_user_profile(db, user_id)
    pre_state_vector = list(pre_profile.state_vector) if pre_profile and pre_profile.state_vector else []

    # Record the full RL action that produced this scenario
    action_taken = {
        "action_type": request.scenario_type,
        "difficulty": request.difficulty,
        "complexity": request.complexity,
        "reinforcement_mode": request.reinforcement_mode,
        "model_used": app_state.get("model_loaded", False),
    }

    # Create ScenarioResult record
    scenario_result = ScenarioResult(
        session_id=session_id,
        user_id=user_id,
        scenario_type=request.scenario_type,
        difficulty=request.difficulty,
        complexity=request.complexity,
        reinforcement_mode=request.reinforcement_mode,
        decision_time_ms=int(telemetry.get("hesitation_pattern", 0)),
        num_pauses=telemetry.get("pause_count", 0),
        num_retries=telemetry.get("retry_count", 0),
        completed=request.success,
        quit_early=behavioral_telemetry.quit_early,
        emotions=emotions,
        reward=reward,
        state_vector=pre_state_vector,
        action_taken=action_taken,
        timestamp=datetime.now(timezone.utc).replace(tzinfo=None),
    )

    db.add(scenario_result)
    await db.flush()

    # Update profile with EMA (rebuilds state_vector in-place on the profile)
    profile_updater = ProfileUpdater()
    await profile_updater.update_profile_after_scenario(
        db=db,
        redis_client=redis,
        user_id=user_id,
        scenario_result=scenario_result,
    )

    # Invalidate Redis cache for this user's profile
    cache_key = f"profile:{request.user_id}"
    await redis.delete(cache_key)

    # Commit transaction (handled by dependency injection)
    await db.commit()

    # Get updated profile — captures post-EMA state_vector as next_state
    profile = await user_repository.get_user_profile(db, user_id)
    updated_difficulty = profile.current_difficulty if profile else request.difficulty

    # Write next_state_vector now that we have the committed post-EMA profile
    if profile and profile.state_vector:
        scenario_result.next_state_vector = list(profile.state_vector)
        await db.commit()

    # Generate encouragement message
    message = generate_encouragement(success=request.success, emotions=emotions)

    return SubmitScenarioResponse(
        emotions=emotions,
        reward=reward,
        updated_difficulty=updated_difficulty,
        message=message,
        force_ended=force_ended, 
    )
