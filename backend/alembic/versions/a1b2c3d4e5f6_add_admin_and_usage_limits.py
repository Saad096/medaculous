"""add admin flag, AI usage limits, subscription tier to users; cascade user deletes

Revision ID: a1b2c3d4e5f6
Revises: d1a396d35001
Create Date: 2026-08-14
"""

from alembic import op
import sqlalchemy as sa

revision = "a1b2c3d4e5f6"
down_revision = "d1a396d35001"
branch_labels = None
depends_on = None

# Every FK in the schema that references users.id, keyed by (table, constraint name).
# See admin.delete_user — cascading here lets that endpoint just delete the User row
# and let Postgres remove everything else the account owns, instead of hand-ordering
# ~15 dependent deletes across every feature table.
_USER_FKS = [
    ("audit_log", "audit_log_user_id_fkey"),
    ("conversations", "conversations_user_id_fkey"),
    ("exam_sessions", "exam_sessions_user_id_fkey"),
    ("exam_setups", "exam_setups_user_id_fkey"),
    ("exam_specialties", "exam_specialties_user_id_fkey"),
    ("exam_streaks", "exam_streaks_user_id_fkey"),
    ("favorite_drugs", "favorite_drugs_user_id_fkey"),
    ("folders", "folders_user_id_fkey"),
    ("notes", "notes_user_id_fkey"),
    ("osce_favorites", "osce_favorites_user_id_fkey"),
    ("osce_step_progress", "osce_step_progress_user_id_fkey"),
    ("otp_codes", "otp_codes_user_id_fkey"),
    ("pdf_documents", "pdf_documents_user_id_fkey"),
    ("pdf_folders", "pdf_folders_user_id_fkey"),
    ("refresh_tokens", "refresh_tokens_user_id_fkey"),
    ("ward_patients", "ward_patients_user_id_fkey"),
    ("ward_shifts", "ward_shifts_user_id_fkey"),
]


def upgrade() -> None:
    op.add_column("users", sa.Column("is_admin", sa.Boolean(), nullable=False, server_default=sa.false()))
    op.add_column("users", sa.Column("ai_monthly_limit", sa.Integer(), nullable=True))
    op.add_column("users", sa.Column("ai_messages_used", sa.Integer(), nullable=False, server_default="0"))
    op.add_column(
        "users",
        sa.Column("usage_period_start", sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now()),
    )
    op.add_column(
        "users", sa.Column("subscription_tier", sa.String(length=20), nullable=False, server_default="trial")
    )

    op.execute("UPDATE users SET is_admin = true WHERE email = 'talk2saadalam@gmail.com'")

    for table, constraint in _USER_FKS:
        op.drop_constraint(constraint, table, type_="foreignkey")
        op.create_foreign_key(constraint, table, "users", ["user_id"], ["id"], ondelete="CASCADE")


def downgrade() -> None:
    for table, constraint in _USER_FKS:
        op.drop_constraint(constraint, table, type_="foreignkey")
        op.create_foreign_key(constraint, table, "users", ["user_id"], ["id"])

    op.drop_column("users", "subscription_tier")
    op.drop_column("users", "usage_period_start")
    op.drop_column("users", "ai_messages_used")
    op.drop_column("users", "ai_monthly_limit")
    op.drop_column("users", "is_admin")
