"""Tests for session management endpoints.

Integration tests covering full session lifecycle including:
- Session start (happy path and error cases)
- Session end (happy path and error cases)
- Full lifecycle flow
- Multiple sessions per user
- Redis cache verification with TTL checks
"""
import pytest
from httpx import AsyncClient
import redis.asyncio as redis


@pytest.mark.asyncio
async def test_start_session_returns_200(test_client: AsyncClient):
    """Test that starting a session returns 200 with session details."""
    # Register a user first
    reg_response = await test_client.post(
        "/api/users/register",
        json={"age": 9, "severity_level": 2}
    )
    assert reg_response.status_code == 201
    user_id = reg_response.json()["user_id"]

    # Start session
    response = await test_client.post(
        "/api/sessions/start",
        json={"user_id": user_id}
    )
    assert response.status_code == 200

    data = response.json()
    assert "session_id" in data
    assert data["user_id"] == user_id
    assert "started_at" in data
    assert data["scenarios_completed"] == 0


@pytest.mark.asyncio
async def test_start_session_user_not_found(test_client: AsyncClient):
    """Test that starting session with non-existent user returns 404."""
    fake_user_id = "00000000-0000-0000-0000-000000000000"
    response = await test_client.post(
        "/api/sessions/start",
        json={"user_id": fake_user_id}
    )
    assert response.status_code == 404

    data = response.json()
    assert "error" in data
    assert data["error"]["code"] == "USER_NOT_FOUND"


@pytest.mark.asyncio
async def test_end_session_returns_200(test_client: AsyncClient):
    """Test that ending a session returns 200 with final metrics."""
    # Register user and start session
    reg_response = await test_client.post(
        "/api/users/register",
        json={"age": 9, "severity_level": 2}
    )
    user_id = reg_response.json()["user_id"]

    start_response = await test_client.post(
        "/api/sessions/start",
        json={"user_id": user_id}
    )
    session_id = start_response.json()["session_id"]

    # End session
    response = await test_client.post(
        f"/api/sessions/{session_id}/end"
    )
    assert response.status_code == 200

    data = response.json()
    assert data["session_id"] == session_id
    assert "ended_at" in data
    assert data["ended_at"] is not None
    assert "scenarios_completed" in data
    assert "message" in data


@pytest.mark.asyncio
async def test_end_session_not_found(test_client: AsyncClient):
    """Test that ending non-existent session returns 404."""
    fake_session_id = "00000000-0000-0000-0000-000000000000"
    response = await test_client.post(
        f"/api/sessions/{fake_session_id}/end"
    )
    assert response.status_code == 404

    data = response.json()
    assert "error" in data
    assert data["error"]["code"] == "SESSION_NOT_FOUND"


@pytest.mark.asyncio
async def test_end_session_already_ended(test_client: AsyncClient):
    """Test that ending an already-ended session returns 400."""
    # Register user and start session
    reg_response = await test_client.post(
        "/api/users/register",
        json={"age": 9, "severity_level": 2}
    )
    user_id = reg_response.json()["user_id"]

    start_response = await test_client.post(
        "/api/sessions/start",
        json={"user_id": user_id}
    )
    session_id = start_response.json()["session_id"]

    # End session first time (should succeed)
    first_end = await test_client.post(
        f"/api/sessions/{session_id}/end"
    )
    assert first_end.status_code == 200

    # End session second time (should fail)
    second_end = await test_client.post(
        f"/api/sessions/{session_id}/end"
    )
    assert second_end.status_code == 400

    data = second_end.json()
    assert "error" in data
    assert data["error"]["code"] == "SESSION_ALREADY_ENDED"


@pytest.mark.asyncio
async def test_session_lifecycle_full(test_client: AsyncClient):
    """Test full session lifecycle: register -> get profile -> start -> end -> get profile."""
    # Step 1: Register user
    reg_response = await test_client.post(
        "/api/users/register",
        json={"age": 9, "severity_level": 2}
    )
    assert reg_response.status_code == 201
    user_id = reg_response.json()["user_id"]

    # Step 2: Get initial profile
    profile1_response = await test_client.get(
        f"/api/users/{user_id}/profile"
    )
    assert profile1_response.status_code == 200
    initial_profile = profile1_response.json()
    assert initial_profile["user_id"] == user_id

    # Step 3: Start session
    start_response = await test_client.post(
        "/api/sessions/start",
        json={"user_id": user_id}
    )
    assert start_response.status_code == 200
    session_id = start_response.json()["session_id"]

    # Step 4: End session
    end_response = await test_client.post(
        f"/api/sessions/{session_id}/end"
    )
    assert end_response.status_code == 200

    # Step 5: Get profile again (should still be accessible)
    profile2_response = await test_client.get(
        f"/api/users/{user_id}/profile"
    )
    assert profile2_response.status_code == 200
    final_profile = profile2_response.json()
    assert final_profile["user_id"] == user_id


@pytest.mark.asyncio
async def test_start_multiple_sessions_same_user(test_client: AsyncClient):
    """Test that a user can have multiple sessions."""
    # Register user
    reg_response = await test_client.post(
        "/api/users/register",
        json={"age": 9, "severity_level": 2}
    )
    user_id = reg_response.json()["user_id"]

    # Start first session
    session1_response = await test_client.post(
        "/api/sessions/start",
        json={"user_id": user_id}
    )
    assert session1_response.status_code == 200
    session1_id = session1_response.json()["session_id"]

    # Start second session
    session2_response = await test_client.post(
        "/api/sessions/start",
        json={"user_id": user_id}
    )
    assert session2_response.status_code == 200
    session2_id = session2_response.json()["session_id"]

    # Verify they have different IDs
    assert session1_id != session2_id


@pytest.mark.asyncio
async def test_session_caches_profile_in_redis(
    test_client: AsyncClient,
    test_redis: redis.Redis
):
    """Test that starting a session caches profile in Redis with ~1800s TTL."""
    # Register user
    reg_response = await test_client.post(
        "/api/users/register",
        json={"age": 9, "severity_level": 2}
    )
    user_id = reg_response.json()["user_id"]

    # Start session (should cache profile)
    start_response = await test_client.post(
        "/api/sessions/start",
        json={"user_id": user_id}
    )
    assert start_response.status_code == 200

    # Check Redis for cached profile
    cache_key = f"profile:{user_id}"
    cached_data = await test_redis.get(cache_key)
    assert cached_data is not None, "Profile should be cached in Redis"

    # Check TTL (should be approximately 1800 seconds)
    ttl = await test_redis.ttl(cache_key)
    assert ttl > 1700, f"TTL {ttl} should be > 1700 seconds"
    assert ttl <= 1800, f"TTL {ttl} should be <= 1800 seconds"
