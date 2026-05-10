"""FastAPI application entry point."""
from fastapi import FastAPI
from fastapi.exceptions import RequestValidationError
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles
from pathlib import Path

from app.core.exceptions import AppException
from app.core.lifespan import lifespan
from app.api.errors import app_exception_handler, validation_exception_handler
from app.api.routes import health, users, sessions, rl, scenarios, auth, analytics, validation
from app.api.routes import admin_ui

# Ensure model metadata is registered for all domains
import app.domains.auth.models  # noqa: F401

# Create FastAPI application
app = FastAPI(
    title="ASD Intervention API",
    version="0.1.0",
    description="Backend API for ASD intervention system with RL-based scenario sequencing",
    lifespan=lifespan,
)

# Allow local web clients (Flutter web dev server/Chrome) to call the API.
app.add_middleware(
    CORSMiddleware,
    allow_origin_regex=r"https?://(localhost|127\.0\.0\.1)(:\d+)?",
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Register exception handlers
app.add_exception_handler(AppException, app_exception_handler)
app.add_exception_handler(RequestValidationError, validation_exception_handler)

# Mount static files for admin dashboard
static_dir = Path(__file__).parent / "static"
static_dir.mkdir(exist_ok=True)
app.mount("/static", StaticFiles(directory=str(static_dir)), name="static")

# Register routers
app.include_router(health.router)
app.include_router(auth.router)
app.include_router(users.router)
app.include_router(sessions.router)
app.include_router(rl.router)
app.include_router(scenarios.router)
app.include_router(admin_ui.router)
app.include_router(analytics.router)
app.include_router(validation.router)


# Health check endpoint
@app.get("/")
async def root():
    """Root endpoint for health check."""
    return {"status": "ok", "message": "ASD Intervention API is running"}
