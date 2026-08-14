"""add title, author, content_preview to pdf_documents

Revision ID: b2c3d4e5f6a7
Revises: a1b2c3d4e5f6
Create Date: 2026-08-15
"""

from alembic import op
import sqlalchemy as sa

revision = "b2c3d4e5f6a7"
down_revision = "a1b2c3d4e5f6"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column("pdf_documents", sa.Column("title", sa.String(length=500), nullable=True))
    op.add_column("pdf_documents", sa.Column("author", sa.String(length=255), nullable=True))
    op.add_column("pdf_documents", sa.Column("content_preview", sa.Text(), nullable=True))


def downgrade() -> None:
    op.drop_column("pdf_documents", "content_preview")
    op.drop_column("pdf_documents", "author")
    op.drop_column("pdf_documents", "title")
