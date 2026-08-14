import uuid

from fastapi import APIRouter, Depends, HTTPException, status
from pydantic import ValidationError
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.deps import enforce_ai_usage_limit, get_current_user
from app.db.session import get_db
from app.models.pharmacy import FavoriteDrug
from app.models.user import User
from app.schemas.pharmacy import (
    FavoriteDrugCreate,
    FavoriteDrugOut,
    InteractionRequest,
    InteractionResponse,
    RecommendationRequest,
    RecommendationResponse,
    SubstituteRequest,
    SubstituteResponse,
)
from app.services.llm import LLMJsonError, ModelTier, generate_json

router = APIRouter(prefix="/pharmacy", tags=["pharmacy"])

_STYLE_RULES = (
    "\n\nWriting style (absolute rules): write every text value in plain, natural "
    "clinical English, the way an experienced pharmacist writes for a colleague, in "
    "complete sentences. The dash characters \u2014 and \u2013 are banned as "
    "punctuation; use a colon, a comma, or a new sentence instead (numeric ranges "
    "like '50-75%' are fine). Arrow symbols, emojis, and decorative symbols are "
    "banned. No machine-sounding shorthand."
)

_PHARMACIST_SYSTEM_PROMPT = """You are a senior clinical pharmacist (board-certified, hospital formulary-committee level) specializing in evidence-based symptomatic pharmacotherapy. You produce structured symptomatic treatment recommendations tailored to the individual patient's presentation and risk filters, at the quality of a formal pharmacy consult.

CRITICAL CLINICAL DIRECTIVES:
1. NEVER diagnose disease. Focus solely on symptomatic relief (e.g. fever, vomiting, allergic rhinitis, headache). Symptomatic treatment is not a substitute for diagnosing the cause.
2. Recommend first-line, second-line, and alternative options exactly as current professional standards rank them — with the ranking_rationale explaining WHY each drug earns its tier for THIS patient (efficacy evidence, safety profile against this patient's specific risk factors, and guideline positioning), not generic praise.
3. Screen this specific patient rigorously before recommending anything: drug allergies (including cross-reactivity, e.g. NSAID/aspirin, sulfonamide), renal and hepatic impairment level, pregnancy trimester and lactation safety (use current evidence, not just old letter categories), pediatric/geriatric dosing and Beers-list concerns, duplicate-therapy risk, and interactions with every drug in their chronic/active regimen. Any identified risk goes in the warning banner with the specific reason, not a vague caution.
4. Identify RED FLAGS in the presenting complaint (e.g. progressive dyspnea, sudden severe chest pain, high fever with neck stiffness, symptoms of sepsis, GI bleeding, dehydration in the very young/old). If present, set urgent_assessment_required to true and explain precisely which feature triggers it and what could be missed by self-treating.
5. Use the selected country's actual market: list brand names genuinely available and popular in that country (Pakistan: Panadol, Brufen…; UK: as in the BNF; USA: Tylenol, Advil…; UAE, India, EU likewise). Do not invent brand names — if unsure a brand exists in that market, prefer the generic name.
6. Dosing must be prescription-grade and complete: exact dose, route, frequency, maximum daily dose, and typical duration; pediatric dosing as mg/kg where weight-based (state "N/A" only when genuinely contraindicated or not recommended); explicit renal/hepatic adjustments; and monitoring requirements where relevant.
7. Cite real, current guidance (NICE, WHO, CDC, IDSA, AAP, national formularies such as the BNF) with year and level of evidence. NEVER fabricate a guideline, year, or evidence level — omit a reference rather than invent one.""" + _STYLE_RULES

_INTERACTION_SYSTEM_PROMPT = (
    "You are a senior clinical pharmacist specializing in drug-drug interactions, working "
    "at the standard of a tertiary-hospital medicines-information service. Analyze the pair "
    "the way an expert would: identify the interaction mechanism precisely (which CYP450 "
    "enzyme or transporter is inhibited/induced, protein-binding displacement, additive "
    "pharmacodynamic effects such as QT prolongation, serotonergic load, CNS/respiratory "
    "depression, bleeding risk, hyperkalemia, or nephrotoxicity), grade severity honestly "
    "against standard interaction references, and state the expected clinical consequence "
    "with its typical onset and magnitude. Management advice must be actionable and "
    "specific: avoid combination / adjust dose (say by how much) / separate administration "
    "times / substitute a named safer alternative / monitor a named parameter (level, "
    "INR, QTc, potassium, renal function) at a stated frequency. If the interaction is "
    "clinically insignificant, say so plainly rather than inventing caution. Never "
    "fabricate an interaction or a reference." + _STYLE_RULES
)

_SUBSTITUTE_SYSTEM_PROMPT = (
    "You are a senior clinical pharmacist advising on therapeutic substitution when a "
    "prescribed drug is unavailable, contraindicated, or unsuitable — at the standard of "
    "a hospital formulary committee. Recommend genuine, evidence-based substitutes: "
    "same-class agents first, then different-class agents with equivalent efficacy for "
    "the indication. For each substitute, be precise about the clinical indication it "
    "covers and its real therapeutic advantage over the target drug (potency, dosing "
    "convenience, safety in renal/hepatic impairment or pregnancy, interaction profile, "
    "cost) — no marketing language. Respect the selected country's market: name only "
    "products actually available there, and reflect realistic local cost tiers. Do not "
    "suggest a substitute that is inappropriate for the target drug's primary indication, "
    "and never invent brand names." + _STYLE_RULES
)


