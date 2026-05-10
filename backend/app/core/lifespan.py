"""Application lifespan management for startup and shutdown events."""
from contextlib import asynccontextmanager
from typing import Any

from fastapi import FastAPI
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncEngine
import redis.asyncio as redis

from app.core.database import create_engine, AsyncSessionLocal
from app.core.redis import get_redis_pool
from app.rl.inference import load_model, load_vec_normalize, RLPredictor

# Module-level dict for shared state
app_state: dict[str, Any] = {}


async def _seed_admin() -> None:
    """Upsert the admin account from ADMIN_EMAIL / ADMIN_PASSWORD env vars."""
    from app.core.config import settings
    from app.core.security import hash_password
    from app.domains.auth.models import AdminAccount

    if not settings.ADMIN_EMAIL or not settings.ADMIN_PASSWORD:
        return

    async with AsyncSessionLocal() as session:
        result = await session.execute(
            select(AdminAccount).where(AdminAccount.email == settings.ADMIN_EMAIL)
        )
        admin = result.scalar_one_or_none()
        if admin is None:
            admin = AdminAccount(
                email=settings.ADMIN_EMAIL,
                hashed_password=hash_password(settings.ADMIN_PASSWORD),
            )
            session.add(admin)
            await session.commit()
            print(f"Admin account seeded for {settings.ADMIN_EMAIL}")
        else:
            print(f"Admin account already exists for {settings.ADMIN_EMAIL}")


@asynccontextmanager
async def lifespan(app: FastAPI):
    """Manage application lifecycle: startup and shutdown events."""
    # Startup
    print("Starting up...")

    # Create async database engine
    print("Initializing database engine...")
    engine: AsyncEngine = create_engine()
    app_state["engine"] = engine

    # Bind engine to session factory
    AsyncSessionLocal.configure(bind=engine)

    # Create Redis pool
    print("Connecting to Redis...")
    redis_pool: redis.Redis = await get_redis_pool()
    app_state["redis"] = redis_pool

    # Load RL model and VecNormalize
    try:
        print("Loading RL model...")
        model = load_model("model_store/ppo_asd_final")
        vec_normalize = load_vec_normalize("model_store/vec_normalize.pkl")
        app_state["rl_predictor"] = RLPredictor(model, vec_normalize)
        app_state["model_loaded"] = True
        print("RL model loaded successfully!")
    except FileNotFoundError as e:
        print(f"WARNING: RL model not found ({e}). Prediction endpoint will return 503.")
        app_state["model_loaded"] = False
        app_state["rl_predictor"] = None

    # Seed admin account from environment variables
    try:
        await _seed_admin()
    except Exception as e:
        print(f"WARNING: Admin seed failed ({e}). Dashboard login may not work.")

    print("Startup complete!")

    yield

    # Shutdown
    print("Shutting down...")

    # Close Redis pool
    if "redis" in app_state:
        print("Closing Redis connection...")
        await app_state["redis"].aclose()

    # Dispose database engine
    if "engine" in app_state:
        print("Disposing database engine...")
        await app_state["engine"].dispose()

    # Clear app state
    app_state.clear()

    print("Shutdown complete!")
