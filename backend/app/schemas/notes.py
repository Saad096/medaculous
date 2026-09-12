import uuid
from datetime import datetime

from pydantic import BaseModel, Field


class FolderCreate(BaseModel):
    name: str = Field(min_length=1, max_length=255)
    parent_id: uuid.UUID | None = None


class FolderUpdate(BaseModel):
    name: str | None = Field(default=None, min_length=1, max_length=255)
    parent_id: uuid.UUID | None = None


class FolderOut(BaseModel):
    id: uuid.UUID
    name: str
    parent_id: uuid.UUID | None
    created_at: datetime
    updated_at: datetime

    model_config = {"from_attributes": True}


class NoteCreate(BaseModel):
    title: str = Field(default="", max_length=500)
    content_html: str = ""
    folder_id: uuid.UUID | None = None


class NoteUpdate(BaseModel):
    title: str | None = Field(default=None, max_length=500)
    content_html: str | None = None
    folder_id: uuid.UUID | None = None
    is_pinned: bool | None = None


class NoteOut(BaseModel):
    id: uuid.UUID
    folder_id: uuid.UUID | None
    title: str
    content_html: str
    is_pinned: bool
    sort_order: int
    created_at: datetime
    updated_at: datetime

    model_config = {"from_attributes": True}


class NoteReorder(BaseModel):
    note_ids: list[uuid.UUID] = Field(min_length=1)
