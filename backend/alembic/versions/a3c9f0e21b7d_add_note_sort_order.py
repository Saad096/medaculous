"""add sort_order to notes

Revision ID: a3c9f0e21b7d
Revises: 57f637a2f3d1
Create Date: 2026-09-13 00:00:00.000000

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa

revision: str = 'a3c9f0e21b7d'
down_revision: Union[str, None] = '57f637a2f3d1'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column('notes', sa.Column('sort_order', sa.Integer(), server_default=sa.text('0'), nullable=False))


def downgrade() -> None:
    op.drop_column('notes', 'sort_order')
