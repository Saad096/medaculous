import logging
import uuid
from datetime import datetime, timezone

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.deps import get_current_user
from app.db.session import get_db
from app.models.note import Folder, Note
from app.models.user import User
from app.schemas.notes import FolderCreate, FolderOut, FolderUpdate, NoteCreate, NoteOut, NoteUpdate
from app.services import search as search_service
from app.services.text_chunking import chunk_text, extract_note_plain_text

router = APIRouter(prefix="/notes", tags=["notes"])
logger = logging.getLogger(__name__)


async def _index_note(note: Note) -> None:
    """Best-effort — a search-indexing failure shouldn't block saving a note."""
    try:
        plain_text = extract_note_plain_text(note.content_html)
        if not plain_text and not note.title:
            await search_service.delete_by_source(user_id=str(note.user_id), source_type="note", source_id=str(note.id))
            return
        chunks = [
            search_service.SearchChunk(
                id=f"note-{note.id}-c{i}",
                user_id=str(note.user_id),
                source_type="note",
                source_id=str(note.id),
                title=note.title or "Untitled note",
                content=piece,
            )
            for i, piece in enumerate(chunk_text(plain_text) or [note.title or ""])
        ]
        await search_service.index_chunks(chunks)
    except Exception:
        logger.warning("Note content indexing failed for %s", note.id, exc_info=True)


async def _get_owned_folder(db: AsyncSession, folder_id: uuid.UUID, user: User) -> Folder:
    folder = await db.get(Folder, folder_id)
    if folder is None or folder.user_id != user.id or folder.is_deleted:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Folder not found.")
    return folder


async def _get_owned_note(db: AsyncSession, note_id: uuid.UUID, user: User) -> Note:
    note = await db.get(Note, note_id)
    if note is None or note.user_id != user.id or note.is_deleted:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Note not found.")
    return note


async def _validate_folder_ref(db: AsyncSession, folder_id: uuid.UUID | None, user: User) -> None:
    """A note/folder's parent_id/folder_id, if given, must point at a real folder the caller owns."""
    if folder_id is not None:
        await _get_owned_folder(db, folder_id, user)


@router.get("/folders", response_model=list[FolderOut])
async def list_folders(user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)) -> list[Folder]:
    result = await db.execute(
        select(Folder).where(Folder.user_id == user.id, Folder.is_deleted.is_(False)).order_by(Folder.name)
    )
    return list(result.scalars().all())


@router.post("/folders", response_model=FolderOut, status_code=status.HTTP_201_CREATED)
async def create_folder(
    payload: FolderCreate, user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)
) -> Folder:
    await _validate_folder_ref(db, payload.parent_id, user)
    folder = Folder(user_id=user.id, name=payload.name, parent_id=payload.parent_id)
    db.add(folder)
    await db.commit()
    await db.refresh(folder)
    return folder


@router.patch("/folders/{folder_id}", response_model=FolderOut)
async def update_folder(
    folder_id: uuid.UUID,
    payload: FolderUpdate,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> Folder:
    folder = await _get_owned_folder(db, folder_id, user)
    if payload.parent_id is not None:
        if payload.parent_id == folder_id:
            raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="A folder cannot contain itself.")
        await _validate_folder_ref(db, payload.parent_id, user)
        folder.parent_id = payload.parent_id
    if payload.name is not None:
        folder.name = payload.name
    folder.updated_at = datetime.now(timezone.utc)
    await db.commit()
    await db.refresh(folder)
    return folder


@router.delete("/folders/{folder_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_folder(
    folder_id: uuid.UUID, user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)
) -> None:
    folder = await _get_owned_folder(db, folder_id, user)
    now = datetime.now(timezone.utc)
    folder.is_deleted = True
    folder.deleted_at = now
    # Notes inside a deleted folder move to "no folder" rather than being
    # soft-deleted themselves — deleting a folder shouldn't silently destroy
    # the notes a user spent time writing.
    notes_result = await db.execute(
        select(Note).where(Note.folder_id == folder_id, Note.is_deleted.is_(False))
    )
    for note in notes_result.scalars().all():
        note.folder_id = None
        note.updated_at = now
    await db.commit()


