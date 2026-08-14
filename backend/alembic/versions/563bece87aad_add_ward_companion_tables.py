"""add ward companion tables

Revision ID: 563bece87aad
Revises: 252d42c7644a
Create Date: 2026-08-12 22:16:04.838014

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa

revision: str = '563bece87aad'
down_revision: Union[str, None] = '252d42c7644a'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.create_table('ward_patients',
    sa.Column('id', sa.UUID(), nullable=False),
    sa.Column('user_id', sa.UUID(), nullable=False),
    sa.Column('initials', sa.String(length=10), nullable=False),
    sa.Column('age', sa.String(length=20), nullable=False),
    sa.Column('dob', sa.String(length=20), nullable=False),
    sa.Column('sex', sa.String(length=10), nullable=False),
    sa.Column('room_number', sa.String(length=20), nullable=False),
    sa.Column('bed_number', sa.String(length=20), nullable=False),
    sa.Column('diagnosis', sa.Text(), nullable=False),
    sa.Column('co_morbids', sa.Text(), nullable=False),
    sa.Column('dnar', sa.Boolean(), nullable=False),
    sa.Column('reviewed', sa.Boolean(), nullable=False),
    sa.Column('sort_order', sa.Integer(), nullable=False),
    sa.Column('notes', sa.Text(), nullable=False),
    sa.Column('created_at', sa.DateTime(timezone=True), server_default=sa.text('now()'), nullable=False),
    sa.ForeignKeyConstraint(['user_id'], ['users.id'], ),
    sa.PrimaryKeyConstraint('id')
    )
    op.create_index(op.f('ix_ward_patients_user_id'), 'ward_patients', ['user_id'], unique=False)
    op.create_table('ward_shifts',
    sa.Column('id', sa.UUID(), nullable=False),
    sa.Column('user_id', sa.UUID(), nullable=False),
    sa.Column('hospital', sa.String(length=255), nullable=False),
    sa.Column('ward', sa.String(length=255), nullable=False),
    sa.Column('specialty', sa.String(length=255), nullable=False),
    sa.Column('shift_type', sa.String(length=20), nullable=False),
    sa.Column('active', sa.Boolean(), nullable=False),
    sa.Column('started_at', sa.DateTime(timezone=True), server_default=sa.text('now()'), nullable=False),
    sa.ForeignKeyConstraint(['user_id'], ['users.id'], ),
    sa.PrimaryKeyConstraint('id')
    )
    op.create_index(op.f('ix_ward_shifts_user_id'), 'ward_shifts', ['user_id'], unique=False)
    op.create_table('ward_tasks',
    sa.Column('id', sa.UUID(), nullable=False),
    sa.Column('patient_id', sa.UUID(), nullable=False),
    sa.Column('title', sa.String(length=500), nullable=False),
    sa.Column('completed', sa.Boolean(), nullable=False),
    sa.Column('priority', sa.String(length=10), nullable=False),
    sa.Column('note', sa.Text(), nullable=False),
    sa.Column('created_at', sa.DateTime(timezone=True), server_default=sa.text('now()'), nullable=False),
    sa.ForeignKeyConstraint(['patient_id'], ['ward_patients.id'], ondelete='CASCADE'),
    sa.PrimaryKeyConstraint('id')
    )
    op.create_index(op.f('ix_ward_tasks_patient_id'), 'ward_tasks', ['patient_id'], unique=False)


def downgrade() -> None:
    op.drop_index(op.f('ix_ward_tasks_patient_id'), table_name='ward_tasks')
    op.drop_table('ward_tasks')
    op.drop_index(op.f('ix_ward_shifts_user_id'), table_name='ward_shifts')
    op.drop_table('ward_shifts')
    op.drop_index(op.f('ix_ward_patients_user_id'), table_name='ward_patients')
    op.drop_table('ward_patients')
