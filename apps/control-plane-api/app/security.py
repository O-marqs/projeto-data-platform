import json
import logging
import re
import uuid
from dataclasses import dataclass
from typing import Any

from fastapi import HTTPException, status

logger = logging.getLogger(__name__)

CONNECTION_READ = "connection:read"
CONNECTION_ADMIN = "connection:admin"
CONNECTION_RESOLVE = "connection:resolve"

_SECRET_REF_PATTERN = re.compile(r"^sref_[A-Za-z0-9][A-Za-z0-9_-]{7,127}$")
_FORBIDDEN_CONFIG_KEY = re.compile(
    r"(?:password|passphrase|secret|token|api[_-]?key|authorization|credential|private[_-]?key|connection[_-]?string)",
    re.IGNORECASE,
)
_SENSITIVE_CONFIG_VALUE = re.compile(
    r"(?:bearer\s+\S+|://[^/\s:@]+:[^@\s]+@|(?:password|token|secret|api[_-]?key)\s*=)",
    re.IGNORECASE,
)


@dataclass(frozen=True)
class Identity:
    """Trusted identity supplied by an authentication adapter in the future."""

    subject: str
    domain_ids: frozenset[uuid.UUID]
    permissions: frozenset[str]
    workload_id: str | None = None

    def can(self, action: str, domain_id: uuid.UUID) -> bool:
        if domain_id not in self.domain_ids:
            return False
        if action == CONNECTION_READ:
            return CONNECTION_READ in self.permissions or CONNECTION_ADMIN in self.permissions
        return action in self.permissions


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


def validate_public_config(value: Any) -> dict[str, Any]:
    if not isinstance(value, dict):
        raise ValueError("connection config must be a JSON object")

    def walk(item: Any) -> None:
        if isinstance(item, dict):
            for key, nested in item.items():
                if not isinstance(key, str) or _FORBIDDEN_CONFIG_KEY.search(key):
                    raise ValueError("connection config contains sensitive material")
                walk(nested)
        elif isinstance(item, list):
            for nested in item:
                walk(nested)
        elif isinstance(item, str) and _SENSITIVE_CONFIG_VALUE.search(item):
            raise ValueError("connection config contains sensitive material")

    walk(value)
    json.dumps(value)
    return value


class SecretResolutionUnavailable(RuntimeError):
    """Raised until SEC-01 supplies a real, authenticated secret resolver."""


class SecretResolver:
    """Contract for SEC-01; this card deliberately provides no resolver."""

    def resolve(self, *, secret_ref: str, identity: Identity, domain_id: uuid.UUID) -> str:
        validate_secret_ref(secret_ref)
        if not identity.can(CONNECTION_RESOLVE, domain_id):
            raise PermissionError("secret resolution is not authorized")
        raise SecretResolutionUnavailable("no secret resolver is configured")
