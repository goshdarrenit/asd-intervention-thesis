"""Admin dashboard routes — server-rendered HTML using Jinja2.

All routes are under /admin/ prefix.
Authentication: httponly cookie containing JWT (sub: "admin:{uuid}").
"""
import csv
import io
from datetime import datetime, timezone
from pathlib import Path

from fastapi import APIRouter, Depends, Form, Request
from fastapi.responses import RedirectResponse, StreamingResponse
from fastapi.templating import Jinja2Templates
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.deps import DbSession, get_db
from app.core.dependencies import get_admin_from_cookie
from app.core.security import create_access_token, verify_password
from app.domains.auth.models import AdminAccount
from app.domains.sessions.models import ScenarioResult, Session
from app.domains.users.models import User, UserProfile

router = APIRouter(prefix="/admin", tags=["admin-ui"])

_templates_dir = Path(__file__).parent.parent.parent / "templates"
templates = Jinja2Templates(directory=str(_templates_dir))


# ── Helper ───────────────────────────────────────────────────────────────────


async def _require_admin(request: Request, db: AsyncSession) -> AdminAccount | None:
    """Return admin from cookie, or None (caller must redirect)."""
    return await get_admin_from_cookie(request, db)


# ── Root ─────────────────────────────────────────────────────────────────────


@router.get("/")
async def admin_root(request: Request, db: DbSession):
    """Redirect to dashboard or login depending on auth state."""
    admin = await _require_admin(request, db)
    if admin:
        return RedirectResponse(url="/admin/dashboard", status_code=302)
    return RedirectResponse(url="/admin/login", status_code=302)


# ── Login / Logout ────────────────────────────────────────────────────────────


@router.get("/login")
async def login_page(request: Request):
    """Render login form."""
    return templates.TemplateResponse(
        "admin/login.html", {"request": request, "error": None}
    )


@router.post("/login")
async def login_submit(
    request: Request,
    db: DbSession,
    email: str = Form(...),
    password: str = Form(...),
):
    """Verify credentials, set httponly cookie, redirect to dashboard."""
    result = await db.execute(
        select(AdminAccount).where(AdminAccount.email == email)
    )
    admin = result.scalar_one_or_none()

    if admin is None or not admin.is_active or not verify_password(password, admin.hashed_password):
        return templates.TemplateResponse(
            "admin/login.html",
            {"request": request, "error": "Invalid email or password"},
            status_code=401,
        )

    token = create_access_token(sub=f"admin:{admin.id}")
    response = RedirectResponse(url="/admin/dashboard", status_code=302)
    response.set_cookie(
        key="access_token",
        value=token,
        httponly=True,
        samesite="lax",
        max_age=7 * 24 * 3600,
    )
    return response


@router.get("/logout")
async def logout(request: Request):
    """Clear auth cookie and redirect to login."""
    response = RedirectResponse(url="/admin/login", status_code=302)
    response.delete_cookie("access_token")
    return response


# ── Dashboard ─────────────────────────────────────────────────────────────────


@router.get("/dashboard")
async def dashboard(request: Request, db: DbSession):
    """Summary stats: total users, sessions today, avg success rate."""
    admin = await _require_admin(request, db)
    if admin is None:
        return RedirectResponse(url="/admin/login", status_code=302)

    total_users = (await db.execute(select(func.count(User.user_id)))).scalar_one()

    today_start = datetime.now(timezone.utc).replace(
        hour=0, minute=0, second=0, microsecond=0, tzinfo=None
    )
    sessions_today = (
        await db.execute(
            select(func.count(Session.session_id)).where(
                Session.started_at >= today_start
            )
        )
    ).scalar_one()

    avg_success = (
        await db.execute(select(func.avg(UserProfile.overall_success_rate)))
    ).scalar_one()

    # ── RL system stats ────────────────────────────────────────────────────
    # Total reward distributed across all sessions (all-time)
    total_reward = (
        await db.execute(select(func.sum(ScenarioResult.reward)))
    ).scalar_one_or_none()

    # Top scenario type this week (most frequently chosen)
    week_start = datetime.now(timezone.utc).replace(tzinfo=None)
    week_start = week_start.replace(hour=0, minute=0, second=0, microsecond=0)
    from datetime import timedelta
    week_start = week_start - timedelta(days=week_start.weekday())

    top_type_row = (
        await db.execute(
            select(
                ScenarioResult.scenario_type,
                func.count(ScenarioResult.result_id).label("cnt"),
            )
            .where(ScenarioResult.timestamp >= week_start)
            .group_by(ScenarioResult.scenario_type)
            .order_by(func.count(ScenarioResult.result_id).desc())
            .limit(1)
        )
    ).first()
    top_scenario_type = top_type_row.scenario_type.replace("_", " ").title() if top_type_row else "—"

    # Sessions ended by safety intervention (all-time)
    intervention_count = (
        await db.execute(
            select(func.count(Session.session_id)).where(
                Session.ended_reason == "intervention"
            )
        )
    ).scalar_one()

    # Model loaded status
    from app.core.lifespan import app_state
    model_active = app_state.get("model_loaded", False)

    return templates.TemplateResponse(
        "admin/dashboard.html",
        {
            "request": request,
            "admin": admin,
            "total_users": total_users,
            "sessions_today": sessions_today,
            "avg_success_rate": round((avg_success or 0.0) * 100, 1),
            "rl_total_reward": round(float(total_reward or 0), 2),
            "rl_top_scenario": top_scenario_type,
            "rl_model_active": model_active,
            "rl_intervention_count": intervention_count,
        },
    )


