"""Session and ScenarioResult models for ASD Intervention System.

sessions table: User session tracking with reward and emotional data
scenario_results table: Individual scenario outcomes with RL training data (state, action, reward, next_state)
"""
import uuid
from datetime import datetime
from typing import Optional

from sqlalchemy import Boolean, Float, ForeignKey, Integer, String, text
from sqlalchemy.dialects.postgresql import JSONB, UUID
from sqlalchemy.orm import Mapped, mapped_column
from sqlalchemy.sql import func

from app.core.database import Base


class Session(Base):
    """Session model mapping to 'sessions' table.

    Tracks user sessions with aggregate metrics for reward and frustration.
    """
    __tablename__ = "sessions"

    session_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        primary_key=True,
        server_default=text("gen_random_uuid()"),
    )
    user_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("users.user_id"),
        nullable=False,
    )
    started_at: Mapped[datetime] = mapped_column(
        server_default=func.now(),
    )
    ended_at: Mapped[Optional[datetime]] = mapped_column(
        nullable=True,
    )
    scenarios_completed: Mapped[int] = mapped_column(
        Integer,
        default=0,
        server_default=text("0"),
    )
    total_reward: Mapped[float] = mapped_column(
        Float,
        default=0.0,
        server_default=text("0.0"),
    )
    average_frustration: Mapped[Optional[float]] = mapped_column(
        Float,
        nullable=True,
    )
    platform: Mapped[Optional[str]] = mapped_column(
        String(20),
        nullable=True,
        comment="Client platform: android, ios, browser, macos, windows, linux",
    )
    ended_reason: Mapped[Optional[str]] = mapped_column(
        String(50),
        nullable=True,
        comment="Values: 'completed', 'timeout', 'user_quit', 'intervention'",
    )

    def __repr__(self) -> str:
        return f"<Session(session_id={self.session_id}, user_id={self.user_id}, scenarios={self.scenarios_completed})>"


class ScenarioResult(Base):
    """ScenarioResult model mapping to 'scenario_results' table.

    Stores all RL training data: state, action, reward, next_state.
    Each result captures user interaction details, behavioral signals, and emotions.
    """
    __tablename__ = "scenario_results"

    result_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        primary_key=True,
        server_default=text("gen_random_uuid()"),
    )
    session_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("sessions.session_id"),
        nullable=False,
    )
    user_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("users.user_id"),
        nullable=False,
    )

    # Scenario details
    scenario_type: Mapped[str] = mapped_column(
        String(50),
        nullable=False,
    )
    difficulty: Mapped[int] = mapped_column(
        Integer,
        nullable=False,
    )
    complexity: Mapped[str] = mapped_column(
        String(10),
        nullable=False,
    )
    reinforcement_mode: Mapped[str] = mapped_column(
        String(20),
        nullable=False,
    )

    # User interaction
    user_choice: Mapped[Optional[str]] = mapped_column(
        String(100),
        nullable=True,
    )
    ai_response: Mapped[Optional[str]] = mapped_column(
        String(100),
        nullable=True,
    )
    outcome_type: Mapped[Optional[str]] = mapped_column(
        String(50),
        nullable=True,
        comment="Values: 'success', 'failure', 'betrayed', 'cooperated'",
    )

    # Behavioral signals
    decision_time_ms: Mapped[Optional[int]] = mapped_column(
        Integer,
        nullable=True,
    )
    num_pauses: Mapped[int] = mapped_column(
        Integer,
        default=0,
        server_default=text("0"),
    )
    num_retries: Mapped[int] = mapped_column(
        Integer,
        default=0,
        server_default=text("0"),
    )
    completed: Mapped[bool] = mapped_column(
        Boolean,
        default=True,
        server_default=text("true"),
    )
    quit_early: Mapped[bool] = mapped_column(
        Boolean,
        default=False,
        server_default=text("false"),
    )

    # Inferred emotions (JSONB)
    emotions: Mapped[Optional[dict]] = mapped_column(
        JSONB,
        nullable=True,
        comment='Example: {"frustration": 0.3, "engagement": 0.8}',
    )

    # RL training data (state, action, reward, next_state)
    state_vector: Mapped[Optional[dict]] = mapped_column(
        JSONB,
        nullable=True,
        comment="State before this scenario",
    )
    action_taken: Mapped[Optional[dict]] = mapped_column(
        JSONB,
        nullable=True,
        comment="RL agent's action",
    )
    reward: Mapped[Optional[float]] = mapped_column(
        Float,
        nullable=True,
    )
    next_state_vector: Mapped[Optional[dict]] = mapped_column(
        JSONB,
        nullable=True,
    )

    timestamp: Mapped[datetime] = mapped_column(
        server_default=func.now(),
    )

    def __repr__(self) -> str:
        return f"<ScenarioResult(result_id={self.result_id}, scenario_type={self.scenario_type}, completed={self.completed})>"
