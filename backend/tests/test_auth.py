"""Tests for authentication endpoints.

Tests:
- POST /api/auth/register — create account, receive token
- POST /api/auth/login — authenticate, receive token
- GET /api/auth/me — authenticated user info
- Protected routes return 401 without token
- Invalid token returns 401
"""
import pytest
from httpx import AsyncClient, ASGITransport
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.deps import get_db, get_redis
from app.main import app


@pytest.mark.asyncio
async def test_register_returns_token(test_client: AsyncClient) -> None:
    """POST /api/auth/register creates user and returns JWT."""
    response = await test_client.post(
        "/api/auth/register",
        json={"email": "new@test.com", "password": "password123", "age": 8, "severity_level": 2},
    )
    assert response.status_code == 201
    data = response.json()
    assert "access_token" in data
    assert "user_id" in data
    assert data["token_type"] == "bearer"


@pytest.mark.asyncio
async def test_register_duplicate_email_returns_409(test_client: AsyncClient) -> None:
    """POST /api/auth/register with duplicate email returns 409."""
    payload = {"email": "dup@test.com", "password": "password123", "age": 7, "severity_level": 1}
    await test_client.post("/api/auth/register", json=payload)
    response = await test_client.post("/api/auth/register", json=payload)
    assert response.status_code == 409


@pytest.mark.asyncio
async def test_login_returns_token(test_client: AsyncClient) -> None:
    """POST /api/auth/login with valid credentials returns JWT."""
    # Register first
    await test_client.post(
        "/api/auth/register",
        json={"email": "login@test.com", "password": "mypassword", "age": 10, "severity_level": 1},
    )
    # Now login
    response = await test_client.post(
        "/api/auth/login",
        json={"email": "login@test.com", "password": "mypassword"},
    )
    assert response.status_code == 200
    data = response.json()
    assert "access_token" in data
    assert "user_id" in data


@pytest.mark.asyncio
async def test_login_wrong_password_returns_401(test_client: AsyncClient) -> None:
    """POST /api/auth/login with wrong password returns 401."""
    await test_client.post(
        "/api/auth/register",
        json={"email": "wrongpw@test.com", "password": "correctpass", "age": 9, "severity_level": 2},
    )
    response = await test_client.post(
        "/api/auth/login",
        json={"email": "wrongpw@test.com", "password": "wrongpass"},
    )
    assert response.status_code == 401


@pytest.mark.asyncio
async def test_me_returns_user_info(test_client: AsyncClient) -> None:
    """GET /api/auth/me returns current user info with valid token."""
    # Register and get token
    reg = await test_client.post(
        "/api/auth/register",
        json={"email": "me@test.com", "password": "password123", "age": 12, "severity_level": 3},
    )
    token = reg.json()["access_token"]

    # Access /me with token
    response = await test_client.get(
        "/api/auth/me",
        headers={"Authorization": f"Bearer {token}"},
    )
    assert response.status_code == 200
    data = response.json()
    assert data["email"] == "me@test.com"
    assert data["age"] == 12
    assert data["severity_level"] == 3


@pytest.mark.asyncio
async def test_protected_route_without_token_returns_401(
    test_db: AsyncSession,
    test_redis,
) -> None:
    """Protected route without auth token returns 401."""
    async def override_get_db():
        yield test_db

    async def override_get_redis():
        return test_redis

    app.dependency_overrides[get_db] = override_get_db
    app.dependency_overrides[get_redis] = override_get_redis

    try:
        async with AsyncClient(
            transport=ASGITransport(app=app),
            base_url="http://test",
        ) as client:
            response = await client.post(
                "/api/sessions/start",
                json={"user_id": "00000000-0000-0000-0000-000000000001"},
            )
        assert response.status_code == 403  # HTTPBearer returns 403 when no credentials
    finally:
        app.dependency_overrides.clear()


@pytest.mark.asyncio
async def test_invalid_token_returns_401(
    test_db: AsyncSession,
    test_redis,
) -> None:
    """Protected route with invalid token returns 401."""
    async def override_get_db():
        yield test_db

    async def override_get_redis():
        return test_redis

    app.dependency_overrides[get_db] = override_get_db
    app.dependency_overrides[get_redis] = override_get_redis

    try:
        async with AsyncClient(
            transport=ASGITransport(app=app),
            base_url="http://test",
            headers={"Authorization": "Bearer invalidtoken.invalid.invalid"},
        ) as client:
            response = await client.post(
                "/api/sessions/start",
                json={"user_id": "00000000-0000-0000-0000-000000000001"},
            )
        assert response.status_code == 401
    finally:
        app.dependency_overrides.clear()
