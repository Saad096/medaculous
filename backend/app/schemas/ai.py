import uuid
from datetime import datetime

from pydantic import BaseModel, Field

from app.models.conversation import ChatMode, MessageRole


class ChatRequest(BaseModel):
    message: str = Field(min_length=1, max_length=8000)
    mode: ChatMode = ChatMode.AUTO
    conversation_id: uuid.UUID | None = None


class ConversationUpdate(BaseModel):
    """Partial update — currently just renaming the title from the history
    panel (feature request: 'rename the title etc')."""

    title: str = Field(min_length=1, max_length=80)


class MessageOut(BaseModel):
    id: uuid.UUID
    role: MessageRole
    content: str
    created_at: datetime

    model_config = {"from_attributes": True}


class ConversationSummary(BaseModel):
    id: uuid.UUID
    mode: ChatMode
    title: str
    is_saved: bool
    created_at: datetime
    updated_at: datetime

    model_config = {"from_attributes": True}


class ConversationDetail(ConversationSummary):
    messages: list[MessageOut]
