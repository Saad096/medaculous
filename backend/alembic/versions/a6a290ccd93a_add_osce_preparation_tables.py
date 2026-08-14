"""add osce preparation tables

Revision ID: a6a290ccd93a
Revises: d9d1bf3d00e8
Create Date: 2026-08-12 23:44:20.594690

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa

revision: str = 'a6a290ccd93a'
down_revision: Union[str, None] = 'd9d1bf3d00e8'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.create_table('osce_stations',
    sa.Column('id', sa.UUID(), nullable=False),
    sa.Column('slug', sa.String(length=100), nullable=False),
    sa.Column('title', sa.String(length=255), nullable=False),
    sa.Column('category', sa.String(length=100), nullable=False),
    sa.Column('system', sa.String(length=100), nullable=False),
    sa.Column('estimated_time', sa.String(length=50), nullable=False),
    sa.Column('summary', sa.Text(), nullable=False),
    sa.Column('sort_order', sa.Integer(), nullable=False),
    sa.PrimaryKeyConstraint('id'),
    sa.UniqueConstraint('slug')
    )
    op.create_table('osce_favorites',
    sa.Column('id', sa.UUID(), nullable=False),
    sa.Column('user_id', sa.UUID(), nullable=False),
    sa.Column('station_id', sa.UUID(), nullable=False),
    sa.Column('created_at', sa.DateTime(timezone=True), server_default=sa.text('now()'), nullable=False),
    sa.ForeignKeyConstraint(['station_id'], ['osce_stations.id'], ondelete='CASCADE'),
    sa.ForeignKeyConstraint(['user_id'], ['users.id'], ),
    sa.PrimaryKeyConstraint('id'),
    sa.UniqueConstraint('user_id', 'station_id', name='uq_osce_favorites_user_station')
    )
    op.create_index(op.f('ix_osce_favorites_station_id'), 'osce_favorites', ['station_id'], unique=False)
    op.create_index(op.f('ix_osce_favorites_user_id'), 'osce_favorites', ['user_id'], unique=False)
    op.create_table('osce_sections',
    sa.Column('id', sa.UUID(), nullable=False),
    sa.Column('station_id', sa.UUID(), nullable=False),
    sa.Column('title', sa.String(length=255), nullable=False),
    sa.Column('sort_order', sa.Integer(), nullable=False),
    sa.ForeignKeyConstraint(['station_id'], ['osce_stations.id'], ondelete='CASCADE'),
    sa.PrimaryKeyConstraint('id')
    )
    op.create_index(op.f('ix_osce_sections_station_id'), 'osce_sections', ['station_id'], unique=False)
    op.create_table('osce_steps',
    sa.Column('id', sa.UUID(), nullable=False),
    sa.Column('section_id', sa.UUID(), nullable=False),
    sa.Column('slug', sa.String(length=50), nullable=False),
    sa.Column('text', sa.Text(), nullable=False),
    sa.Column('hint', sa.Text(), nullable=True),
    sa.Column('is_key_step', sa.Boolean(), nullable=False),
    sa.Column('sort_order', sa.Integer(), nullable=False),
    sa.ForeignKeyConstraint(['section_id'], ['osce_sections.id'], ondelete='CASCADE'),
    sa.PrimaryKeyConstraint('id'),
    sa.UniqueConstraint('slug')
    )
    op.create_index(op.f('ix_osce_steps_section_id'), 'osce_steps', ['section_id'], unique=False)
    op.create_table('osce_step_progress',
    sa.Column('id', sa.UUID(), nullable=False),
    sa.Column('user_id', sa.UUID(), nullable=False),
    sa.Column('step_id', sa.UUID(), nullable=False),
    sa.Column('checked_at', sa.DateTime(timezone=True), server_default=sa.text('now()'), nullable=False),
    sa.ForeignKeyConstraint(['step_id'], ['osce_steps.id'], ondelete='CASCADE'),
    sa.ForeignKeyConstraint(['user_id'], ['users.id'], ),
    sa.PrimaryKeyConstraint('id'),
    sa.UniqueConstraint('user_id', 'step_id', name='uq_osce_step_progress_user_step')
    )
    op.create_index(op.f('ix_osce_step_progress_step_id'), 'osce_step_progress', ['step_id'], unique=False)
    op.create_index(op.f('ix_osce_step_progress_user_id'), 'osce_step_progress', ['user_id'], unique=False)


def downgrade() -> None:
    op.drop_index(op.f('ix_osce_step_progress_user_id'), table_name='osce_step_progress')
    op.drop_index(op.f('ix_osce_step_progress_step_id'), table_name='osce_step_progress')
    op.drop_table('osce_step_progress')
    op.drop_index(op.f('ix_osce_steps_section_id'), table_name='osce_steps')
    op.drop_table('osce_steps')
    op.drop_index(op.f('ix_osce_sections_station_id'), table_name='osce_sections')
    op.drop_table('osce_sections')
    op.drop_index(op.f('ix_osce_favorites_user_id'), table_name='osce_favorites')
    op.drop_index(op.f('ix_osce_favorites_station_id'), table_name='osce_favorites')
    op.drop_table('osce_favorites')
    op.drop_table('osce_stations')
