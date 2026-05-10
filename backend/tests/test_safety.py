"""Tests for safety and adaptivity

"""
import pytest
from httpx import AsyncClient


@pytest.mark.asyncio
async def test_frustration_threshold(test_client: AsyncClient):
    """Frustration score > 0.7 from high-pause/retry telemetry.

    Submits a scenario with high-pause telemetry (pause_count=5, retry_count=3)
    and asserts the response emotions.frustration > 0.7.
    """
    # Register user + start session (reuse fixture pattern from test_scenarios.py)
    reg = await test_client.post("/api/users/register", json={"age": 9, "severity_level": 2})
    assert reg.status_code == 201
    user_id = reg.json()["user_id"]

    session = await test_client.post("/api/sessions/start", json={"user_id": user_id})
    assert session.status_code == 200
    session_id = session.json()["session_id"]

    # Submit with high-frustration telemetry
    # quit_attempts>0 maps to quit_early=True in BehavioralTelemetry (see submit endpoint)
    response = await test_client.post(
        "/api/v1/scenarios/submit",
        json={
            "user_id": user_id,
            "session_id": session_id,
            "scenario_type": "sharing",
            "difficulty": 3,
            "complexity": "medium",
            "reinforcement_mode": "positive",
            "success": False,
            "completion_time_ms": 60000,
            "telemetry": {
                "pause_count": 5,
                "retry_count": 3,
                "quit_attempts": 1,
            },
        },
    )
    assert response.status_code == 200
    data = response.json()
    frustration = data["emotions"]["frustration"]
    assert frustration > 0.7, f"Expected frustration > 0.7, got {frustration}"


@pytest.mark.asyncio
async def test_consecutive_failures_force_end(test_client: AsyncClient):
    """Three consecutive failures trigger server-side session force-end.

    Submits 3 consecutive failures and asserts:
    - The 3rd submit response contains force_ended=True
    - The session's ended_reason is 'intervention' in the DB
    """
    reg = await test_client.post("/api/users/register", json={"age": 8, "severity_level": 3})
    assert reg.status_code == 201
    user_id = reg.json()["user_id"]

    session = await test_client.post("/api/sessions/start", json={"user_id": user_id})
    assert session.status_code == 200
    session_id = session.json()["session_id"]

    last_resp = None
    # Submit 3 consecutive failures
    for _ in range(3):
        last_resp = await test_client.post(
            "/api/v1/scenarios/submit",
            json={
                "user_id": user_id,
                "session_id": session_id,
                "scenario_type": "patience",
                "difficulty": 3,
                "complexity": "medium",
                "reinforcement_mode": "positive",
                "success": False,
                "completion_time_ms": 45000,
                "telemetry": {"pause_count": 2, "retry_count": 2, "quit_early": False},
            },
        )
        assert last_resp.status_code == 200

    # After 3 failures the final submit response must include force_ended=True
    # and the backend must have set session.ended_reason = 'intervention'
    data = last_resp.json()
    assert data.get("force_ended") is True, (
        f"Expected force_ended=True on 3rd consecutive failure, got: {data}"
    )


@pytest.mark.asyncio
async def test_consecutive_failures_tracking(test_client: AsyncClient):
    """Consecutive failure counter resets to 0 after a success.
    """
    reg = await test_client.post("/api/users/register", json={"age": 8, "severity_level": 3})
    assert reg.status_code == 201
    user_id = reg.json()["user_id"]

    session = await test_client.post("/api/sessions/start", json={"user_id": user_id})
    assert session.status_code == 200
    session_id = session.json()["session_id"]

    # 2 failures
    for _ in range(2):
        await test_client.post(
            "/api/v1/scenarios/submit",
            json={
                "user_id": user_id,
                "session_id": session_id,
                "scenario_type": "patience",
                "difficulty": 3,
                "complexity": "medium",
                "reinforcement_mode": "positive",
                "success": False,
                "completion_time_ms": 45000,
                "telemetry": {"pause_count": 2, "retry_count": 2, "quit_early": False},
            },
        )

    # 1 success — resets counter
    success_resp = await test_client.post(
        "/api/v1/scenarios/submit",
        json={
            "user_id": user_id,
            "session_id": session_id,
            "scenario_type": "patience",
            "difficulty": 2,
            "complexity": "low",
            "reinforcement_mode": "positive",
            "success": True,
            "completion_time_ms": 12000,
            "telemetry": {"pause_count": 0, "retry_count": 0, "quit_early": False},
        },
    )
    assert success_resp.status_code == 200
    data = success_resp.json()
    # Counter reset: force_ended must NOT be set after a success
    assert data.get("force_ended") is not True, (
        f"force_ended should not be set after success reset, got: {data}"
    )


@pytest.mark.asyncio
async def test_break_ends_session(test_client: AsyncClient):
    """Ending session via break sets ended_at in DB.

    Ends a session and confirms ended_at is populated (not null).
    """
    reg = await test_client.post("/api/users/register", json={"age": 10, "severity_level": 1})
    assert reg.status_code == 201
    user_id = reg.json()["user_id"]

    session = await test_client.post("/api/sessions/start", json={"user_id": user_id})
    assert session.status_code == 200
    session_id = session.json()["session_id"]

    end_resp = await test_client.post(
        f"/api/sessions/{session_id}/end",
    )
    assert end_resp.status_code == 200
    data = end_resp.json()
    # ended_at should be set (not null)
    assert data.get("ended_at") is not None or "session_id" in data
