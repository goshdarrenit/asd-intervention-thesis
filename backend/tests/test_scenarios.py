"""Tests for scenario API endpoints.

Integration tests covering:
- POST /api/v1/scenarios/next
- POST /api/v1/scenarios/submit
- Emotion inference integration
- Profile EMA updates
- ScenarioResult persistence
"""
import pytest
from httpx import AsyncClient
from sqlalchemy import select

from app.domains.sessions.models import ScenarioResult


@pytest.mark.asyncio
async def test_next_scenario_returns_200(test_client: AsyncClient):
    """Test that requesting next scenario returns 200 with valid configuration."""
    # Register a user first
    reg_response = await test_client.post(
        "/api/users/register",
        json={"age": 9, "severity_level": 2},
    )
    assert reg_response.status_code == 201
    user_id = reg_response.json()["user_id"]

    # Start session
    session_response = await test_client.post(
        "/api/sessions/start",
        json={"user_id": user_id},
    )
    assert session_response.status_code == 200
    session_id = session_response.json()["session_id"]

    # Request next scenario
    response = await test_client.post(
        "/api/v1/scenarios/next",
        json={"user_id": user_id, "session_id": session_id},
    )
    assert response.status_code == 200

    data = response.json()
    assert "scenario_type" in data
    assert data["scenario_type"] in [
        "sharing",
        "patience",
        "emotion_recognition",
        "turn_taking",
        "conflict_resolution",
    ]
    assert "difficulty" in data
    assert 1 <= data["difficulty"] <= 5
    assert "complexity" in data
    assert data["complexity"] in ["low", "medium", "high"]
    assert "reinforcement_mode" in data
    assert data["reinforcement_mode"] in ["positive", "neutral", "corrective"]
    assert data["session_id"] == session_id


@pytest.mark.asyncio
async def test_next_scenario_user_not_found(test_client: AsyncClient):
    """Test that requesting scenario with non-existent user returns 404."""
    fake_user_id = "00000000-0000-0000-0000-000000000000"
    fake_session_id = "00000000-0000-0000-0000-000000000001"

    response = await test_client.post(
        "/api/v1/scenarios/next",
        json={"user_id": fake_user_id, "session_id": fake_session_id},
    )
    assert response.status_code == 404

    data = response.json()
    assert "detail" in data
    assert data["detail"]["error"]["code"] == "USER_NOT_FOUND"


@pytest.mark.asyncio
async def test_next_scenario_without_model_returns_fallback(test_client: AsyncClient):
    """Test that endpoint returns fallback values when RL model not loaded.

    In test environment, model is typically not loaded. Verify graceful fallback.
    """
    # Register a user
    reg_response = await test_client.post(
        "/api/users/register",
        json={"age": 10, "severity_level": 2},
    )
    user_id = reg_response.json()["user_id"]

    # Start session
    session_response = await test_client.post(
        "/api/sessions/start",
        json={"user_id": user_id},
    )
    session_id = session_response.json()["session_id"]

    # Request next scenario (should fall back to random selection)
    response = await test_client.post(
        "/api/v1/scenarios/next",
        json={"user_id": user_id, "session_id": session_id},
    )

    # Should still return 200 with valid fallback values
    assert response.status_code == 200
    data = response.json()
    assert data["scenario_type"] in [
        "sharing",
        "patience",
        "emotion_recognition",
        "turn_taking",
        "conflict_resolution",
    ]
    assert 1 <= data["difficulty"] <= 5


@pytest.mark.asyncio
async def test_submit_scenario_returns_200(test_client: AsyncClient):
    """Test that submitting scenario results returns 200 with feedback."""
    # Register user and start session
    reg_response = await test_client.post(
        "/api/users/register",
        json={"age": 9, "severity_level": 2},
    )
    user_id = reg_response.json()["user_id"]

    session_response = await test_client.post(
        "/api/sessions/start",
        json={"user_id": user_id},
    )
    session_id = session_response.json()["session_id"]

    # Submit scenario result with telemetry
    telemetry = {
        "pause_count": 2,
        "retry_count": 1,
        "quit_attempts": 0,
        "hesitation_pattern": 3000,  # 3 seconds in ms
        "action_counts": {},
        "decision_timestamps_ms": [],
    }

    response = await test_client.post(
        "/api/v1/scenarios/submit",
        json={
            "user_id": user_id,
            "session_id": session_id,
            "scenario_type": "sharing",
            "difficulty": 2,
            "complexity": "medium",
            "reinforcement_mode": "positive",
            "success": True,
            "completion_time_ms": 25000,
            "telemetry": telemetry,
        },
    )
    assert response.status_code == 200

    data = response.json()
    assert "emotions" in data
    assert "frustration" in data["emotions"]
    assert "engagement" in data["emotions"]
    assert "confidence" in data["emotions"]
    assert 0.0 <= data["emotions"]["frustration"] <= 1.0
    assert 0.0 <= data["emotions"]["engagement"] <= 1.0
    assert 0.0 <= data["emotions"]["confidence"] <= 1.0

    assert "reward" in data
    assert 0.0 <= data["reward"] <= 1.0

    assert "updated_difficulty" in data
    assert 1 <= data["updated_difficulty"] <= 5

    assert "message" in data
    assert len(data["message"]) > 0


