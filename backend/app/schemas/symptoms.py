from pydantic import BaseModel, Field


class SymptomCheckRequest(BaseModel):
    symptoms: list[str] = Field(min_length=1)
    age: str | None = None
    sex: str | None = None
    duration: str | None = None


class DiagnosisOut(BaseModel):
    condition: str
    likelihood: str
    explanation: str
    red_flags: str
    common_causes: str
    next_steps: str


class SymptomCheckResponse(BaseModel):
    clinical_summary: str
    diagnoses: list[DiagnosisOut]
