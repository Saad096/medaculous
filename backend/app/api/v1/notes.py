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
from app.schemas.notes import FolderCreate, FolderOut, FolderUpdate, NoteCreate, NoteOut, NoteReorder, NoteUpdate
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


@router.get("/folders/trash", response_model=list[FolderOut])
async def list_trashed_folders(user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)) -> list[Folder]:
    # Registered before /folders/{folder_id} — same routing reason as
    # GET /trash below: a static path must be matched before a variable one.
    result = await db.execute(
        select(Folder)
        .where(Folder.user_id == user.id, Folder.is_deleted.is_(True))
        .order_by(Folder.deleted_at.desc())
    )
    return list(result.scalars().all())


@router.post("/folders/{folder_id}/restore", response_model=FolderOut)
async def restore_folder(
    folder_id: uuid.UUID, user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)
) -> Folder:
    folder = await db.get(Folder, folder_id)
    if folder is None or folder.user_id != user.id or not folder.is_deleted:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Folder not found in trash.")
    # The notes that were in this folder were already permanently reassigned
    # to "no folder" at delete time (see delete_folder below) rather than
    # soft-deleted alongside it, so restoring only brings the folder shell
    # back, not its old contents — there's no record left of which notes
    # used to be in it.
    folder.is_deleted = False
    folder.deleted_at = None
    folder.updated_at = datetime.now(timezone.utc)
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
    # "parent_id" in model_fields_set (not "payload.parent_id is not None") —
    # the Move feature needs to be able to send parent_id: null to move a
    # folder back to top level, which a plain not-None check could never
    # distinguish from the field simply being omitted (owner feedback,
    # 2026-09-11).
    if "parent_id" in payload.model_fields_set:
        new_parent_id = payload.parent_id
        if new_parent_id is not None:
            if new_parent_id == folder_id:
                raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="A folder cannot contain itself.")
            await _validate_folder_ref(db, new_parent_id, user)
            # Walk up from the destination; if this folder is among its own
            # ancestors, the move would create a cycle (e.g. dragging
            # "Radiology" into its own child "MRI Protocols").
            cursor: uuid.UUID | None = new_parent_id
            while cursor is not None:
                if cursor == folder_id:
                    raise HTTPException(
                        status_code=status.HTTP_400_BAD_REQUEST, detail="A folder cannot be moved inside its own subfolder."
                    )
                cursor = (await db.get(Folder, cursor)).parent_id
        folder.parent_id = new_parent_id
    if payload.name is not None:
        folder.name = payload.name
    folder.updated_at = datetime.now(timezone.utc)
    await db.commit()
    await db.refresh(folder)
    return folder


async def _release_notes(db: AsyncSession, folder_id: uuid.UUID, now: datetime) -> None:
    """Notes directly inside a folder move to "no folder" rather than being
    soft-deleted themselves — deleting a folder shouldn't silently destroy
    the notes a user spent time writing."""
    notes_result = await db.execute(select(Note).where(Note.folder_id == folder_id, Note.is_deleted.is_(False)))
    for note in notes_result.scalars().all():
        note.folder_id = None
        note.updated_at = now


@router.delete("/folders/{folder_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_folder(
    folder_id: uuid.UUID, user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)
) -> None:
    folder = await _get_owned_folder(db, folder_id, user)
    now = datetime.now(timezone.utc)
    folder.is_deleted = True
    folder.deleted_at = now
    await _release_notes(db, folder_id, now)

    # Every nested sub-folder underneath this one is soft-deleted too —
    # otherwise it stays "alive" but unreachable: hidden from every listing
    # because its parent no longer shows up anywhere, yet not in Trash
    # either since nothing marked it deleted (owner feedback, 2026-09-11).
    frontier = [folder_id]
    while frontier:
        children_result = await db.execute(
            select(Folder).where(Folder.parent_id.in_(frontier), Folder.is_deleted.is_(False))
        )
        children = list(children_result.scalars().all())
        frontier = []
        for child in children:
            child.is_deleted = True
            child.deleted_at = now
            await _release_notes(db, child.id, now)
            frontier.append(child.id)
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


@router.get("/search", response_model=list[NoteOut])
async def search_notes(
    q: str, user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)
) -> list[Note]:
    # Registered before /{note_id} — same routing reason as GET /trash below:
    # a static path must be matched before the {note_id} pattern, or "search"
    # gets captured by {note_id} and fails UUID parsing with a 422.
    query = q.strip().lower()
    if len(query) < 2:
        return []
    result = await db.execute(
        select(Note).where(Note.user_id == user.id, Note.is_deleted.is_(False)).order_by(Note.updated_at.desc())
    )
    # Filtered in Python against the plain-text extraction (same helper used
    # for search indexing) rather than a SQL ILIKE straight against the raw
    # Quill Delta JSON in content_html — matching against actual words
    # instead of JSON structure is both more accurate and simpler than
    # keeping a second, separately-maintained search path in sync with the
    # Azure index used elsewhere in this file.
    return [
        note
        for note in result.scalars().all()
        if query in note.title.lower() or query in extract_note_plain_text(note.content_html).lower()
    ]


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

    # Deleted folders also need purging here — owner feedback, 2026-09-11:
    # a deleted folder had no way to ever leave Trash at all before this.
    folders_result = await db.execute(select(Folder).where(Folder.user_id == user.id, Folder.is_deleted.is_(True)))
    trashed_folders = list(folders_result.scalars().all())
    trashed_folder_ids = {folder.id for folder in trashed_folders}
    if trashed_folder_ids:
        # parent_id has no ON DELETE rule, so hard-deleting a folder while
        # any other folder (trashed or not — a nested folder isn't forced
        # into Trash just because its parent is) still points at it via
        # parent_id would violate the foreign key. Detach every such
        # reference first rather than erroring or silently skipping the
        # purge — the child folder simply becomes top-level instead of
        # disappearing with its now-gone parent.
        children_result = await db.execute(select(Folder).where(Folder.parent_id.in_(trashed_folder_ids)))
        for child in children_result.scalars().all():
            child.parent_id = None
        for folder in trashed_folders:
            await db.delete(folder)

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


@router.patch("/reorder", status_code=status.HTTP_204_NO_CONTENT)
async def reorder_notes(
    payload: NoteReorder, user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)
) -> None:
    # Registered before PATCH /{note_id} — same routing reason as the other
    # static paths in this file: otherwise "reorder" gets captured by
    # {note_id} and fails UUID parsing with a 422.
    #
    # note_ids is exactly the list currently shown on screen (one folder, or
    # "All Notes"), in the user's new drag-and-drop order — sort_order is
    # only ever compared within that same list, so reassigning it as a plain
    # 0..N-1 sequence per call is enough; it doesn't need to be globally
    # unique or gap-free across folders.
    for index, note_id in enumerate(payload.note_ids):
        note = await _get_owned_note(db, note_id, user)
        note.sort_order = index
    await db.commit()


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
