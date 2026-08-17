"""
Single entry point for every Anthropic API call in the backend.

Model choice, retries, and prompt templates all live here so they aren't
scattered across feature routers. Model IDs are read from settings (confirm
current lineup/IDs against https://docs.claude.com before changing defaults —
see backend/.env.example).

Tiering follows the master spec:
- HAIKU  — cheap/fast: quick classification, short replies, simple routing
- SONNET — workhorse: default for most in-app assistant/chat calls (Medaculous AI,
           symptom checker, drug recommendations)
- OPUS   — complex/high-stakes reasoning where accuracy justifies the extra cost
"""

import json
import re
from collections.abc import AsyncIterator
from enum import Enum
from functools import lru_cache

from anthropic import AsyncAnthropic

from app.core.config import settings


class LLMJsonError(Exception):
    """Raised when the model's response isn't valid JSON after a retry."""


class ModelTier(str, Enum):
    HAIKU = "haiku"
    SONNET = "sonnet"
    OPUS = "opus"


_TIER_TO_MODEL = {
    ModelTier.HAIKU: settings.ANTHROPIC_MODEL_HAIKU,
    ModelTier.SONNET: settings.ANTHROPIC_MODEL_SONNET,
    ModelTier.OPUS: settings.ANTHROPIC_MODEL_OPUS,
}


@lru_cache
def get_client() -> AsyncAnthropic:
    # max_retries covers 408/409/429/5xx with exponential backoff out of the box.
    return AsyncAnthropic(api_key=settings.ANTHROPIC_API_KEY, max_retries=3)


async def generate_text(
    *,
    system: str,
    user_message: str,
    tier: ModelTier = ModelTier.SONNET,
    max_tokens: int = 2048,
) -> str:
    """One-shot, non-streaming completion. Use for symptom checker / drug recommendation calls."""
    text, _ = await _generate_text_with_stop_reason(
        system=system, user_message=user_message, tier=tier, max_tokens=max_tokens
    )
    return text


async def _generate_text_with_stop_reason(
    *,
    system: str,
    user_message: str,
    tier: ModelTier = ModelTier.SONNET,
    max_tokens: int = 2048,
) -> tuple[str, str]:
    client = get_client()
    response = await client.messages.create(
        model=_TIER_TO_MODEL[tier],
        max_tokens=max_tokens,
        system=system,
        messages=[{"role": "user", "content": user_message}],
    )
    text = "".join(block.text for block in response.content if block.type == "text")
    return text, response.stop_reason


_JSON_FENCE = re.compile(r"^```(?:json)?\s*|\s*```$", re.MULTILINE)


def _parse_json_response(raw: str) -> dict:
    text = _JSON_FENCE.sub("", raw.strip()).strip()
    # Trim any stray prose around the object (e.g. "Here is the JSON:").
    if not text.startswith("{"):
        start, end = text.find("{"), text.rfind("}")
        if start != -1 and end > start:
            text = text[start : end + 1]
    try:
        return json.loads(text)
    except json.JSONDecodeError:
        # Models regularly emit literal newlines inside long string values
        # (multi-line dosing, newline-separated brand names). strict=False
        # accepts those control characters instead of failing the request.
        return json.loads(text, strict=False)


async def generate_json(
    *,
    system: str,
    user_message: str,
    tier: ModelTier = ModelTier.SONNET,
    max_tokens: int = 4096,
) -> dict:
    """One-shot completion constrained to a single JSON object.

    Claude has no Gemini-style responseSchema, so the schema is described in
    the prompt and enforced by asking for JSON-only output. The retry adapts
    to *why* the first attempt failed, found live in production (2026-08-17
    — the same broad multi-symptom pharmacy query 502'd intermittently even
    after bumping its base max_tokens):
    - stop_reason == "max_tokens" means the response was genuinely cut off
      mid-object — retrying with the same budget and a "please be careful"
      nudge just truncates at the exact same point again. Retry with a much
      larger budget instead.
    - Any other parse failure (stray prose, code fences) is a formatting
      issue the nudge actually addresses, so that retry path is unchanged.
    LLMJsonError bubbles up to a 502 per master spec's "transparent UI
    states" — never silently return a wrong shape.
    """
    json_system = f"{system}\n\nRespond with ONLY a single valid JSON object. No prose, no markdown code fences."
    current_max_tokens = max_tokens
    raw = ""
    for attempt in range(2):
        raw, stop_reason = await _generate_text_with_stop_reason(
            system=json_system, user_message=user_message, tier=tier, max_tokens=current_max_tokens
        )
        try:
            return _parse_json_response(raw)
        except (json.JSONDecodeError, ValueError):
            if attempt == 0:
                if stop_reason == "max_tokens":
                    current_max_tokens = min(current_max_tokens * 2, 64000)
                else:
                    json_system += "\n\nYour previous response was not valid JSON. Return ONLY the JSON object, nothing else."
                continue
    raise LLMJsonError(f"Model did not return valid JSON after retry: {raw[:500]!r}")


async def stream_chat(
    *,
    system: str,
    messages: list[dict[str, str]],
    tier: ModelTier = ModelTier.SONNET,
    max_tokens: int = 4096,
) -> AsyncIterator[str]:
    """Streaming multi-turn chat — backs the Medaculous AI assistant (Ward/ER/Exam modes)."""
    client = get_client()
    async with client.messages.stream(
        model=_TIER_TO_MODEL[tier],
        max_tokens=max_tokens,
        system=system,
        messages=messages,
    ) as stream:
        async for text in stream.text_stream:
            yield text
