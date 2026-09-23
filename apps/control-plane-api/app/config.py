from functools import lru_cache

from pydantic import model_validator
from pydantic_settings import BaseSettings, SettingsConfigDict

CURRENT_MIGRATION_REVISION = "0004_connection_public_schema"
LEGACY_MIGRATION_REVISIONS = {
    "0001_initial_control_plane",
    "0002_connection",
    "0003_connection_config_safety",
}


class Settings(BaseSettings):
    app_env: str = "local"
    log_level: str = "INFO"
    database_url: str = (
        "postgresql+psycopg://control_user:change-me-control-password"
        "@control-db:5432/control_db"
    )
    required_migration_revision: str = CURRENT_MIGRATION_REVISION

    model_config = SettingsConfigDict(
        env_prefix="CONTROL_",
        env_file=".env",
        extra="ignore",
    )

    @model_validator(mode="after")
    def upgrade_legacy_revision_expectation(self) -> "Settings":
        if self.required_migration_revision in LEGACY_MIGRATION_REVISIONS:
            self.required_migration_revision = CURRENT_MIGRATION_REVISION
        return self


@lru_cache
def get_settings() -> Settings:
    return Settings()
