"""Custom application exceptions with structured error format."""
from typing import Any


class AppException(Exception):
    """Base application exception with structured error information."""

    def __init__(
        self,
        message: str,
        code: str,
        status_code: int = 500,
        details: dict[str, Any] | None = None,
    ):
        self.message = message
        self.code = code
        self.status_code = status_code
        self.details = details or {}
        super().__init__(self.message)


class UserNotFoundException(AppException):
    """Raised when a user is not found."""

    def __init__(self, user_id: str | int, details: dict[str, Any] | None = None):
        super().__init__(
            message=f"User not found: {user_id}",
            code="USER_NOT_FOUND",
            status_code=404,
            details=details or {"user_id": user_id},
        )


class SessionNotFoundException(AppException):
    """Raised when a session is not found."""

    def __init__(self, session_id: str | int, details: dict[str, Any] | None = None):
        super().__init__(
            message=f"Session not found: {session_id}",
            code="SESSION_NOT_FOUND",
            status_code=404,
            details=details or {"session_id": session_id},
        )


class ValidationException(AppException):
    """Raised when validation fails."""

    def __init__(self, message: str, details: dict[str, Any] | None = None):
        super().__init__(
            message=message,
            code="VALIDATION_ERROR",
            status_code=422,
            details=details,
        )


class SessionAlreadyEndedException(AppException):
    """Raised when attempting to end a session that is already ended."""

    def __init__(self, session_id: str | int, details: dict[str, Any] | None = None):
        super().__init__(
            message=f"Session already ended: {session_id}",
            code="SESSION_ALREADY_ENDED",
            status_code=400,
            details=details or {"session_id": session_id},
        )
