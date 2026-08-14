import uuid
from datetime import datetime

from pydantic import BaseModel


class RecommendationRequest(BaseModel):
    symptoms: str
    age: str | None = None
    sex: str | None = None
    weight: str | None = None
    pregnancy: str | None = None
    breastfeeding: str | None = None
    allergies: str | None = None
    chronic_diseases: str | None = None
    renal_impairment: str | None = None
    hepatic_impairment: str | None = None
    country: str = "Pakistan"


class ClinicalReference(BaseModel):
    guideline: str
    details: str
    year: str
    evidence_level: str


class Medication(BaseModel):
    generic_name: str
    drug_class: str
    brand_names: list[str]
    adult_dose: str
    pediatric_dose: str
    route: str
    frequency: str
    max_daily_dose: str
    typical_duration: str
    mechanism_of_action: str
    side_effects: list[str]
    contraindications: list[str]
    interactions: list[str]
    pregnancy_safety: str
    breastfeeding_safety: str
    renal_adjustment: str
    hepatic_adjustment: str
    monitoring_requirements: str
    tier: str
    ranking_rationale: str
    clinical_references: list[ClinicalReference]


class RecommendationResponse(BaseModel):
    warning_banner: str = ""
    urgent_assessment_required: bool = False
    urgent_assessment_rationale: str = ""
    recommendations: list[Medication]


class InteractionRequest(BaseModel):
    drug_a: str
    drug_b: str


class InteractionResponse(BaseModel):
    severity: str
    mechanism: str
    management: str
    clinical_tip: str


class SubstituteRequest(BaseModel):
    target_med: str
    country: str = "Pakistan"


class Substitute(BaseModel):
    generic_name: str
    drug_class: str
    clinical_indication: str
    therapeutic_advantage: str
    cost_tier: str


class SubstituteResponse(BaseModel):
    substitutes: list[Substitute]


class FavoriteDrugOut(BaseModel):
    id: uuid.UUID
    generic_name: str
    data: Medication
    created_at: datetime

    model_config = {"from_attributes": True}


class FavoriteDrugCreate(BaseModel):
    medication: Medication
