"""Pydantic schemas for user domain.

Request and response models for user registration and profile management.
"""
from typing import Optional
from uuid import UUID

from pydantic import BaseModel, ConfigDict, Field


class UserCreate(BaseModel):
    """Request schema for user registration.

    guardian_email is optional.
    """
    age: int = Field(..., ge=4, le=18, description="Child's age in years")
    severity_level: int = Field(..., ge=1, le=3, description="ASD severity level (1=mild, 2=moderate, 3=severe)")
    guardian_email: Optional[str] = Field(None, max_length=255, description="Optional guardian email for notifications")


class UserResponse(BaseModel):
    """Response schema for user registration."""
    user_id: UUID
    message: str = "User registered successfully"

    model_config = ConfigDict(from_attributes=True)


class UserProfileResponse(BaseModel):
    """Response schema for user profile retrieval.

    Returns aggregate statistics, learning characteristics, and JSONB fields.
    """
    user_id: UUID
    overall_success_rate: float
    scenarios_completed: int
    current_difficulty: int
    learning_rate: float
    frustration_tolerance: float
    preferred_scenarios: dict
    emotional_history: dict

    model_config = ConfigDict(from_attributes=True)
