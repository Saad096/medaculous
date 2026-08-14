import uuid

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.deps import get_current_user
from app.db.session import get_db
from app.models.osce import OsceFavorite, OsceSection, OsceStation, OsceStep, OsceStepProgress
from app.models.user import User
from app.schemas.osce import OsceStationOut, StepProgressUpdate

router = APIRouter(prefix="/osce", tags=["osce"])


async def _load_stations(db: AsyncSession, user_id: uuid.UUID) -> list[dict]:
    stations = list((await db.execute(select(OsceStation).order_by(OsceStation.sort_order))).scalars().all())
    sections = list((await db.execute(select(OsceSection).order_by(OsceSection.sort_order))).scalars().all())
    steps = list((await db.execute(select(OsceStep).order_by(OsceStep.sort_order))).scalars().all())
    favorite_station_ids = set(
        (await db.execute(select(OsceFavorite.station_id).where(OsceFavorite.user_id == user_id)))
        .scalars()
        .all()
    )
    checked_step_ids = set(
        (await db.execute(select(OsceStepProgress.step_id).where(OsceStepProgress.user_id == user_id)))
        .scalars()
        .all()
    )

    steps_by_section: dict[uuid.UUID, list[OsceStep]] = {}
    for step in steps:
        steps_by_section.setdefault(step.section_id, []).append(step)

    sections_by_station: dict[uuid.UUID, list[OsceSection]] = {}
    for section in sections:
        sections_by_station.setdefault(section.station_id, []).append(section)

    out = []
    for station in stations:
        station_sections = []
        completed_steps = 0
        total_steps = 0
        for section in sections_by_station.get(station.id, []):
            section_steps = []
            for step in steps_by_section.get(section.id, []):
                checked = step.id in checked_step_ids
                total_steps += 1
                if checked:
                    completed_steps += 1
                section_steps.append(
                    {
                        "id": step.id,
                        "slug": step.slug,
                        "text": step.text,
                        "hint": step.hint,
                        "is_key_step": step.is_key_step,
                        "checked": checked,
                    }
                )
            station_sections.append({"id": section.id, "title": section.title, "steps": section_steps})

        out.append(
            {
                "id": station.id,
                "slug": station.slug,
                "title": station.title,
                "category": station.category,
                "system": station.system,
                "estimated_time": station.estimated_time,
                "summary": station.summary,
                "is_favorite": station.id in favorite_station_ids,
                "completed_steps": completed_steps,
                "total_steps": total_steps,
                "sections": station_sections,
            }
        )
    return out


@router.get("/stations", response_model=list[OsceStationOut])
async def list_stations(
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
) -> list[dict]:
    return await _load_stations(db, current_user.id)


@router.post("/favorites/{station_id}", status_code=status.HTTP_201_CREATED)
async def add_favorite(
    station_id: uuid.UUID,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
) -> dict:
    station = await db.get(OsceStation, station_id)
    if station is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Station not found")

    existing = await db.scalar(
        select(OsceFavorite).where(OsceFavorite.user_id == current_user.id, OsceFavorite.station_id == station_id)
    )
    if existing is None:
        db.add(OsceFavorite(user_id=current_user.id, station_id=station_id))
        await db.commit()
    return {"is_favorite": True}


@router.delete("/favorites/{station_id}", status_code=status.HTTP_204_NO_CONTENT)
async def remove_favorite(
    station_id: uuid.UUID,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
) -> None:
    favorite = await db.scalar(
        select(OsceFavorite).where(OsceFavorite.user_id == current_user.id, OsceFavorite.station_id == station_id)
    )
    if favorite is not None:
        await db.delete(favorite)
        await db.commit()


@router.patch("/steps/{step_id}/progress", status_code=status.HTTP_204_NO_CONTENT)
async def set_step_progress(
    step_id: uuid.UUID,
    payload: StepProgressUpdate,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
) -> None:
    step = await db.get(OsceStep, step_id)
    if step is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Step not found")

    existing = await db.scalar(
        select(OsceStepProgress).where(OsceStepProgress.user_id == current_user.id, OsceStepProgress.step_id == step_id)
    )
    if payload.checked and existing is None:
        db.add(OsceStepProgress(user_id=current_user.id, step_id=step_id))
        await db.commit()
    elif not payload.checked and existing is not None:
        await db.delete(existing)
        await db.commit()


@router.delete("/stations/{station_id}/progress", status_code=status.HTTP_204_NO_CONTENT)
async def reset_station_progress(
    station_id: uuid.UUID,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
) -> None:
    station = await db.get(OsceStation, station_id)
    if station is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Station not found")

    step_ids = (
        (
            await db.execute(
                select(OsceStep.id).join(OsceSection, OsceStep.section_id == OsceSection.id).where(
                    OsceSection.station_id == station_id
                )
            )
        )
        .scalars()
        .all()
    )
    if step_ids:
        progress_rows = list(
            (
                await db.execute(
                    select(OsceStepProgress).where(
                        OsceStepProgress.user_id == current_user.id, OsceStepProgress.step_id.in_(step_ids)
                    )
                )
            )
            .scalars()
            .all()
        )
        for row in progress_rows:
            await db.delete(row)
        await db.commit()
