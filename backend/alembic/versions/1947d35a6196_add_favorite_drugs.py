"""add favorite_drugs

Revision ID: 1947d35a6196
Revises: d1fd94c2b542
Create Date: 2026-08-12 19:30:43.995826

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql

revision: str = '1947d35a6196'
down_revision: Union[str, None] = 'd1fd94c2b542'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.create_table('favorite_drugs',
    sa.Column('id', sa.UUID(), nullable=False),
    sa.Column('user_id', sa.UUID(), nullable=False),
    sa.Column('generic_name', sa.String(length=255), nullable=False),
    sa.Column('data', postgresql.JSONB(astext_type=sa.Text()), nullable=False),
    sa.Column('created_at', sa.DateTime(timezone=True), server_default=sa.text('now()'), nullable=False),
    sa.ForeignKeyConstraint(['user_id'], ['users.id'], ),
    sa.PrimaryKeyConstraint('id')
    )
    op.create_index(op.f('ix_favorite_drugs_user_id'), 'favorite_drugs', ['user_id'], unique=False)


def downgrade() -> None:
    op.drop_index(op.f('ix_favorite_drugs_user_id'), table_name='favorite_drugs')
    op.drop_table('favorite_drugs')
