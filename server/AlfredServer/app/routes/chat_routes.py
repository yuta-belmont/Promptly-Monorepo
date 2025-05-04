"""
Chat-related API routes.
"""

from fastapi import APIRouter, HTTPException, Body
from typing import Dict, Any, List, Optional
import logging

# Import the Pub/Sub publisher
from app.pubsub.messaging.publisher import TaskPublisher

# Original Firebase service (keep for transition period)
from app.services.firebase_service import FirebaseService

router = APIRouter()
firebase_service = FirebaseService()
task_publisher = TaskPublisher()  # Initialize the Pub/Sub publisher

logger = logging.getLogger(__name__)

@router.post("/messages/process")
async def process_message(
    data: Dict[str, Any] = Body(...)
) -> Dict[str, Any]:
    """
    Process a user message using the AI service.
    
    Args:
        data: A dictionary containing:
            - user_id: The ID of the user
            - message_content: The content of the user's message
            - message_history: Optional. The history of messages in the chat
            - chat_id: Optional. The ID of the chat
            - message_id: Optional. The ID of the message
            - user_full_name: Optional. The full name of the user
            - client_time: Optional. The current time on the client device
            
    Returns:
        A dictionary containing:
            - task_id: The ID of the created task
            - request_id: The ID of the request for streaming
    """
    try:
        user_id = data.get("user_id")
        message_content = data.get("message_content")
        message_history = data.get("message_history", [])
        chat_id = data.get("chat_id")
        message_id = data.get("message_id")
        user_full_name = data.get("user_full_name")
        client_time = data.get("client_time")
        
        if not user_id or not message_content:
            raise HTTPException(status_code=400, detail="Missing required fields: user_id and message_content")
        
        # OPTION 1: For a transition period, add to both Firestore and Pub/Sub
        # Add the task to Firestore (for backward compatibility)
        task_id = firebase_service.add_message_task(
            user_id=user_id,
            message_content=message_content,
            message_history=message_history,
            user_full_name=user_full_name,
            client_time=client_time,
            chat_id=chat_id,
            message_id=message_id
        )
        
        # Publish the task to Pub/Sub (new system)
        request_id = task_publisher.publish_message_task(
            user_id=user_id,
            message_content=message_content,
            message_history=message_history,
            user_full_name=user_full_name,
            client_time=client_time,
            chat_id=chat_id,
            message_id=message_id
        )
        
        # OPTION 2: For direct cutover, use only Pub/Sub
        # request_id = task_publisher.publish_message_task(
        #     user_id=user_id,
        #     message_content=message_content,
        #     message_history=message_history,
        #     user_full_name=user_full_name,
        #     client_time=client_time,
        #     chat_id=chat_id,
        #     message_id=message_id
        # )
        # task_id = None  # No Firestore task ID
        
        return {
            "task_id": task_id,  # Firestore task ID (for backward compatibility)
            "request_id": request_id,  # Pub/Sub request ID (for streaming)
            "stream_url": f"/api/v1/stream/{request_id}"  # URL for client to connect for streaming
        }
            
    except Exception as e:
        logger.error(f"Error processing message: {e}")
        raise HTTPException(status_code=500, detail=f"Error processing message: {str(e)}")

# ... other endpoints ... 