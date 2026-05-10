"""CrewAI validation framework."""
import pytest
import pytest_asyncio
from unittest.mock import AsyncMock, MagicMock, patch
from httpx import AsyncClient, ASGITransport

from validation.results_schema import PersonaRating, SupervisorReport
from validation.persona_agents import build_persona_agents
from validation.runner import run_trial
from app.main import app


# --- Schema validation ---
def test_schemas():
    rating = PersonaRating(persona="low_verbal", score=3, justification="Seems okay")
    assert rating.score == 3
    report = SupervisorReport(
        scenario_id="sharing_peer_conflict",
        persona_ratings=[rating],
        mean_score=3.0,
        safety_flags=[],
        recommendation="approve",
    )
    assert report.recommendation in ("approve", "revise", "reject")


# --- Persona agents constructable without API call ---
def test_persona_agents_build():
    mock_llm = MagicMock()
    agents = build_persona_agents(mock_llm)
    assert len(agents) == 5
    roles = [a.role for a in agents]
    assert len(set(roles)) == 5  # all distinct roles


# --- run_trial returns SupervisorReport ---
@pytest.mark.asyncio
async def test_run_trial_returns_report():
    mock_rating = PersonaRating(persona="low_verbal", score=4, justification="Good")
    mock_report = SupervisorReport(
        scenario_id="sharing_peer_conflict",
        persona_ratings=[mock_rating],
        mean_score=4.0,
        safety_flags=[],
        recommendation="approve",
    )
    mock_crew_output = MagicMock()
    mock_crew_output.pydantic = mock_report
    mock_crew_output.raw = "raw output"

    scenario = {"id": "sharing_peer_conflict", "description": "test", "context": "test"}

    with patch("validation.runner.Crew") as MockCrew:
        instance = MockCrew.return_value
        instance.kickoff_async = AsyncMock(return_value=mock_crew_output)
        result = await run_trial(scenario)

    assert isinstance(result, SupervisorReport)
    assert result.scenario_id == "sharing_peer_conflict"


# --- Log file created ---
@pytest.mark.asyncio
async def test_log_file_created(tmp_path, monkeypatch):
    mock_rating = PersonaRating(persona="low_verbal", score=3, justification="ok")
    mock_report = SupervisorReport(
        scenario_id="patience_queue",
        persona_ratings=[mock_rating],
        mean_score=3.0,
        safety_flags=[],
        recommendation="approve",
    )
    mock_crew_output = MagicMock()
    mock_crew_output.pydantic = mock_report
    mock_crew_output.raw = "raw agent output for logging"

    scenario = {"id": "patience_queue", "description": "test", "context": "test"}

    # Redirect logs to tmp_path
    import validation.runner as runner_mod
    monkeypatch.setattr(runner_mod, "LOGS_DIR", tmp_path)

    with patch("validation.runner.Crew") as MockCrew:
        instance = MockCrew.return_value
        instance.kickoff_async = AsyncMock(return_value=mock_crew_output)
        await run_trial(scenario)

    log_files = list(tmp_path.glob("*_patience_queue.log"))
    assert len(log_files) == 1
    log_content = log_files[0].read_text()
    assert '"scenario_id"' in log_content
    assert '"patience_queue"' in log_content


# --- POST /api/validation/run returns 200 with SupervisorReport ---
@pytest.mark.asyncio
async def test_run_endpoint():
    mock_rating = PersonaRating(persona="low_verbal", score=4, justification="Fine")
    mock_report = SupervisorReport(
        scenario_id="sharing_peer_conflict",
        persona_ratings=[mock_rating],
        mean_score=4.0,
        safety_flags=[],
        recommendation="approve",
    )

    with patch("app.api.routes.validation.run_trial", new_callable=AsyncMock) as mock_run:
        mock_run.return_value = mock_report
        async with AsyncClient(
            transport=ASGITransport(app=app), base_url="http://test"
        ) as client:
            response = await client.post(
                "/api/validation/run",
                json={"scenario_id": "sharing_peer_conflict"},
            )

    assert response.status_code == 200
    data = response.json()
    assert data["scenario_id"] == "sharing_peer_conflict"
    assert data["recommendation"] in ("approve", "revise", "reject")


# --- Unknown scenario_id returns 404 ---
@pytest.mark.asyncio
async def test_invalid_scenario_id():
    async with AsyncClient(
        transport=ASGITransport(app=app), base_url="http://test"
    ) as client:
        response = await client.post(
            "/api/validation/run",
            json={"scenario_id": "nonexistent_scenario_xyz"},
        )
    assert response.status_code == 404
