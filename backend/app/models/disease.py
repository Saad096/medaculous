import uuid
from datetime import datetime

from sqlalchemy import DateTime, ForeignKey, Integer, String, Text, UniqueConstraint, func
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import Mapped, mapped_column

from app.db.base import Base

# Fixed section order the legacy app's UI iterates in — content sections are
# admin-authored per disease (see DiseaseSection), so this is purely display
# order, not stored per-row. "Notes" is deliberately absent: in the legacy
# app that slot was always user-generated, never pre-authored content (see
# DiscoveryReport §1 "Systems" — per-disease user notes are a separate,
# not-yet-built table, tracked in OPEN_QUESTIONS.md).
DISEASE_SECTION_ORDER = [
    "Definition",
    "Classification",
    "Signs/Symptoms",
    "Anatomy",
    "Pathophysiology",
    "Approach",
    "Investigations",
    "Diagnosis",
    "Differentials",
    "Patient Advice",
    "Management",
    "Prescribing Information",
    "Calculators",
    "Evidence",
    "Complications",
]


class System(Base):
    __tablename__ = "systems"

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    name: Mapped[str] = mapped_column(String(100), nullable=False, unique=True)
    icon: Mapped[str] = mapped_column(String(16), nullable=False, default="")
    sort_order: Mapped[int] = mapped_column(Integer, nullable=False, default=0)


class Disease(Base):
    __tablename__ = "diseases"
    __table_args__ = (UniqueConstraint("system_id", "name", name="uq_diseases_system_name"),)

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    system_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), ForeignKey("systems.id"), nullable=False, index=True)
    name: Mapped[str] = mapped_column(String(255), nullable=False)
    category: Mapped[str] = mapped_column(String(255), nullable=False)

    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), onupdate=func.now()
    )


class DiseaseSection(Base):
    __tablename__ = "disease_sections"
    __table_args__ = (UniqueConstraint("disease_id", "section_key", name="uq_disease_sections_disease_key"),)

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    disease_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("diseases.id", ondelete="CASCADE"), nullable=False, index=True
    )
    section_key: Mapped[str] = mapped_column(String(50), nullable=False)
    content: Mapped[str] = mapped_column(Text, nullable=False, default="")
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), onupdate=func.now()
    )


class DiseaseNote(Base):
    """A single private note a user can attach to one specific disease topic
    (e.g. "Atrial Fibrillation") — deliberately separate from the general
    Notes/Folders feature (see app.models.note.Note): owner feedback,
    2026-09-11, a topic note must stay on that topic's page only and never
    appear in the app-wide Notes section. One row per (user, disease) —
    the unique constraint is what enforces "only one note per topic".
    """

    __tablename__ = "disease_notes"
    __table_args__ = (UniqueConstraint("user_id", "disease_id", name="uq_disease_notes_user_disease"),)

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    user_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), ForeignKey("users.id"), nullable=False, index=True)
    disease_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("diseases.id", ondelete="CASCADE"), nullable=False, index=True
    )
    content_html: Mapped[str] = mapped_column(Text, nullable=False, default="")
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), onupdate=func.now()
    )
