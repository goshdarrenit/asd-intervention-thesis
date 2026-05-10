"""HTTP client and CrewAI tools for driving live game sessions during validation.

Validation test users are created idempotently via try-login-then-register.
Tokens are minted directly using create_access_token (same process as FastAPI app).
"""
import os
import httpx
from crewai.tools import BaseTool

from app.core.security import create_access_token

BASE_URL = os.getenv("VALIDATION_API_BASE_URL", "http://localhost:8000")


def _make_token(user_id: str) -> str:
    return create_access_token(sub=f"user:{user_id}")


def check_backend_health() -> bool:
    try:
        r = httpx.get(f"{BASE_URL}/health", timeout=5.0)
        return r.status_code == 200
    except (httpx.ConnectError, httpx.TimeoutException):
        return False


def ensure_test_user(persona_name: str, age: int, severity_level: int) -> str:
    """Create or retrieve a deterministic test user for this persona.

    Uses a fixed email/password so runs are idempotent.
    Returns user_id as a string.
    """
    email = f"validation.{persona_name}@asd-thesis.test"
    password = "ValidationPass123!"

    # Try login first (user already exists from a previous run)
    r = httpx.post(
        f"{BASE_URL}/api/auth/login",
        json={"email": email, "password": password},
        timeout=10.0,
    )
    if r.status_code == 200:
        return str(r.json()["user_id"])

    # Not found — register
    r = httpx.post(
        f"{BASE_URL}/api/auth/register",
        json={
            "email": email,
            "password": password,
            "age": age,
            "severity_level": severity_level,
        },
        timeout=10.0,
    )
    r.raise_for_status()
    return str(r.json()["user_id"])


def reset_test_user_profile(user_id: str, starting_difficulty: int = 3) -> None:
    """Reset a validation test user's profile to clean defaults at the given starting difficulty."""
    r = httpx.post(
        f"{BASE_URL}/api/validation/reset-profile",
        json={"user_id": user_id, "starting_difficulty": starting_difficulty},
        timeout=10.0,
    )
    r.raise_for_status()


class StartSessionTool(BaseTool):
    name: str = "start_session"
    description: str = "Start a new game session for a user. Returns the session_id string."

    def _run(self, user_id: str) -> str:
        token = _make_token(user_id)
        r = httpx.post(
            f"{BASE_URL}/api/sessions/start",
            json={"user_id": user_id, "platform": "validation"},
            headers={"Authorization": f"Bearer {token}"},
            timeout=15.0,
        )
        r.raise_for_status()
        return r.json()["session_id"]


class GetNextScenarioTool(BaseTool):
    name: str = "get_next_scenario"
    description: str = (
        "Get the next scenario assignment from the RL model for a session. "
        "Returns JSON string with: scenario_type, difficulty, complexity, reinforcement_mode."
    )

    def _run(self, user_id: str, session_id: str) -> str:
        token = _make_token(user_id)
        r = httpx.post(
            f"{BASE_URL}/api/v1/scenarios/next",
            json={"user_id": user_id, "session_id": session_id},
            headers={"Authorization": f"Bearer {token}"},
            timeout=15.0,
        )
        r.raise_for_status()
        return r.text


class SubmitScenarioTool(BaseTool):
    name: str = "submit_scenario"
    description: str = (
        "Submit scenario results with behavioral telemetry. "
        "Returns JSON string with: emotions, reward, updated_difficulty, message, force_ended."
    )

    def _run(
        self,
        user_id: str,
        session_id: str,
        scenario_type: str,
        difficulty: int,
        complexity: str,
        reinforcement_mode: str,
        success: bool,
        completion_time_ms: int,
        pause_count: int,
        retry_count: int,
        hesitation_pattern: int,
        quit_attempts: int,
    ) -> str:
        token = _make_token(user_id)
        r = httpx.post(
            f"{BASE_URL}/api/v1/scenarios/submit",
            json={
                "user_id": user_id,
                "session_id": session_id,
                "scenario_type": scenario_type,
                "difficulty": difficulty,
                "complexity": complexity,
                "reinforcement_mode": reinforcement_mode,
                "success": success,
                "completion_time_ms": completion_time_ms,
                "telemetry": {
                    "pause_count": pause_count,
                    "retry_count": retry_count,
                    "hesitation_pattern": hesitation_pattern,
                    "quit_attempts": quit_attempts,
                    "action_counts": {},
                    "decision_timestamps_ms": [],
                },
            },
            headers={"Authorization": f"Bearer {token}"},
            timeout=15.0,
        )
        # 400 means session was already force-ended by a prior submit
        if r.status_code == 400:
            return '{"force_ended": true, "already_ended": true}'
        r.raise_for_status()
        return r.text


class EndSessionTool(BaseTool):
    name: str = "end_session"
    description: str = "End a game session. Returns JSON string with final session metrics."

    def _run(self, user_id: str, session_id: str) -> str:
        token = _make_token(user_id)
        r = httpx.post(
            f"{BASE_URL}/api/sessions/{session_id}/end",
            headers={"Authorization": f"Bearer {token}"},
            timeout=15.0,
        )
        # 400 = session already ended (e.g. force-ended)
        if r.status_code == 400:
            return '{"already_ended": true}'
        r.raise_for_status()
        return r.text
