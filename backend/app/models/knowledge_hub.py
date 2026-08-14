import uuid
from datetime import datetime

from sqlalchemy import Boolean, DateTime, ForeignKey, Integer, String, Text, func
from sqlalchemy.dialects.postgresql import JSONB, UUID
from sqlalchemy.orm import Mapped, mapped_column

from app.db.base import Base


class PdfFolder(Base):
    __tablename__ = "pdf_folders"

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    user_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), ForeignKey("users.id"), nullable=False, index=True)
    name: Mapped[str] = mapped_column(String(255), nullable=False)
    parent_id: Mapped[uuid.UUID | None] = mapped_column(UUID(as_uuid=True), ForeignKey("pdf_folders.id"), nullable=True)

    is_deleted: Mapped[bool] = mapped_column(Boolean, default=False, nullable=False)

    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())


class PdfDocument(Base):
    __tablename__ = "pdf_documents"

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    user_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), ForeignKey("users.id"), nullable=False, index=True)
    folder_id: Mapped[uuid.UUID | None] = mapped_column(UUID(as_uuid=True), ForeignKey("pdf_folders.id"), nullable=True)

    filename: Mapped[str] = mapped_column(String(500), nullable=False)
    size_bytes: Mapped[int] = mapped_column(Integer, nullable=False)
    page_count: Mapped[int] = mapped_column(Integer, nullable=False, default=0)

    # Extracted once at upload time from the PDF's own embedded metadata /
    # first page of text (see _extract_pdf_metadata) — owner request,
    # 2026-08-14: the list showed nothing but filename/page count/size, no
    # indication of what's actually in the document. Null title/author means
    # the PDF simply doesn't carry that metadata (common for scans).
    title: Mapped[str | None] = mapped_column(String(500), nullable=True)
    author: Mapped[str | None] = mapped_column(String(255), nullable=True)
    content_preview: Mapped[str | None] = mapped_column(Text, nullable=True)

    is_deleted: Mapped[bool] = mapped_column(Boolean, default=False, nullable=False)

    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), onupdate=func.now()
    )

    @property
    def storage_filename(self) -> str:
        # The on-disk name never changes even if the user renames the document —
        # `filename` is display-only, so renaming is a pure DB update.
        return f"{self.id}.pdf"


class PdfBookmark(Base):
    __tablename__ = "pdf_bookmarks"

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    pdf_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), ForeignKey("pdf_documents.id", ondelete="CASCADE"), nullable=False, index=True)
    page_number: Mapped[int] = mapped_column(Integer, nullable=False)
    label: Mapped[str] = mapped_column(String(255), nullable=False, default="")

    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())


class PdfAnnotation(Base):
    """MVP annotation scope: highlight and note only (OPEN_QUESTIONS.md) —
    the legacy's Konva freehand pen/shapes/stickers/image tools are cut,
    mirroring the freehand-drawing cut already made for Notes."""

    __tablename__ = "pdf_annotations"

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    pdf_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), ForeignKey("pdf_documents.id", ondelete="CASCADE"), nullable=False, index=True)
    page_number: Mapped[int] = mapped_column(Integer, nullable=False)
    type: Mapped[str] = mapped_column(String(20), nullable=False)  # "highlight" | "note"
    color: Mapped[str] = mapped_column(String(20), nullable=False, default="#FFEB3B")
    # Rects are page-relative fractions (0..1) so they stay correct regardless
    # of render resolution/zoom: [{"x","y","width","height"}, ...].
    rects: Mapped[list] = mapped_column(JSONB, nullable=False, default=list)
    text: Mapped[str] = mapped_column(Text, nullable=False, default="")
    note: Mapped[str] = mapped_column(Text, nullable=False, default="")

    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())
