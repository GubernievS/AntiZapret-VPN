"""Add HA tables: wg_file_state, wg_server_keys, nodes + NOTIFY triggers

Revision ID: 0002
Revises:
Create Date: 2026-04-16
"""
from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql

revision = '0002'
down_revision = None
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        'wg_file_state',
        sa.Column('path', sa.String(500), primary_key=True),
        sa.Column('content', sa.LargeBinary(), nullable=False),
        sa.Column('sha256', sa.String(64), nullable=False),
        sa.Column('size_bytes', sa.Integer(), nullable=False),
        sa.Column('updated_at', sa.DateTime(), nullable=False, server_default=sa.func.now()),
        sa.Column('updated_by', sa.String(100), nullable=False),
    )

    op.create_table(
        'wg_server_keys',
        sa.Column('iface', sa.String(50), primary_key=True),
        sa.Column('private_key', sa.Text(), nullable=False),
        sa.Column('public_key', sa.Text(), nullable=False),
        sa.Column('created_at', sa.DateTime(), nullable=False, server_default=sa.func.now()),
    )

    op.create_table(
        'nodes',
        sa.Column('id', sa.Integer(), primary_key=True, autoincrement=True),
        sa.Column('hostname', sa.String(255), unique=True, nullable=False),
        sa.Column('private_ip', sa.String(50), nullable=False),
        sa.Column('enroll_token', sa.String(255), unique=True, nullable=False),
        sa.Column('last_seen', sa.DateTime(), nullable=True),
        sa.Column('health', sa.String(20), nullable=True),
        sa.Column('applied_sha', postgresql.JSONB(), nullable=True),
        sa.Column('metrics', postgresql.JSONB(), nullable=True),
        sa.Column('created_at', sa.DateTime(), nullable=False, server_default=sa.func.now()),
    )

    # Trigger 1: notify agents when file content changes
    op.execute("""
        CREATE OR REPLACE FUNCTION notify_wg_file_changed() RETURNS trigger
        LANGUAGE plpgsql AS $$
        BEGIN
            PERFORM pg_notify('wg_file_state_changed', NEW.path);
            RETURN NEW;
        END;
        $$;

        CREATE TRIGGER trg_wg_file_changed
        AFTER INSERT OR UPDATE ON wg_file_state
        FOR EACH ROW EXECUTE FUNCTION notify_wg_file_changed();
    """)

    # Trigger 2: notify frontend when node confirms apply
    op.execute("""
        CREATE OR REPLACE FUNCTION notify_node_applied() RETURNS trigger
        LANGUAGE plpgsql AS $$
        BEGIN
            IF OLD.applied_sha IS DISTINCT FROM NEW.applied_sha THEN
                PERFORM pg_notify('node_applied', NEW.id::text);
            END IF;
            RETURN NEW;
        END;
        $$;

        CREATE TRIGGER trg_node_applied
        AFTER UPDATE ON nodes
        FOR EACH ROW EXECUTE FUNCTION notify_node_applied();
    """)


def downgrade() -> None:
    op.execute("DROP TRIGGER IF EXISTS trg_node_applied ON nodes")
    op.execute("DROP FUNCTION IF EXISTS notify_node_applied")
    op.execute("DROP TRIGGER IF EXISTS trg_wg_file_changed ON wg_file_state")
    op.execute("DROP FUNCTION IF EXISTS notify_wg_file_changed")
    op.drop_table('nodes')
    op.drop_table('wg_server_keys')
    op.drop_table('wg_file_state')
