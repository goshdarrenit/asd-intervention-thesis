"""RL inference API routes."""

from typing import Annotated

import numpy as np
from fastapi import APIRouter, HTTPException, status
from pydantic import BaseModel, Field, field_validator

from app.core.lifespan import app_state

# Create router
router = APIRouter(prefix="/api/v1/rl", tags=["rl"])


class PredictRequest(BaseModel):
    """Request schema for RL prediction endpoint."""

    state_vector: list[float] = Field(
        ...,
        description="60-dimensional state vector representing user state",
        min_length=60,
        max_length=60,
    )

    @field_validator("state_vector")
    @classmethod
    def validate_state_vector_length(cls, v: list[float]) -> list[float]:
        """Validate state vector has exactly 60 dimensions."""
        if len(v) != 60:
            raise ValueError(f"state_vector must have exactly 60 elements, got {len(v)}")
        return v


class PredictResponse(BaseModel):
    """Response schema for RL prediction endpoint."""

    action_index: int = Field(..., description="Flat action index (0-224)")
    action_type: str = Field(..., description="Scenario type")
    difficulty_delta: int = Field(..., description="Difficulty adjustment (-2 to +2)")
    reinforcement_mode: str = Field(..., description="Reinforcement strategy")
    complexity_level: str = Field(..., description="Complexity level")
    latency_ms: float = Field(..., description="Prediction latency in milliseconds")


@router.post("/predict", response_model=PredictResponse)
async def predict_action(request: PredictRequest) -> PredictResponse:
    """Predict next action from current user state.

    This endpoint uses the trained PPO model to predict the optimal action
    (scenario + difficulty + reinforcement + complexity) given the current
    user state vector.

    Args:
        request: PredictRequest containing 60-dim state vector

    Returns:
        PredictResponse with predicted action components and latency

    Raises:
        HTTPException 503: If RL model is not loaded
        HTTPException 422: If state_vector validation fails

    Example:
        ```python
        response = await client.post("/api/v1/rl/predict", json={
            "state_vector": [0.5, 0.3, ...] # 60 floats
        })
        # response.json() = {
        #     "action_index": 42,
        #     "action_type": "sharing",
        #     "difficulty_delta": 0,
        #     "reinforcement_mode": "positive",
        #     "complexity_level": "medium",
        #     "latency_ms": 12.34
        # }
        ```
    """
    # Check if model is loaded
    if not app_state.get("model_loaded", False):
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail={
                "error": {
                    "message": "RL model not loaded",
                    "code": "MODEL_NOT_LOADED",
                }
            },
        )

    # Get predictor from app state
    predictor = app_state["rl_predictor"]

    # Convert state vector to numpy array and predict
    state_array = np.array(request.state_vector, dtype=np.float32)
    result = predictor.predict(state_array, deterministic=True)

    # Extract decoded action components
    decoded = result["decoded_action"]

    return PredictResponse(
        action_index=result["action_index"],
        action_type=decoded["action_type"],
        difficulty_delta=decoded["difficulty_delta"],
        reinforcement_mode=decoded["reinforcement_mode"],
        complexity_level=decoded["complexity_level"],
        latency_ms=result["latency_ms"],
    )
