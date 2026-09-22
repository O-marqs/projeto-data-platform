from urllib.parse import urlsplit

import pytest
from sqlalchemy import text
from sqlalchemy.orm import Session

from app.config import Settings
from app.db import create_engine_for_settings, create_session_factory


@pytest.fixture(scope="session")
def settings() -> Settings:
    configured = Settings()
    database_name = urlsplit(configured.database_url).path.lstrip("/")
    if configured.app_env != "test" or database_name != "control_test_db":
        raise RuntimeError(
            "Testes bloqueados: use CONTROL_APP_ENV=test e o database descartavel control_test_db."
        )
    return configured


@pytest.fixture(scope="session")
def session_factory(settings: Settings):
    engine = create_engine_for_settings(settings)
    factory = create_session_factory(engine)
    yield factory
    engine.dispose()


@pytest.fixture
def db_session(session_factory) -> Session:
    session = session_factory()
    try:
        yield session
    finally:
        session.rollback()
        for table in ("data_products", "teams", "domains", "organizations"):
            session.execute(text(f"DELETE FROM {table}"))
        session.commit()
        session.close()
