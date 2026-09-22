from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql


revision = "0002_connection"
down_revision = "0001_initial_control_plane"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        "connections",
        sa.Column(
            "id",
            postgresql.UUID(as_uuid=True),
            server_default=sa.text("gen_random_uuid()"),
            nullable=False,
        ),
        sa.Column("domain_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("name", sa.String(length=100), nullable=False),
        sa.Column("connection_type", sa.String(length=50), nullable=False),
        sa.Column(
            "config",
            postgresql.JSONB(astext_type=sa.Text()),
            server_default=sa.text("'{}'::jsonb"),
            nullable=False,
        ),
        sa.Column("secret_ref", sa.String(length=128), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.ForeignKeyConstraint(["domain_id"], ["domains.id"]),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("domain_id", "name", name="uq_connections_domain_name"),
        sa.CheckConstraint("length(trim(name)) > 0", name="ck_connections_name_not_blank"),
        sa.CheckConstraint(
            "secret_ref ~ '^sref_[A-Za-z0-9][A-Za-z0-9_-]{7,127}$'",
            name="ck_connections_secret_ref_opaque",
        ),
    )


def downgrade() -> None:
    op.drop_table("connections")
