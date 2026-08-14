"""add drug_profiles

Revision ID: 371533b0c562
Revises: 1947d35a6196
Create Date: 2026-08-12 20:30:45.690336

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa

revision: str = '371533b0c562'
down_revision: Union[str, None] = '1947d35a6196'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.create_table('drug_profiles',
    sa.Column('id', sa.UUID(), nullable=False),
    sa.Column('generic_name', sa.String(length=255), nullable=False),
    sa.Column('drug_class', sa.String(length=255), nullable=False),
    sa.Column('therapeutic_area', sa.String(length=255), nullable=False),
    sa.Column('brand_names', sa.Text(), nullable=False),
    sa.Column('mechanism_of_action', sa.Text(), nullable=False),
    sa.Column('indications', sa.Text(), nullable=False),
    sa.Column('dosage', sa.Text(), nullable=False),
    sa.Column('contraindications', sa.Text(), nullable=False),
    sa.Column('adverse_effects', sa.Text(), nullable=False),
    sa.Column('drug_interactions', sa.Text(), nullable=False),
    sa.Column('pregnancy_lactation', sa.Text(), nullable=False),
    sa.Column('monitoring_parameters', sa.Text(), nullable=False),
    sa.Column('pharmacokinetics', sa.Text(), nullable=False),
    sa.Column('clinical_notes', sa.Text(), nullable=False),
    sa.Column('is_ai_generated', sa.Boolean(), nullable=False),
    sa.Column('created_at', sa.DateTime(timezone=True), server_default=sa.text('now()'), nullable=False),
    sa.Column('updated_at', sa.DateTime(timezone=True), server_default=sa.text('now()'), nullable=False),
    sa.PrimaryKeyConstraint('id')
    )
    op.create_index(op.f('ix_drug_profiles_generic_name'), 'drug_profiles', ['generic_name'], unique=True)


def downgrade() -> None:
    op.drop_index(op.f('ix_drug_profiles_generic_name'), table_name='drug_profiles')
    op.drop_table('drug_profiles')
