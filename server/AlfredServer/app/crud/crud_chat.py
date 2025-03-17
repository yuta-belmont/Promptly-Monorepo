from typing import List, Optional, Dict, Any, Union

from sqlalchemy.orm import Session
from sqlalchemy import desc

from app.crud.base import CRUDBase
from app.models.chat import Chat, ChatMessage
from app.schemas.chat import ChatCreate, ChatUpdate, ChatMessageCreate, ChatMessageUpdate


class CRUDChat(CRUDBase[Chat, ChatCreate, ChatUpdate]):
    def get_by_user_id(
        self, db: Session, *, user_id: str, skip: int = 0, limit: int = 100
    ) -> List[Chat]:
        return (
            db.query(self.model)
            .filter(Chat.user_id == user_id)
            .filter(Chat.is_active == True)
            .order_by(desc(Chat.updated_at))
            .offset(skip)
            .limit(limit)
            .all()
        )
    
    def get_with_messages(self, db: Session, *, id: str) -> Optional[Chat]:
        return (
            db.query(self.model)
            .filter(Chat.id == id)
            .first()
        )


class CRUDChatMessage(CRUDBase[ChatMessage, ChatMessageCreate, ChatMessageUpdate]):
    def get_by_chat_id(
        self, db: Session, *, chat_id: str, skip: int = 0, limit: int = 100
    ) -> List[ChatMessage]:
        return (
            db.query(self.model)
            .filter(ChatMessage.chat_id == chat_id)
            .order_by(ChatMessage.sequence)
            .offset(skip)
            .limit(limit)
            .all()
        )
    
    def get_last_message_sequence(self, db: Session, *, chat_id: str) -> int:
        last_message = (
            db.query(self.model)
            .filter(ChatMessage.chat_id == chat_id)
            .order_by(desc(ChatMessage.sequence))
            .first()
        )
        if last_message:
            return last_message.sequence
        return 0


chat = CRUDChat(Chat)
chat_message = CRUDChatMessage(ChatMessage) 