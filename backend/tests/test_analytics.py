"""
Analytics API test suite.

Implementation lives in backend/app/api/routes/analytics.py.
"""
import asyncio

import pytest
import pytest_asyncio
from httpx import ASGITransport, AsyncClient
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.deps import get_db, get_redis
from app.main import app


# ---------------------------------------------------------------------------
# Fixtures — async_client, test_user, auth_headers
# ---------------------------------------------------------------------------


@pytest_asyncio.fixture
async def async_client(test_db: AsyncSession, test_redis):
    """Unauthenticated AsyncClient with DB/Redis overrides."""

    async def override_get_db():
        yield test_db

    async def override_get_redis():
        return test_redis

    app.dependency_overrides[get_db] = override_get_db
    app.dependency_overrides[get_redis] = override_get_redis

    async with AsyncClient(
        transport=ASGITransport(app=app),
        base_url="http://test",
    ) as client:
        yield client

    app.dependency_overrides.clear()


@pytest_asyncio.fixture
async def test_user(async_client: AsyncClient) -> dict:
    """Register a test user via API and return {user_id, access_token}."""
    resp = await async_client.post(
        "/api/auth/register",
        json={
            "email": "analytics_test@test.com",
            "password": "testpass123",
            "age": 9,
            "severity_level": 2,
        },
    )
    assert resp.status_code == 201, f"Register failed: {resp.text}"
    data = resp.json()
    return {"user_id": data["user_id"], "access_token": data["access_token"]}


@pytest_asyncio.fixture
async def auth_headers(test_user: dict) -> dict:
    """Return Authorization header dict for the test user."""
    return {"Authorization": f"Bearer {test_user['access_token']}"}


# ---------------------------------------------------------------------------
# GET /api/analytics/user/{user_id}
# ---------------------------------------------------------------------------


@pytest.mark.asyncio
async def test_user_analytics(
    async_client: AsyncClient, test_user: dict, auth_headers: dict
):
    """GET /api/analytics/user/{user_id} returns 200 + learning curve data.

    Response must contain: scenarios (list), window_5_success_rate (list),
    emotional_trends (list). Empty list is valid for user with no history.
    Requires Bearer token (401 without auth).
    """
    user_id = test_user["user_id"]

    # Unauthenticated -> 403 (HTTPBearer) or 401
    resp = await async_client.get(f"/api/analytics/user/{user_id}")
    assert resp.status_code in (401, 403), f"Expected 401/403, got {resp.status_code}"

    # Authenticated -> 200
    resp = await async_client.get(
        f"/api/analytics/user/{user_id}", headers=auth_headers
    )
    assert resp.status_code == 200, f"Expected 200, got {resp.status_code}: {resp.text}"
    data = resp.json()
    assert "scenarios" in data
    assert "window_5_success_rate" in data
    assert "emotional_trends" in data
    assert isinstance(data["scenarios"], list)
    assert isinstance(data["window_5_success_rate"], list)
    assert isinstance(data["emotional_trends"], list)


# ---------------------------------------------------------------------------
# GET /api/analytics/rl_agent/performance
# ---------------------------------------------------------------------------


@pytest.mark.asyncio
async def test_rl_performance(async_client: AsyncClient, auth_headers: dict):
    """GET /api/analytics/rl_agent/performance returns 200 + model info.

    Response must contain: model_version (str), training_metrics (dict),
    evaluation_summary (dict or null). Does not require rl_training_logs rows.
    Reads model_store/model_checksums.sha256 for version.
    """
    # Unauthenticated -> 403 or 401
    resp = await async_client.get("/api/analytics/rl_agent/performance")
    assert resp.status_code in (401, 403)

    # Authenticated -> 200
    resp = await async_client.get(
        "/api/analytics/rl_agent/performance", headers=auth_headers
    )
    assert resp.status_code == 200, f"Expected 200, got {resp.status_code}: {resp.text}"
    data = resp.json()
    assert "model_version" in data
    assert "training_metrics" in data
    assert isinstance(data["model_version"], str)
    assert isinstance(data["training_metrics"], dict)


# ---------------------------------------------------------------------------
# 10 concurrent users
# ---------------------------------------------------------------------------


@pytest.mark.asyncio
async def test_concurrent_users(
    async_client: AsyncClient, test_user: dict, auth_headers: dict
):
    """10 concurrent GET /api/analytics/user/{user_id} requests, all return 200.

    Uses asyncio.gather() with httpx.AsyncClient. No 500 errors allowed.
    Measures max latency (informational only — not a hard assertion).
    """
    user_id = test_user["user_id"]
    url = f"/api/analytics/user/{user_id}"

    async def one_request():
        resp = await async_client.get(url, headers=auth_headers)
        return resp.status_code

    codes = await asyncio.gather(*[one_request() for _ in range(10)])
    assert all(c == 200 for c in codes), f"Some requests failed: {codes}"
