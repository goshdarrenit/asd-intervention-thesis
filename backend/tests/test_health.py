"""Tests for health check endpoint."""
import pytest
from httpx import AsyncClient


@pytest.mark.asyncio
async def test_health_endpoint_returns_200(test_client: AsyncClient):
    """Test that health endpoint returns 200 with all checks."""
    response = await test_client.get("/health")
    assert response.status_code == 200

    data = response.json()
    assert data["status"] == "healthy"
    assert "checks" in data
    assert "database" in data["checks"]
    assert "redis" in data["checks"]
    assert data["checks"]["database"] == "healthy"
    assert data["checks"]["redis"] == "healthy"


@pytest.mark.asyncio
async def test_health_shows_rl_model_status(test_client: AsyncClient):
    """Test that health endpoint includes RL model status."""
    response = await test_client.get("/health")
    data = response.json()

    assert "rl_model" in data["checks"]
    assert data["checks"]["rl_model"] in ["loaded", "not_loaded"]
