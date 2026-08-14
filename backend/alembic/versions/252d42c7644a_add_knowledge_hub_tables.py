"""add knowledge_hub tables

Revision ID: 252d42c7644a
Revises: 371533b0c562
Create Date: 2026-08-12 21:21:51.044420

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql

revision: str = '252d42c7644a'
down_revision: Union[str, None] = '371533b0c562'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.create_table('pdf_folders',
    sa.Column('id', sa.UUID(), nullable=False),
    sa.Column('user_id', sa.UUID(), nullable=False),
    sa.Column('name', sa.String(length=255), nullable=False),
    sa.Column('parent_id', sa.UUID(), nullable=True),
    sa.Column('is_deleted', sa.Boolean(), nullable=False),
    sa.Column('created_at', sa.DateTime(timezone=True), server_default=sa.text('now()'), nullable=False),
    sa.ForeignKeyConstraint(['parent_id'], ['pdf_folders.id'], ),
    sa.ForeignKeyConstraint(['user_id'], ['users.id'], ),
    sa.PrimaryKeyConstraint('id')
    )
    op.create_index(op.f('ix_pdf_folders_user_id'), 'pdf_folders', ['user_id'], unique=False)
    op.create_table('pdf_documents',
    sa.Column('id', sa.UUID(), nullable=False),
    sa.Column('user_id', sa.UUID(), nullable=False),
    sa.Column('folder_id', sa.UUID(), nullable=True),
    sa.Column('filename', sa.String(length=500), nullable=False),
    sa.Column('size_bytes', sa.Integer(), nullable=False),
    sa.Column('page_count', sa.Integer(), nullable=False),
    sa.Column('is_deleted', sa.Boolean(), nullable=False),
    sa.Column('created_at', sa.DateTime(timezone=True), server_default=sa.text('now()'), nullable=False),
    sa.Column('updated_at', sa.DateTime(timezone=True), server_default=sa.text('now()'), nullable=False),
    sa.ForeignKeyConstraint(['folder_id'], ['pdf_folders.id'], ),
    sa.ForeignKeyConstraint(['user_id'], ['users.id'], ),
    sa.PrimaryKeyConstraint('id')
    )
    op.create_index(op.f('ix_pdf_documents_user_id'), 'pdf_documents', ['user_id'], unique=False)
    op.create_table('pdf_annotations',
    sa.Column('id', sa.UUID(), nullable=False),
    sa.Column('pdf_id', sa.UUID(), nullable=False),
    sa.Column('page_number', sa.Integer(), nullable=False),
    sa.Column('type', sa.String(length=20), nullable=False),
    sa.Column('color', sa.String(length=20), nullable=False),
    sa.Column('rects', postgresql.JSONB(astext_type=sa.Text()), nullable=False),
    sa.Column('text', sa.Text(), nullable=False),
    sa.Column('note', sa.Text(), nullable=False),
    sa.Column('created_at', sa.DateTime(timezone=True), server_default=sa.text('now()'), nullable=False),
    sa.ForeignKeyConstraint(['pdf_id'], ['pdf_documents.id'], ondelete='CASCADE'),
    sa.PrimaryKeyConstraint('id')
    )
    op.create_index(op.f('ix_pdf_annotations_pdf_id'), 'pdf_annotations', ['pdf_id'], unique=False)
    op.create_table('pdf_bookmarks',
    sa.Column('id', sa.UUID(), nullable=False),
    sa.Column('pdf_id', sa.UUID(), nullable=False),
    sa.Column('page_number', sa.Integer(), nullable=False),
    sa.Column('label', sa.String(length=255), nullable=False),
    sa.Column('created_at', sa.DateTime(timezone=True), server_default=sa.text('now()'), nullable=False),
    sa.ForeignKeyConstraint(['pdf_id'], ['pdf_documents.id'], ondelete='CASCADE'),
    sa.PrimaryKeyConstraint('id')
    )
    op.create_index(op.f('ix_pdf_bookmarks_pdf_id'), 'pdf_bookmarks', ['pdf_id'], unique=False)


def downgrade() -> None:
    op.drop_index(op.f('ix_pdf_bookmarks_pdf_id'), table_name='pdf_bookmarks')
    op.drop_table('pdf_bookmarks')
    op.drop_index(op.f('ix_pdf_annotations_pdf_id'), table_name='pdf_annotations')
    op.drop_table('pdf_annotations')
    op.drop_index(op.f('ix_pdf_documents_user_id'), table_name='pdf_documents')
    op.drop_table('pdf_documents')
    op.drop_index(op.f('ix_pdf_folders_user_id'), table_name='pdf_folders')
    op.drop_table('pdf_folders')
