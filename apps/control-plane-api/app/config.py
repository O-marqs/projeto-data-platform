from functools import lru_cache

from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    app_env: str = "local"
    log_level: str = "INFO"
    database_url: str = (
        "postgresql+psycopg://control_user:change-me-control-password"
        "@control-db:5432/control_db"
    )
    required_migration_revision: str = "0003_connection_config_safety"

    model_config = SettingsConfigDict(
        env_prefix="CONTROL_",
        env_file=".env",
        extra="ignore",
    )


@lru_cache
def get_settings() -> Settings:
    return Settings()
