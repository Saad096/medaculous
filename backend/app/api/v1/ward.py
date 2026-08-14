import uuid

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import delete, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.deps import get_current_user
from app.db.session import get_db
from app.models.user import User
from app.models.ward import WardPatient, WardShift, WardTask
from app.schemas.ward import (
    PatientCreate,
    PatientOut,
    PatientUpdate,
    ShiftCreate,
    ShiftOut,
    TaskCreate,
    TaskOut,
    TaskUpdate,
)

router = APIRouter(prefix="/ward", tags=["ward"])


async def _get_owned_patient(db: AsyncSession, patient_id: uuid.UUID, user: User) -> WardPatient:
    patient = await db.get(WardPatient, patient_id)
    if patient is None or patient.user_id != user.id:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Patient not found.")
    return patient


async def _get_owned_task(db: AsyncSession, task_id: uuid.UUID, user: User) -> WardTask:
    task = await db.get(WardTask, task_id)
    if task is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Task not found.")
    await _get_owned_patient(db, task.patient_id, user)
    return task


# --- Shift -----------------------------------------------------------------


@router.get("/shift", response_model=ShiftOut | None)
async def get_current_shift(user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)) -> WardShift | None:
    result = await db.execute(select(WardShift).where(WardShift.user_id == user.id).order_by(WardShift.started_at.desc()).limit(1))
    return result.scalar_one_or_none()


@router.post("/shift", response_model=ShiftOut, status_code=status.HTTP_201_CREATED)
async def start_shift(body: ShiftCreate, user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)) -> WardShift:
    # Matches legacy behavior exactly: starting a new shift does not touch
    # existing patients/tasks — only "wipe" (below) clears those.
    shift = WardShift(user_id=user.id, **body.model_dump())
    db.add(shift)
    await db.commit()
    await db.refresh(shift)
    return shift


@router.patch("/shift/{shift_id}/complete", response_model=ShiftOut)
async def complete_shift(shift_id: uuid.UUID, user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)) -> WardShift:
    shift = await db.get(WardShift, shift_id)
    if shift is None or shift.user_id != user.id:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Shift not found.")
    shift.active = False
    await db.commit()
    await db.refresh(shift)
    return shift


@router.delete("/wipe", status_code=status.HTTP_204_NO_CONTENT)
async def wipe_shift_data(user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)) -> None:
    """Confidentiality purge (DISCOVERY_REPORT.md §9): permanently deletes the
    shift, every patient, and every task for this user. Irreversible."""
    patient_ids = (await db.execute(select(WardPatient.id).where(WardPatient.user_id == user.id))).scalars().all()
    if patient_ids:
        await db.execute(delete(WardTask).where(WardTask.patient_id.in_(patient_ids)))
    await db.execute(delete(WardPatient).where(WardPatient.user_id == user.id))
    await db.execute(delete(WardShift).where(WardShift.user_id == user.id))
    await db.commit()


# --- Patients -----------------------------------------------------------------


@router.get("/patients", response_model=list[PatientOut])
async def list_patients(user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)) -> list[WardPatient]:
    result = await db.execute(select(WardPatient).where(WardPatient.user_id == user.id).order_by(WardPatient.sort_order))
    return list(result.scalars().all())


@router.post("/patients", response_model=PatientOut, status_code=status.HTTP_201_CREATED)
async def create_patient(body: PatientCreate, user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)) -> WardPatient:
    max_order = await db.scalar(select(WardPatient.sort_order).where(WardPatient.user_id == user.id).order_by(WardPatient.sort_order.desc()).limit(1))
    patient = WardPatient(user_id=user.id, sort_order=(max_order or 0) + 1, **body.model_dump())
    db.add(patient)
    await db.commit()
    await db.refresh(patient)
    return patient


@router.patch("/patients/{patient_id}", response_model=PatientOut)
async def update_patient(
    patient_id: uuid.UUID, body: PatientUpdate, user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)
) -> WardPatient:
    patient = await _get_owned_patient(db, patient_id, user)
    for key, value in body.model_dump(exclude_unset=True).items():
        setattr(patient, key, value)
    await db.commit()
    await db.refresh(patient)
    return patient


@router.delete("/patients/{patient_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_patient(patient_id: uuid.UUID, user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)) -> None:
    patient = await _get_owned_patient(db, patient_id, user)
    await db.delete(patient)
    await db.commit()


# --- Tasks -----------------------------------------------------------------


@router.get("/tasks", response_model=list[TaskOut])
async def list_tasks(user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)) -> list[WardTask]:
    result = await db.execute(
        select(WardTask).join(WardPatient, WardTask.patient_id == WardPatient.id).where(WardPatient.user_id == user.id)
    )
    return list(result.scalars().all())


@router.post("/tasks", response_model=TaskOut, status_code=status.HTTP_201_CREATED)
async def create_task(body: TaskCreate, user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)) -> WardTask:
    await _get_owned_patient(db, body.patient_id, user)
    task = WardTask(**body.model_dump())
    db.add(task)
    await db.commit()
    await db.refresh(task)
    return task


@router.patch("/tasks/{task_id}", response_model=TaskOut)
async def update_task(
    task_id: uuid.UUID, body: TaskUpdate, user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)
) -> WardTask:
    task = await _get_owned_task(db, task_id, user)
    for key, value in body.model_dump(exclude_unset=True).items():
        setattr(task, key, value)
    await db.commit()
    await db.refresh(task)
    return task


@router.delete("/tasks/{task_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_task(task_id: uuid.UUID, user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)) -> None:
    task = await _get_owned_task(db, task_id, user)
    await db.delete(task)
    await db.commit()
