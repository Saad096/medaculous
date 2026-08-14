import uuid
from datetime import datetime

from pydantic import BaseModel


class FolderCreate(BaseModel):
    name: str
    parent_id: uuid.UUID | None = None


class FolderOut(BaseModel):
    id: uuid.UUID
    name: str
    parent_id: uuid.UUID | None

    model_config = {"from_attributes": True}


class PdfDocumentOut(BaseModel):
    id: uuid.UUID
    folder_id: uuid.UUID | None
    filename: str
    size_bytes: int
    page_count: int
    title: str | None
    author: str | None
    content_preview: str | None
    created_at: datetime
    updated_at: datetime

    model_config = {"from_attributes": True}


class PdfDocumentUpdate(BaseModel):
    filename: str | None = None
    folder_id: uuid.UUID | None = None
    clear_folder: bool = False


class PdfSearchHit(BaseModel):
    pdf_id: uuid.UUID
    filename: str
    page_number: int | None
    snippet: str


class BookmarkCreate(BaseModel):
    page_number: int
    label: str = ""


class BookmarkOut(BaseModel):
    id: uuid.UUID
    pdf_id: uuid.UUID
    page_number: int
    label: str

    model_config = {"from_attributes": True}


class Rect(BaseModel):
    x: float
    y: float
    width: float
    height: float


class AnnotationCreate(BaseModel):
    page_number: int
    type: str  # "highlight" | "note"
    color: str = "#FFEB3B"
    rects: list[Rect] = []
    text: str = ""
    note: str = ""


class AnnotationOut(BaseModel):
    id: uuid.UUID
    pdf_id: uuid.UUID
    page_number: int
    type: str
    color: str
    rects: list[Rect]
    text: str
    note: str

    model_config = {"from_attributes": True}
