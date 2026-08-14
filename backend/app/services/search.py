"""
Azure AI Search — per-user-scoped retrieval across Knowledge Hub PDFs, Notes,
and AI chat history. Powers two things: (1) Knowledge Hub's full-text PDF
search (previously scope-cut to filename-only, see OPEN_QUESTIONS.md), and
(2) retrieval-augmented context for Medaculous AI chat, so answers can draw on
a user's own notes/documents/past conversations, not just the current
conversation's own message history.

Design: ONE shared index (`AZURE_SEARCH_INDEX`) rather than one index per user.
Azure AI Search's documented pattern for multi-tenant search is a single index
with a filterable `user_id` field enforced on every query ("security
trimming"), not per-user indexes — the service's index-count quota (typically
50) would be blown through at any real user scale, and a shared index with
rich metadata fields (source_type, folder_name, page_number, tags) gives
better relevance tuning per user via filters than physical isolation would.
Every query in this module takes user_id and enforces it as a hard filter —
never call search_content()/delete_by_source() without it.

No embedding provider is configured (Anthropic doesn't offer one, and no
Azure OpenAI resource was provisioned), so retrieval is BM25 full-text search
with Azure's semantic reranker layered on top when the service tier supports
it (falls back to plain full-text automatically otherwise — see
search_content's try/except). This is a real relevance upgrade over naive
keyword matching without requiring a vector pipeline; content_vector-based
similarity search can be added later as a swap-in if an embedding provider is
chosen (see OPEN_QUESTIONS.md).
"""

import logging
from dataclasses import dataclass, field
from datetime import datetime, timezone
from functools import lru_cache
from typing import Any, Literal

from azure.core.credentials import AzureKeyCredential
from azure.core.exceptions import ResourceNotFoundError
from azure.search.documents.aio import SearchClient
from azure.search.documents.indexes.aio import SearchIndexClient
from azure.search.documents.indexes.models import (
    SearchField,
    SearchFieldDataType,
    SearchIndex,
    SemanticConfiguration,
    SemanticField,
    SemanticPrioritizedFields,
    SemanticSearch,
)
from azure.search.documents.models import QueryType

from app.core.config import settings

logger = logging.getLogger(__name__)

SourceType = Literal["knowledge_hub_pdf", "note", "chat_message"]

_SEMANTIC_CONFIG_NAME = "default"


@lru_cache
def _index_client() -> SearchIndexClient:
    return SearchIndexClient(endpoint=settings.AZURE_SEARCH_ENDPOINT, credential=AzureKeyCredential(settings.AZURE_SEARCH_KEY))


@lru_cache
def _search_client() -> SearchClient:
    return SearchClient(
        endpoint=settings.AZURE_SEARCH_ENDPOINT,
        index_name=settings.AZURE_SEARCH_INDEX,
        credential=AzureKeyCredential(settings.AZURE_SEARCH_KEY),
    )


def _build_index() -> SearchIndex:
    fields = [
        SearchField(name="id", type=SearchFieldDataType.String, key=True, filterable=True),
        SearchField(name="user_id", type=SearchFieldDataType.String, filterable=True),
        SearchField(name="source_type", type=SearchFieldDataType.String, filterable=True, facetable=True),
        SearchField(name="source_id", type=SearchFieldDataType.String, filterable=True),
        SearchField(name="title", type=SearchFieldDataType.String, searchable=True),
        SearchField(
            name="content", type=SearchFieldDataType.String, searchable=True, analyzer_name="en.microsoft"
        ),
        SearchField(name="folder_name", type=SearchFieldDataType.String, filterable=True, facetable=True),
        SearchField(name="page_number", type=SearchFieldDataType.Int32, filterable=True, sortable=True),
        SearchField(name="chat_role", type=SearchFieldDataType.String, filterable=True),
        SearchField(
            name="tags",
            type=SearchFieldDataType.Collection(SearchFieldDataType.String),
            filterable=True,
            facetable=True,
        ),
        SearchField(name="created_at", type=SearchFieldDataType.DateTimeOffset, filterable=True, sortable=True),
    ]
    semantic_search = SemanticSearch(
        configurations=[
            SemanticConfiguration(
                name=_SEMANTIC_CONFIG_NAME,
                prioritized_fields=SemanticPrioritizedFields(
                    title_field=SemanticField(field_name="title"),
                    content_fields=[SemanticField(field_name="content")],
                    keywords_fields=[SemanticField(field_name="tags")],
                ),
            )
        ]
    )
    return SearchIndex(name=settings.AZURE_SEARCH_INDEX, fields=fields, semantic_search=semantic_search)


