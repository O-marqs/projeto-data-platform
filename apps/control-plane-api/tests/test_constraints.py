from uuid import uuid4

import pytest
from sqlalchemy.exc import IntegrityError

from app.models import DataProduct, Domain, Organization, Team


def slug(prefix: str) -> str:
    return f"{prefix}-{uuid4().hex[:10]}"


def test_domain_slug_is_unique_per_organization_and_reusable_across_organizations(db_session) -> None:
    first_org = Organization(slug=slug("org"))
    second_org = Organization(slug=slug("org"))
    db_session.add_all([first_org, second_org])
    db_session.commit()

    first_domain = Domain(organization_id=first_org.id, slug="analytics")
    db_session.add(first_domain)
    db_session.commit()

    duplicate = Domain(organization_id=first_org.id, slug="analytics")
    db_session.add(duplicate)
    with pytest.raises(IntegrityError):
        db_session.commit()
    db_session.rollback()

    db_session.add(Domain(organization_id=second_org.id, slug="analytics"))
    db_session.commit()


def test_team_slug_is_unique_per_organization(db_session) -> None:
    first_org = Organization(slug=slug("org"))
    second_org = Organization(slug=slug("org"))
    db_session.add_all([first_org, second_org])
    db_session.commit()

    db_session.add(Team(organization_id=first_org.id, slug="platform", name="Platform"))
    db_session.commit()

    db_session.add(Team(organization_id=first_org.id, slug="platform", name="Duplicate"))
    with pytest.raises(IntegrityError):
        db_session.commit()
    db_session.rollback()

    db_session.add(Team(organization_id=second_org.id, slug="platform", name="Platform"))
    db_session.commit()


def test_data_product_slug_is_unique_per_domain_and_domain_is_required(db_session) -> None:
    organization = Organization(slug=slug("org"))
    db_session.add(organization)
    db_session.commit()
    domain = Domain(organization_id=organization.id, slug=slug("domain"))
    db_session.add(domain)
    db_session.commit()

    db_session.add(DataProduct(domain_id=domain.id, slug="orders"))
    db_session.commit()

    db_session.add(DataProduct(domain_id=domain.id, slug="orders"))
    with pytest.raises(IntegrityError):
        db_session.commit()
    db_session.rollback()

    db_session.add(DataProduct(domain_id=uuid4(), slug=slug("orphan")))
    with pytest.raises(IntegrityError):
        db_session.commit()
