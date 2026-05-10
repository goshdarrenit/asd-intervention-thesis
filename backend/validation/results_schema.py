"""Pydantic result models for the CrewAI validation framework."""
from pydantic import BaseModel, Field


class TelemetryDecision(BaseModel):
    """Structured behavioral decision produced by a persona LLM agent for one scenario."""
    success: bool
    completion_time_ms: int = Field(ge=2000, le=180000)
    pause_count: int = Field(ge=0, le=25)
    retry_count: int = Field(ge=0, le=15)
    hesitation_pattern: int = Field(ge=500, le=30000, description="mean decision time in ms")
    quit_attempts: int = Field(ge=0, le=1)
    reasoning: str = Field(description="one sentence explaining behavioral choices")


class PersonaRating(BaseModel):
    persona: str
    score: int = Field(ge=1, le=5)
    justification: str
    dimension_scores: "DimensionScores | None" = None


class DimensionScores(BaseModel):
    emotion_accuracy: int = Field(ge=1, le=5)
    difficulty_progression: int = Field(ge=1, le=5)
    reinforcement_appropriateness: int = Field(ge=1, le=5)
    force_end_correctness: int = Field(ge=1, le=5, default=3)


class ScenarioInteraction(BaseModel):
    scenario_number: int
    scenario_type: str
    difficulty: int
    complexity: str
    reinforcement_mode: str
    telemetry: dict
    system_response: dict


class PersonaSessionResult(BaseModel):
    persona: str
    user_id: str
    session_id: str
    scenarios: list[ScenarioInteraction]
    force_ended: bool
    final_metrics: dict


class TrialResult(BaseModel):
    scenario_id: str
    persona_ratings: list[PersonaRating]


class SupervisorReport(BaseModel):
    scenario_id: str
    persona_ratings: list[PersonaRating]
    mean_score: float
    safety_flags: list[str]
    recommendation: str  # "approve" | "revise" | "reject"
    session_results: list[PersonaSessionResult] | None = None
    adaptation_summary: str | None = None


PersonaRating.model_rebuild()
