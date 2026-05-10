# ASD Intervention System

MSc thesis project — a reinforcement learning-based adaptive social skills intervention system for children with Autism Spectrum Disorder (ASD). The system presents interactive game scenarios and uses a trained PPO agent to adapt difficulty and scenario selection in real time based on each child's emotional and behavioural responses.

---

## Overview

- **Mobile app** — Flutter + Flame game engine. Five interactive social skill scenarios (Sharing, Turn-Taking, Emotion Recognition, Patience, Conflict Resolution) with animated hint overlays and adaptive difficulty.
- **Backend API** — FastAPI + PostgreSQL + Redis. Manages users, sessions, RL inference, and admin dashboard.
- **RL agent** — PPO (Proximal Policy Optimisation) trained via Stable-Baselines3 on a custom Gymnasium environment with 50 synthetic user profiles.
- **Validation framework** — CrewAI multi-agent system with 5 ASD child persona agents and a supervisor for automated evaluation.

---

## Tech Stack

| Layer | Technology |
|-------|-----------|
| Mobile | Flutter 3, Flame, Riverpod |
| Backend | FastAPI, SQLAlchemy 2, Alembic |
| Database | PostgreSQL 18, Redis 8 |
| RL | Stable-Baselines3 (PPO), Gymnasium |
| Validation | CrewAI |
| Infrastructure | Docker, Docker Compose |
| Analysis | JupyterLab, pandas, scipy, seaborn |

---

## Project Structure

```
├── backend/
│   ├── app/
│   │   ├── api/routes/        # FastAPI route handlers
│   │   ├── domains/           # Business logic (users, sessions, scenarios)
│   │   └── rl/                # RL environment, inference, reward calculator
│   ├── model_store/           # Trained PPO model + VecNormalize stats
│   ├── notebooks/             # Jupyter analysis notebooks
│   ├── scripts/               # Evaluation + training scripts
│   ├── validation/            # CrewAI persona agents + runner
│   └── tests/
├── mobile/
│   └── lib/
│       ├── core/              # Network, database, theme
│       └── features/          # Auth, home, scenarios, session, progress
└── docker-compose.yml
```

---

## Getting Started

### Prerequisites

- Docker + Docker Compose
- Flutter SDK
- Python 3.12+ with `uv`

### 1. Environment setup

```bash
cp .env.example .env
# Edit .env and set your credentials
```

### 2. Start the backend

```bash
docker-compose up -d
```

Services:
- API: http://localhost:8000
- API docs: http://localhost:8000/docs
- Admin dashboard: http://localhost:8000/admin/

### 3. Run the mobile app (browser)

```bash
cd mobile
/path/to/flutter/bin/flutter run -d chrome
```

Press `r` in the terminal to hot reload after code changes.

---

## Development

### Jump directly to a scenario (skip login)

In `mobile/lib/main.dart`, set:

```dart
const String? _kDevScenario = 'sharing'; // or 'turn_taking', 'emotion_recognition', 'patience', 'conflict_resolution'
```

Set to `null` to restore the normal login flow.

### Backend dependencies

```bash
cd backend
uv sync                        # core dependencies
uv sync --extra analysis       # adds jupyter, pandas, scipy, seaborn
uv sync --extra dev            # adds pytest, ruff
```

---

## Jupyter Notebooks

```bash
cd backend/notebooks
uv run jupyter lab
```

| Notebook | Description |
|----------|-------------|
| `rl_training_analysis.ipynb` | RL training metrics and reward curves |
| `evaluation_analysis.ipynb` | Statistical comparison of RL vs baselines |
| `comparison_study.ipynb` | Agent comparison study |

Generate evaluation data before running notebooks:

```bash
cd backend
uv run python scripts/run_evaluation.py --mode full
```

---

## CrewAI Validation

Requires the API to be running. Run phases in order:

```bash
# Phase 1 — set up 5 test user personas
curl -s -X POST http://localhost:8000/api/validation/run \
  -H "Content-Type: application/json" \
  -d '{"scenario_id": "full_session_validation", "phase": 1}' | python3 -m json.tool

# Phase 2 — LLM persona agents drive live sessions (~60-180s)
curl -s -X POST http://localhost:8000/api/validation/run \
  -H "Content-Type: application/json" \
  -d '{"scenario_id": "full_session_validation", "phase": 2}' | python3 -m json.tool

# Phase 3 — evaluation crew scores RL adaptation quality
curl -s -X POST http://localhost:8000/api/validation/run \
  -H "Content-Type: application/json" \
  -d '{"scenario_id": "full_session_validation", "phase": 3}' | python3 -m json.tool
```

Configure the LLM in `.env`:

```env
VALIDATION_MODEL=ollama/qwen2.5:14b
VALIDATION_MAX_TOKENS=4096
OLLAMA_HOST=http://host.docker.internal:11434
```

---

## RL Training

```bash
cd backend
uv run python scripts/train_rl_agent.py
```

The trained model is saved to `model_store/ppo_asd_final`.

