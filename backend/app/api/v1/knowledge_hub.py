import asyncio
import io
import logging
import uuid
from pathlib import Path

from fastapi import APIRouter, Depends, HTTPException, UploadFile, status
from fastapi.responses import FileResponse
from pypdf import PdfReader
from pypdf.errors import PdfReadError
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.deps import get_current_user
from app.core.config import settings
from app.db.session import get_db
from app.models.knowledge_hub import PdfAnnotation, PdfBookmark, PdfDocument, PdfFolder
from app.models.user import User
from app.schemas.knowledge_hub import (
    AnnotationCreate,
    AnnotationOut,
    BookmarkCreate,
    BookmarkOut,
    FolderCreate,
    FolderOut,
    FolderRename,
    PdfDocumentOut,
    PdfDocumentUpdate,
    PdfSearchHit,
)
from app.services import search as search_service
from app.services.text_chunking import chunk_text

router = APIRouter(prefix="/knowledge-hub", tags=["knowledge-hub"])


_CONTENT_PREVIEW_MAX_CHARS = 400


def _extract_pdf_metadata(content: bytes) -> tuple[str | None, str | None, str | None]:
    """Best-effort title/author (from the PDF's own embedded metadata) plus a
    plain-text excerpt of the first page carrying real text — a scanned or
    image-only PDF just yields (None, None, None), same as any other
    extraction failure, since the upload itself must never fail over this."""
    try:
        reader = PdfReader(io.BytesIO(content))
        meta = reader.metadata
        title = (meta.title or "").strip() if meta else ""
        author = (meta.author or "").strip() if meta else ""
        preview = ""
        for page in reader.pages:
            text = (page.extract_text() or "").strip()
            if text:
                preview = " ".join(text.split())[:_CONTENT_PREVIEW_MAX_CHARS]
                break
        return (title or None, author or None, preview or None)
    except Exception:
        logger.warning("PDF metadata extraction failed", exc_info=True)
        return (None, None, None)


async def _index_pdf_content(pdf: PdfDocument, content: bytes) -> None:
    """Extracts per-page text and indexes it for full-text search. Best-effort:
    a scanned/image-only PDF or an extraction failure shouldn't block the
    upload — the PDF is still stored and viewable, just not content-searchable."""
    try:
        reader = PdfReader(io.BytesIO(content))
        chunks = []
        for page_num, page in enumerate(reader.pages, start=1):
            page_text = (page.extract_text() or "").strip()
            if not page_text:
                continue
            for i, piece in enumerate(chunk_text(page_text)):
                chunks.append(
                    search_service.SearchChunk(
                        id=f"pdf-{pdf.id}-p{page_num}-c{i}",
                        user_id=str(pdf.user_id),
                        source_type="knowledge_hub_pdf",
                        source_id=str(pdf.id),
                        title=pdf.filename,
                        content=piece,
                        page_number=page_num,
                    )
                )
        await search_service.index_chunks(chunks)
    except Exception:
        logger.warning("PDF content indexing failed for %s", pdf.id, exc_info=True)


logger = logging.getLogger(__name__)


def _storage_root() -> Path:
    root = Path(settings.PDF_STORAGE_DIR)
    root.mkdir(parents=True, exist_ok=True)
    return root


def _pdf_path(user_id: uuid.UUID, pdf_id: uuid.UUID) -> Path:
    user_dir = _storage_root() / str(user_id)
    user_dir.mkdir(parents=True, exist_ok=True)
    return user_dir / f"{pdf_id}.pdf"


async def _get_owned_folder(db: AsyncSession, folder_id: uuid.UUID, user: User) -> PdfFolder:
    folder = await db.get(PdfFolder, folder_id)
    if folder is None or folder.user_id != user.id or folder.is_deleted:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Folder not found.")
    return folder


async def _get_owned_pdf(db: AsyncSession, pdf_id: uuid.UUID, user: User) -> PdfDocument:
    pdf = await db.get(PdfDocument, pdf_id)
    if pdf is None or pdf.user_id != user.id or pdf.is_deleted:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="PDF not found.")
    return pdf


# --- Folders -----------------------------------------------------------------


@router.get("/folders", response_model=list[FolderOut])
async def list_folders(user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)) -> list[PdfFolder]:
    result = await db.execute(
        select(PdfFolder).where(PdfFolder.user_id == user.id, PdfFolder.is_deleted.is_(False)).order_by(PdfFolder.name)
    )
    return list(result.scalars().all())


@router.post("/folders", response_model=FolderOut, status_code=status.HTTP_201_CREATED)
async def create_folder(
    body: FolderCreate, user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)
) -> PdfFolder:
    if body.parent_id is not None:
        await _get_owned_folder(db, body.parent_id, user)
    folder = PdfFolder(user_id=user.id, name=body.name, parent_id=body.parent_id)
    db.add(folder)
    await db.commit()
    await db.refresh(folder)
    return folder


