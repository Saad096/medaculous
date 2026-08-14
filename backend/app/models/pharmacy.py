import uuid
from datetime import datetime

from sqlalchemy import DateTime, ForeignKey, String, func
from sqlalchemy.dialects.postgresql import JSONB, UUID
from sqlalchemy.orm import Mapped, mapped_column

from app.db.base import Base


class FavoriteDrug(Base):
    """A saved AI-generated drug recommendation.

    Stores the full recommendation object as JSONB rather than re-deriving
    it from generic_name later — the AI-generated content (dosing, brands,
    references) is what the user actually bookmarked, and can legitimately
    read differently on a later live call for the same drug.
    """

    __tablename__ = "favorite_drugs"

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    user_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), ForeignKey("users.id"), nullable=False, index=True)
    generic_name: Mapped[str] = mapped_column(String(255), nullable=False)
    data: Mapped[dict] = mapped_column(JSONB, nullable=False)

    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())
