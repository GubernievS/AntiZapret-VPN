"""awg escape obfuscation

Revision ID: 0004
Revises: 0003
Create Date: 2026-04-21
"""
from alembic import op
import sqlalchemy as sa


revision = "0004"
down_revision = "0003"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        "wg_obfuscation_params",
        sa.Column("iface", sa.String(64), primary_key=True),
        sa.Column("jc", sa.Integer, nullable=False),
        sa.Column("jmin", sa.Integer, nullable=False),
        sa.Column("jmax", sa.Integer, nullable=False),
        sa.Column("s1", sa.Integer, nullable=False),
        sa.Column("s2", sa.Integer, nullable=False),
        sa.Column("h1", sa.BigInteger, nullable=False),
        sa.Column("h2", sa.BigInteger, nullable=False),
        sa.Column("h3", sa.BigInteger, nullable=False),
        sa.Column("h4", sa.BigInteger, nullable=False),
        sa.Column("i1", sa.Text, nullable=False),
        sa.Column("created_at", sa.DateTime, server_default=sa.func.now(), nullable=False),
        sa.Column("updated_at", sa.DateTime, server_default=sa.func.now(), nullable=False),
    )
    op.add_column(
        "system_settings",
        sa.Column("escape_enabled", sa.Boolean, nullable=False, server_default=sa.false()),
    )


def downgrade() -> None:
    op.drop_column("system_settings", "escape_enabled")
    op.drop_table("wg_obfuscation_params")
