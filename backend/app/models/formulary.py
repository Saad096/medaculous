import uuid
from datetime import datetime

from sqlalchemy import Boolean, DateTime, String, Text, func
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import Mapped, mapped_column

from app.db.base import Base


class DrugProfile(Base):
    """A formulary drug monograph.

    Seeded once from the legacy app's curated ~100-drug list, plus any
    AI-generated profile created on first user search for a drug not yet in
    the formulary (is_ai_generated=True) — either way, generation happens
    server-side exactly once and the row is then shared by every user
    (DISCOVERY_REPORT.md §4 migration note), replacing the legacy pattern of
    every client re-generating the same content into its own localStorage.
    """

    __tablename__ = "drug_profiles"

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    generic_name: Mapped[str] = mapped_column(String(255), nullable=False, unique=True, index=True)
    drug_class: Mapped[str] = mapped_column(String(255), nullable=False)
    therapeutic_area: Mapped[str] = mapped_column(String(255), nullable=False)
    brand_names: Mapped[str] = mapped_column(Text, nullable=False, default="")

    mechanism_of_action: Mapped[str] = mapped_column(Text, nullable=False, default="")
    indications: Mapped[str] = mapped_column(Text, nullable=False, default="")
    dosage: Mapped[str] = mapped_column(Text, nullable=False, default="")
    contraindications: Mapped[str] = mapped_column(Text, nullable=False, default="")
    adverse_effects: Mapped[str] = mapped_column(Text, nullable=False, default="")
    drug_interactions: Mapped[str] = mapped_column(Text, nullable=False, default="")
    pregnancy_lactation: Mapped[str] = mapped_column(Text, nullable=False, default="")
    monitoring_parameters: Mapped[str] = mapped_column(Text, nullable=False, default="")
    pharmacokinetics: Mapped[str] = mapped_column(Text, nullable=False, default="")
    clinical_notes: Mapped[str] = mapped_column(Text, nullable=False, default="")

    is_ai_generated: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False)

    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), onupdate=func.now()
    )
