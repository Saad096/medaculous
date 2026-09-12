"""add disease_notes

Revision ID: 57f637a2f3d1
Revises: b2c3d4e5f6a7
Create Date: 2026-09-11 00:00:00.000000

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql

revision: str = '57f637a2f3d1'
down_revision: Union[str, None] = 'b2c3d4e5f6a7'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.create_table(
        'disease_notes',
        sa.Column('id', postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column('user_id', postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column('disease_id', postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column('content_html', sa.Text(), nullable=False),
        sa.Column('updated_at', sa.DateTime(timezone=True), server_default=sa.text('now()'), nullable=False),
        sa.ForeignKeyConstraint(['user_id'], ['users.id']),
        sa.ForeignKeyConstraint(['disease_id'], ['diseases.id'], ondelete='CASCADE'),
        sa.PrimaryKeyConstraint('id'),
        sa.UniqueConstraint('user_id', 'disease_id', name='uq_disease_notes_user_disease'),
    )
    op.create_index(op.f('ix_disease_notes_user_id'), 'disease_notes', ['user_id'])
    op.create_index(op.f('ix_disease_notes_disease_id'), 'disease_notes', ['disease_id'])


def downgrade() -> None:
    op.drop_index(op.f('ix_disease_notes_disease_id'), table_name='disease_notes')
    op.drop_index(op.f('ix_disease_notes_user_id'), table_name='disease_notes')
    op.drop_table('disease_notes')
