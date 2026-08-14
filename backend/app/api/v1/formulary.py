import uuid

from fastapi import APIRouter, Depends, HTTPException, status
from pydantic import ValidationError
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.deps import get_current_user
from app.db.session import get_db
from app.models.formulary import DrugProfile
from app.models.user import User
from app.schemas.formulary import DrugProfileOut, DrugSummary, SearchOrCreateRequest, SearchOrCreateResponse
from app.services.llm import LLMJsonError, ModelTier, generate_json

router = APIRouter(prefix="/formulary", tags=["formulary"])

# Ports src/lib/drugUtils.ts's cleanClassName(): normalizes a verbose
# pharmacological descriptor an AI-generated profile might return for
# drug_class down to the short label the curated formulary already uses, so
# a newly-created drug files under the same class as its siblings instead of
# spawning a one-off duplicate class heading.
_CLASS_NAME_MAP = {
    "angiotensin converting enzyme inhibitor": "ACE Inhibitors",
    "beta-1 adrenergic antagonist": "Beta Blockers",
    "beta adrenergic antagonist": "Beta Blockers",
    "alpha-1 adrenergic antagonist": "Alpha Blockers",
    "alpha-2 adrenergic agonist": "Alpha-2 Agonists",
    "calcium channel blocker": "Calcium Channel Blockers",
    "h2-antagonist": "H2 Blockers",
    "proton pump inhibitor": "Proton Pump Inhibitors",
    "selective serotonin reuptake inhibitor": "SSRIs",
    "angiotensin-ii receptor antagonist": "ARBs",
    "sulfonylurea": "Sulfonylureas",
    "h1-antagonist": "Antihistamines",
    "nsaid": "NSAIDs",
    "opioid": "Opioids",
    "benzodiazepine": "Benzodiazepines",
    "statin": "Statins",
}


def _clean_class_name(name: str) -> str:
    if not name:
        return "Other"
    lowered = name.lower()
    for key, value in _CLASS_NAME_MAP.items():
        if key in lowered:
            return value
    return name


_GENERATE_SYSTEM_PROMPT = (
    "You are a senior clinical pharmacologist writing formulary monographs at the standard "
    "of the BNF, FDA prescribing information, and Medscape — reference-grade content that "
    "clinicians will prescribe from. Requirements: dosing must be prescription-complete "
    "(dose, route, frequency, maximum dose, duration, weight-based mg/kg pediatric dosing "
    "where applicable) and organized by indication; always include renal and hepatic "
    "dose adjustments where they exist; describe the mechanism of action at receptor/"
    "enzyme level in plain clinical language; for interactions, name the important ones "
    "with their mechanism (CYP450 enzyme, transporter, additive pharmacodynamic effect) "
    "and clinical consequence, most dangerous first; for pregnancy/lactation, give "
    "current evidence-based guidance (trimester-specific where it matters), not just a "
    "legacy letter category; monitoring parameters must be specific (what to measure, "
    "when, and target ranges where they exist). Use precise, current information only — "
    "if a detail is genuinely uncertain or varies by market, say so rather than guessing, "
    "and never invent brand names, doses, or references. Clinical notes should read like "
    "pearls from an experienced prescriber: the traps, the counselling points, and the "
    "practice realities that don't appear in the label."
    "\n\nWriting style (absolute rules): write every field in plain, natural clinical "
    "English, the way an experienced prescriber writes for a colleague, in complete "
    "sentences. The dash characters \u2014 and \u2013 are banned as punctuation; use "
    "a colon, a comma, or a new sentence instead (numeric ranges like '50-75%' are "
    "fine). Arrow symbols, emojis, and decorative symbols are banned. No "
    "machine-sounding shorthand."
)


@router.get("/tree", response_model=dict[str, dict[str, list[DrugSummary]]])
async def get_formulary_tree(
    user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)
) -> dict[str, dict[str, list[DrugSummary]]]:
    result = await db.execute(select(DrugProfile).order_by(DrugProfile.therapeutic_area, DrugProfile.drug_class, DrugProfile.generic_name))
    tree: dict[str, dict[str, list[DrugSummary]]] = {}
    for drug in result.scalars().all():
        classes = tree.setdefault(drug.therapeutic_area, {})
        classes.setdefault(drug.drug_class, []).append(DrugSummary.model_validate(drug))
    return tree


