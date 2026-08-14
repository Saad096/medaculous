"""Plain-text chunking for search indexing. No tokenizer dependency — chunks
by character count with overlap, which is good enough for BM25/semantic
search (unlike LLM context windows, search relevance isn't sensitive to
splitting mid-sentence occasionally)."""

import json
import re

_TAG_RE = re.compile(r"<[^>]+>")
_WHITESPACE_RE = re.compile(r"\s+")

_CHUNK_SIZE = 1500
_CHUNK_OVERLAP = 200


def strip_html(html: str) -> str:
    """Note content is stored as HTML (see Note.content_html) — search needs
    the plain text underneath, not markup."""
    text = _TAG_RE.sub(" ", html)
    return _WHITESPACE_RE.sub(" ", text).strip()


def extract_note_plain_text(content: str) -> str:
    """Note.content_html now stores flutter_quill Delta JSON (a list of
    {"insert": ...} ops), not HTML — see frontend's NoteContentCodec. Pull out
    only the string inserts (skip image/embed ops entirely, since an embed's
    "insert" value is a dict holding a base64 data: URI that must never reach
    the search index). Falls back to strip_html for pre-migration plain-text/
    HTML notes, where json.loads fails.
    """
    try:
        ops = json.loads(content)
    except (json.JSONDecodeError, TypeError):
        return strip_html(content)
    if not isinstance(ops, list):
        return strip_html(content)

    pieces = []
    for op in ops:
        if isinstance(op, dict) and isinstance(op.get("insert"), str):
            pieces.append(op["insert"])
    return _WHITESPACE_RE.sub(" ", "".join(pieces)).strip()


def chunk_text(text: str, *, chunk_size: int = _CHUNK_SIZE, overlap: int = _CHUNK_OVERLAP) -> list[str]:
    text = text.strip()
    if not text:
        return []
    if len(text) <= chunk_size:
        return [text]

    chunks = []
    start = 0
    while start < len(text):
        end = start + chunk_size
        chunks.append(text[start:end])
        if end >= len(text):
            break
        start = end - overlap
    return chunks
