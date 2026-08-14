"""add systems, diseases, disease_sections

Revision ID: d1fd94c2b542
Revises: f4021dda22e9
Create Date: 2026-08-12 16:54:39.231381

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa

revision: str = 'd1fd94c2b542'
down_revision: Union[str, None] = 'f4021dda22e9'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.create_table('systems',
        sa.Column('id', sa.UUID(), nullable=False),
        sa.Column('name', sa.String(length=100), nullable=False),
        sa.Column('icon', sa.String(length=16), nullable=False),
        sa.Column('sort_order', sa.Integer(), nullable=False),
        sa.PrimaryKeyConstraint('id'),
        sa.UniqueConstraint('name'),
    )
    op.create_table('diseases',
        sa.Column('id', sa.UUID(), nullable=False),
        sa.Column('system_id', sa.UUID(), nullable=False),
        sa.Column('name', sa.String(length=255), nullable=False),
        sa.Column('category', sa.String(length=255), nullable=False),
        sa.Column('created_at', sa.DateTime(timezone=True), server_default=sa.text('now()'), nullable=False),
        sa.Column('updated_at', sa.DateTime(timezone=True), server_default=sa.text('now()'), nullable=False),
        sa.ForeignKeyConstraint(['system_id'], ['systems.id'], ),
        sa.PrimaryKeyConstraint('id'),
        sa.UniqueConstraint('system_id', 'name', name='uq_diseases_system_name'),
    )
    op.create_index(op.f('ix_diseases_system_id'), 'diseases', ['system_id'], unique=False)

    op.create_table('disease_sections',
        sa.Column('id', sa.UUID(), nullable=False),
        sa.Column('disease_id', sa.UUID(), nullable=False),
        sa.Column('section_key', sa.String(length=50), nullable=False),
        sa.Column('content', sa.Text(), nullable=False),
        sa.Column('updated_at', sa.DateTime(timezone=True), server_default=sa.text('now()'), nullable=False),
        sa.ForeignKeyConstraint(['disease_id'], ['diseases.id'], ondelete='CASCADE'),
        sa.PrimaryKeyConstraint('id'),
        sa.UniqueConstraint('disease_id', 'section_key', name='uq_disease_sections_disease_key'),
    )
    op.create_index(op.f('ix_disease_sections_disease_id'), 'disease_sections', ['disease_id'], unique=False)


def downgrade() -> None:
    op.drop_index(op.f('ix_disease_sections_disease_id'), table_name='disease_sections')
    op.drop_table('disease_sections')
    op.drop_index(op.f('ix_diseases_system_id'), table_name='diseases')
    op.drop_table('diseases')
    op.drop_table('systems')
