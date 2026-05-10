"""SQLAlchemy query helpers for analytics endpoints."""
from pathlib import Path
from uuid import UUID

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.domains.sessions.models import ScenarioResult


async def get_user_scenario_history(db: AsyncSession, user_id: UUID) -> list[dict]:
    """Return scenario results for user ordered by timestamp. LIMIT 500."""
    stmt = (
        select(ScenarioResult)
        .where(ScenarioResult.user_id == user_id)
        .order_by(ScenarioResult.timestamp)
        .limit(500)
    )
    rows = (await db.execute(stmt)).scalars().all()
    return [
        {
            "scenario_type": r.scenario_type,
            "completed": r.completed,
            "num_retries": r.num_retries,
            "emotions": r.emotions or {},
            "timestamp": r.timestamp.isoformat() if r.timestamp else None,
        }
        for r in rows
    ]


def get_model_metadata() -> dict:
    """Read model version from model_checksums.sha256."""
    checksum_path = Path("model_store/model_checksums.sha256")
    if checksum_path.exists():
        content = checksum_path.read_text().strip()
        # Format: "SHA256_HASH  filename"
        sha = content.split()[0][:12] if content else "unknown"
    else:
        sha = "unknown"
    return {
        "model_version": sha,
        "model_path": "model_store/ppo_asd_final.zip",
        "algorithm": "PPO",
        "training_timesteps": 100000,
        "training_metrics": {
            "validation_reward": 65.589,
            "convergence_timestep": 100000,
        },
        "evaluation_summary": None,
    }
