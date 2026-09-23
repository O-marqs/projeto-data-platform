import json
import logging
import re
import uuid
from dataclasses import dataclass
from typing import Any
from urllib.parse import urlsplit

from fastapi import HTTPException, status
from sqlalchemy.orm import Session

logger = logging.getLogger(__name__)

CONNECTION_READ = "connection:read"
CONNECTION_ADMIN = "connection:admin"
CONNECTION_RESOLVE = "connection:resolve"

_SECRET_REF_PATTERN = re.compile(r"^sref_[A-Za-z0-9][A-Za-z0-9_-]{7,127}$")
_IDENTIFIER_PATTERN = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$")
_HOSTNAME_PATTERN = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._-]{0,252}$")
_SENSITIVE_CONFIG_VALUE = re.compile(
    r"(?:bearer\s+\S+|://[^/\s:@]+:[^@\s]+@|(?:password|token|secret|api[_-]?key)\s*=)",
    re.IGNORECASE,
)

PUBLIC_CONFIG_SCHEMA: dict[str, dict[str, str]] = {
    "postgresql": {
        "endpoint": "endpoint",
        "database": "identifier",
        "schema": "identifier",
        "port": "port",
        "sslmode": "sslmode",
    },
    "s3": {
        "endpoint": "endpoint",
        "bucket": "identifier",
        "region": "identifier",
        "path_style": "boolean",
        "use_ssl": "boolean",
    },
}


@dataclass(frozen=True)
class Identity:
    """Trusted identity supplied by an authentication adapter in the future."""

    subject: str
    domain_ids: frozenset[uuid.UUID]
    permissions: frozenset[str]
    workload_id: str | None = None
    connection_ids: frozenset[uuid.UUID] = frozenset()

    def can(self, action: str, domain_id: uuid.UUID) -> bool:
        if domain_id not in self.domain_ids:
            return False
        if action == CONNECTION_READ:
            return CONNECTION_READ in self.permissions or CONNECTION_ADMIN in self.permissions
        return action in self.permissions

    def can_connection(
        self,
        action: str,
        *,
        connection_id: uuid.UUID,
        domain_id: uuid.UUID,
        require_workload: bool = False,
    ) -> bool:
        if require_workload and not self.workload_id:
            return False
        return self.can(action, domain_id) and connection_id in self.connection_ids


def get_current_identity() -> Identity:
    """Deny requests until a real authentication adapter is integrated."""

    raise HTTPException(
        status_code=status.HTTP_401_UNAUTHORIZED,
        detail={"code": "authentication_required"},
        headers={"WWW-Authenticate": "Bearer"},
    )


def validate_secret_ref(value: str) -> str:
    if not isinstance(value, str) or not _SECRET_REF_PATTERN.fullmatch(value):
        raise ValueError("secret_ref must be an opaque sref_ identifier")
    return value


def validate_connection_type(value: str) -> str:
    if not isinstance(value, str) or value not in PUBLIC_CONFIG_SCHEMA:
        raise ValueError("connection_type is not supported in this stage")
    return value


def _validate_endpoint(value: Any) -> None:
    if not isinstance(value, str) or not value or len(value) > 255:
        raise ValueError("connection endpoint must be a public endpoint")
    if _SENSITIVE_CONFIG_VALUE.search(value):
        raise ValueError("connection config contains sensitive material")
    if "://" not in value:
        if not _HOSTNAME_PATTERN.fullmatch(value):
            raise ValueError("connection endpoint must be a public endpoint")
        return
    parsed = urlsplit(value)
    if parsed.scheme not in {"http", "https"} or not parsed.hostname:
        raise ValueError("connection endpoint must be a public endpoint")
    if parsed.username or parsed.password or parsed.query or parsed.fragment:
        raise ValueError("connection config contains sensitive material")


def _validate_public_field(name: str, kind: str, value: Any) -> None:
    if kind == "endpoint":
        _validate_endpoint(value)
    elif kind == "identifier":
        if not isinstance(value, str) or not _IDENTIFIER_PATTERN.fullmatch(value):
            raise ValueError(f"connection config field {name} is invalid")
    elif kind == "port":
        if isinstance(value, bool) or not isinstance(value, int) or not 1 <= value <= 65535:
            raise ValueError("connection config port is invalid")
    elif kind == "sslmode":
        if value not in {"disable", "require", "verify-ca", "verify-full"}:
            raise ValueError("connection config sslmode is invalid")
    elif kind == "boolean":
        if not isinstance(value, bool):
            raise ValueError(f"connection config field {name} must be boolean")
    else:
        raise ValueError("connection config schema is invalid")


def validate_public_config(value: Any, connection_type: str) -> dict[str, Any]:
    validate_connection_type(connection_type)
    if not isinstance(value, dict):
        raise ValueError("connection config must be a JSON object")

    schema = PUBLIC_CONFIG_SCHEMA[connection_type]
    unknown_fields = set(value) - set(schema)
    if unknown_fields:
        raise ValueError("connection config contains a field outside the public schema")
    for name, field_value in value.items():
        if not isinstance(name, str):
            raise ValueError("connection config field names must be strings")
        _validate_public_field(name, schema[name], field_value)
    json.dumps(value)
    return value


class SecretResolutionUnavailable(RuntimeError):
    """Raised when the base resolver has not been replaced by a real one."""


class SecretResolver:
    """Base contract; VaultSecretResolver is the opt-in SEC-01 implementation."""

    def resolve(
        self,
        *,
        connection_id: uuid.UUID,
        identity: Identity,
        session: Session,
    ) -> str:
        """Resolve only after loading and authorizing a persisted Connection."""

        from app.models import Connection

        connection = session.get(Connection, connection_id)
        if connection is None:
            raise LookupError("connection not found")
        if not identity.can_connection(
            CONNECTION_RESOLVE,
            connection_id=connection.id,
            domain_id=connection.domain_id,
            require_workload=True,
        ):
            raise PermissionError("secret resolution is not authorized")
        validate_secret_ref(connection.secret_ref)
        raise SecretResolutionUnavailable("no secret resolver is configured")
