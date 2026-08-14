"""
One-time loader: reads scripts/osce_data_export.json (produced by the
Node extractor at the repo root, scripts/extract_osce_data.cjs) and
populates the osce_stations/osce_sections/osce_steps tables with the
curated static OSCE station data.

Idempotent — safe to re-run: stations are matched by slug and their
sections/steps are fully replaced (cascade-deleted then re-inserted)
rather than diffed, since the source is a small static reference set.

Run from backend/: PYTHONPATH=. ./.venv/bin/python scripts/load_osce_data.py
"""
import asyncio
import json
from pathlib import Path

from sqlalchemy import delete, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.db.session import AsyncSessionLocal
from app.models.osce import OsceSection, OsceStation, OsceStep

EXPORT_PATH = Path(__file__).resolve().parents[2] / "scripts" / "osce_data_export.json"


async def load(db: AsyncSession, stations: list[dict]) -> None:
    upserted = 0
    for entry in stations:
        existing = await db.scalar(select(OsceStation).where(OsceStation.slug == entry["slug"]))
        if existing is None:
            station = OsceStation(
                slug=entry["slug"],
                title=entry["title"],
                category=entry["category"],
                system=entry["system"],
                estimated_time=entry["estimated_time"],
                summary=entry["summary"],
                sort_order=entry["sort_order"],
            )
            db.add(station)
            await db.flush()
        else:
            station = existing
            station.title = entry["title"]
            station.category = entry["category"]
            station.system = entry["system"]
            station.estimated_time = entry["estimated_time"]
            station.summary = entry["summary"]
            station.sort_order = entry["sort_order"]
            await db.execute(delete(OsceSection).where(OsceSection.station_id == station.id))
            await db.flush()

        for section_entry in entry["sections"]:
            section = OsceSection(
                station_id=station.id,
                title=section_entry["title"],
                sort_order=section_entry["sort_order"],
            )
            db.add(section)
            await db.flush()

            for step_entry in section_entry["steps"]:
                db.add(
                    OsceStep(
                        section_id=section.id,
                        slug=step_entry["slug"],
                        text=step_entry["text"],
                        hint=step_entry["hint"],
                        is_key_step=step_entry["is_key_step"],
                        sort_order=step_entry["sort_order"],
                    )
                )

        upserted += 1

    await db.commit()
    print(f"osce stations upserted: {upserted}")


async def main() -> None:
    data = json.loads(EXPORT_PATH.read_text(encoding="utf-8"))
    async with AsyncSessionLocal() as db:
        await load(db, data["stations"])


if __name__ == "__main__":
    asyncio.run(main())
