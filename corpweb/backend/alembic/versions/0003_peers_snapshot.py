"""Add peers_snapshot to nodes

Revision ID: 0003
Revises: 0002
Create Date: 2026-04-17
"""
from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql

revision = '0003'
down_revision = '0002'

def upgrade() -> None:
    op.add_column('nodes', sa.Column('peers_snapshot', postgresql.JSONB(), nullable=True))

def downgrade() -> None:
    op.drop_column('nodes', 'peers_snapshot')
