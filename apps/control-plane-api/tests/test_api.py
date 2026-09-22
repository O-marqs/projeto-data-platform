from fastapi.testclient import TestClient

from app.config import Settings
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
