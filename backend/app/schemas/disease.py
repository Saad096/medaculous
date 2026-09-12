import uuid
from datetime import datetime

from pydantic import BaseModel


class SystemOut(BaseModel):
    id: uuid.UUID
    name: str
    icon: str

    model_config = {"from_attributes": True}


class DiseaseSummary(BaseModel):
    id: uuid.UUID
    name: str
    category: str

    model_config = {"from_attributes": True}


class DiseaseDetailOut(DiseaseSummary):
    system_id: uuid.UUID
    sections: dict[str, str]


class DiseaseNoteOut(BaseModel):
    id: uuid.UUID
    disease_id: uuid.UUID
    content_html: str
    updated_at: datetime

    model_config = {"from_attributes": True}


class DiseaseNoteUpdate(BaseModel):
    content_html: str
