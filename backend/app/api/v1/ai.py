import logging
import uuid
from datetime import datetime, timezone

from fastapi import APIRouter, Depends, HTTPException, status
from fastapi.responses import StreamingResponse
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.deps import enforce_ai_usage_limit, get_current_user
from app.db.session import get_db
from app.models.conversation import Conversation, Message, MessageRole
from app.models.exam_planner import ExamSession, ExamSetup, ExamTopic
from app.models.user import User
from app.models.ward import WardPatient, WardTask
from app.schemas.ai import ChatRequest, ConversationDetail, ConversationSummary, ConversationUpdate, MessageOut
from app.services import search as search_service
from app.services.llm import ModelTier, stream_chat
from app.services.text_chunking import chunk_text

router = APIRouter(prefix="/ai", tags=["ai"])
logger = logging.getLogger(__name__)

# Master spec §4.5: chat runs on the Sonnet tier by default. The disclaimer is a
# non-negotiable UI element (rendered by the client under every assistant
# message) — it's reinforced here in the system prompt too so the model's own
# behavior stays consistent with it, not as a substitute for the UI footer.
#
# Prompt design: a shared expert-clinical core (evidence standards, safety
# rules, mobile-friendly formatting) + a mode-specific persona on top, so all
# four modes answer at consultant level but with the right structure for the
# setting (bedside / resus / exam hall).
_CLINICAL_CORE = """

CLINICAL STANDARDS (apply to every answer):
- Answer at the level of an experienced consultant/attending in the relevant specialty: precise terminology, current practice, and the reasoning an expert would actually use — not textbook boilerplate.
- Ground recommendations in named, current guidance where it exists (e.g. NICE, BNF, Resuscitation Council UK, WHO, AHA/ACC, ESC, IDSA, KDIGO, SIGN) and say which guideline you are drawing on. If guidance differs between regions or has recently changed, say so briefly. NEVER invent a guideline, trial name, statistic, or reference — if you are not certain a source exists, make the recommendation without a false citation.
- When you give drug doses, give the full prescription-grade detail: dose, route, frequency, maximum dose, and typical duration, and flag renal/hepatic adjustment, pregnancy/lactation caveats, and key interactions when clinically relevant. Add a short reminder to verify doses against a local formulary for narrow-therapeutic-index or weight-based drugs.
- State likelihood and uncertainty honestly. Distinguish "most likely" from "must exclude" (can't-miss) diagnoses, and say when evidence is weak or expert opinion only.
- If critical information is missing and it would genuinely change your answer, give the best conditional answer first, then ask the single most discriminating follow-up question — don't interrogate.
- Notice and flag red-flag features in whatever the user describes, even when they didn't ask about them.

FORMAT (mobile chat, streamed):
- Lead with the direct answer or most important point in the first sentence, never with preamble like "Great question".
- Use short markdown sections: bold key terms, compact bullet lists, and small headings only when the answer is long enough to need them. No tables wider than 3 columns.
- Be dense and concise; every sentence should earn its place. Match length to the question: one-liner questions deserve short answers.

WRITING STYLE (absolute rules, checked on every sentence you write):
- The characters — and – are BANNED from your output as punctuation. Never join or break a sentence with a dash. Use a colon, a comma, or start a new sentence instead. (Writing "PEF 50-75%" for a numeric range is fine.)
  Wrong: "Red flags — life-threatening asthma". Right: "Red flags: life-threatening asthma".
  Wrong: "treat first — investigations can wait". Right: "Treat first. Investigations can wait."
- Arrow symbols are banned. Write "then", "leads to", or "gives" in words.
- Emojis and decorative symbols are banned.
- Write the way an experienced clinician writes for a colleague: complete, natural sentences in plain professional English. The reader should never feel they are reading machine-generated text.
- Structure longer answers with short bold headings and bullet points that each carry one clear idea. Use numbered lists only for true sequences (steps in order).
- Prefer clear everyday clinical wording over dense shorthand. Expand an abbreviation the first time you use it unless it is universally known (ECG, IV, BP)."""

