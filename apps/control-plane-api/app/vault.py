import json
from dataclasses import dataclass, field
from typing import Any
from urllib.error import HTTPError, URLError
from urllib.parse import quote
from urllib.request import Request, urlopen
from uuid import UUID

from sqlalchemy.orm import Session

from app.models import Connection
from app.security import CONNECTION_RESOLVE, Identity, validate_secret_ref


class VaultError(RuntimeError):
    """Base error for controlled Vault integration failures."""


class VaultUnavailable(VaultError):
    """Vault cannot be reached from the workload."""


class VaultSealed(VaultError):
    """Vault is initialized but sealed or not ready for reads."""


class VaultAccessDenied(VaultError):
    """Vault rejected the workload token or policy path."""


class VaultAuthenticationFailed(VaultError):
    """AppRole authentication did not produce a usable workload token."""


class VaultResponseInvalid(VaultError):
    """Vault returned a response that cannot be used safely."""


@dataclass(frozen=True)
class VaultWorkloadIdentity:
    """Identity and token produced by a successful AppRole login.

    The token is intentionally kept out of repr output. It exists only in the
    workload process and is never part of an HTTP response or Control DB row.
    """

    identity: Identity
    token: str = field(repr=False)
    token_accessor: str | None = field(default=None, repr=False)


def connection_secret_path(connection: Connection) -> str:
    """Build the only Vault path accepted for a persisted Connection."""

    secret_ref = validate_secret_ref(connection.secret_ref)
    return (
        f"connections/{connection.domain_id}/{connection.id}/{secret_ref}"
    )


class VaultClient:
    def __init__(
        self,
        address: str,
        *,
        approle_mount: str = "approle",
        kv_mount: str = "pdp",
        timeout: float = 3.0,
    ) -> None:
        self.address = address.rstrip("/")
        self.approle_mount = approle_mount.strip("/")
        self.kv_mount = kv_mount.strip("/")
        self.timeout = timeout

    def _request(
        self,
        method: str,
        path: str,
        *,
        token: str | None = None,
        payload: dict[str, Any] | None = None,
    ) -> dict[str, Any]:
        body = None if payload is None else json.dumps(payload).encode("utf-8")
        headers = {"Content-Type": "application/json"}
        if token:
            headers["X-Vault-Token"] = token
        request = Request(
            f"{self.address}{path}",
            data=body,
            headers=headers,
            method=method,
        )
        try:
            with urlopen(request, timeout=self.timeout) as response:
                raw = response.read()
        except HTTPError as error:
            if error.code in {401, 403}:
                raise VaultAccessDenied("Vault denied the workload request") from None
            if error.code in {501, 503}:
                raise VaultSealed("Vault is not ready for workload requests") from None
            raise VaultError(f"Vault request failed with HTTP {error.code}") from None
        except (TimeoutError, URLError, OSError):
            raise VaultUnavailable("Vault is unavailable") from None

        if not raw:
            return {}
        try:
            decoded = json.loads(raw.decode("utf-8"))
        except (UnicodeDecodeError, json.JSONDecodeError):
            raise VaultResponseInvalid("Vault returned an invalid response") from None
        if not isinstance(decoded, dict):
            raise VaultResponseInvalid("Vault returned an invalid response")
        return decoded

    def authenticate_approle(self, role_id: str, secret_id: str) -> VaultWorkloadIdentity:
        response = self._request(
            "POST",
            f"/v1/auth/{quote(self.approle_mount, safe='')}/login",
            payload={"role_id": role_id, "secret_id": secret_id},
        )
        auth = response.get("auth")
        if not isinstance(auth, dict):
            raise VaultAuthenticationFailed("Vault did not return an AppRole session")
        token = auth.get("client_token")
        metadata = auth.get("metadata")
        if not isinstance(token, str) or not token or not isinstance(metadata, dict):
            raise VaultAuthenticationFailed("Vault returned incomplete workload identity")

        try:
            domain_id = UUID(str(metadata["domain_id"]))
            connection_id = UUID(str(metadata["connection_id"]))
            workload_id = str(metadata["workload_id"])
        except (KeyError, TypeError, ValueError):
            raise VaultAuthenticationFailed("Vault workload metadata is invalid") from None
        if not workload_id:
            raise VaultAuthenticationFailed("Vault workload metadata is invalid")

        identity = Identity(
            subject=f"vault:approle:{workload_id}",
            domain_ids=frozenset({domain_id}),
            permissions=frozenset({CONNECTION_RESOLVE}),
            workload_id=workload_id,
            connection_ids=frozenset({connection_id}),
        )
        accessor = auth.get("accessor")
        return VaultWorkloadIdentity(
            identity=identity,
            token=token,
            token_accessor=accessor if isinstance(accessor, str) else None,
        )

    def read_kv2(self, path: str, *, token: str) -> dict[str, Any]:
        encoded_path = quote(path.strip("/"), safe="/")
        response = self._request(
            "GET",
            f"/v1/{quote(self.kv_mount, safe='')}/data/{encoded_path}",
            token=token,
        )
        data = response.get("data")
        if not isinstance(data, dict) or not isinstance(data.get("data"), dict):
            raise VaultResponseInvalid("Vault returned an invalid KV response")
        return data["data"]

    def revoke_self(self, *, token: str) -> None:
        self._request("POST", "/v1/auth/token/revoke-self", token=token, payload={})


class VaultSecretResolver:
    """Resolve a persisted Connection through a real authenticated workload."""

    def __init__(self, client: VaultClient, workload: VaultWorkloadIdentity) -> None:
        self._client = client
        self._workload = workload

    def resolve(
        self,
        *,
        connection_id: UUID,
        identity: Identity,
        session: Session,
    ) -> str:
        # Object identity prevents a caller from reconstructing a trusted
        # Identity from arbitrary request fields inside this process.
        if identity is not self._workload.identity:
            raise PermissionError("secret resolution requires a Vault-authenticated workload")

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

        data = self._client.read_kv2(
            connection_secret_path(connection),
            token=self._workload.token,
        )
        if data.get("secret_ref") != connection.secret_ref:
            raise VaultResponseInvalid("Vault secret reference does not match Connection")
        value = data.get("value")
        if not isinstance(value, str) or not value:
            raise VaultResponseInvalid("Vault secret value is unavailable")
        return value