# ── Users list ────────────────────────────────────────────────────────────────


@router.get("/users")
async def users_list(request: Request, db: DbSession, page: int = 1):
    """Paginated table of all users."""
    admin = await _require_admin(request, db)
    if admin is None:
        return RedirectResponse(url="/admin/login", status_code=302)

    page_size = 20
    offset = (page - 1) * page_size

    # Join users with profiles
    rows = (
        await db.execute(
            select(User, UserProfile)
            .join(UserProfile, User.user_id == UserProfile.user_id, isouter=True)
            .order_by(User.created_at.desc())
            .limit(page_size)
            .offset(offset)
        )
    ).all()

    total = (await db.execute(select(func.count(User.user_id)))).scalar_one()

    # Get last session per user
    last_sessions_rows = (
        await db.execute(
            select(Session.user_id, func.max(Session.started_at).label("last_session"))
            .group_by(Session.user_id)
        )
    ).all()
    last_session_map = {str(r.user_id): r.last_session for r in last_sessions_rows}

    users_data = []
    for user, profile in rows:
        users_data.append(
            {
                "user_id": str(user.user_id),
                "email": user.email or "—",
                "age": user.age,
                "severity": user.severity_level,
                "scenarios_completed": profile.scenarios_completed if profile else 0,
                "success_rate": round((profile.overall_success_rate if profile else 0.0) * 100, 1),
                "last_session": last_session_map.get(str(user.user_id)),
                "created_at": user.created_at,
            }
        )

    return templates.TemplateResponse(
        "admin/users.html",
        {
            "request": request,
            "admin": admin,
            "users": users_data,
            "page": page,
            "total_pages": max(1, (total + page_size - 1) // page_size),
            "total": total,
        },
    )


# ── User detail ───────────────────────────────────────────────────────────────


@router.get("/users/{uid}")
async def user_detail(request: Request, uid: str, db: DbSession):
    """User profile + charts + session history."""
    admin = await _require_admin(request, db)
    if admin is None:
        return RedirectResponse(url="/admin/login", status_code=302)

    from uuid import UUID

    try:
        user_uuid = UUID(uid)
    except ValueError:
        return RedirectResponse(url="/admin/users", status_code=302)

    user_result = await db.execute(select(User).where(User.user_id == user_uuid))
    user = user_result.scalar_one_or_none()
    if user is None:
        return RedirectResponse(url="/admin/users", status_code=302)

    profile_result = await db.execute(
        select(UserProfile).where(UserProfile.user_id == user_uuid)
    )
    profile = profile_result.scalar_one_or_none()

    # Session history (last 20)
    sessions_result = await db.execute(
        select(Session)
        .where(Session.user_id == user_uuid)
        .order_by(Session.started_at.desc())
        .limit(20)
    )
    sessions = sessions_result.scalars().all()

    # Scenario results for timeline charts (last 50, chronological)
    results_result = await db.execute(
        select(ScenarioResult)
        .where(ScenarioResult.user_id == user_uuid)
        .order_by(ScenarioResult.timestamp.asc())
        .limit(50)
    )
    results = results_result.scalars().all()

    # Build timeline chart data
    success_rates = []
    difficulties = []
    frustrations = []
    engagements = []
    confidences = []
    labels = []

    for i, r in enumerate(results, 1):
        labels.append(i)
        success_rates.append(1 if r.completed else 0)
        difficulties.append(r.difficulty)
        emotions = r.emotions or {}
        frustrations.append(round(emotions.get("frustration", 0), 3))
        engagements.append(round(emotions.get("engagement", 0), 3))
        confidences.append(round(emotions.get("confidence", 0), 3))

    # ── RL aggregate stats (all-time) ──────────────────────────────────────
    _SCENARIO_TYPES = [
        "sharing", "patience", "emotion_recognition",
        "turn_taking", "conflict_resolution",
    ]
    _REINF_MODES = ["positive", "neutral", "corrective"]

    # Scenario type distribution
    type_count_rows = (await db.execute(
        select(ScenarioResult.scenario_type,
               func.count(ScenarioResult.result_id).label("cnt"))
        .where(ScenarioResult.user_id == user_uuid)
        .group_by(ScenarioResult.scenario_type)
    )).all()
    _type_counts = {r.scenario_type: r.cnt for r in type_count_rows}

    # Average reward per scenario type
    avg_reward_rows = (await db.execute(
        select(ScenarioResult.scenario_type,
               func.avg(ScenarioResult.reward).label("avg_r"))
        .where(ScenarioResult.user_id == user_uuid)
        .group_by(ScenarioResult.scenario_type)
    )).all()
    _avg_reward = {r.scenario_type: round(float(r.avg_r or 0), 3) for r in avg_reward_rows}

    # Reinforcement mode breakdown
    reinf_rows = (await db.execute(
        select(ScenarioResult.reinforcement_mode,
               func.count(ScenarioResult.result_id).label("cnt"))
        .where(ScenarioResult.user_id == user_uuid)
        .group_by(ScenarioResult.reinforcement_mode)
    )).all()
    _reinf_counts = {r.reinforcement_mode: r.cnt for r in reinf_rows}

    # Total cumulative reward
    total_reward_val = (await db.execute(
        select(func.sum(ScenarioResult.reward))
        .where(ScenarioResult.user_id == user_uuid)
    )).scalar_one_or_none()
    total_reward = round(float(total_reward_val or 0), 3)

    # Model vs fallback — derived from the fetched results (populated since Step 1)
    model_count = sum(
        1 for r in results
        if r.action_taken and r.action_taken.get("model_used") is True
    )
    fallback_count = sum(
        1 for r in results
        if r.action_taken and r.action_taken.get("model_used") is False
    )

    # Flatten into chart-ready lists (consistent ordering)
    rl_type_labels   = [t.replace("_", " ").title() for t in _SCENARIO_TYPES]
    rl_type_counts   = [_type_counts.get(t, 0) for t in _SCENARIO_TYPES]
    rl_type_rewards  = [_avg_reward.get(t, 0) for t in _SCENARIO_TYPES]
    rl_reinf_labels  = [m.title() for m in _REINF_MODES]
    rl_reinf_counts  = [_reinf_counts.get(m, 0) for m in _REINF_MODES]

    return templates.TemplateResponse(
        "admin/user_detail.html",
        {
            "request": request,
            "admin": admin,
            "user": user,
            "profile": profile,
            "sessions": sessions,
            "chart_labels": labels,
            "chart_success": success_rates,
            "chart_difficulty": difficulties,
            "chart_frustration": frustrations,
            "chart_engagement": engagements,
            "chart_confidence": confidences,
            # RL summary
            "rl_type_labels": rl_type_labels,
            "rl_type_counts": rl_type_counts,
            "rl_type_rewards": rl_type_rewards,
            "rl_reinf_labels": rl_reinf_labels,
            "rl_reinf_counts": rl_reinf_counts,
            "rl_total_reward": total_reward,
            "rl_model_count": model_count,
            "rl_fallback_count": fallback_count,
        },
    )


@router.post("/users/{uid}/disable")
async def disable_user(request: Request, uid: str, db: DbSession):
    """Set user active=False (soft disable)."""
    admin = await _require_admin(request, db)
    if admin is None:
        return RedirectResponse(url="/admin/login", status_code=302)

    from uuid import UUID

    try:
        user_uuid = UUID(uid)
    except ValueError:
        return RedirectResponse(url="/admin/users", status_code=302)

    result = await db.execute(select(User).where(User.user_id == user_uuid))
    user = result.scalar_one_or_none()
    if user is not None:
        # Users table doesn't have is_active yet; clear their email to block login
        user.hashed_password = None
        await db.commit()

    return RedirectResponse(url=f"/admin/users/{uid}", status_code=302)


# ── Session detail ────────────────────────────────────────────────────────


@router.get("/sessions/{sid}")
async def session_detail(request: Request, sid: str, db: DbSession):
    """Per-session RL decision log with reward/emotion charts."""
    admin = await _require_admin(request, db)
    if admin is None:
        return RedirectResponse(url="/admin/login", status_code=302)

    import uuid as _uuid
    try:
        session_uuid = _uuid.UUID(sid)
    except ValueError:
        return RedirectResponse(url="/admin/users", status_code=302)

    session_result = await db.execute(
        select(Session).where(Session.session_id == session_uuid)
    )
    session = session_result.scalar_one_or_none()
    if session is None:
        return RedirectResponse(url="/admin/users", status_code=302)

    user_result = await db.execute(
        select(User).where(User.user_id == session.user_id)
    )
    user = user_result.scalar_one_or_none()

    results_result = await db.execute(
        select(ScenarioResult)
        .where(ScenarioResult.session_id == session_uuid)
        .order_by(ScenarioResult.timestamp.asc())
    )
    results = results_result.scalars().all()

    # Duration in minutes
    duration_mins = None
    if session.ended_at and session.started_at:
        duration_mins = int(
            (session.ended_at - session.started_at).total_seconds() / 60
        )

    # Per-step data for table + charts
    labels, chart_rewards, chart_difficulty = [], [], []
    chart_frustration, chart_engagement, chart_confidence = [], [], []
    step_data = []

    for i, r in enumerate(results, 1):
        emotions = r.emotions or {}
        action = r.action_taken or {}
        labels.append(i)
        chart_rewards.append(round(r.reward or 0, 3))
        chart_difficulty.append(r.difficulty)
        chart_frustration.append(round(emotions.get("frustration", 0), 3))
        chart_engagement.append(round(emotions.get("engagement", 0), 3))
        chart_confidence.append(round(emotions.get("confidence", 0), 3))
        step_data.append({
            "step": i,
            "scenario_type": r.scenario_type,
            "difficulty": r.difficulty,
            "complexity": r.complexity,
            "reinforcement_mode": r.reinforcement_mode,
            "model_used": action.get("model_used"),   # None = pre-Step-1 row
            "success": r.completed,
            "reward": round(r.reward or 0, 3),
            "frustration": round(emotions.get("frustration", 0), 3),
            "engagement": round(emotions.get("engagement", 0), 3),
            "confidence": round(emotions.get("confidence", 0), 3),
            "decision_time_ms": r.decision_time_ms,
            "num_pauses": r.num_pauses,
            "num_retries": r.num_retries,
            "quit_early": r.quit_early,
        })

    return templates.TemplateResponse(
        "admin/session_detail.html",
        {
            "request": request,
            "admin": admin,
            "session": session,
            "user": user,
            "duration_mins": duration_mins,
            "step_data": step_data,
            "labels": labels,
            "chart_rewards": chart_rewards,
            "chart_difficulty": chart_difficulty,
            "chart_frustration": chart_frustration,
            "chart_engagement": chart_engagement,
            "chart_confidence": chart_confidence,
        },
    )


# ── CSV export ────────────────────────────────────────────────────────────────


@router.get("/export/csv")
async def export_csv(request: Request, db: DbSession):
    """StreamingResponse of all users + aggregate stats as CSV."""
    admin = await _require_admin(request, db)
    if admin is None:
        return RedirectResponse(url="/admin/login", status_code=302)

    rows = (
        await db.execute(
            select(User, UserProfile)
            .join(UserProfile, User.user_id == UserProfile.user_id, isouter=True)
            .order_by(User.created_at.asc())
        )
    ).all()

    def generate():
        buf = io.StringIO()
        writer = csv.writer(buf)
        writer.writerow(
            [
                "user_id",
                "email",
                "age",
                "severity_level",
                "scenarios_completed",
                "overall_success_rate",
                "current_difficulty",
                "created_at",
            ]
        )
        for user, profile in rows:
            writer.writerow(
                [
                    str(user.user_id),
                    user.email or "",
                    user.age,
                    user.severity_level,
                    profile.scenarios_completed if profile else 0,
                    profile.overall_success_rate if profile else 0.0,
                    profile.current_difficulty if profile else 2,
                    user.created_at.isoformat() if user.created_at else "",
                ]
            )
            buf.seek(0)
            yield buf.read()
            buf.truncate(0)
            buf.seek(0)

    return StreamingResponse(
        generate(),
        media_type="text/csv",
        headers={"Content-Disposition": "attachment; filename=users_export.csv"},
    )
