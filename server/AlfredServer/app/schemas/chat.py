from typing import Optional, List, Any, Dict
from pydantic import BaseModel


# Schemas for the stateless API
class MessageResponse(BaseModel):
    id: str
    content: str


class OptimizedChatResponse(BaseModel):
    """
    Optimized response format for mobile clients.
    Only includes the message ID and optional metadata.
    Used by the stateless API.
    
    The metadata field can contain:
    - status: The status of the task ('pending', 'processing', 'completed', 'failed')
    - message_id: ID of a message task to listen for
    - checklist_id: ID of a checklist task to listen for
    """
    response: MessageResponse
    metadata: Optional[Dict[str, Any]] = None 