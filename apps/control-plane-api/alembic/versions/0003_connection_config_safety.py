from alembic import op


revision = "0003_connection_config_safety"
down_revision = "0002_connection"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_check_constraint(
        "ck_connections_config_public_keys",
        "connections",
        "config::text !~* '(password|passphrase|secret|token|(api|access)[_-]?key|authorization|credential|private[_-]?key|connection[_-]?string)'",
    )
    op.create_check_constraint(
        "ck_connections_config_no_embedded_credentials",
        "connections",
        "config::text !~* '(bearer[[:space:]]+|://[^/[:space:]@]+:[^@[:space:]]+@)'",
    )


def downgrade() -> None:
    op.drop_constraint("ck_connections_config_no_embedded_credentials", "connections", type_="check")
    op.drop_constraint("ck_connections_config_public_keys", "connections", type_="check")
