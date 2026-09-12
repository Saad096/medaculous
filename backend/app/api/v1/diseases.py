import uuid

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.deps import get_current_user
from app.db.session import get_db
from app.models.disease import DISEASE_SECTION_ORDER, Disease, DiseaseNote, DiseaseSection, System
from app.models.user import User
from app.schemas.disease import DiseaseDetailOut, DiseaseNoteOut, DiseaseNoteUpdate, DiseaseSummary, SystemOut

router = APIRouter(tags=["diseases"])


@router.get("/systems", response_model=list[SystemOut])
async def list_systems(
    user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)
) -> list[System]:
    result = await db.execute(select(System).order_by(System.sort_order))
    return list(result.scalars().all())


@router.get("/systems/{system_id}/diseases", response_model=list[DiseaseSummary])
async def list_diseases(
    system_id: uuid.UUID,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> list[Disease]:
    system = await db.get(System, system_id)
    if system is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="System not found.")
    result = await db.execute(
        select(Disease).where(Disease.system_id == system_id).order_by(Disease.category, Disease.name)
    )
    return list(result.scalars().all())


@router.get("/diseases/search", response_model=list[DiseaseSummary])
async def search_diseases(
    q: str,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> list[Disease]:
    if len(q.strip()) < 2:
        return []
    result = await db.execute(
        select(Disease).where(Disease.name.ilike(f"%{q.strip()}%")).order_by(Disease.name).limit(50)
    )
    return list(result.scalars().all())


@router.get("/diseases/{disease_id}", response_model=DiseaseDetailOut)
async def get_disease(
    disease_id: uuid.UUID,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> DiseaseDetailOut:
    disease = await db.get(Disease, disease_id)
    if disease is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Disease not found.")

    result = await db.execute(select(DiseaseSection).where(DiseaseSection.disease_id == disease_id))
    by_key = {s.section_key: s.content for s in result.scalars().all()}
    # Ordered per DISEASE_SECTION_ORDER regardless of DB row order; sections
    # with no authored content for this disease are simply omitted rather
    # than sent as empty strings, so the client can skip rendering them.
    ordered_sections = {key: by_key[key] for key in DISEASE_SECTION_ORDER if key in by_key}

    return DiseaseDetailOut(
        id=disease.id,
        system_id=disease.system_id,
        name=disease.name,
        category=disease.category,
        sections=ordered_sections,
    )


@router.get("/diseases/{disease_id}/note", response_model=DiseaseNoteOut | None)
async def get_disease_note(
    disease_id: uuid.UUID,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> DiseaseNote | None:
    return await db.scalar(
        select(DiseaseNote).where(DiseaseNote.disease_id == disease_id, DiseaseNote.user_id == user.id)
    )


@router.put("/diseases/{disease_id}/note", response_model=DiseaseNoteOut)
async def upsert_disease_note(
    disease_id: uuid.UUID,
    payload: DiseaseNoteUpdate,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> DiseaseNote:
    disease = await db.get(Disease, disease_id)
    if disease is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Disease not found.")

    note = await db.scalar(
        select(DiseaseNote).where(DiseaseNote.disease_id == disease_id, DiseaseNote.user_id == user.id)
    )
    if note is None:
        note = DiseaseNote(user_id=user.id, disease_id=disease_id, content_html=payload.content_html)
        db.add(note)
    else:
        note.content_html = payload.content_html
    await db.commit()
    await db.refresh(note)
    return note
