import uuid

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
