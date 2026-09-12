from fastapi import APIRouter, Depends, HTTPException, status
from pydantic import ValidationError

from app.api.deps import enforce_ai_usage_limit
from app.models.user import User
from app.schemas.symptoms import SymptomCheckRequest, SymptomCheckResponse
from app.services.llm import LLMJsonError, ModelTier, generate_json

router = APIRouter(prefix="/symptoms", tags=["symptoms"])

_SYSTEM_PROMPT = """You are an expert diagnostician — a senior consultant physician with broad experience across internal medicine, emergency medicine, pediatrics, and primary care — generating a differential diagnosis for clinicians and medical students. This is decision support for trained professionals, not a diagnosis for a patient.

How to reason (like an expert, not a symptom-lookup table):
- Weigh each candidate diagnosis by pre-test probability: the patient's age and sex, symptom combination and duration, and real-world epidemiology. A common disease presenting typically outranks a rare disease presenting classically.
- Rank by likelihood, but ALWAYS include the relevant can't-miss diagnoses (life- or organ-threatening conditions compatible with this presentation) even when their likelihood is Low — and make clear in the explanation that they are included because they must be excluded, not because they are probable.
- The explanation for each diagnosis must show clinical reasoning: which features of THIS presentation support it, which argue against it, and what would clinch or exclude it — not a generic disease description.
- Red flags must be specific to the diagnosis and presentation (the exact symptoms/signs that should trigger urgent referral or emergency care), not generic advice.
- Next steps must be prioritized and concrete: the focused history questions, examination findings, and first-line investigations that best discriminate between the top differentials, in the order a clinician would actually do them.
- Use precise medical terminology, current diagnostic criteria, and named guidance (e.g. NICE, WHO, specialty-society criteria) where it genuinely applies. Never invent statistics or criteria.
- If the presentation itself suggests an emergency (e.g. features of sepsis, ACS, stroke, ectopic pregnancy), say so plainly in the clinical summary before anything else.

Writing style (absolute rules): write every string value in plain, natural clinical English, the way an experienced physician writes for a colleague, in complete sentences. The dash characters — and – are banned as punctuation; use a colon, a comma, or a new sentence instead (numeric ranges like "50-75%" are fine). Arrow symbols, emojis, and decorative symbols are banned. No machine-sounding shorthand."""


@router.post("/check", response_model=SymptomCheckResponse)
async def check_symptoms(
    body: SymptomCheckRequest, user: User = Depends(enforce_ai_usage_limit)
) -> SymptomCheckResponse:
    prompt = f"""Patient Info:
- Age: {body.age or "Not provided"}
- Sex: {body.sex or "Not provided"}
- Symptom Duration: {body.duration or "Not provided"}

Symptoms:
{", ".join(body.symptoms)}

Return a JSON object with exactly these two properties:
1. "clinical_summary": a brief overall clinical summary of the presentation and what needs to be considered.
2. "diagnoses": an array of the 5 to 8 most clinically relevant differential diagnoses, ranked from most likely to least likely, always including the relevant can't-miss diagnoses. Each item must have:
   - "condition" (string)
   - "likelihood" (one of "High", "Moderate", "Low")
   - "explanation" (string)
   - "red_flags" (string, comma separated list of red-flag symptoms)
   - "common_causes" (string, explanation of common causes)
   - "next_steps" (string, comma separated list of recommended next steps)
"""
    try:
        data = await generate_json(
            system=_SYSTEM_PROMPT,
            user_message=prompt,
            tier=ModelTier.SONNET,
            max_tokens=8192,
            response_model=SymptomCheckResponse,
        )
        return SymptomCheckResponse.model_validate(data)
    except (LLMJsonError, ValidationError) as exc:
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY, detail="The AI model returned an unexpected response. Please try again."
        ) from exc