@router.post("/recommendations", response_model=RecommendationResponse)
async def get_recommendations(
    body: RecommendationRequest, user: User = Depends(enforce_ai_usage_limit)
) -> RecommendationResponse:
    prompt = f"""Patient presentation:
- Symptom / Complaint: "{body.symptoms}"
- Patient Age: "{body.age or "Not specified"}"
- Sex: "{body.sex or "Not specified"}"
- Weight: "{body.weight + " kg" if body.weight else "Not specified"}"
- Pregnancy Status: "{body.pregnancy or "No"}"
- Lactation/Breastfeeding: "{body.breastfeeding or "No"}"
- Known Drug Allergies: "{body.allergies or "None"}"
- Chronic Diseases / Active Regimens: "{body.chronic_diseases or "None"}"
- Renal Impairment Level: "{body.renal_impairment or "None"}"
- Hepatic Impairment Level: "{body.hepatic_impairment or "None"}"
- Selected Country for Brands: "{body.country}"

Return a JSON object with exactly these properties:
- "warning_banner": a warning highlighting major patient risk matches (allergies, liver, kidney, pregnancy, lactation, drug-drug interactions with active regimens, pediatric risks, duplicate therapy, etc.). Empty string if no major risks.
- "urgent_assessment_required": true if red flags or severe symptoms are detected requiring immediate medical attention instead of self-care.
- "urgent_assessment_rationale": clinical explanation of why urgent care is required (empty string if not required).
- "recommendations": an array of structured drug recommendations ranked by tier. Each item must have:
  - "generic_name", "drug_class" (strings)
  - "brand_names" (array of strings, common brand names in the selected country)
  - "adult_dose", "pediatric_dose" (strings; pediatric_dose is "N/A" if contraindicated/not recommended)
  - "route", "frequency", "max_daily_dose", "typical_duration" (strings)
  - "mechanism_of_action" (string)
  - "side_effects", "contraindications", "interactions" (arrays of strings)
  - "pregnancy_safety", "breastfeeding_safety", "renal_adjustment", "hepatic_adjustment", "monitoring_requirements" (strings)
  - "tier": one of "First-line treatment", "Second-line treatment", "Alternative options"
  - "ranking_rationale" (string)
  - "clinical_references": array of objects with "guideline", "details", "year", "evidence_level" (strings)
"""
    try:
        # A tiered recommendation list with clinical references per drug runs
        # much longer than the other pharmacy endpoints — the default 4096
        # cap truncated the JSON mid-object in testing.
        data = await generate_json(
            system=_PHARMACIST_SYSTEM_PROMPT, user_message=prompt, tier=ModelTier.SONNET, max_tokens=8192
        )
        return RecommendationResponse.model_validate(data)
    except (LLMJsonError, ValidationError) as exc:
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY, detail="The AI model returned an unexpected response. Please try again."
        ) from exc


@router.post("/check-interactions", response_model=InteractionResponse)
async def check_interactions(body: InteractionRequest, user: User = Depends(enforce_ai_usage_limit)) -> InteractionResponse:
    prompt = f"""Analyze potential drug-drug interactions between "{body.drug_a}" and "{body.drug_b}".

Return a JSON object with exactly these properties:
- "severity": one of "Major", "Moderate", "Minor", "None"
- "mechanism": brief clinical description of the pharmacokinetic/pharmacodynamic interaction mechanism
- "management": actionable clinical guidance or monitoring requirements
- "clinical_tip": short piece of advice for healthcare professionals
"""
    try:
        data = await generate_json(system=_INTERACTION_SYSTEM_PROMPT, user_message=prompt, tier=ModelTier.SONNET)
        return InteractionResponse.model_validate(data)
    except (LLMJsonError, ValidationError) as exc:
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY, detail="The AI model returned an unexpected response. Please try again."
        ) from exc


@router.post("/find-substitutes", response_model=SubstituteResponse)
async def find_substitutes(body: SubstituteRequest, user: User = Depends(enforce_ai_usage_limit)) -> SubstituteResponse:
    prompt = f"""For the medication "{body.target_med}", find 3 therapeutic substitutions or alternative brand names (considering country context: {body.country}).

Return a JSON object with exactly one property, "substitutes": an array of objects, each with:
- "generic_name", "drug_class", "clinical_indication", "therapeutic_advantage" (strings)
- "cost_tier": one of "$", "$$", "$$$"
"""
    try:
        data = await generate_json(system=_SUBSTITUTE_SYSTEM_PROMPT, user_message=prompt, tier=ModelTier.SONNET)
        return SubstituteResponse.model_validate(data)
    except (LLMJsonError, ValidationError) as exc:
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY, detail="The AI model returned an unexpected response. Please try again."
        ) from exc


@router.get("/favorites", response_model=list[FavoriteDrugOut])
async def list_favorites(
    user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)
) -> list[FavoriteDrug]:
    result = await db.execute(
        select(FavoriteDrug).where(FavoriteDrug.user_id == user.id).order_by(FavoriteDrug.created_at.desc())
    )
    return list(result.scalars().all())


@router.post("/favorites", response_model=FavoriteDrugOut, status_code=status.HTTP_201_CREATED)
async def add_favorite(
    body: FavoriteDrugCreate, user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)
) -> FavoriteDrug:
    favorite = FavoriteDrug(
        user_id=user.id,
        generic_name=body.medication.generic_name,
        data=body.medication.model_dump(),
    )
    db.add(favorite)
    await db.commit()
    await db.refresh(favorite)
    return favorite


@router.delete("/favorites/{favorite_id}", status_code=status.HTTP_204_NO_CONTENT)
async def remove_favorite(
    favorite_id: uuid.UUID, user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)
) -> None:
    favorite = await db.get(FavoriteDrug, favorite_id)
    if favorite is None or favorite.user_id != user.id:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Favorite not found.")
    await db.delete(favorite)
    await db.commit()