@router.patch("/folders/{folder_id}", response_model=FolderOut)
async def rename_folder(
    folder_id: uuid.UUID,
    body: FolderRename,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> PdfFolder:
    folder = await _get_owned_folder(db, folder_id, user)
    folder.name = body.name.strip()
    await db.commit()
    await db.refresh(folder)
    return folder


@router.delete("/folders/{folder_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_folder(
    folder_id: uuid.UUID, user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)
) -> None:
    folder = await _get_owned_folder(db, folder_id, user)
    folder.is_deleted = True
    # PDFs in a deleted folder move to root rather than being deleted, same
    # design choice already made for Notes folders.
    result = await db.execute(select(PdfDocument).where(PdfDocument.folder_id == folder_id))
    for pdf in result.scalars().all():
        pdf.folder_id = None
    await db.commit()


# --- PDFs ----------------------------------------------------------------------


@router.get("/pdfs", response_model=list[PdfDocumentOut])
async def list_pdfs(
    folder_id: uuid.UUID | None = None,
    q: str | None = None,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> list[PdfDocument]:
    query = select(PdfDocument).where(PdfDocument.user_id == user.id, PdfDocument.is_deleted.is_(False))
    if q:
        query = query.where(PdfDocument.filename.ilike(f"%{q}%"))
    elif folder_id is not None:
        query = query.where(PdfDocument.folder_id == folder_id)
    else:
        query = query.where(PdfDocument.folder_id.is_(None))
    result = await db.execute(query.order_by(PdfDocument.filename))
    return list(result.scalars().all())


@router.get("/search", response_model=list[PdfSearchHit])
async def search_pdf_content(
    q: str, user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)
) -> list[PdfSearchHit]:
    """Full-text search *inside* PDF content, not just filenames (list_pdfs'
    `q` param does filename-only matching) — the Knowledge Hub search bar
    calls this in addition to list_pdfs so results include content matches."""
    hits = await search_service.search_content(user_id=str(user.id), query=q, source_types=["knowledge_hub_pdf"], top=10)
    results = []
    for hit in hits:
        pdf_id = uuid.UUID(hit.source_id)
        pdf = await db.get(PdfDocument, pdf_id)
        if pdf is None or pdf.user_id != user.id or pdf.is_deleted:
            continue  # index entry outlived the PDF row somehow — skip rather than error
        snippet = hit.content[:280] + ("…" if len(hit.content) > 280 else "")
        results.append(PdfSearchHit(pdf_id=pdf_id, filename=hit.title, page_number=hit.page_number, snippet=snippet))
    return results


@router.post("/pdfs", response_model=PdfDocumentOut, status_code=status.HTTP_201_CREATED)
async def upload_pdf(
    file: UploadFile,
    folder_id: uuid.UUID | None = None,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> PdfDocument:
    if file.content_type not in ("application/pdf", "application/octet-stream"):
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Only PDF files are supported.")
    if folder_id is not None:
        await _get_owned_folder(db, folder_id, user)

    content = await file.read()
    max_bytes = settings.PDF_MAX_UPLOAD_MB * 1024 * 1024
    if len(content) > max_bytes:
        raise HTTPException(
            status_code=status.HTTP_413_REQUEST_ENTITY_TOO_LARGE,
            detail=f"PDF exceeds the {settings.PDF_MAX_UPLOAD_MB}MB upload limit.",
        )

    try:
        page_count = len(PdfReader(io.BytesIO(content)).pages)
    except PdfReadError as exc:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Not a valid PDF file.") from exc

    title, author, content_preview = _extract_pdf_metadata(content)
    pdf = PdfDocument(
        user_id=user.id,
        folder_id=folder_id,
        filename=file.filename or "Untitled.pdf",
        size_bytes=len(content),
        page_count=page_count,
        title=title,
        author=author,
        content_preview=content_preview,
    )
    db.add(pdf)
    await db.flush()
    _pdf_path(user.id, pdf.id).write_bytes(content)
    await db.commit()
    await db.refresh(pdf)
    await _index_pdf_content(pdf, content)
    return pdf


@router.get("/pdfs/{pdf_id}", response_model=PdfDocumentOut)
async def get_pdf_metadata(
    pdf_id: uuid.UUID, user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)
) -> PdfDocument:
    return await _get_owned_pdf(db, pdf_id, user)


@router.get("/pdfs/{pdf_id}/file")
async def get_pdf_file(pdf_id: uuid.UUID, user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)) -> FileResponse:
    pdf = await _get_owned_pdf(db, pdf_id, user)
    path = _pdf_path(user.id, pdf.id)
    if not path.exists():
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="PDF file missing from storage.")
    return FileResponse(path, media_type="application/pdf", filename=pdf.filename)


