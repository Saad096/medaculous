import uuid
from datetime import date, datetime, timezone

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import delete, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.deps import get_current_user
from app.data.exam_planner_data import DEFAULT_BLUEPRINT, EXAM_INFO
from app.db.session import get_db
from app.models.exam_planner import (
    ExamSession,
    ExamSetup,
    ExamSpecialty,
    ExamStreak,
    ExamTopic,
    ExamTopicMeta,
)
from app.models.user import User
from app.schemas.exam_planner import (
    CatchupResult,
    ExamInfoOut,
    PlannerStats,
    RegenerateResult,
    SessionOut,
    SessionUpdate,
    SetupCreate,
    SetupOut,
    SpecialtyCreate,
    SpecialtyOut,
    StreakOut,
    TopicCreate,
    TopicMetaUpdate,
    TopicNotesUpdate,
    TopicOut,
)
from app.services.exam_planner_engine import (
    calculate_planner_stats,
    compute_adaptive_catchup,
    generate_study_schedule,
    schedule_topic_revisions,
    update_streak_on_completion,
)

router = APIRouter(prefix="/exam-planner", tags=["exam-planner"])


@router.get("/exams", response_model=list[ExamInfoOut])
async def list_exams(user: User = Depends(get_current_user)) -> list[dict]:
    return EXAM_INFO


async def _load_specialties(db: AsyncSession, user_id: uuid.UUID) -> list[ExamSpecialty]:
    result = await db.execute(
        select(ExamSpecialty).where(ExamSpecialty.user_id == user_id).order_by(ExamSpecialty.sort_order)
    )
    specialties = list(result.scalars().all())
    for sp in specialties:
        topics_result = await db.execute(select(ExamTopic).where(ExamTopic.specialty_id == sp.id))
        sp.topics_loaded = list(topics_result.scalars().all())  # type: ignore[attr-defined]
    return specialties


def _specialty_dict(sp: ExamSpecialty) -> dict:
    return {
        "id": sp.id,
        "key": sp.key,
        "title": sp.title,
        "topics": [
            {
                "id": t.id,
                "key": t.key,
                "title": t.title,
                "estimated_minutes": t.estimated_minutes,
                "high_yield": t.high_yield,
                "difficulty": t.difficulty,
            }
            for t in sp.topics_loaded  # type: ignore[attr-defined]
        ],
    }


@router.get("/setup", response_model=SetupOut | None)
async def get_setup(user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)) -> ExamSetup | None:
    return await db.scalar(select(ExamSetup).where(ExamSetup.user_id == user.id))


@router.post("/setup", response_model=SetupOut, status_code=status.HTTP_201_CREATED)
async def create_setup(
    body: SetupCreate, user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)
) -> ExamSetup:
    # Starting a new setup replaces any existing plan entirely (matches the
    # legacy's single-blob-overwrite semantics — see ExamSetup docstring).
    existing = await db.scalar(select(ExamSetup).where(ExamSetup.user_id == user.id))
    if existing is not None:
        old_specialty_ids = (
            (await db.execute(select(ExamSpecialty.id).where(ExamSpecialty.user_id == user.id))).scalars().all()
        )
        if old_specialty_ids:
            old_topic_ids = (
                (await db.execute(select(ExamTopic.id).where(ExamTopic.specialty_id.in_(old_specialty_ids))))
                .scalars()
                .all()
            )
            if old_topic_ids:
                await db.execute(delete(ExamTopicMeta).where(ExamTopicMeta.topic_id.in_(old_topic_ids)))
        await db.execute(delete(ExamSession).where(ExamSession.user_id == user.id))
        await db.execute(delete(ExamSpecialty).where(ExamSpecialty.user_id == user.id))
        await db.delete(existing)
        await db.execute(delete(ExamStreak).where(ExamStreak.user_id == user.id))
        await db.flush()

    setup = ExamSetup(user_id=user.id, **body.model_dump())
    db.add(setup)
    db.add(ExamStreak(user_id=user.id))

    specialties: list[ExamSpecialty] = []
    for order, sp_data in enumerate(DEFAULT_BLUEPRINT):
        specialty = ExamSpecialty(
            user_id=user.id,
            key=sp_data["key"],
            title=sp_data["title"],
            description=sp_data["description"],
            icon=sp_data["icon"],
            sort_order=order,
        )
        db.add(specialty)
        await db.flush()
        specialty.topics_loaded = []  # type: ignore[attr-defined]
        for topic_data in sp_data["topics"]:
            topic = ExamTopic(
                specialty_id=specialty.id,
                key=topic_data["key"],
                title=topic_data["title"],
                estimated_minutes=topic_data["estimated_minutes"],
                difficulty=topic_data["difficulty"],
                high_yield=topic_data["high_yield"],
                learning_objectives=topic_data["learning_objectives"],
                suggested_resources=topic_data.get("suggested_resources", []),
            )
            db.add(topic)
            await db.flush()
            db.add(ExamTopicMeta(topic_id=topic.id, difficulty=topic.difficulty))
            specialty.topics_loaded.append(topic)  # type: ignore[attr-defined]
        specialties.append(specialty)

    setup_dict = {
        "start_date": setup.start_date,
        "target_exam_date": setup.target_exam_date,
        "study_preference": setup.study_preference,
        "study_mode": setup.study_mode,
        "daily_study_minutes": setup.daily_study_minutes,
        "available_days_per_week": setup.available_days_per_week,
    }
    session_dicts = generate_study_schedule(setup_dict, [_specialty_dict(sp) for sp in specialties])
    for s in session_dicts:
        db.add(ExamSession(user_id=user.id, **s))

    await db.commit()
    await db.refresh(setup)
    return setup


