from alembic import op


revision = "0004_connection_public_schema"
down_revision = "0003_connection_config_safety"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_check_constraint(
        "ck_connections_type_supported",
        "connections",
        "connection_type IN ('postgresql', 's3')",
    )
    op.create_check_constraint(
        "ck_connections_config_object",
        "connections",
        "jsonb_typeof(config) = 'object'",
    )
    op.create_check_constraint(
        "ck_connections_config_public_allowlist",
        "connections",
        """
        CASE
            WHEN connection_type = 'postgresql' THEN
                config - ARRAY['endpoint', 'database', 'schema', 'port', 'sslmode']::text[] = '{}'::jsonb
            WHEN connection_type = 's3' THEN
                config - ARRAY['endpoint', 'bucket', 'region', 'path_style', 'use_ssl']::text[] = '{}'::jsonb
            ELSE false
        END
        """,
    )
    op.create_check_constraint(
        "ck_connections_config_public_scalar_types",
        "connections",
        """
        CASE
            WHEN connection_type = 'postgresql' THEN
                (NOT (config ? 'endpoint') OR jsonb_typeof(config -> 'endpoint') = 'string')
                AND (NOT (config ? 'database') OR jsonb_typeof(config -> 'database') = 'string')
                AND (NOT (config ? 'schema') OR jsonb_typeof(config -> 'schema') = 'string')
                AND (NOT (config ? 'port') OR jsonb_typeof(config -> 'port') = 'number')
                AND (NOT (config ? 'sslmode') OR jsonb_typeof(config -> 'sslmode') = 'string')
            WHEN connection_type = 's3' THEN
                (NOT (config ? 'endpoint') OR jsonb_typeof(config -> 'endpoint') = 'string')
                AND (NOT (config ? 'bucket') OR jsonb_typeof(config -> 'bucket') = 'string')
                AND (NOT (config ? 'region') OR jsonb_typeof(config -> 'region') = 'string')
                AND (NOT (config ? 'path_style') OR jsonb_typeof(config -> 'path_style') = 'boolean')
                AND (NOT (config ? 'use_ssl') OR jsonb_typeof(config -> 'use_ssl') = 'boolean')
            ELSE false
        END
        """,
    )


def downgrade() -> None:
    op.drop_constraint("ck_connections_config_public_scalar_types", "connections", type_="check")
    op.drop_constraint("ck_connections_config_public_allowlist", "connections", type_="check")
    op.drop_constraint("ck_connections_config_object", "connections", type_="check")
    op.drop_constraint("ck_connections_type_supported", "connections", type_="check")
