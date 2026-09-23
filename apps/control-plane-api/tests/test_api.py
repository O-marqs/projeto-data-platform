from fastapi.testclient import TestClient

from app.config import CURRENT_MIGRATION_REVISION, Settings
from app.main import create_app


def test_liveness_does_not_require_database(settings: Settings) -> None:
    with TestClient(create_app(settings)) as client:
        response = client.get("/health/live")

    assert response.status_code == 200
    assert response.json() == {"status": "ok"}


def test_readiness_requires_current_migration(settings: Settings) -> None:
    with TestClient(create_app(settings)) as client:
        response = client.get("/health/ready")

    assert response.status_code == 200
    assert response.json() == {
        "status": "ready",
        "database": "ok",
        "migrations": "current",
    }


def test_legacy_revision_setting_is_upgraded_to_current_head(settings: Settings) -> None:
    legacy = Settings(
        database_url=settings.database_url,
        required_migration_revision="0001_initial_control_plane",
    )

    assert legacy.required_migration_revision == CURRENT_MIGRATION_REVISION


def test_readiness_returns_503_when_migrations_are_pending(settings: Settings) -> None:
    pending = Settings(
        database_url=settings.database_url,
        required_migration_revision="0005_pending_revision",
    )
    with TestClient(create_app(pending)) as client:
        response = client.get("/health/ready")

    assert response.status_code == 503
    assert response.json() == {
        "detail": {"status": "not_ready", "reason": "migrations_not_current"}
    }


def test_readiness_returns_503_without_database() -> None:
    unavailable = Settings(
        database_url="postgresql+psycopg://control_user:invalid@control-db:5999/control_db"
    )
    with TestClient(create_app(unavailable)) as client:
        response = client.get("/health/ready")

    assert response.status_code == 503
    assert response.json() == {
        "detail": {"status": "not_ready", "reason": "database_unavailable"}
    }