@router.delete("/setup", status_code=status.HTTP_204_NO_CONTENT)
async def delete_setup(user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)) -> None:
    specialty_ids = (await db.execute(select(ExamSpecialty.id).where(ExamSpecialty.user_id == user.id))).scalars().all()
    if specialty_ids:
        topic_ids = (
            (await db.execute(select(ExamTopic.id).where(ExamTopic.specialty_id.in_(specialty_ids)))).scalars().all()
        )
        if topic_ids:
            await db.execute(delete(ExamTopicMeta).where(ExamTopicMeta.topic_id.in_(topic_ids)))
    await db.execute(delete(ExamSession).where(ExamSession.user_id == user.id))
    await db.execute(delete(ExamSpecialty).where(ExamSpecialty.user_id == user.id))
    await db.execute(delete(ExamSetup).where(ExamSetup.user_id == user.id))
    await db.execute(delete(ExamStreak).where(ExamStreak.user_id == user.id))
    await db.commit()


async def _session_out(db: AsyncSession, session: ExamSession) -> SessionOut:
    topic = await db.get(ExamTopic, session.topic_id)
    specialty = await db.get(ExamSpecialty, topic.specialty_id) if topic else None
    return SessionOut(
        id=session.id,
        topic_id=session.topic_id,
        topic_title=topic.title if topic else "",
        specialty_title=specialty.title if specialty else "",
        date=session.date,
        type=session.type,
        revision_iteration=session.revision_iteration,
        estimated_minutes=session.estimated_minutes,
        status=session.status,
        completed_at=session.completed_at,
        actual_minutes_spent=session.actual_minutes_spent,
        confidence_rating=session.confidence_rating,
        is_moved=session.is_moved,
        notes=session.notes,
    )


@router.get("/schedule", response_model=list[SessionOut])
async def get_schedule(
    start_date: date,
    end_date: date,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> list[SessionOut]:
    result = await db.execute(
        select(ExamSession)
        .where(ExamSession.user_id == user.id, ExamSession.date >= start_date, ExamSession.date <= end_date)
        .order_by(ExamSession.date)
    )
    return [await _session_out(db, s) for s in result.scalars().all()]


@router.get("/schedule/today", response_model=list[SessionOut])
async def get_today_schedule(user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)) -> list[SessionOut]:
    today = datetime.now(timezone.utc).date()
    result = await db.execute(
        select(ExamSession).where(ExamSession.user_id == user.id, ExamSession.date == today)
    )
    return [await _session_out(db, s) for s in result.scalars().all()]


