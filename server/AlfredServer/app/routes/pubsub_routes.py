"""
API routes for the Pub/Sub-based messaging system.
These routes handle client requests and utilize the Pub/Sub system for processing.
"""

from fastapi import APIRouter, Request, Response, HTTPException, Depends
from fastapi.responses import JSONResponse
import logging
import json
from typing import Dict, Any, Optional

from app.pubsub.messaging.task_manager import PubSubTaskManager
from app.api.deps import get_current_user
from app.models.user import User

router = APIRouter()
logger = logging.getLogger(__name__)

@router.post("/api/v1/pubsub/message")
async def process_message(request: Request, current_user: User = Depends(get_current_user)):
    """
    Process a message using Pub/Sub.
    
    This endpoint creates a message task and returns a request ID that can be used
    to subscribe to the SSE stream for real-time updates.
    """
    # Extract user ID from the authenticated user
    user_id = current_user.id
    
    # Get request data
    data = await request.json()
    
    # Extract required fields
    message_content = data.get("message")
    if not message_content:
        raise HTTPException(status_code=400, detail="Message content is required")
    
    # Extract optional fields
    message_history = data.get("context_messages", [])
    user_full_name = data.get("user_full_name", current_user.full_name)
    client_time = data.get("current_time")
    
    # Create and publish task
    task_manager = PubSubTaskManager()
    request_id = task_manager.create_message_task(
        user_id=user_id,
        message_content=message_content,
        message_history=message_history,
        user_full_name=user_full_name,
        client_time=client_time
    )
    
    logger.info(f"Created message task {request_id} for user {user_id}")
    
    # Return request ID for SSE subscription
    return {"request_id": request_id}

@router.post("/api/v1/pubsub/checklist")
async def process_checklist(request: Request, current_user: User = Depends(get_current_user)):
    """
    Process a checklist request using Pub/Sub.
    
    This endpoint creates a checklist task and returns a request ID that can be used
    to subscribe to the SSE stream for real-time updates.
    """
    # Extract user ID from the authenticated user
    user_id = current_user.id
    
    # Get request data
    data = await request.json()
    
    # Extract message field or outline data
    message_content = data.get("message")
    outline_data = data.get("outline")
    
    # Check if we have either a message or an outline
    if not message_content and not outline_data:
        raise HTTPException(
            status_code=400, 
            detail="Either message content or outline data is required"
        )
    
    # Extract optional fields
    message_history = data.get("context_messages", [])
    client_time = data.get("current_time")
    
    # Create and publish task
    task_manager = PubSubTaskManager()
    request_id = task_manager.create_checklist_task(
        user_id=user_id,
        message_content=message_content or "",  # Empty string if None
        message_history=message_history,
        client_time=client_time,
        outline_data=outline_data
    )
    
    logger.info(f"Created checklist task {request_id} for user {user_id}")
    
    # Return request ID for SSE subscription
    return {"request_id": request_id}

@router.post("/api/v1/pubsub/checkin")
async def process_checkin(request: Request, current_user: User = Depends(get_current_user)):
    """
    Process a check-in analysis request using Pub/Sub.
    
    This endpoint creates a check-in task and returns a request ID that can be used
    to subscribe to the SSE stream for real-time updates.
    """
    # Extract user ID from the authenticated user
    user_id = current_user.id
    
    # Get request data
    data = await request.json()
    
    # Extract required field
    checklist_data = data.get("checklist_data")
    if not checklist_data:
        raise HTTPException(status_code=400, detail="Checklist data is required")
    
    # Extract optional fields
    user_full_name = data.get("user_full_name", current_user.full_name)
    client_time = data.get("current_time")
    alfred_personality = data.get("alfred_personality")
    user_objectives = data.get("user_objectives")
    
    # Create and publish task
    task_manager = PubSubTaskManager()
    request_id = task_manager.create_checkin_task(
        user_id=user_id,
        checklist_data=checklist_data,
        user_full_name=user_full_name,
        client_time=client_time,
        alfred_personality=alfred_personality,
        user_objectives=user_objectives
    )
    
    logger.info(f"Created check-in task {request_id} for user {user_id}")
    
    # Return request ID for SSE subscription
    return {"request_id": request_id} 