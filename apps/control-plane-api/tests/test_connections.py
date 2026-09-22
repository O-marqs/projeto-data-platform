import logging
from uuid import UUID, uuid4

import pytest
from fastapi.testclient import TestClient
from sqlalchemy.exc import IntegrityError

from app.config import Settings
from app.main import create_app
from app.models import Connection, Domain, Organization
from app.security import (
    CONNECTION_ADMIN,
    CONNECTION_READ,
    CONNECTION_RESOLVE,
    Identity,
    get_current_identity,
    validate_public_config,
)


def slug(prefix: str) -> str:
    return f"{prefix}-{uuid4().hex[:10]}"


def create_connection(db_session) -> tuple[UUID, UUID, str]:
    organization = Organization(slug=slug("org"))
    db_session.add(organization)
    db_session.commit()

    domain = Domain(organization_id=organization.id, slug=slug("domain"))
    db_session.add(domain)
    db_session.commit()
    connection = Connection(
        domain_id=domain.id,
        name="orders-source",
        connection_type="postgresql",
        config={"endpoint": "orders.internal", "database": "orders"},
        secret_ref=f"sref_{uuid4().hex}",
    )
    db_session.add(connection)
    db_session.commit()
    return connection.id, domain.id, connection.secret_ref


def client_for(settings: Settings, identity: Identity) -> TestClient:
    app = create_app(settings)
    app.dependency_overrides[get_current_identity] = lambda: identity
    return TestClient(app)


def test_authorized_identity_reads_connection_without_secret_ref(settings, db_session) -> None:
    connection_id, domain_id, secret_ref = create_connection(db_session)
    identity = Identity(
        subject="synthetic-reader",
        domain_ids=frozenset({domain_id}),
        permissions=frozenset({CONNECTION_READ}),
    )

    with client_for(settings, identity) as client:
        response = client.get(f"/connections/{connection_id}")

    assert response.status_code == 200
    body = response.json()
    assert body["id"] == str(connection_id)
    assert body["domain_id"] == str(domain_id)
    assert body["connection_type"] == "postgresql"
    assert "secret_ref" not in body
    assert secret_ref not in response.text


def test_missing_identity_is_denied_without_http_identity_headers(settings, db_session) -> None:
    connection_id, _, _ = create_connection(db_session)
    with TestClient(create_app(settings)) as client:
        response = client.get(
            f"/connections/{connection_id}",
            headers={"X-User-ID": "synthetic-admin", "X-Domain-ID": "forged"},
        )

    assert response.status_code == 401
    assert response.json() == {"detail": {"code": "authentication_required"}}


def test_other_domain_is_denied_even_when_connection_id_is_known(settings, db_session) -> None:
    connection_id, domain_id, _ = create_connection(db_session)
    other_identity = Identity(
        subject="synthetic-other-domain",
        domain_ids=frozenset({uuid4()}),
        permissions=frozenset({CONNECTION_READ, CONNECTION_ADMIN, CONNECTION_RESOLVE}),
    )

    with client_for(settings, other_identity) as client:
        response = client.get(f"/connections/{connection_id}")

    assert response.status_code == 403
    assert response.json() == {"detail": {"code": "connection_access_denied"}}
    assert str(domain_id) not in response.text


@pytest.mark.parametrize(
    "permissions,expected_status",
    [
        ({CONNECTION_ADMIN}, 200),
        ({CONNECTION_RESOLVE}, 403),
        (set(), 403),
    ],
)
def test_connection_permission_matrix(settings, db_session, permissions, expected_status) -> None:
    connection_id, domain_id, _ = create_connection(db_session)
    identity = Identity(
        subject="synthetic-matrix",
        domain_ids=frozenset({domain_id}),
        permissions=frozenset(permissions),
    )

    with client_for(settings, identity) as client:
        response = client.get(f"/connections/{connection_id}")

    assert response.status_code == expected_status


def test_sensitive_values_are_not_logged_or_returned(settings, db_session, caplog) -> None:
    connection_id, domain_id, _ = create_connection(db_session)
    marker = "synthetic-secret-marker-do-not-publish"
    identity = Identity(
        subject="synthetic-denied",
        domain_ids=frozenset({uuid4()}),
        permissions=frozenset({CONNECTION_READ}),
    )

    caplog.set_level(logging.INFO, logger="app.main")
    with client_for(settings, identity) as client:
        response = client.get(
            f"/connections/{connection_id}",
            headers={"Authorization": f"Bearer {marker}"},
        )

    assert response.status_code == 403
    assert marker not in response.text
    assert marker not in caplog.text
    assert str(domain_id) not in response.text


def test_public_config_rejects_sensitive_keys_and_connection_strings() -> None:
    with pytest.raises(ValueError, match="sensitive material"):
        validate_public_config({"password": "synthetic-secret"})
    with pytest.raises(ValueError, match="sensitive material"):
        validate_public_config({"endpoint": "postgresql://user:secret@host/db"})


def test_connection_constraints_reject_invalid_secret_ref_and_duplicate_name(db_session) -> None:
    organization = Organization(slug=slug("org"))
    db_session.add(organization)
    db_session.commit()
    domain = Domain(organization_id=organization.id, slug=slug("domain"))
    db_session.add(domain)
    db_session.commit()

    with pytest.raises(ValueError, match="opaque"):
        Connection(
            domain_id=domain.id,
            name="invalid-secret-ref",
            connection_type="postgresql",
            config={},
            secret_ref="/host/path/to/secret",
        )

    first = Connection(
        domain_id=domain.id,
        name="same-name",
        connection_type="postgresql",
        config={},
        secret_ref=f"sref_{uuid4().hex}",
    )
    second = Connection(
        domain_id=domain.id,
        name="same-name",
        connection_type="s3",
        config={},
        secret_ref=f"sref_{uuid4().hex}",
    )
    db_session.add(first)
    db_session.commit()
    db_session.add(second)
    with pytest.raises(IntegrityError):
        db_session.commit()