@router.get("/pdfs/{pdf_id}/outline")
async def get_pdf_outline(
    pdf_id: uuid.UUID, user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)
) -> list[dict]:
    """Document outline (table of contents) embedded in the PDF, flattened
    with nesting levels, so the viewer can offer jump-to-section navigation
    (feature PDF, Knowledge Hub fix #3)."""
    pdf = await _get_owned_pdf(db, pdf_id, user)
    path = _pdf_path(user.id, pdf.id)
    if not path.exists():
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="PDF file missing from storage.")

    def _extract() -> list[dict]:
        try:
            reader = PdfReader(str(path))
        except PdfReadError:
            return []

        entries: list[dict] = []

        def walk(nodes, level: int) -> None:
            for node in nodes:
                if isinstance(node, list):
                    walk(node, level + 1)
                    continue
                try:
                    page_index = reader.get_destination_page_number(node)
                except Exception:
                    continue
                title = (node.title or "").strip()
                if not title or page_index is None:
                    continue
                entries.append({"title": title, "page": page_index + 1, "level": level})

        try:
            walk(reader.outline, 0)
        except Exception:
            return []
        return entries

    return await asyncio.to_thread(_extract)


@router.patch("/pdfs/{pdf_id}", response_model=PdfDocumentOut)
async def update_pdf(
    pdf_id: uuid.UUID,
    body: PdfDocumentUpdate,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> PdfDocument:
    pdf = await _get_owned_pdf(db, pdf_id, user)
    if body.filename is not None:
        pdf.filename = body.filename
    if body.clear_folder:
        pdf.folder_id = None
    elif body.folder_id is not None:
        await _get_owned_folder(db, body.folder_id, user)
        pdf.folder_id = body.folder_id
    await db.commit()
    await db.refresh(pdf)
    return pdf


@router.delete("/pdfs/{pdf_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_pdf(pdf_id: uuid.UUID, user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)) -> None:
    pdf = await _get_owned_pdf(db, pdf_id, user)
    pdf.is_deleted = True
    await db.commit()
    _pdf_path(user.id, pdf.id).unlink(missing_ok=True)
    try:
        await search_service.delete_by_source(user_id=str(user.id), source_type="knowledge_hub_pdf", source_id=str(pdf.id))
    except Exception:
        logger.warning("Failed to remove search index entries for deleted PDF %s", pdf.id, exc_info=True)


# --- Bookmarks -----------------------------------------------------------------


@router.get("/pdfs/{pdf_id}/bookmarks", response_model=list[BookmarkOut])
async def list_bookmarks(
    pdf_id: uuid.UUID, user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)
) -> list[PdfBookmark]:
    await _get_owned_pdf(db, pdf_id, user)
    result = await db.execute(select(PdfBookmark).where(PdfBookmark.pdf_id == pdf_id).order_by(PdfBookmark.page_number))
    return list(result.scalars().all())


@router.post("/pdfs/{pdf_id}/bookmarks", response_model=BookmarkOut, status_code=status.HTTP_201_CREATED)
async def create_bookmark(
    pdf_id: uuid.UUID, body: BookmarkCreate, user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)
) -> PdfBookmark:
    await _get_owned_pdf(db, pdf_id, user)
    bookmark = PdfBookmark(pdf_id=pdf_id, page_number=body.page_number, label=body.label)
    db.add(bookmark)
    await db.commit()
    await db.refresh(bookmark)
    return bookmark


@router.delete("/bookmarks/{bookmark_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_bookmark(bookmark_id: uuid.UUID, user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)) -> None:
    bookmark = await db.get(PdfBookmark, bookmark_id)
    if bookmark is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Bookmark not found.")
    await _get_owned_pdf(db, bookmark.pdf_id, user)
    await db.delete(bookmark)
    await db.commit()


# --- Annotations -----------------------------------------------------------------


@router.get("/pdfs/{pdf_id}/annotations", response_model=list[AnnotationOut])
async def list_annotations(
    pdf_id: uuid.UUID, user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)
) -> list[PdfAnnotation]:
    await _get_owned_pdf(db, pdf_id, user)
    result = await db.execute(select(PdfAnnotation).where(PdfAnnotation.pdf_id == pdf_id).order_by(PdfAnnotation.page_number))
    return list(result.scalars().all())


@router.post("/pdfs/{pdf_id}/annotations", response_model=AnnotationOut, status_code=status.HTTP_201_CREATED)
async def create_annotation(
    pdf_id: uuid.UUID, body: AnnotationCreate, user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)
) -> PdfAnnotation:
    await _get_owned_pdf(db, pdf_id, user)
    # "ink" = freehand pen stroke: rects hold the ordered points as zero-size
    # page-relative rects, text holds the stroke width as a page-width fraction.
    if body.type not in ("highlight", "note", "ink"):
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="type must be 'highlight', 'note' or 'ink'.")
    annotation = PdfAnnotation(
        pdf_id=pdf_id,
        page_number=body.page_number,
        type=body.type,
        color=body.color,
        rects=[r.model_dump() for r in body.rects],
        text=body.text,
        note=body.note,
    )
    db.add(annotation)
    await db.commit()
    await db.refresh(annotation)
    return annotation


@router.delete("/annotations/{annotation_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_annotation(annotation_id: uuid.UUID, user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)) -> None:
    annotation = await db.get(PdfAnnotation, annotation_id)
    if annotation is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Annotation not found.")
    await _get_owned_pdf(db, annotation.pdf_id, user)
    await db.delete(annotation)
    await db.commit()
