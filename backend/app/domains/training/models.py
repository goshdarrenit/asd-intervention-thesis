"""RLTrainingLog model for ASD Intervention System.

rl_training_logs table: Training metrics for RL agent (policy loss, value loss, entropy)
"""
import uuid
from datetime import datetime
from typing import Optional

from sqlalchemy import Float, Integer, String, text
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import Mapped, mapped_column
from sqlalchemy.sql import func

from app.core.database import Base


class RLTrainingLog(Base):
    """RLTrainingLog model mapping to 'rl_training_logs' table.

    Stores training metrics for RL agent during policy optimization.
    """
    __tablename__ = "rl_training_logs"

    log_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        primary_key=True,
        server_default=text("gen_random_uuid()"),
    )
    training_run_name: Mapped[Optional[str]] = mapped_column(
        String(100),
        nullable=True,
    )
    episode: Mapped[Optional[int]] = mapped_column(
        Integer,
        nullable=True,
    )
    timestep: Mapped[Optional[int]] = mapped_column(
        Integer,
        nullable=True,
    )
    mean_reward: Mapped[Optional[float]] = mapped_column(
        Float,
        nullable=True,
    )
    policy_loss: Mapped[Optional[float]] = mapped_column(
        Float,
        nullable=True,
    )
    value_loss: Mapped[Optional[float]] = mapped_column(
        Float,
        nullable=True,
    )
    entropy: Mapped[Optional[float]] = mapped_column(
        Float,
        nullable=True,
    )
    timestamp: Mapped[datetime] = mapped_column(
        server_default=func.now(),
    )

    def __repr__(self) -> str:
        return f"<RLTrainingLog(log_id={self.log_id}, run={self.training_run_name}, episode={self.episode})>"