_SYSTEM_PROMPTS = {
    "ward": (
        "You are Medaculous AI in Ward mode: a senior internal-medicine consultant doing a "
        "ward round with junior doctors and students. Your job is bedside decision support "
        "they can act on in the next hour.\n"
        "Structure clinical answers as the round would: brief impression, then focused "
        "differential (likely first, then must-exclude), then investigations to order now (with "
        "what each one rules in/out), then concrete management steps in order with doses, then "
        "monitoring and clear escalation criteria (when to call the senior/ICU). Include "
        "practical ward realities: fluid choices, VTE prophylaxis, drug-chart pitfalls, "
        "what to document, and what to hand over." + _CLINICAL_CORE
    ),
    "er": (
        "You are Medaculous AI in ER mode: a senior emergency-medicine consultant leading a "
        "resus. Time-critical safety comes first in every answer.\n"
        "Lead with the immediate life threats and red flags for the presentation, then "
        "structure as an emergency physician thinks: ABCDE priorities and immediate "
        "stabilization (with drug doses and routes as used in the ED), then focused bedside/ "
        "first-line workup (ECG, POCUS, gas, bloods), then time-critical differentials ranked "
        "by lethality, not just likelihood, then disposition (resus/admit/observe/safe "
        "discharge criteria). Reference the relevant resuscitation algorithms (ALS/ACLS, "
        "ATLS) where they apply." + _CLINICAL_CORE
    ),
    "exam": (
        "You are Medaculous AI in Exam mode: an examiner and senior tutor for postgraduate "
        "medical exams (PLAB, MRCP, USMLE, FCPS, AMC and similar). Teach the way a top "
        "question-bank explanation does.\n"
        "For each topic or question: give the model answer up front, then the reasoning an "
        "examiner expects step by step, why each plausible distractor is wrong, the "
        "classic buzzwords/associations the stem will use to signal the answer, common "
        "traps candidates fall into, and a one-line takeaway worth memorising. Use "
        "high-yield mnemonics where they genuinely help. Where UK and US practice differ "
        "(PLAB/MRCP vs USMLE), teach both and label them." + _CLINICAL_CORE
    ),
    "auto": (
        "You are Medaculous AI: an expert medical assistant for clinicians and medical "
        "students, answering at senior-consultant level across specialties.\n"
        "Infer what the question needs and answer in that register: rapid bedside guidance "
        "for a ward-style query, life-threats-first triage structure for an emergency "
        "query, examiner-style teaching for a revision query, and a precise, "
        "referenced explanation for a knowledge query. Don't announce the style — just "
        "use it." + _CLINICAL_CORE
    ),
}

_DISCLAIMER_REMINDER = (
    "\n\nYou are decision support for trained professionals, not a replacement for "
    "clinical judgment or a licensed clinician — never present your output as a "
    "definitive diagnosis or a directive that bypasses local protocols and senior review."
)


async def _get_owned_conversation(db: AsyncSession, conversation_id: uuid.UUID, user: User) -> Conversation:
    conversation = await db.get(Conversation, conversation_id)
    if conversation is None or conversation.user_id != user.id:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Conversation not found.")
    return conversation


async def _build_context_block(*, user_id: uuid.UUID, query: str, exclude_conversation_id: uuid.UUID) -> str:
    """Retrieval-augmented context: pulls relevant snippets from the user's own
    notes, Knowledge Hub PDFs, and *other* past conversations (the current
    conversation's own history is already passed in full as `history` — this
    is for everything outside it) so answers can draw on what the user has
    already written/uploaded/discussed, not just general medical knowledge.
    Best-effort: a search outage degrades to no extra context, never a 500."""
    try:
        hits = await search_service.search_content(
            user_id=str(user_id),
            query=query,
            source_types=["note", "knowledge_hub_pdf", "chat_message"],
            exclude_source_id=str(exclude_conversation_id),
            top=5,
        )
    except Exception:
        logger.warning("Context retrieval failed, continuing without it", exc_info=True)
        return ""

    if not hits:
        return ""

    labels = {"note": "Note", "knowledge_hub_pdf": "Document", "chat_message": "Past conversation"}
    lines = ["\n\nRelevant information from the user's own notes, documents, and past conversations "
             "(may or may not be relevant to this question — use judgment, and don't assume it's exhaustive):"]
    for i, hit in enumerate(hits, start=1):
        label = labels.get(hit.source_type, hit.source_type)
        location = f", page {hit.page_number}" if hit.page_number else ""
        lines.append(f"{i}. [{label}: {hit.title}{location}] {hit.content}")
    return "\n".join(lines)