@router.get("", response_model=list[NoteOut])
async def list_notes(
    folder_id: uuid.UUID | None = None,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> list[Note]:
    query = select(Note).where(Note.user_id == user.id, Note.is_deleted.is_(False))
    if folder_id is not None:
        query = query.where(Note.folder_id == folder_id)
    query = query.order_by(Note.is_pinned.desc(), Note.updated_at.desc())
    result = await db.execute(query)
    return list(result.scalars().all())


@router.post("", response_model=NoteOut, status_code=status.HTTP_201_CREATED)
async def create_note(
    payload: NoteCreate, user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)
) -> Note:
    await _validate_folder_ref(db, payload.folder_id, user)
    note = Note(
        user_id=user.id,
        folder_id=payload.folder_id,
        title=payload.title,
        content_html=payload.content_html,
    )
    db.add(note)
    await db.commit()
    await db.refresh(note)
    await _index_note(note)
    return note


@router.get("/trash", response_model=list[NoteOut])
async def list_trash(user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)) -> list[Note]:
    # Registered before /{note_id} — a static path must come first, otherwise
    # "trash" would be captured by {note_id} and fail UUID parsing with a 422.
    result = await db.execute(
        select(Note)
        .where(Note.user_id == user.id, Note.is_deleted.is_(True))
        .order_by(Note.deleted_at.desc())
    )
    return list(result.scalars().all())


@router.delete("/trash", status_code=status.HTTP_204_NO_CONTENT)
async def empty_trash(user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)) -> None:
    # Registered before /{note_id} for the same routing reason as GET /trash
    # above — a static path must be matched before the {note_id} pattern.
    result = await db.execute(select(Note).where(Note.user_id == user.id, Note.is_deleted.is_(True)))
    trashed = list(result.scalars().all())
    for note in trashed:
        await db.delete(note)
    await db.commit()
    for note in trashed:
        try:
            await search_service.delete_by_source(user_id=str(user.id), source_type="note", source_id=str(note.id))
        except Exception:
            logger.warning("Failed to remove search index entries for purged note %s", note.id, exc_info=True)


@router.post("/{note_id}/restore", response_model=NoteOut)
async def restore_note(
    note_id: uuid.UUID, user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)
) -> Note:
    note = await db.get(Note, note_id)
    if note is None or note.user_id != user.id or not note.is_deleted:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Note not found in trash.")
    note.is_deleted = False
    note.deleted_at = None
    note.updated_at = datetime.now(timezone.utc)
    await db.commit()
    await db.refresh(note)
    await _index_note(note)
    return note


@router.get("/{note_id}", response_model=NoteOut)
async def get_note(
    note_id: uuid.UUID, user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)
) -> Note:
    return await _get_owned_note(db, note_id, user)


@router.patch("/{note_id}", response_model=NoteOut)
async def update_note(
    note_id: uuid.UUID,
    payload: NoteUpdate,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> Note:
    note = await _get_owned_note(db, note_id, user)
    if payload.folder_id is not None:
        await _validate_folder_ref(db, payload.folder_id, user)
    update_data = payload.model_dump(exclude_unset=True)
    for field, value in update_data.items():
        setattr(note, field, value)
    note.updated_at = datetime.now(timezone.utc)
    await db.commit()
    await db.refresh(note)
    await _index_note(note)
    return note


@router.delete("/{note_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_note(
    note_id: uuid.UUID, user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)
) -> None:
    note = await _get_owned_note(db, note_id, user)
    note.is_deleted = True
    note.deleted_at = datetime.now(timezone.utc)
    await db.commit()
    try:
        await search_service.delete_by_source(user_id=str(user.id), source_type="note", source_id=str(note.id))
    except Exception:
        logger.warning("Failed to remove search index entries for deleted note %s", note.id, exc_info=True)
