from collections.abc import Generator
from contextlib import asynccontextmanager
from datetime import datetime
import logging
from typing import Annotated
from uuid import UUID

from fastapi import Depends, FastAPI, HTTPException, status
from pydantic import BaseModel, ConfigDict
from sqlalchemy import select, text
from sqlalchemy.exc import SQLAlchemyError
from sqlalchemy.orm import Session, sessionmaker

from app.config import Settings, get_settings
from app.db import create_engine_for_settings, create_session_factory, session_dependency
from app.models import Connection
from app.security import CONNECTION_READ, Identity, get_current_identity

logger = logging.getLogger(__name__)


class ConnectionResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: UUID
    domain_id: UUID
    name: str
    connection_type: str
    config: dict[str, object]
    created_at: datetime


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
    TrustedIdentity = Annotated[Identity, Depends(get_current_identity)]

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

    @app.get(
        "/connections/{connection_id}",
        response_model=ConnectionResponse,
        tags=["connections"],
    )
    def get_connection(
        connection_id: UUID,
        session: DbSession,
        identity: TrustedIdentity,
    ) -> ConnectionResponse:
        connection = session.scalar(
            select(Connection).where(Connection.id == connection_id)
        )
        if connection is None:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail={"code": "connection_not_found"},
            )

        allowed = identity.can(CONNECTION_READ, connection.domain_id)
        logger.info(
            "connection_access",
            extra={
                "operation": "connection.read",
                "resource_id": str(connection.id),
                "domain_id": str(connection.domain_id),
                "decision": "allow" if allowed else "deny",
            },
        )
        if not allowed:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail={"code": "connection_access_denied"},
            )

        return ConnectionResponse.model_validate(connection)

    return app


app = create_app()
