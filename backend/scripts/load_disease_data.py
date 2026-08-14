"""
One-time loader: reads scripts/disease_data_export.json (produced by the
Node extractor at the repo root, scripts/extract_disease_data.cjs) and
populates the systems/diseases/disease_sections tables.

Idempotent — safe to re-run: existing rows are matched by natural key
(system name; disease system_id+name; section disease_id+section_key) and
updated in place rather than duplicated, so re-running after fixing a typo
in the source data doesn't leave orphaned old rows behind.

Run from backend/: ./.venv/bin/python scripts/load_disease_data.py
"""
import asyncio
import json
from pathlib import Path

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.db.session import AsyncSessionLocal
from app.models.disease import Disease, DiseaseSection, System

EXPORT_PATH = Path(__file__).resolve().parents[2] / "scripts" / "disease_data_export.json"


async def load(db: AsyncSession, data: dict) -> None:
    system_ids: dict = {}
    for index, sys_data in enumerate(data["systems"]):
        existing = await db.scalar(select(System).where(System.name == sys_data["name"]))
        if existing is None:
            existing = System(name=sys_data["name"], icon=sys_data.get("icon", ""), sort_order=index)
            db.add(existing)
            await db.flush()
        else:
            existing.icon = sys_data.get("icon", "")
            existing.sort_order = index
        system_ids[sys_data["name"]] = existing.id

    disease_count = 0
    section_count = 0
    skipped_unknown_system = []

    for entry in data["diseases"]:
        system_id = system_ids.get(entry["system"])
        if system_id is None:
            skipped_unknown_system.append(entry["name"])
            continue

        existing = await db.scalar(
            select(Disease).where(Disease.system_id == system_id, Disease.name == entry["name"])
        )
        if existing is None:
            existing = Disease(system_id=system_id, name=entry["name"], category=entry["category"])
            db.add(existing)
            await db.flush()
        else:
            existing.category = entry["category"]
        disease_count += 1

        for section_key, content in entry["sections"].items():
            section = await db.scalar(
                select(DiseaseSection).where(
                    DiseaseSection.disease_id == existing.id, DiseaseSection.section_key == section_key
                )
            )
            if section is None:
                db.add(DiseaseSection(disease_id=existing.id, section_key=section_key, content=content))
            else:
                section.content = content
            section_count += 1

    await db.commit()
    print(f"systems: {len(system_ids)}")
    print(f"diseases upserted: {disease_count}")
    print(f"sections upserted: {section_count}")
    if skipped_unknown_system:
        print(f"skipped (unknown system, check source data): {skipped_unknown_system}")
    if data.get("unmatched"):
        print(f"diseases with no content in the legacy app (pre-existing gap, not loaded): {data['unmatched']}")


async def main() -> None:
    data = json.loads(EXPORT_PATH.read_text(encoding="utf-8"))
    async with AsyncSessionLocal() as db:
        await load(db, data)


if __name__ == "__main__":
    asyncio.run(main())
