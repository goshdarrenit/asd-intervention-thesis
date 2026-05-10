#!/bin/sh
set -e

# Run migrations using the venv baked into the image (avoids uv re-downloading Python)
.venv/bin/alembic upgrade head

# Start application
exec .venv/bin/uvicorn app.main:app --host 0.0.0.0 --port 8000