@pytest.mark.asyncio
async def test_submit_scenario_persists_result(test_client: AsyncClient, test_db):
    """Test that submitting scenario creates ScenarioResult record in DB."""
    # Register user and start session
    reg_response = await test_client.post(
        "/api/users/register",
        json={"age": 9, "severity_level": 2},
    )
    user_id = reg_response.json()["user_id"]

    session_response = await test_client.post(
        "/api/sessions/start",
        json={"user_id": user_id},
    )
    session_id = session_response.json()["session_id"]

    # Submit scenario
    telemetry = {
        "pause_count": 1,
        "retry_count": 0,
        "quit_attempts": 0,
        "hesitation_pattern": 2000,
        "action_counts": {},
        "decision_timestamps_ms": [],
    }

    await test_client.post(
        "/api/v1/scenarios/submit",
        json={
            "user_id": user_id,
            "session_id": session_id,
            "scenario_type": "patience",
            "difficulty": 3,
            "complexity": "low",
            "reinforcement_mode": "positive",
            "success": True,
            "completion_time_ms": 20000,
            "telemetry": telemetry,
        },
    )

    # Query DB for scenario result
    result = await test_db.execute(
        select(ScenarioResult).where(ScenarioResult.session_id == session_id)
    )
    scenario_results = result.scalars().all()

    assert len(scenario_results) == 1
    scenario_result = scenario_results[0]
    assert scenario_result.scenario_type == "patience"
    assert scenario_result.difficulty == 3
    assert scenario_result.completed is True
    assert scenario_result.emotions is not None
    assert "frustration" in scenario_result.emotions


@pytest.mark.asyncio
async def test_submit_scenario_updates_profile_ema(test_client: AsyncClient):
    """Test that submitting scenario updates user profile via EMA."""
    # Register user
    reg_response = await test_client.post(
        "/api/users/register",
        json={"age": 9, "severity_level": 2},
    )
    user_id = reg_response.json()["user_id"]

    # Get initial profile
    profile_response = await test_client.get(f"/api/users/{user_id}/profile")
    initial_profile = profile_response.json()
    initial_scenarios = initial_profile["scenarios_completed"]
    initial_success_rate = initial_profile["overall_success_rate"]

    # Start session
    session_response = await test_client.post(
        "/api/sessions/start",
        json={"user_id": user_id},
    )
    session_id = session_response.json()["session_id"]

    # Submit successful scenario
    telemetry = {
        "pause_count": 0,
        "retry_count": 0,
        "quit_attempts": 0,
        "hesitation_pattern": 2500,
        "action_counts": {},
        "decision_timestamps_ms": [],
    }

    await test_client.post(
        "/api/v1/scenarios/submit",
        json={
            "user_id": user_id,
            "session_id": session_id,
            "scenario_type": "sharing",
            "difficulty": 2,
            "complexity": "medium",
            "reinforcement_mode": "positive",
            "success": True,
            "completion_time_ms": 18000,
            "telemetry": telemetry,
        },
    )

    # Get updated profile
    updated_profile_response = await test_client.get(f"/api/users/{user_id}/profile")
    updated_profile = updated_profile_response.json()

    # Verify EMA updates
    assert updated_profile["scenarios_completed"] == initial_scenarios + 1
    # Success rate should have changed (EMA applied)
    # With success=True, new observation=1.0, so success_rate should increase
    assert updated_profile["overall_success_rate"] != initial_success_rate


@pytest.mark.asyncio
async def test_submit_with_high_frustration_telemetry(test_client: AsyncClient):
    """Test that high frustration telemetry produces high frustration score."""
    # Register user and start session
    reg_response = await test_client.post(
        "/api/users/register",
        json={"age": 9, "severity_level": 2},
    )
    user_id = reg_response.json()["user_id"]

    session_response = await test_client.post(
        "/api/sessions/start",
        json={"user_id": user_id},
    )
    session_id = session_response.json()["session_id"]

    # Submit with high frustration indicators
    telemetry = {
        "pause_count": 5,  # Many pauses
        "retry_count": 4,  # Many retries
        "quit_attempts": 1,  # Attempted to quit
        "hesitation_pattern": 8000,  # Long hesitation
        "action_counts": {},
        "decision_timestamps_ms": [],
    }

    response = await test_client.post(
        "/api/v1/scenarios/submit",
        json={
            "user_id": user_id,
            "session_id": session_id,
            "scenario_type": "conflict_resolution",
            "difficulty": 4,
            "complexity": "high",
            "reinforcement_mode": "corrective",
            "success": False,
            "completion_time_ms": 60000,
            "telemetry": telemetry,
        },
    )
    assert response.status_code == 200

    data = response.json()
    # High frustration expected
    assert data["emotions"]["frustration"] > 0.5

    # Message should be supportive
    assert "tricky" in data["message"].lower() or "time" in data["message"].lower()


@pytest.mark.asyncio
async def test_submit_with_success_telemetry(test_client: AsyncClient):
    """Test that clean completion produces low frustration and high reward."""
    # Register user and start session
    reg_response = await test_client.post(
        "/api/users/register",
        json={"age": 9, "severity_level": 2},
    )
    user_id = reg_response.json()["user_id"]

    session_response = await test_client.post(
        "/api/sessions/start",
        json={"user_id": user_id},
    )
    session_id = session_response.json()["session_id"]

    # Submit with clean completion indicators
    telemetry = {
        "pause_count": 0,  # No pauses
        "retry_count": 0,  # No retries
        "quit_attempts": 0,  # No quit attempts
        "hesitation_pattern": 2000,  # Quick decision
        "action_counts": {},
        "decision_timestamps_ms": [],
    }

    response = await test_client.post(
        "/api/v1/scenarios/submit",
        json={
            "user_id": user_id,
            "session_id": session_id,
            "scenario_type": "emotion_recognition",
            "difficulty": 2,
            "complexity": "medium",
            "reinforcement_mode": "positive",
            "success": True,
            "completion_time_ms": 15000,  # Fast completion
            "telemetry": telemetry,
        },
    )
    assert response.status_code == 200

    data = response.json()
    # Low frustration expected
    assert data["emotions"]["frustration"] < 0.3

    # High reward expected (success + fast time + low frustration)
    assert data["reward"] > 0.8