@router.patch("/sessions/{session_id}", response_model=SessionOut)
async def update_session(
    session_id: uuid.UUID, body: SessionUpdate, user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)
) -> SessionOut:
    session = await db.get(ExamSession, session_id)
    if session is None or session.user_id != user.id:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Session not found.")

    was_completed = session.status == "completed"
    for key, value in body.model_dump(exclude_unset=True).items():
        setattr(session, key, value)

    if body.status == "completed" and not was_completed:
        today = datetime.now(timezone.utc).date()
        session.completed_at = datetime.now(timezone.utc)

        setup = await db.scalar(select(ExamSetup).where(ExamSetup.user_id == user.id))
        topic = await db.get(ExamTopic, session.topic_id)
        meta = await db.get(ExamTopicMeta, session.topic_id)

        if meta is not None:
            meta.status = "completed"
            meta.last_studied_at = datetime.now(timezone.utc)
            if session.actual_minutes_spent:
                meta.study_time_minutes += session.actual_minutes_spent
            if session.confidence_rating:
                meta.confidence_rating = session.confidence_rating
            if session.type == "revision":
                meta.revisions_count += 1

        # Spaced-repetition: schedule this topic's next revisions (study
        # sessions only — a completed revision doesn't spawn another chain).
        if session.type == "study" and setup is not None and topic is not None:
            existing = await db.execute(select(ExamSession).where(ExamSession.user_id == user.id))
            existing_dicts = [{"topic_id": s.topic_id, "type": s.type, "date": s.date} for s in existing.scalars().all()]
            difficulty = meta.difficulty if meta else topic.difficulty
            new_sessions = schedule_topic_revisions(
                topic.id, today, difficulty, setup.target_exam_date, existing_dicts
            )
            for s in new_sessions:
                db.add(ExamSession(user_id=user.id, **s))

        streak = await db.get(ExamStreak, user.id)
        if streak is not None:
            updated = update_streak_on_completion(
                {
                    "current_streak": streak.current_streak,
                    "longest_streak": streak.longest_streak,
                    "last_studied_date": streak.last_studied_date,
                    "total_study_days": streak.total_study_days,
                },
                today,
            )
            streak.current_streak = updated["current_streak"]
            streak.longest_streak = updated["longest_streak"]
            streak.last_studied_date = updated["last_studied_date"]
            streak.total_study_days = updated["total_study_days"]

    await db.commit()
    await db.refresh(session)
    return await _session_out(db, session)


@router.post("/catchup", response_model=CatchupResult)
async def run_catchup(user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)) -> CatchupResult:
    setup = await db.scalar(select(ExamSetup).where(ExamSetup.user_id == user.id))
    if setup is None:
        return CatchupResult(redistributed_count=0)

    today = datetime.now(timezone.utc).date()
    missed_result = await db.execute(
        select(ExamSession).where(ExamSession.user_id == user.id, ExamSession.date < today, ExamSession.status == "pending")
    )
    missed = list(missed_result.scalars().all())
    if not missed:
        return CatchupResult(redistributed_count=0)

    setup_dict = {
        "target_exam_date": setup.target_exam_date,
        "study_mode": setup.study_mode,
        "available_days_per_week": setup.available_days_per_week,
    }
    reassignments = compute_adaptive_catchup(
        [{"id": s.id, "date": s.date} for s in missed], setup_dict, today
    )
    for session in missed:
        new_date = reassignments.get(session.id)
        if new_date is not None:
            session.date = new_date
            session.is_moved = True

    await db.commit()
    return CatchupResult(redistributed_count=len(reassignments))


@router.get("/streak", response_model=StreakOut)
async def get_streak(user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)) -> ExamStreak:
    streak = await db.get(ExamStreak, user.id)
    if streak is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="No active plan.")
    return streak


@router.get("/stats", response_model=PlannerStats)
async def get_stats(user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)) -> dict:
    specialties = await _load_specialties(db, user.id)
    if not specialties:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="No active plan.")

    topic_ids = [t.id for sp in specialties for t in sp.topics_loaded]  # type: ignore[attr-defined]
    meta_result = await db.execute(select(ExamTopicMeta).where(ExamTopicMeta.topic_id.in_(topic_ids)))
    topic_meta_by_id = {
        m.topic_id: {
            "status": m.status,
            "study_time_minutes": m.study_time_minutes,
            "confidence_rating": m.confidence_rating,
        }
        for m in meta_result.scalars().all()
    }

    sessions_result = await db.execute(select(ExamSession).where(ExamSession.user_id == user.id))
    sessions = [{"status": s.status, "type": s.type} for s in sessions_result.scalars().all()]

    streak = await db.get(ExamStreak, user.id)
    streak_dict = {"current_streak": streak.current_streak} if streak else None

    return calculate_planner_stats([_specialty_dict(sp) for sp in specialties], topic_meta_by_id, sessions, streak_dict)


