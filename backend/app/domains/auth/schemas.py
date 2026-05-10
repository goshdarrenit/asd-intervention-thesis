"""Pydantic schemas for authentication endpoints."""
from uuid import UUID

from pydantic import BaseModel, Field


class RegisterRequest(BaseModel):
    """Request schema for guardian account registration."""

    email: str = Field(..., description="Guardian email address")
    password: str = Field(..., min_length=8, description="Password (min 8 characters)")
    age: int = Field(..., ge=4, le=18, description="Child's age in years")
    severity_level: int = Field(..., ge=1, le=3, description="ASD severity level (1-3)")


class LoginRequest(BaseModel):
    """Request schema for login."""

    email: str
    password: str


class TokenResponse(BaseModel):
    """Response schema returning JWT access token."""

    access_token: str
    token_type: str = "bearer"
    user_id: UUID


class MeResponse(BaseModel):
    """Response schema for /auth/me."""

    user_id: UUID
    email: str | None
    age: int
    severity_level: int
