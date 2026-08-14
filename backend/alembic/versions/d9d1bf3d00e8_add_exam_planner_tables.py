"""add exam planner tables

Revision ID: d9d1bf3d00e8
Revises: 563bece87aad
Create Date: 2026-08-12 23:09:31.242509

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql

revision: str = 'd9d1bf3d00e8'
down_revision: Union[str, None] = '563bece87aad'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.create_table('exam_setups',
    sa.Column('id', sa.UUID(), nullable=False),
    sa.Column('user_id', sa.UUID(), nullable=False),
    sa.Column('exam_id', sa.String(length=20), nullable=False),
    sa.Column('custom_exam_name', sa.String(length=255), nullable=False),
    sa.Column('target_exam_date', sa.Date(), nullable=False),
    sa.Column('start_date', sa.Date(), nullable=False),
    sa.Column('prep_level', sa.String(length=20), nullable=False),
    sa.Column('daily_study_minutes', sa.Integer(), nullable=False),
    sa.Column('available_days_per_week', postgresql.JSONB(astext_type=sa.Text()), nullable=False),
    sa.Column('study_preference', sa.String(length=30), nullable=False),
    sa.Column('goal', sa.String(length=30), nullable=False),
    sa.Column('study_mode', sa.String(length=20), nullable=False),
    sa.Column('created_at', sa.DateTime(timezone=True), server_default=sa.text('now()'), nullable=False),
    sa.ForeignKeyConstraint(['user_id'], ['users.id'], ),
    sa.PrimaryKeyConstraint('id')
    )
    op.create_index(op.f('ix_exam_setups_user_id'), 'exam_setups', ['user_id'], unique=True)
    op.create_table('exam_specialties',
    sa.Column('id', sa.UUID(), nullable=False),
    sa.Column('user_id', sa.UUID(), nullable=False),
    sa.Column('key', sa.String(length=100), nullable=False),
    sa.Column('title', sa.String(length=255), nullable=False),
    sa.Column('description', sa.Text(), nullable=False),
    sa.Column('icon', sa.String(length=50), nullable=False),
    sa.Column('sort_order', sa.Integer(), nullable=False),
    sa.ForeignKeyConstraint(['user_id'], ['users.id'], ),
    sa.PrimaryKeyConstraint('id')
    )
    op.create_index(op.f('ix_exam_specialties_user_id'), 'exam_specialties', ['user_id'], unique=False)
    op.create_table('exam_streaks',
    sa.Column('user_id', sa.UUID(), nullable=False),
    sa.Column('current_streak', sa.Integer(), nullable=False),
    sa.Column('longest_streak', sa.Integer(), nullable=False),
    sa.Column('last_studied_date', sa.Date(), nullable=True),
    sa.Column('total_study_days', sa.Integer(), nullable=False),
    sa.ForeignKeyConstraint(['user_id'], ['users.id'], ),
    sa.PrimaryKeyConstraint('user_id')
    )
    op.create_table('exam_topics',
    sa.Column('id', sa.UUID(), nullable=False),
    sa.Column('specialty_id', sa.UUID(), nullable=False),
    sa.Column('key', sa.String(length=100), nullable=False),
    sa.Column('title', sa.String(length=500), nullable=False),
    sa.Column('estimated_minutes', sa.Integer(), nullable=False),
    sa.Column('difficulty', sa.String(length=20), nullable=False),
    sa.Column('high_yield', sa.Boolean(), nullable=False),
    sa.Column('learning_objectives', postgresql.JSONB(astext_type=sa.Text()), nullable=False),
    sa.Column('suggested_resources', postgresql.JSONB(astext_type=sa.Text()), nullable=False),
    sa.ForeignKeyConstraint(['specialty_id'], ['exam_specialties.id'], ondelete='CASCADE'),
    sa.PrimaryKeyConstraint('id')
    )
    op.create_index(op.f('ix_exam_topics_specialty_id'), 'exam_topics', ['specialty_id'], unique=False)
    op.create_table('exam_sessions',
    sa.Column('id', sa.UUID(), nullable=False),
    sa.Column('user_id', sa.UUID(), nullable=False),
    sa.Column('topic_id', sa.UUID(), nullable=False),
    sa.Column('date', sa.Date(), nullable=False),
    sa.Column('type', sa.String(length=10), nullable=False),
    sa.Column('revision_iteration', sa.Integer(), nullable=True),
    sa.Column('estimated_minutes', sa.Integer(), nullable=False),
    sa.Column('status', sa.String(length=20), nullable=False),
    sa.Column('completed_at', sa.DateTime(timezone=True), nullable=True),
    sa.Column('actual_minutes_spent', sa.Integer(), nullable=True),
    sa.Column('confidence_rating', sa.Integer(), nullable=True),
    sa.Column('is_moved', sa.Boolean(), nullable=False),
    sa.Column('notes', sa.Text(), nullable=False),
    sa.ForeignKeyConstraint(['topic_id'], ['exam_topics.id'], ondelete='CASCADE'),
    sa.ForeignKeyConstraint(['user_id'], ['users.id'], ),
    sa.PrimaryKeyConstraint('id')
    )
    op.create_index(op.f('ix_exam_sessions_date'), 'exam_sessions', ['date'], unique=False)
    op.create_index(op.f('ix_exam_sessions_topic_id'), 'exam_sessions', ['topic_id'], unique=False)
    op.create_index(op.f('ix_exam_sessions_user_id'), 'exam_sessions', ['user_id'], unique=False)
    op.create_table('exam_topic_meta',
    sa.Column('topic_id', sa.UUID(), nullable=False),
    sa.Column('status', sa.String(length=20), nullable=False),
    sa.Column('difficulty', sa.String(length=20), nullable=False),
    sa.Column('study_time_minutes', sa.Integer(), nullable=False),
    sa.Column('revisions_count', sa.Integer(), nullable=False),
    sa.Column('confidence_rating', sa.Integer(), nullable=False),
    sa.Column('is_bookmarked', sa.Boolean(), nullable=False),
    sa.Column('notes', sa.Text(), nullable=False),
    sa.Column('checklists', postgresql.JSONB(astext_type=sa.Text()), nullable=False),
    sa.Column('last_studied_at', sa.DateTime(timezone=True), nullable=True),
    sa.ForeignKeyConstraint(['topic_id'], ['exam_topics.id'], ondelete='CASCADE'),
    sa.PrimaryKeyConstraint('topic_id')
    )


def downgrade() -> None:
    op.drop_table('exam_topic_meta')
    op.drop_index(op.f('ix_exam_sessions_user_id'), table_name='exam_sessions')
    op.drop_index(op.f('ix_exam_sessions_topic_id'), table_name='exam_sessions')
    op.drop_index(op.f('ix_exam_sessions_date'), table_name='exam_sessions')
    op.drop_table('exam_sessions')
    op.drop_index(op.f('ix_exam_topics_specialty_id'), table_name='exam_topics')
    op.drop_table('exam_topics')
    op.drop_table('exam_streaks')
    op.drop_index(op.f('ix_exam_specialties_user_id'), table_name='exam_specialties')
    op.drop_table('exam_specialties')
    op.drop_index(op.f('ix_exam_setups_user_id'), table_name='exam_setups')
    op.drop_table('exam_setups')
