"""Data access layer for users and profiles.

Repository pattern for database operations on User and UserProfile models.
"""
from typing import Optional
from uuid import UUID

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from app.domains.users.models import User, UserProfile


async def create_user(
    db: AsyncSession,
    age: int,
    severity_level: int,
    guardian_email: Optional[str] = None,
    email: Optional[str] = None,
    hashed_password: Optional[str] = None,
) -> User:
    """Create a new user with an initialized profile.

    Creates:
    - User row with demographic data
    - UserProfile row with defaults and initialized state_vector

    The state_vector is initialized as a 60-element list with:
    - First 2 elements: normalized age and severity_level
    - Remaining 58 elements: zeros (will be populated by RL model)

    Args:
        db: Async database session
        age: Child's age (4-18)
        severity_level: ASD severity (1-3)
        guardian_email: Optional guardian contact email

    Returns:
        User: Created user with profile relationship loaded
    """
    # Create user
    user = User(
        age=age,
        severity_level=severity_level,
        guardian_email=guardian_email,
        email=email,
        hashed_password=hashed_password,
    )
    db.add(user)
    await db.flush()  # Get user_id without committing

    # Normalize age and severity for state vector
    # Age: 4-18 -> map to [0, 1]
    normalized_age = (age - 4) / (18 - 4)
    # Severity: 1-3 -> map to [0, 1]
    normalized_severity = (severity_level - 1) / (3 - 1)

    # Initialize 60-dimensional state vector
    state_vector = [normalized_age, normalized_severity] + [0.0] * 58

    # Create profile with initialized state_vector
    profile = UserProfile(
        user_id=user.user_id,
        state_vector=state_vector,  # Store as list directly (JSONB handles it)
    )
    db.add(profile)
    await db.flush()

    # Load the profile relationship
    await db.refresh(user, attribute_names=["profile"])

    return user


async def get_user_by_id(db: AsyncSession, user_id: UUID) -> Optional[User]:
    """Fetch user by ID.

    Args:
        db: Async database session
        user_id: User UUID

    Returns:
        User if found, None otherwise
    """
    result = await db.execute(
        select(User).where(User.user_id == user_id)
    )
    return result.scalar_one_or_none()


async def get_user_by_email(db: AsyncSession, email: str) -> Optional[User]:
    """Fetch user by email address.

    Args:
        db: Async database session
        email: Guardian email address

    Returns:
        User if found, None otherwise
    """
    result = await db.execute(select(User).where(User.email == email))
    return result.scalar_one_or_none()


async def get_user_profile(db: AsyncSession, user_id: UUID) -> Optional[UserProfile]:
    """Fetch user profile by user_id.

    Args:
        db: Async database session
        user_id: User UUID

    Returns:
        UserProfile if found, None otherwise
    """
    result = await db.execute(
        select(UserProfile).where(UserProfile.user_id == user_id)
    )
    return result.scalar_one_or_none()
