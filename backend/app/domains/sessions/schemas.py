"""Pydantic schemas for session domain.

Request and response models for session lifecycle operations.
"""
from datetime import datetime
from typing import Optional
from uuid import UUID

from pydantic import BaseModel, ConfigDict


class SessionStartRequest(BaseModel):
    """Request schema for starting a new session.

    Session initiated with user_id reference.
    """
    user_id: UUID
    platform: Optional[str] = None


class SessionResponse(BaseModel):
    """Response schema for session operations.

    Returns session details including aggregate metrics.
    """
    session_id: UUID
    user_id: UUID
    started_at: datetime
    ended_at: Optional[datetime]
    scenarios_completed: int
    total_reward: float
    average_frustration: Optional[float]
    platform: Optional[str]
    ended_reason: Optional[str]

    model_config = ConfigDict(from_attributes=True)


class SessionEndResponse(BaseModel):
    """Response schema for session end operation.

    Includes final metrics and completion message.
    """
    session_id: UUID
    ended_at: datetime
    scenarios_completed: int
    total_reward: float
    average_frustration: Optional[float]
    message: str = "Session ended successfully"

    model_config = ConfigDict(from_attributes=True)
