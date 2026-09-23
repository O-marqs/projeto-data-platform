import json
import os
from pathlib import Path
from uuid import UUID

import pytest

from app.db import create_engine_for_settings, create_session_factory
from app.config import Settings
from app.vault import (
    VaultAccessDenied,
    VaultAuthenticationFailed,
    VaultClient,
    VaultSealed,
    VaultSecretResolver,
    VaultUnavailable,
    connection_secret_path,
)


def _case() -> dict[str, str]:
    path = os.environ.get("SEC01_CASE_FILE", "/run/secrets/sec01-case.json")
    case_path = Path(path)
    if not case_path.exists():
        pytest.skip("Vault integration fixture is provisioned by scripts/sec01.ps1")
    return json.loads(case_path.read_text(encoding="utf-8"))


def _client() -> VaultClient:
    settings = Settings()
    return VaultClient(
        settings.vault_addr,
        approle_mount=settings.vault_approle_mount,
        kv_mount=settings.vault_kv_mount,
    )


def _credentials() -> dict[str, str]:
    path = os.environ.get("SEC01_CREDENTIAL_FILE", "/run/secrets/sec01-workload.json")
    return json.loads(Path(path).read_text(encoding="utf-8"))


def test_vault_workload_is_scoped_and_revocable() -> None:
    case = _case()
    credentials = _credentials()
    settings = Settings()
    factory = create_session_factory(create_engine_for_settings(settings))
    session = factory()
    try:
        client = _client()
        with pytest.raises(VaultAuthenticationFailed):
            client.authenticate_approle(credentials["role_id"], "synthetic-invalid-secret-id")
        workload = client.authenticate_approle(
            credentials["role_id"], credentials["secret_id"]
        )
        with pytest.raises(VaultAuthenticationFailed):
            client.authenticate_approle(
                credentials["role_id"], credentials["secret_id"]
            )
        resolver = VaultSecretResolver(client, workload)
        first_connection_id = UUID(case["connection_id"])
        second_connection_id = UUID(case["other_connection_id"])

        resolved = resolver.resolve(
            connection_id=first_connection_id,
            identity=workload.identity,
            session=session,
        )
        assert resolved == case["expected_value"]

        with pytest.raises(PermissionError):
            resolver.resolve(
                connection_id=second_connection_id,
                identity=workload.identity,
                session=session,
            )

        # The resolver must calculate this path from the persisted Connection.
        from app.models import Connection

        other_connection = session.get(Connection, second_connection_id)
        assert other_connection is not None
        with pytest.raises(VaultAccessDenied):
            client.read_kv2(
                connection_secret_path(other_connection), token=workload.token
            )

        client.revoke_self(token=workload.token)
        first_connection = session.get(Connection, first_connection_id)
        assert first_connection is not None
        with pytest.raises(VaultAccessDenied):
            client.read_kv2(
                connection_secret_path(first_connection), token=workload.token
            )
    finally:
        session.close()


def test_vault_failure_is_controlled() -> None:
    case = _case()
    if case.get("mode") == "available":
        pytest.skip("failure-mode test is executed with Vault stopped or sealed")

    credentials = _credentials()
    error_type = case.get("mode")
    with pytest.raises((VaultUnavailable, VaultSealed)) as caught:
        _client().authenticate_approle(credentials["role_id"], credentials["secret_id"])
    assert case["expected_value"] not in str(caught.value)
    if error_type == "unavailable":
        assert isinstance(caught.value, VaultUnavailable)
    else:
        assert isinstance(caught.value, VaultSealed)
