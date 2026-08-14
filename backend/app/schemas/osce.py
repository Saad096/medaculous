import uuid

from pydantic import BaseModel


class OsceStepOut(BaseModel):
    id: uuid.UUID
    slug: str
    text: str
    hint: str | None
    is_key_step: bool
    checked: bool

    model_config = {"from_attributes": True}


class OsceSectionOut(BaseModel):
    id: uuid.UUID
    title: str
    steps: list[OsceStepOut]

    model_config = {"from_attributes": True}


class OsceStationOut(BaseModel):
    id: uuid.UUID
    slug: str
    title: str
    category: str
    system: str
    estimated_time: str
    summary: str
    is_favorite: bool
    completed_steps: int
    total_steps: int
    sections: list[OsceSectionOut]

    model_config = {"from_attributes": True}


class StepProgressUpdate(BaseModel):
    checked: bool
