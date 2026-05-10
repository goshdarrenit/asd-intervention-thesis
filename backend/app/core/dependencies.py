"""FastAPI dependency functions for authentication."""
from typing import Annotated
from uuid import UUID

from fastapi import Depends, HTTPException, Request, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.deps import get_db
from app.core.security import decode_token
from app.domains.auth.models import AdminAccount
from app.domains.users.models import User

_bearer_scheme = HTTPBearer()


async def get_current_user(
    credentials: Annotated[HTTPAuthorizationCredentials, Depends(_bearer_scheme)],
    db: Annotated[AsyncSession, Depends(get_db)],
) -> User:
    """Decode Bearer JWT and return the authenticated User.

    Raises:
        401: If token is missing, invalid, or user not found.
    """
    credentials_exception = HTTPException(
        status_code=status.HTTP_401_UNAUTHORIZED,
        detail="Could not validate credentials",
        headers={"WWW-Authenticate": "Bearer"},
    )

    payload = decode_token(credentials.credentials)
    if payload is None:
        raise credentials_exception

    sub: str = payload.get("sub", "")
    if not sub.startswith("user:"):
        raise credentials_exception

    try:
        user_id = UUID(sub[len("user:"):])
    except ValueError:
        raise credentials_exception

    result = await db.execute(select(User).where(User.user_id == user_id))
    user = result.scalar_one_or_none()
    if user is None:
        raise credentials_exception

    return user


async def get_admin_from_cookie(
    request: Request,
    db: Annotated[AsyncSession, Depends(get_db)],
) -> AdminAccount | None:
    """Decode cookie JWT and return AdminAccount, or None if not authenticated."""
    token = request.cookies.get("access_token")
    if not token:
        return None

    payload = decode_token(token)
    if payload is None:
        return None

    sub: str = payload.get("sub", "")
    if not sub.startswith("admin:"):
        return None

    try:
        admin_id = UUID(sub[len("admin:"):])
    except ValueError:
        return None

    result = await db.execute(select(AdminAccount).where(AdminAccount.id == admin_id))
    admin = result.scalar_one_or_none()
    if admin is None or not admin.is_active:
        return None

    return admin


# Type alias for protected routes
CurrentUser = Annotated[User, Depends(get_current_user)]
