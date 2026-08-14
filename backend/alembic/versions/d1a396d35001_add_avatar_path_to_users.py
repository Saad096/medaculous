"""add avatar_path to users

Revision ID: d1a396d35001
Revises: a6a290ccd93a
Create Date: 2026-08-14 18:36:09.548010

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa

revision: str = 'd1a396d35001'
down_revision: Union[str, None] = 'a6a290ccd93a'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column('users', sa.Column('avatar_path', sa.String(length=255), nullable=True))


def downgrade() -> None:
    op.drop_column('users', 'avatar_path')
