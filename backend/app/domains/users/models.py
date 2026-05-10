"""User and UserProfile models for ASD Intervention System.


users table: Basic demographic information
user_profiles table: Learning characteristics, preferences, JSONB state vectors
"""
import uuid
from datetime import datetime
from typing import Optional

from sqlalchemy import CheckConstraint, Float, ForeignKey, Integer, String, text
from sqlalchemy.dialects.postgresql import JSONB, UUID
from sqlalchemy.orm import Mapped, mapped_column, relationship
from sqlalchemy.sql import func

from app.core.database import Base


class User(Base):
    """User model mapping to 'users' table.

    Stores basic demographic and contact information for children with ASD.
    """
    __tablename__ = "users"

    user_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        primary_key=True,
        server_default=text("gen_random_uuid()"),
    )
    age: Mapped[int] = mapped_column(
        Integer,
        nullable=False,
    )
    severity_level: Mapped[int] = mapped_column(
        Integer,
        nullable=False,
    )
    guardian_email: Mapped[Optional[str]] = mapped_column(
        String(255),
        nullable=True,
    )
    email: Mapped[Optional[str]] = mapped_column(
        String(255),
        unique=True,
        nullable=True,
    )
    hashed_password: Mapped[Optional[str]] = mapped_column(
        String,
        nullable=True,
    )
    created_at: Mapped[datetime] = mapped_column(
        server_default=func.now(),
    )
    updated_at: Mapped[datetime] = mapped_column(
        server_default=func.now(),
        onupdate=func.now(),
    )

    # Relationships
    profile: Mapped["UserProfile"] = relationship(
        "UserProfile",
        back_populates="user",
        uselist=False,
    )

    # Constraints
    __table_args__ = (
        CheckConstraint("age >= 4 AND age <= 18", name="age_range"),
        CheckConstraint("severity_level BETWEEN 1 AND 3", name="severity_range"),
    )

    def __repr__(self) -> str:
        return f"<User(user_id={self.user_id}, age={self.age}, severity={self.severity_level})>"


class UserProfile(Base):
    """UserProfile model mapping to 'user_profiles' table.

    Stores composite representation including:
    - Aggregate statistics (success rate, scenarios completed)
    - Learning characteristics (learning rate, frustration tolerance)
    - JSONB fields for preferences, history, emotional data
    - 60-dimensional state vector for RL model input
    """
    __tablename__ = "user_profiles"

    user_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("users.user_id"),
        primary_key=True,
    )

    # Aggregate statistics
    overall_success_rate: Mapped[float] = mapped_column(
        Float,
        default=0.5,
        server_default=text("0.5"),
    )
    scenarios_completed: Mapped[int] = mapped_column(
        Integer,
        default=0,
        server_default=text("0"),
    )
    total_session_time: Mapped[int] = mapped_column(
        Integer,
        default=0,
        server_default=text("0"),
        comment="Total time in seconds",
    )
    current_difficulty: Mapped[int] = mapped_column(
        Integer,
        default=2,
        server_default=text("2"),
    )

    # Learning characteristics
    learning_rate: Mapped[float] = mapped_column(
        Float,
        default=0.5,
        server_default=text("0.5"),
        comment="How fast user improves (0-1)",
    )
    frustration_tolerance: Mapped[float] = mapped_column(
        Float,
        default=0.5,
        server_default=text("0.5"),
    )

    # JSONB fields for preferences and history
    preferred_scenarios: Mapped[dict] = mapped_column(
        JSONB,
        server_default=text(
            """'{"sharing": 0.2, "patience": 0.2, "emotion_recognition": 0.2, "turn_taking": 0.2, "conflict_resolution": 0.2}'::jsonb"""
        ),
        comment="Equal distribution across 5 core scenario types",
    )
    last_5_scenarios: Mapped[list] = mapped_column(
        JSONB,
        server_default=text("'[]'::jsonb"),
    )
    last_5_success_rates: Mapped[list] = mapped_column(
        JSONB,
        server_default=text("'[]'::jsonb"),
    )
    emotional_history: Mapped[dict] = mapped_column(
        JSONB,
        server_default=text(
            """'{"frustration_mean": 0.3, "engagement_mean": 0.7, "confidence_mean": 0.5}'::jsonb"""
        ),
    )

    # 60-dimensional state vector for RL model (stored as flat array)
    state_vector: Mapped[Optional[dict]] = mapped_column(
        JSONB,
        nullable=True,
    )

    updated_at: Mapped[datetime] = mapped_column(
        server_default=func.now(),
        onupdate=func.now(),
    )

    # Foreign key (not explicit in mapped_column since it's PK)
    # The relationship establishes the foreign key via back_populates

    # Relationships
    user: Mapped["User"] = relationship(
        "User",
        back_populates="profile",
        foreign_keys=[user_id],
    )

    # Constraints
    __table_args__ = (
        CheckConstraint("current_difficulty BETWEEN 1 AND 5", name="difficulty_range"),
    )

    def __repr__(self) -> str:
        return f"<UserProfile(user_id={self.user_id}, success_rate={self.overall_success_rate:.2f})>"