@router.get("/specialties", response_model=list[SpecialtyOut])
async def list_specialties(user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)) -> list[dict]:
    specialties = await _load_specialties(db, user.id)
    topic_ids = [t.id for sp in specialties for t in sp.topics_loaded]  # type: ignore[attr-defined]
    metas: dict[uuid.UUID, ExamTopicMeta] = {}
    if topic_ids:
        result = await db.execute(select(ExamTopicMeta).where(ExamTopicMeta.topic_id.in_(topic_ids)))
        metas = {m.topic_id: m for m in result.scalars().all()}

    return [
        {
            "id": sp.id,
            "key": sp.key,
            "title": sp.title,
            "description": sp.description,
            "icon": sp.icon,
            "topics": [_topic_out_dict(t, metas.get(t.id)) for t in sp.topics_loaded],  # type: ignore[attr-defined]
        }
        for sp in specialties
    ]


def _topic_out_dict(topic: ExamTopic, meta: ExamTopicMeta | None) -> dict:
    return {
        "id": topic.id,
        "key": topic.key,
        "title": topic.title,
        "estimated_minutes": topic.estimated_minutes,
        "difficulty": meta.difficulty if meta else topic.difficulty,
        "high_yield": topic.high_yield,
        "learning_objectives": topic.learning_objectives,
        "suggested_resources": topic.suggested_resources,
        "notes": meta.notes if meta else "",
        "checklists": meta.checklists if meta else [],
        "is_bookmarked": meta.is_bookmarked if meta else False,
        "status": meta.status if meta else "pending",
        "confidence_rating": meta.confidence_rating if meta else 3,
    }


async def _get_owned_topic(db: AsyncSession, user_id: uuid.UUID, topic_id: uuid.UUID) -> ExamTopic:
    topic = await db.scalar(
        select(ExamTopic)
        .join(ExamSpecialty, ExamTopic.specialty_id == ExamSpecialty.id)
        .where(ExamTopic.id == topic_id, ExamSpecialty.user_id == user_id)
    )
    if topic is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Topic not found")
    return topic


@router.patch("/topics/{topic_id}/notes", response_model=TopicOut)
async def update_topic_notes(
    topic_id: uuid.UUID,
    payload: TopicNotesUpdate,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> dict:
    topic = await _get_owned_topic(db, user.id, topic_id)
    meta = await db.get(ExamTopicMeta, topic_id)
    if meta is None:
        meta = ExamTopicMeta(topic_id=topic_id, difficulty=topic.difficulty)
        db.add(meta)
    meta.notes = payload.notes
    await db.commit()
    await db.refresh(meta)
    return _topic_out_dict(topic, meta)


@router.patch("/topics/{topic_id}/meta", response_model=TopicOut)
async def update_topic_meta(
    topic_id: uuid.UUID,
    payload: TopicMetaUpdate,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> dict:
    """Partial update of a topic's personal notes, checklist items, and
    bookmark flag — backs the planner's Notes tab (feature PDF: "In the notes
    tab, notes can be added to each topic with a checklist")."""
    topic = await _get_owned_topic(db, user.id, topic_id)
    meta = await db.get(ExamTopicMeta, topic_id)
    if meta is None:
        meta = ExamTopicMeta(topic_id=topic_id, difficulty=topic.difficulty)
        db.add(meta)
    if payload.notes is not None:
        meta.notes = payload.notes
    if payload.checklists is not None:
        meta.checklists = payload.checklists
    if payload.is_bookmarked is not None:
        meta.is_bookmarked = payload.is_bookmarked
    if payload.difficulty is not None:
        meta.difficulty = payload.difficulty
    await db.commit()
    await db.refresh(meta)
    return _topic_out_dict(topic, meta)


def _slugify(title: str) -> str:
    return "-".join("".join(c if c.isalnum() else " " for c in title.lower()).split())[:100]


@router.post("/specialties", response_model=SpecialtyOut, status_code=status.HTTP_201_CREATED)
async def create_specialty(
    body: SpecialtyCreate, user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)
) -> dict:
    """Add a custom specialty category to the syllabus (feature PDF:
    "Syllabus tab allows ability to add topics to the syllabus")."""
    setup = await db.scalar(select(ExamSetup).where(ExamSetup.user_id == user.id))
    if setup is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="No active plan.")
    max_order = max(
        [
            *(await db.execute(select(ExamSpecialty.sort_order).where(ExamSpecialty.user_id == user.id))).scalars(),
            -1,
        ]
    )
    specialty = ExamSpecialty(
        user_id=user.id,
        key=_slugify(body.title) or "custom",
        title=body.title.strip(),
        description=body.description,
        icon="library_books",
        sort_order=max_order + 1,
    )
    db.add(specialty)
    await db.commit()
    await db.refresh(specialty)
    return {
        "id": specialty.id,
        "key": specialty.key,
        "title": specialty.title,
        "description": specialty.description,
        "icon": specialty.icon,
        "topics": [],
    }


