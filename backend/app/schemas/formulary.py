import uuid
from datetime import datetime

from pydantic import BaseModel


class DrugSummary(BaseModel):
    id: uuid.UUID
    generic_name: str
    drug_class: str
    therapeutic_area: str
    brand_names: str

    model_config = {"from_attributes": True}


class DrugProfileOut(BaseModel):
    id: uuid.UUID
    generic_name: str
    drug_class: str
    therapeutic_area: str
    brand_names: str
    mechanism_of_action: str
    indications: str
    dosage: str
    contraindications: str
    adverse_effects: str
    drug_interactions: str
    pregnancy_lactation: str
    monitoring_parameters: str
    pharmacokinetics: str
    clinical_notes: str
    is_ai_generated: bool
    updated_at: datetime

    model_config = {"from_attributes": True}


class SearchOrCreateRequest(BaseModel):
    generic_name: str


class SearchOrCreateResponse(BaseModel):
    is_valid_drug: bool
    profile: DrugProfileOut | None = None
    message: str = ""
