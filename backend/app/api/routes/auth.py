"""Authentication routes — register, login, and me."""
from fastapi import APIRouter, HTTPException, status
from sqlalchemy import select

from app.api.deps import DbSession
from app.core.dependencies import CurrentUser
from app.core.security import create_access_token, hash_password, verify_password
from app.domains.auth.schemas import LoginRequest, MeResponse, RegisterRequest, TokenResponse
from app.domains.users import repository as user_repository
from app.domains.users.models import User

router = APIRouter(prefix="/api/auth", tags=["auth"])


@router.post("/register", response_model=TokenResponse, status_code=status.HTTP_201_CREATED)
async def register(request: RegisterRequest, db: DbSession) -> TokenResponse:
    """Register a new guardian account and child profile.

    Creates a User row with hashed password and email, plus an initialized
    UserProfile. Returns a JWT access token.

    Raises:
        409: Email already registered.
    """
    # Check for duplicate email
    result = await db.execute(select(User).where(User.email == request.email))
    if result.scalar_one_or_none() is not None:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="Email already registered",
        )

    # Create user with auth credentials
    user = await user_repository.create_user(
        db=db,
        age=request.age,
        severity_level=request.severity_level,
        email=request.email,
        hashed_password=hash_password(request.password),
    )

    token = create_access_token(sub=f"user:{user.user_id}")
    return TokenResponse(access_token=token, user_id=user.user_id)


@router.post("/login", response_model=TokenResponse)
async def login(request: LoginRequest, db: DbSession) -> TokenResponse:
    """Authenticate with email + password, return JWT.

    Raises:
        401: Invalid email or password.
    """
    result = await db.execute(select(User).where(User.email == request.email))
    user = result.scalar_one_or_none()

    if user is None or user.hashed_password is None:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid email or password",
        )

    if not verify_password(request.password, user.hashed_password):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid email or password",
        )

    token = create_access_token(sub=f"user:{user.user_id}")
    return TokenResponse(access_token=token, user_id=user.user_id)


@router.get("/me", response_model=MeResponse)
async def me(current_user: CurrentUser) -> MeResponse:
    """Return the authenticated user's profile info.

    Requires: Authorization: Bearer <token>
    """
    return MeResponse(
        user_id=current_user.user_id,
        email=current_user.email,
        age=current_user.age,
        severity_level=current_user.severity_level,
    )
