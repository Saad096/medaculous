import uuid
from datetime import datetime

from sqlalchemy import Boolean, DateTime, ForeignKey, Integer, String, Text, func
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import Mapped, mapped_column

from app.db.base import Base


class WardShift(Base):
    """Mirrors the legacy's single wc_shift object — one row represents 'the
    current shift'; starting a new one creates a fresh row rather than
    overwriting, so past shifts aren't silently lost, but the app only ever
    reads the most recent row per user (matches legacy behavior exactly)."""

    __tablename__ = "ward_shifts"

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    user_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), ForeignKey("users.id"), nullable=False, index=True)
    hospital: Mapped[str] = mapped_column(String(255), nullable=False, default="")
    ward: Mapped[str] = mapped_column(String(255), nullable=False)
    specialty: Mapped[str] = mapped_column(String(255), nullable=False)
    shift_type: Mapped[str] = mapped_column(String(20), nullable=False)  # Morning|Evening|Night|Weekend|On-call
    active: Mapped[bool] = mapped_column(Boolean, nullable=False, default=True)

    started_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())


class WardPatient(Base):
    __tablename__ = "ward_patients"

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    user_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), ForeignKey("users.id"), nullable=False, index=True)

    initials: Mapped[str] = mapped_column(String(10), nullable=False)
    age: Mapped[str] = mapped_column(String(20), nullable=False, default="")
    dob: Mapped[str] = mapped_column(String(20), nullable=False, default="")
    sex: Mapped[str] = mapped_column(String(10), nullable=False)  # Male|Female|Other
    room_number: Mapped[str] = mapped_column(String(20), nullable=False, default="")
    bed_number: Mapped[str] = mapped_column(String(20), nullable=False, default="")
    diagnosis: Mapped[str] = mapped_column(Text, nullable=False, default="")
    co_morbids: Mapped[str] = mapped_column(Text, nullable=False, default="")
    dnar: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False)
    reviewed: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False)
    sort_order: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
    notes: Mapped[str] = mapped_column(Text, nullable=False, default="")

    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())


class WardTask(Base):
    __tablename__ = "ward_tasks"

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    patient_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("ward_patients.id", ondelete="CASCADE"), nullable=False, index=True
    )
    title: Mapped[str] = mapped_column(String(500), nullable=False)
    completed: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False)
    priority: Mapped[str] = mapped_column(String(10), nullable=False, default="Medium")  # Low|Medium|High
    note: Mapped[str] = mapped_column(Text, nullable=False, default="")

    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())