_ensured = False


async def ensure_index_exists() -> None:
    """Idempotent — creates the index once if it doesn't exist yet. Safe to
    call before every write/query; a no-op after the first successful check
    this process (module-level flag, not persisted)."""
    global _ensured
    if _ensured:
        return
    client = _index_client()
    try:
        await client.get_index(settings.AZURE_SEARCH_INDEX)
    except ResourceNotFoundError:
        await client.create_index(_build_index())
        logger.info("Created Azure AI Search index %s", settings.AZURE_SEARCH_INDEX)
    _ensured = True


@dataclass
class SearchChunk:
    id: str
    user_id: str
    source_type: SourceType
    source_id: str
    title: str
    content: str
    folder_name: str | None = None
    page_number: int | None = None
    chat_role: str | None = None
    tags: list[str] = field(default_factory=list)

    def to_document(self) -> dict[str, Any]:
        return {
            "id": self.id,
            "user_id": self.user_id,
            "source_type": self.source_type,
            "source_id": self.source_id,
            "title": self.title,
            "content": self.content,
            "folder_name": self.folder_name,
            "page_number": self.page_number,
            "chat_role": self.chat_role,
            "tags": self.tags,
            "created_at": datetime.now(timezone.utc).isoformat(),
        }


async def index_chunks(chunks: list[SearchChunk]) -> None:
    if not chunks:
        return
    await ensure_index_exists()
    await _search_client().merge_or_upload_documents(documents=[c.to_document() for c in chunks])


def _escape(value: str) -> str:
    """OData string literals escape a single quote by doubling it."""
    return value.replace("'", "''")


async def delete_by_source(*, user_id: str, source_type: SourceType, source_id: str) -> None:
    """Removes every indexed chunk for one PDF/note/conversation. Called on
    delete so search never surfaces content the user has removed — the same
    confidentiality bar Ward Companion's wipe endpoint already holds to."""
    await ensure_index_exists()
    client = _search_client()
    results = await client.search(
        search_text="*",
        filter=(
            f"user_id eq '{_escape(user_id)}' and source_type eq '{source_type}' "
            f"and source_id eq '{_escape(source_id)}'"
        ),
        select=["id"],
        top=1000,
    )
    ids = [doc["id"] async for doc in results]
    if ids:
        await client.delete_documents(documents=[{"id": i} for i in ids])


@dataclass
class SearchHit:
    source_type: str
    source_id: str
    title: str
    content: str
    page_number: int | None
    score: float


async def search_content(
    *,
    user_id: str,
    query: str,
    source_types: list[SourceType] | None = None,
    exclude_source_id: str | None = None,
    top: int = 5,
) -> list[SearchHit]:
    """Full-text (+ semantic reranking, when the service tier supports it)
    search scoped to one user. Every caller MUST pass the real user_id."""
    if not query or not query.strip():
        return []
    await ensure_index_exists()
    client = _search_client()

    filter_parts = [f"user_id eq '{_escape(user_id)}'"]
    if source_types:
        type_filter = " or ".join(f"source_type eq '{t}'" for t in source_types)
        filter_parts.append(f"({type_filter})")
    if exclude_source_id:
        filter_parts.append(f"source_id ne '{_escape(exclude_source_id)}'")
    filter_expr = " and ".join(filter_parts)

    try:
        results = await client.search(
            search_text=query,
            filter=filter_expr,
            query_type=QueryType.SEMANTIC,
            semantic_configuration_name=_SEMANTIC_CONFIG_NAME,
            top=top,
        )
        hits = [hit async for hit in results]
    except Exception:
        # Semantic ranking isn't available on every service tier (e.g. Free) —
        # fall back to plain BM25 full-text rather than failing the request.
        logger.warning("Semantic search unavailable, falling back to full-text search", exc_info=True)
        results = await client.search(search_text=query, filter=filter_expr, top=top)
        hits = [hit async for hit in results]

    return [
        SearchHit(
            source_type=hit["source_type"],
            source_id=hit["source_id"],
            title=hit["title"],
            content=hit["content"],
            page_number=hit.get("page_number"),
            score=hit.get("@search.rerankerScore") or hit.get("@search.score") or 0.0,
        )
        for hit in hits
    ]
