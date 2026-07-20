"""Daily Sketch FastAPI application entrypoint."""

from fastapi import FastAPI

from app.api.health import router as health_router
from app.api.moderation import router as moderation_router
from app.api.v1 import router as v1_router
from app.core.errors import register_exception_handlers
from app.core.logging import configure_logging
from app.core.middleware import RequestIDMiddleware
from app.core.settings import get_settings


def create_app() -> FastAPI:
    settings = get_settings()
    configure_logging(settings)

    application = FastAPI(
        title="Daily Sketch API",
        version=settings.release_version,
        docs_url="/docs" if settings.app_env != "production" else None,
        redoc_url="/redoc" if settings.app_env != "production" else None,
    )
    application.add_middleware(RequestIDMiddleware, settings=settings)
    register_exception_handlers(application)
    application.include_router(health_router)
    application.include_router(v1_router)
    application.include_router(moderation_router)
    return application


app = create_app()