@router.get("/drugs/{drug_id}", response_model=DrugProfileOut)
async def get_drug(
    drug_id: uuid.UUID, user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)
) -> DrugProfile:
    drug = await db.get(DrugProfile, drug_id)
    if drug is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Drug not found.")

    # Lazy "generate once, cache forever": curated drugs seeded from the
    # legacy static data never had pharmacokinetics/clinical_notes filled
    # in — backfill both in a single call on first view, then every
    # subsequent viewer (of any account) reads the cached row.
    if not drug.pharmacokinetics or not drug.clinical_notes:
        prompt = f"""Provide the pharmacokinetics and clinical notes for {drug.generic_name} ({drug.drug_class}).

Return a JSON object with exactly these two string properties:
- "pharmacokinetics": absorption, half-life, metabolism, and elimination summary.
- "clinical_notes": a concise summary of clinical pearls and warnings for a physician (under 100 words).
"""
        try:
            data = await generate_json(system=_GENERATE_SYSTEM_PROMPT, user_message=prompt, tier=ModelTier.SONNET)
            drug.pharmacokinetics = data.get("pharmacokinetics") or drug.pharmacokinetics
            drug.clinical_notes = data.get("clinical_notes") or drug.clinical_notes
            await db.commit()
            await db.refresh(drug)
        except LLMJsonError:
            # Leave fields blank rather than fail the whole detail view —
            # the client shows "No information available" for empty
            # sections rather than an error state for one AI hiccup.
            pass

    return drug


@router.post("/search-or-create", response_model=SearchOrCreateResponse)
async def search_or_create_drug(
    body: SearchOrCreateRequest, user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)
) -> SearchOrCreateResponse:
    existing = await db.scalar(select(DrugProfile).where(DrugProfile.generic_name.ilike(body.generic_name.strip())))
    if existing is not None:
        return SearchOrCreateResponse(is_valid_drug=True, profile=DrugProfileOut.model_validate(existing))

    prompt = f"""The user searched for "{body.generic_name.strip()}". If this is a valid medication, provide a
comprehensive drug profile. If it is not a valid, real medication, set is_valid_drug to false.

Return a JSON object with exactly these properties:
- "is_valid_drug" (boolean)
- "generic_name" (string)
- "drug_class" (string, pharmacological class)
- "therapeutic_area" (string, body system, e.g. "Cardiovascular System")
- "brand_names" (string, popular brand names grouped by country, newline separated, e.g. "Pakistan: BrandA, BrandB\\nUK: BrandC")
- "mechanism_of_action" (string)
- "indications" (string)
- "dosage" (string, adult and pediatric dosing by indication)
- "contraindications" (string)
- "adverse_effects" (string)
- "drug_interactions" (string)
- "pregnancy_lactation" (string)
- "monitoring_parameters" (string)
- "pharmacokinetics" (string)
- "clinical_notes" (string, concise clinical pearls and warnings)
"""
    try:
        data = await generate_json(
            system=_GENERATE_SYSTEM_PROMPT, user_message=prompt, tier=ModelTier.SONNET, max_tokens=8192
        )
    except LLMJsonError as exc:
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY, detail="The AI model returned an unexpected response. Please try again."
        ) from exc

    if not data.get("is_valid_drug"):
        return SearchOrCreateResponse(is_valid_drug=False, message=f'Could not find a valid drug matching "{body.generic_name}".')

    # The AI may resolve a brand/alternate name the user typed (e.g. "Tylenol")
    # to a generic name already curated in the formulary (e.g. "Paracetamol") —
    # return that existing row instead of colliding with its unique constraint.
    resolved_name = data.get("generic_name") or body.generic_name.strip()
    already_present = await db.scalar(select(DrugProfile).where(DrugProfile.generic_name.ilike(resolved_name)))
    if already_present is not None:
        return SearchOrCreateResponse(is_valid_drug=True, profile=DrugProfileOut.model_validate(already_present))

    try:
        profile = DrugProfile(
            generic_name=data.get("generic_name") or body.generic_name.strip(),
            drug_class=_clean_class_name(data.get("drug_class") or "Unknown"),
            therapeutic_area=data.get("therapeutic_area") or "Other",
            brand_names=data.get("brand_names") or "",
            mechanism_of_action=data.get("mechanism_of_action") or "",
            indications=data.get("indications") or "",
            dosage=data.get("dosage") or "",
            contraindications=data.get("contraindications") or "",
            adverse_effects=data.get("adverse_effects") or "",
            drug_interactions=data.get("drug_interactions") or "",
            pregnancy_lactation=data.get("pregnancy_lactation") or "",
            monitoring_parameters=data.get("monitoring_parameters") or "",
            pharmacokinetics=data.get("pharmacokinetics") or "",
            clinical_notes=data.get("clinical_notes") or "",
            is_ai_generated=True,
        )
        db.add(profile)
        await db.commit()
        await db.refresh(profile)
    except ValidationError as exc:
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY, detail="The AI model returned an unexpected response. Please try again."
        ) from exc

    return SearchOrCreateResponse(is_valid_drug=True, profile=DrugProfileOut.model_validate(profile))
