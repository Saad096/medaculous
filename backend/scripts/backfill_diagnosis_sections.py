"""
One-time backfill: generates the "Diagnosis" disease-detail section for every
disease that doesn't have one yet (owner feedback, 2026-08-22 — only 3 of 444
diseases had this section, so the "Diagnosis" box was missing almost
everywhere in the app).

Uses the same AI service (app.services.llm) already used elsewhere in the
backend, prompted with each disease's existing Definition/Investigations/
Differentials content as context so the generated section reads consistently
with the sections around it (bold sub-labels, concise clinical bullets, UK
NICE-guideline style where applicable) and matches the existing average
section length.

Idempotent — skips any disease that already has a Diagnosis row, so it's safe
to re-run after fixing a failure without regenerating or duplicating content.

Run from backend/: ./.venv/bin/python scripts/backfill_diagnosis_sections.py
"""
import asyncio
import uuid

from sqlalchemy import select

from app.db.session import AsyncSessionLocal
from app.models.disease import Disease, DiseaseSection
from app.services.llm import ModelTier, generate_text

CONCURRENCY = 6

SYSTEM_PROMPT = (
    "You are a clinical content writer producing a single disease-reference section "
    "for a medical app used by doctors and medical students. Write only the "
    '"Diagnosis" section for the named condition: how the diagnosis is actually made '
    "(criteria, key confirmatory tests, clinical scoring/decision rules where relevant). "
    "Follow the exact style of the example sections given to you: bold sub-labels "
    "(e.g. **Criteria:**) followed by a concise clinical sentence or two, one per line, "
    "blank line between each. Do not repeat the condition name or the word 'Diagnosis' "
    "as a heading — start directly with the content. No preamble, no markdown code "
    "fences, no closing remarks. Match the length of the example sections (roughly "
    "80-160 words)."
)


async def generate_for(disease: Disease, context: dict[str, str]) -> str:
    context_block = "\n\n".join(f"{key}:\n{value}" for key, value in context.items() if value)
    user_message = (
        f"Condition: {disease.name}\n"
        f"Category: {disease.category}\n\n"
        f"Existing sections for this condition (for context/consistency only):\n{context_block}"
    )
    return await generate_text(system=SYSTEM_PROMPT, user_message=user_message, tier=ModelTier.SONNET, max_tokens=600)


async def backfill_one(semaphore: asyncio.Semaphore, disease_id: uuid.UUID, results: dict) -> None:
    async with semaphore:
        async with AsyncSessionLocal() as db:
            disease = await db.get(Disease, disease_id)
            if disease is None:
                return
            existing_sections = (
                await db.execute(select(DiseaseSection).where(DiseaseSection.disease_id == disease_id))
            ).scalars().all()
            by_key = {s.section_key: s.content for s in existing_sections}
            if "Diagnosis" in by_key:
                results["skipped"] += 1
                return
            context = {
                "Definition": by_key.get("Definition", ""),
                "Investigations": by_key.get("Investigations", ""),
                "Differentials": by_key.get("Differentials", ""),
            }
            try:
                content = await generate_for(disease, context)
            except Exception as exc:  # noqa: BLE001 - log and keep the rest of the batch going
                results["failed"].append((disease.name, str(exc)))
                return
            db.add(DiseaseSection(disease_id=disease_id, section_key="Diagnosis", content=content.strip()))
            await db.commit()
            results["done"] += 1
            print(f"  done: {disease.name} ({results['done']} so far)")


async def main() -> None:
    async with AsyncSessionLocal() as db:
        missing = (
            await db.execute(
                select(Disease.id).where(
                    ~Disease.id.in_(select(DiseaseSection.disease_id).where(DiseaseSection.section_key == "Diagnosis"))
                )
            )
        ).scalars().all()

    print(f"{len(missing)} diseases missing a Diagnosis section. Generating...")
    results = {"done": 0, "skipped": 0, "failed": []}
    semaphore = asyncio.Semaphore(CONCURRENCY)
    await asyncio.gather(*(backfill_one(semaphore, disease_id, results) for disease_id in missing))

    print(f"\nDone: {results['done']} generated, {results['skipped']} already had one, {len(results['failed'])} failed.")
    if results["failed"]:
        print("Failed (re-run this script to retry these):")
        for name, error in results["failed"]:
            print(f"  - {name}: {error}")


if __name__ == "__main__":
    asyncio.run(main())
