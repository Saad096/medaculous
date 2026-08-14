"""
One-time loader: reads scripts/formulary_data_export.json (produced by the
Node extractor at the repo root, scripts/extract_formulary_data.cjs) and
populates the drug_profiles table with the curated static formulary.

Idempotent — safe to re-run: existing rows are matched by generic_name and
updated in place rather than duplicated.

Run from backend/: PYTHONPATH=. ./.venv/bin/python scripts/load_formulary_data.py
"""
import asyncio
import json
from pathlib import Path

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.db.session import AsyncSessionLocal
from app.models.formulary import DrugProfile

EXPORT_PATH = Path(__file__).resolve().parents[2] / "scripts" / "formulary_data_export.json"

_FIELDS = [
    "drug_class", "therapeutic_area", "brand_names", "mechanism_of_action", "indications",
    "dosage", "contraindications", "adverse_effects", "drug_interactions",
    "pregnancy_lactation", "monitoring_parameters",
]


async def load(db: AsyncSession, drugs: list[dict]) -> None:
    upserted = 0
    for entry in drugs:
        existing = await db.scalar(select(DrugProfile).where(DrugProfile.generic_name == entry["generic_name"]))
        if existing is None:
            db.add(DrugProfile(generic_name=entry["generic_name"], **{k: entry[k] for k in _FIELDS}))
        else:
            for key in _FIELDS:
                setattr(existing, key, entry[key])
        upserted += 1

    await db.commit()
    print(f"drug profiles upserted: {upserted}")


async def main() -> None:
    data = json.loads(EXPORT_PATH.read_text(encoding="utf-8"))
    async with AsyncSessionLocal() as db:
        await load(db, data["drugs"])


if __name__ == "__main__":
    asyncio.run(main())