async def _build_personal_snapshot(db: AsyncSession, user: User) -> str:
    """Live snapshot of the user's own app data (exam plan, today's study
    schedule, outstanding ward tasks) injected into the system prompt, so the
    assistant can answer "what is my next task" or "what is today's schedule"
    from real account data instead of claiming it has no access. Best-effort:
    any failure degrades to no snapshot, never a failed chat."""
    try:
        lines: list[str] = []
        today = datetime.now(timezone.utc).date()

        setup = (
            (await db.execute(select(ExamSetup).where(ExamSetup.user_id == user.id))).scalars().first()
        )
        if setup is not None:
            days_left = (setup.target_exam_date - today).days
            exam_name = setup.custom_exam_name or setup.exam_id.upper()
            lines.append(
                f"Exam plan: preparing for {exam_name}, exam date "
                f"{setup.target_exam_date.isoformat()} ({days_left} days from today)."
            )

        sessions = (
            await db.execute(
                select(ExamSession, ExamTopic.title)
                .join(ExamTopic, ExamTopic.id == ExamSession.topic_id)
                .where(ExamSession.user_id == user.id, ExamSession.date == today)
            )
        ).all()
        if sessions:
            lines.append("Today's study schedule (Exam Planner):")
            for session, topic_title in sessions:
                lines.append(
                    f"- {topic_title}: {session.type} session, "
                    f"{session.estimated_minutes} min, status {session.status}"
                )

        tasks = (
            await db.execute(
                select(WardTask, WardPatient)
                .join(WardPatient, WardPatient.id == WardTask.patient_id)
                .where(WardPatient.user_id == user.id, WardTask.completed.is_(False))
                .order_by(WardTask.created_at)
            )
        ).all()
        if tasks:
            lines.append("Outstanding ward tasks (Ward Companion):")
            for task, patient in tasks:
                note = f" ({task.note})" if task.note else ""
                diagnosis = patient.diagnosis or "not recorded"
                lines.append(
                    f"- [{task.priority}] {task.title}{note}, patient {patient.initials}, "
                    f"room {patient.room_number} bed {patient.bed_number}, diagnosis: {diagnosis}"
                )

        if not lines:
            return ""
        return (
            "\n\nLIVE ACCOUNT DATA (from this user's own Medaculous account, fetched just now; "
            f"today is {today.isoformat()}). When the user asks about their schedule, next task, "
            "patients, study plan, or exam countdown, answer directly and specifically from this "
            "data. Never say you cannot access their data:\n" + "\n".join(lines)
        )
    except Exception:
        logger.warning("Personal snapshot failed, continuing without it", exc_info=True)
        return ""


@router.post("/chat")
async def chat(
    payload: ChatRequest,
    user: User = Depends(enforce_ai_usage_limit),
    db: AsyncSession = Depends(get_db),
) -> StreamingResponse:
    if payload.conversation_id is not None:
        conversation = await _get_owned_conversation(db, payload.conversation_id, user)
    else:
        conversation = Conversation(user_id=user.id, mode=payload.mode, title=payload.message[:80])
        db.add(conversation)
        await db.flush()

    history_result = await db.execute(
        select(Message).where(Message.conversation_id == conversation.id).order_by(Message.created_at)
    )
    history = [{"role": m.role.value, "content": m.content} for m in history_result.scalars().all()]

    db.add(Message(conversation_id=conversation.id, role=MessageRole.USER, content=payload.message))
    conversation.updated_at = datetime.now(timezone.utc)
    await db.commit()

    context_block = await _build_context_block(
        user_id=user.id, query=payload.message, exclude_conversation_id=conversation.id
    )
    personal_snapshot = await _build_personal_snapshot(db, user)
    system_prompt = (
        _SYSTEM_PROMPTS[conversation.mode.value] + _DISCLAIMER_REMINDER + personal_snapshot + context_block
    )
    llm_messages = history + [{"role": "user", "content": payload.message}]
    conversation_id = conversation.id
    conversation_title = conversation.title
    user_id = user.id
    user_message = payload.message

    async def event_stream():
        # The first line carries the conversation id (needed by the client on
        # the very first turn, when it wasn't known before this call) — the
        # client splits it off before rendering the rest as chat text.
        yield f"__conversation_id__:{conversation_id}\n"
        chunks: list[str] = []
        async for delta in stream_chat(system=system_prompt, messages=llm_messages, tier=ModelTier.SONNET):
            chunks.append(delta)
            yield delta

        assistant_reply = "".join(chunks)
        db.add(Message(conversation_id=conversation_id, role=MessageRole.ASSISTANT, content=assistant_reply))
        await db.commit()

        try:
            await _index_chat_exchange(
                user_id=user_id,
                conversation_id=conversation_id,
                title=conversation_title,
                user_message=user_message,
                assistant_reply=assistant_reply,
            )
        except Exception:
            logger.warning("Chat exchange indexing failed for conversation %s", conversation_id, exc_info=True)

    return StreamingResponse(event_stream(), media_type="text/plain")