@router.post("/specialties/{specialty_id}/topics", response_model=TopicOut, status_code=status.HTTP_201_CREATED)
async def create_topic(
    specialty_id: uuid.UUID,
    body: TopicCreate,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> dict:
    specialty = await db.get(ExamSpecialty, specialty_id)
    if specialty is None or specialty.user_id != user.id:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Specialty not found.")
    topic = ExamTopic(
        specialty_id=specialty_id,
        key=_slugify(body.title) or "topic",
        title=body.title.strip(),
        estimated_minutes=max(body.estimated_minutes, 15),
        difficulty=body.difficulty,
        high_yield=False,
        learning_objectives=[],
        suggested_resources=[],
    )
    db.add(topic)
    await db.flush()
    meta = ExamTopicMeta(topic_id=topic.id, difficulty=topic.difficulty)
    db.add(meta)
    await db.commit()
    await db.refresh(topic)
    await db.refresh(meta)
    return _topic_out_dict(topic, meta)


@router.delete("/topics/{topic_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_topic(
    topic_id: uuid.UUID, user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)
) -> None:
    topic = await _get_owned_topic(db, user.id, topic_id)
    await db.execute(delete(ExamSession).where(ExamSession.topic_id == topic.id))
    await db.execute(delete(ExamTopicMeta).where(ExamTopicMeta.topic_id == topic.id))
    await db.delete(topic)
    await db.commit()


@router.post("/schedule/regenerate", response_model=RegenerateResult)
async def regenerate_schedule(
    user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)
) -> RegenerateResult:
    """Rebuild the pending schedule from today for every topic not yet
    completed — used after the syllabus is edited so new topics get study
    days. Completed sessions are kept for history and stats."""
    setup = await db.scalar(select(ExamSetup).where(ExamSetup.user_id == user.id))
    if setup is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="No active plan.")

    await db.execute(delete(ExamSession).where(ExamSession.user_id == user.id, ExamSession.status == "pending"))

    specialties = await _load_specialties(db, user.id)
    topic_ids = [t.id for sp in specialties for t in sp.topics_loaded]  # type: ignore[attr-defined]
    metas: dict[uuid.UUID, ExamTopicMeta] = {}
    if topic_ids:
        result = await db.execute(select(ExamTopicMeta).where(ExamTopicMeta.topic_id.in_(topic_ids)))
        metas = {m.topic_id: m for m in result.scalars().all()}

    remaining: list[dict] = []
    for sp in specialties:
        sp_dict = _specialty_dict(sp)
        sp_dict["topics"] = [
            t
            for t in sp_dict["topics"]
            if (metas.get(t["id"]) is None or metas[t["id"]].status != "completed")
        ]
        if sp_dict["topics"]:
            remaining.append(sp_dict)

    today = datetime.now(timezone.utc).date()
    setup_dict = {
        "start_date": max(setup.start_date, today),
        "target_exam_date": setup.target_exam_date,
        "study_preference": setup.study_preference,
        "study_mode": setup.study_mode,
        "daily_study_minutes": setup.daily_study_minutes,
        "available_days_per_week": setup.available_days_per_week,
    }
    session_dicts = generate_study_schedule(setup_dict, remaining)
    for s in session_dicts:
        db.add(ExamSession(user_id=user.id, **s))
    await db.commit()
    return RegenerateResult(created_sessions=len(session_dicts))
