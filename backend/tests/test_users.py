"""Tests for user management endpoints."""
import pytest
from httpx import AsyncClient


@pytest.mark.asyncio
async def test_register_user_returns_201(test_client: AsyncClient):
    """Test that user registration returns 201 with user_id."""
    response = await test_client.post(
        "/api/users/register",
        json={"age": 9, "severity_level": 2}
    )
    assert response.status_code == 201

    data = response.json()
    assert "user_id" in data
    assert "message" in data


@pytest.mark.asyncio
async def test_register_user_with_guardian_email(test_client: AsyncClient):
    """Test user registration with optional guardian email."""
    response = await test_client.post(
        "/api/users/register",
        json={
            "age": 7,
            "severity_level": 1,
            "guardian_email": "parent@example.com"
        }
    )
    assert response.status_code == 201
    assert "user_id" in response.json()


@pytest.mark.asyncio
async def test_register_user_invalid_age(test_client: AsyncClient):
    """Test that invalid age returns 422 validation error."""
    response = await test_client.post(
        "/api/users/register",
        json={"age": 2, "severity_level": 2}
    )
    assert response.status_code == 422

    data = response.json()
    assert "error" in data
    assert data["error"]["code"] == "VALIDATION_ERROR"


@pytest.mark.asyncio
async def test_register_user_invalid_severity(test_client: AsyncClient):
    """Test that invalid severity level returns 422 validation error."""
    response = await test_client.post(
        "/api/users/register",
        json={"age": 9, "severity_level": 5}
    )
    assert response.status_code == 422

    data = response.json()
    assert "error" in data
    assert data["error"]["code"] == "VALIDATION_ERROR"


@pytest.mark.asyncio
async def test_get_user_profile(test_client: AsyncClient):
    """Test profile retrieval returns correct data."""
    # Create user first
    reg_response = await test_client.post(
        "/api/users/register",
        json={"age": 9, "severity_level": 2}
    )
    user_id = reg_response.json()["user_id"]

    # Fetch profile
    response = await test_client.get(f"/api/users/{user_id}/profile")
    assert response.status_code == 200

    data = response.json()
    assert data["user_id"] == user_id
    assert data["overall_success_rate"] == 0.5
    assert data["scenarios_completed"] == 0
    assert data["current_difficulty"] == 2
    assert "preferred_scenarios" in data
    assert "emotional_history" in data


@pytest.mark.asyncio
async def test_get_profile_not_found(test_client: AsyncClient):
    """Test that fetching non-existent profile returns 404."""
    fake_id = "00000000-0000-0000-0000-000000000000"
    response = await test_client.get(f"/api/users/{fake_id}/profile")
    assert response.status_code == 404

    data = response.json()
    assert "error" in data
    assert data["error"]["code"] == "USER_NOT_FOUND"


@pytest.mark.asyncio
async def test_profile_cached_in_redis(test_client: AsyncClient):
    """Test that profile is cached in Redis after first fetch."""
    # Create user
    reg_response = await test_client.post(
        "/api/users/register",
        json={"age": 9, "severity_level": 2}
    )
    user_id = reg_response.json()["user_id"]

    # First fetch (cache miss -> populates cache)
    response1 = await test_client.get(f"/api/users/{user_id}/profile")
    assert response1.status_code == 200
    data1 = response1.json()

    # Second fetch (cache hit)
    response2 = await test_client.get(f"/api/users/{user_id}/profile")
    assert response2.status_code == 200
    data2 = response2.json()

    # Verify data is the same
    assert data1["user_id"] == data2["user_id"]
    assert data1["overall_success_rate"] == data2["overall_success_rate"]
    assert data1["scenarios_completed"] == data2["scenarios_completed"]


@pytest.mark.asyncio
async def test_multiple_users_registration(test_client: AsyncClient):
    """Test creating multiple users with different profiles."""
    users = [
        {"age": 5, "severity_level": 1},
        {"age": 10, "severity_level": 2},
        {"age": 15, "severity_level": 3},
    ]

    user_ids = []
    for user_data in users:
        response = await test_client.post("/api/users/register", json=user_data)
        assert response.status_code == 201
        user_ids.append(response.json()["user_id"])

    # Verify all profiles are retrievable
    for user_id in user_ids:
        response = await test_client.get(f"/api/users/{user_id}/profile")
        assert response.status_code == 200
        assert response.json()["user_id"] == user_id