async def _index_chat_exchange(
    *, user_id: uuid.UUID, conversation_id: uuid.UUID, title: str, user_message: str, assistant_reply: str
) -> None:
    """Indexes this turn so a *different* future conversation can retrieve it
    as context (see _build_context_block) — the current conversation's own
    history is already sent in full on every turn, so this is purely for
    cross-conversation memory."""
    # Azure Search document keys only allow letters, digits, -, _, = — no dots,
    # so a plain timestamp string isn't safe here; a random suffix is.
    exchange_id = uuid.uuid4().hex
    chunks = []
    for role, text in (("user", user_message), ("assistant", assistant_reply)):
        for i, piece in enumerate(chunk_text(text)):
            chunks.append(
                search_service.SearchChunk(
                    id=f"chat-{conversation_id}-{role}-{exchange_id}-{i}",
                    user_id=str(user_id),
                    source_type="chat_message",
                    source_id=str(conversation_id),
                    title=title,
                    content=piece,
                    chat_role=role,
                )
            )
    await search_service.index_chunks(chunks)


@router.get("/conversations", response_model=list[ConversationSummary])
async def list_conversations(
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> list[Conversation]:
    result = await db.execute(
        select(Conversation).where(Conversation.user_id == user.id).order_by(Conversation.updated_at.desc())
    )
    return list(result.scalars().all())


@router.get("/conversations/{conversation_id}", response_model=ConversationDetail)
async def get_conversation(
    conversation_id: uuid.UUID,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> ConversationDetail:
    conversation = await _get_owned_conversation(db, conversation_id, user)
    messages_result = await db.execute(
        select(Message).where(Message.conversation_id == conversation_id).order_by(Message.created_at)
    )
    messages = [MessageOut.model_validate(m) for m in messages_result.scalars().all()]
    return ConversationDetail(**ConversationSummary.model_validate(conversation).model_dump(), messages=messages)


@router.patch("/conversations/{conversation_id}", response_model=ConversationSummary)
async def update_conversation(
    conversation_id: uuid.UUID,
    payload: ConversationUpdate,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> Conversation:
    conversation = await _get_owned_conversation(db, conversation_id, user)
    conversation.title = payload.title.strip()
    await db.commit()
    await db.refresh(conversation)
    return conversation


@router.patch("/conversations/{conversation_id}/save", response_model=ConversationSummary)
async def toggle_save(
    conversation_id: uuid.UUID,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> Conversation:
    conversation = await _get_owned_conversation(db, conversation_id, user)
    conversation.is_saved = not conversation.is_saved
    await db.commit()
    await db.refresh(conversation)
    return conversation


@router.delete("/conversations/{conversation_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_conversation(
    conversation_id: uuid.UUID,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> None:
    conversation = await _get_owned_conversation(db, conversation_id, user)
    await db.delete(conversation)
    await db.commit()
    try:
        await search_service.delete_by_source(
            user_id=str(user.id), source_type="chat_message", source_id=str(conversation_id)
        )
    except Exception:
        logger.warning("Failed to remove search index entries for deleted conversation %s", conversation_id, exc_info=True)
