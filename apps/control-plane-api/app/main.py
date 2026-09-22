from collections.abc import Generator
from contextlib import asynccontextmanager
from typing import Annotated

from fastapi import Depends, FastAPI, HTTPException, status
from sqlalchemy import text
from sqlalchemy.exc import SQLAlchemyError
from sqlalchemy.orm import Session, sessionmaker

from app.config import Settings, get_settings
from app.db import create_engine_for_settings, create_session_factory, session_dependency


def create_app(
    settings: Settings | None = None,
    session_factory: sessionmaker[Session] | None = None,
) -> FastAPI:
    configured_settings = settings or get_settings()
    engine = create_engine_for_settings(configured_settings)
    configured_session_factory = session_factory or create_session_factory(engine)

    @asynccontextmanager
    async def lifespan(_: FastAPI):
        try:
            yield
        finally:
            engine.dispose()

    app = FastAPI(
        title="Data Platform Control Plane API",
        version="0.1.0",
        lifespan=lifespan,
    )

    def get_db() -> Generator[Session, None, None]:
        yield from session_dependency(configured_session_factory)

    DbSession = Annotated[Session, Depends(get_db)]

    @app.get("/health/live", tags=["health"])
    def live() -> dict[str, str]:
        return {"status": "ok"}

    @app.get("/health/ready", tags=["health"])
    def ready(session: DbSession) -> dict[str, str]:
        try:
            session.execute(text("SELECT 1"))
        except SQLAlchemyError:
            raise HTTPException(
                status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
                detail={"status": "not_ready", "reason": "database_unavailable"},
            ) from None

        try:
            revision = session.execute(
                text("SELECT version_num FROM alembic_version")
            ).scalar_one_or_none()
        except SQLAlchemyError:
            raise HTTPException(
                status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
                detail={"status": "not_ready", "reason": "migrations_not_applied"},
            ) from None

        if revision != configured_settings.required_migration_revision:
            raise HTTPException(
                status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
                detail={"status": "not_ready", "reason": "migrations_not_current"},
            )

        return {"status": "ready", "database": "ok", "migrations": "current"}

    return app


app = create_app()
