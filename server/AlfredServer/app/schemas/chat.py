from typing import Optional, List, Any, Dict
from datetime import datetime
from pydantic import BaseModel


# ChatMessage schemas
class ChatMessageBase(BaseModel):
    role: str
    content: str


class ChatMessageCreate(ChatMessageBase):
    chat_id: str
    sequence: int


class ChatMessageUpdate(BaseModel):
    role: Optional[str] = None
    content: Optional[str] = None


class ChatMessageInDBBase(ChatMessageBase):
    id: str
    chat_id: str
    created_at: datetime
    sequence: int

    class Config:
        from_attributes = True


class ChatMessage(ChatMessageInDBBase):
    pass


# New optimized response schemas for mobile clients
class MessageResponse(BaseModel):
    id: str
    content: str


class OptimizedChatResponse(BaseModel):
    """
    Optimized response format for mobile clients.
    Only includes the assistant's message and optional metadata.
    Reduces payload size by 70-80% compared to the full chat response.
    """
    response: MessageResponse
    metadata: Optional[Dict[str, Any]] = None


# Chat schemas
class ChatBase(BaseModel):
    title: Optional[str] = "New Chat"
    is_active: Optional[bool] = True


class ChatCreate(ChatBase):
    user_id: str


class ChatUpdate(BaseModel):
    title: Optional[str] = None
    is_active: Optional[bool] = None


class ChatInDBBase(ChatBase):
    id: str
    user_id: str
    created_at: datetime
    updated_at: Optional[datetime] = None

    class Config:
        from_attributes = True


class Chat(ChatInDBBase):
    pass


class ChatWithMessages(Chat):
    messages: List[ChatMessage] = [] 