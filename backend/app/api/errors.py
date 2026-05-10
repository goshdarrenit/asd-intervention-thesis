"""Exception handlers for structured error responses."""
from fastapi import Request
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse

from app.core.exceptions import AppException


async def app_exception_handler(request: Request, exc: AppException) -> JSONResponse:
    """Handle custom AppException with structured JSON error format."""
    return JSONResponse(
        status_code=exc.status_code,
        content={
            "error": {
                "message": exc.message,
                "code": exc.code,
                "details": exc.details,
            }
        },
    )


async def validation_exception_handler(
    request: Request, exc: RequestValidationError
) -> JSONResponse:
    """Handle FastAPI validation errors with structured JSON error format."""
    return JSONResponse(
        status_code=422,
        content={
            "error": {
                "message": "Validation error",
                "code": "VALIDATION_ERROR",
                "details": {"errors": exc.errors()},
            }
        },
    )
