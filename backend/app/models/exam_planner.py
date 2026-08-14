import uuid
from datetime import date, datetime

from sqlalchemy import Boolean, Date, DateTime, ForeignKey, Integer, String, Text, func
from sqlalchemy.dialects.postgresql import JSONB, UUID
from sqlalchemy.orm import Mapped, mapped_column

from app.db.base import Base


class ExamSetup(Base):
    """One active plan per user (mirrors the legacy's single UserPlannerData
    blob) — starting a new setup replaces the previous one entirely."""

    __tablename__ = "exam_setups"

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    user_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), ForeignKey("users.id"), nullable=False, unique=True, index=True)

    exam_id: Mapped[str] = mapped_column(String(20), nullable=False)
    custom_exam_name: Mapped[str] = mapped_column(String(255), nullable=False, default="")
    target_exam_date: Mapped[date] = mapped_column(Date, nullable=False)
    start_date: Mapped[date] = mapped_column(Date, nullable=False)
    prep_level: Mapped[str] = mapped_column(String(20), nullable=False)
    daily_study_minutes: Mapped[int] = mapped_column(Integer, nullable=False, default=60)
    available_days_per_week: Mapped[list] = mapped_column(JSONB, nullable=False, default=list)  # [0..6]
    study_preference: Mapped[str] = mapped_column(String(30), nullable=False)
    goal: Mapped[str] = mapped_column(String(30), nullable=False)
    study_mode: Mapped[str] = mapped_column(String(20), nullable=False)

    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())


class ExamSpecialty(Base):
    __tablename__ = "exam_specialties"

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    user_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), ForeignKey("users.id"), nullable=False, index=True)
    key: Mapped[str] = mapped_column(String(100), nullable=False)
    title: Mapped[str] = mapped_column(String(255), nullable=False)
    description: Mapped[str] = mapped_column(Text, nullable=False, default="")
    icon: Mapped[str] = mapped_column(String(50), nullable=False, default="")
    sort_order: Mapped[int] = mapped_column(Integer, nullable=False, default=0)


class ExamTopic(Base):
    __tablename__ = "exam_topics"

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    specialty_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("exam_specialties.id", ondelete="CASCADE"), nullable=False, index=True
    )
    key: Mapped[str] = mapped_column(String(100), nullable=False)
    title: Mapped[str] = mapped_column(String(500), nullable=False)
    estimated_minutes: Mapped[int] = mapped_column(Integer, nullable=False, default=45)
    difficulty: Mapped[str] = mapped_column(String(20), nullable=False, default="moderate")
    high_yield: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False)
    learning_objectives: Mapped[list] = mapped_column(JSONB, nullable=False, default=list)
    suggested_resources: Mapped[list] = mapped_column(JSONB, nullable=False, default=list)


class ExamSession(Base):
    __tablename__ = "exam_sessions"

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    user_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), ForeignKey("users.id"), nullable=False, index=True)
    topic_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), ForeignKey("exam_topics.id", ondelete="CASCADE"), nullable=False, index=True)

    date: Mapped[date] = mapped_column(Date, nullable=False, index=True)
    type: Mapped[str] = mapped_column(String(10), nullable=False)  # study|revision
    revision_iteration: Mapped[int | None] = mapped_column(Integer, nullable=True)
    estimated_minutes: Mapped[int] = mapped_column(Integer, nullable=False, default=45)
    status: Mapped[str] = mapped_column(String(20), nullable=False, default="pending")  # pending|completed|skipped|postponed
    completed_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    actual_minutes_spent: Mapped[int | None] = mapped_column(Integer, nullable=True)
    confidence_rating: Mapped[int | None] = mapped_column(Integer, nullable=True)
    is_moved: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False)
    notes: Mapped[str] = mapped_column(Text, nullable=False, default="")


class ExamTopicMeta(Base):
    __tablename__ = "exam_topic_meta"

    topic_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("exam_topics.id", ondelete="CASCADE"), primary_key=True
    )
    status: Mapped[str] = mapped_column(String(20), nullable=False, default="pending")
    difficulty: Mapped[str] = mapped_column(String(20), nullable=False, default="moderate")
    study_time_minutes: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
    revisions_count: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
    confidence_rating: Mapped[int] = mapped_column(Integer, nullable=False, default=3)
    is_bookmarked: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False)
    notes: Mapped[str] = mapped_column(Text, nullable=False, default="")
    checklists: Mapped[list] = mapped_column(JSONB, nullable=False, default=list)
    last_studied_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)


class ExamStreak(Base):
    __tablename__ = "exam_streaks"

    user_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), ForeignKey("users.id"), primary_key=True)
    current_streak: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
    longest_streak: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
    last_studied_date: Mapped[date | None] = mapped_column(Date, nullable=True)
    total_study_days: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
