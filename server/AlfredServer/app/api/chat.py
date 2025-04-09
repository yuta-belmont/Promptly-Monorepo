from typing import Optional, List, Dict, Any
from fastapi import APIRouter, Depends, HTTPException, status, Response
from pydantic import BaseModel, Field
import json

from app.schemas.chat import OptimizedChatResponse, MessageResponse
from app.api import deps
from app.models.user import User
from app.services.ai_service import AIService
from app.services.firebase_service import FirebaseService

router = APIRouter(prefix="/chat", tags=["chat"])

# Initialize services
firebase_service = FirebaseService()
ai_service = AIService()

class ChecklistSubItem(BaseModel):
    title: str

class ChecklistItem(BaseModel):
    title: str
    notification: Optional[str] = None
    subitems: Optional[List[ChecklistSubItem]] = []

class ChecklistDate(BaseModel):
    notes: Optional[str] = None
    items: List[ChecklistItem]

class ChecklistGroup(BaseModel):
    name: Optional[str] = None
    dates: Dict[str, ChecklistDate]

class ChecklistData(BaseModel):
    checklist_data: Dict[str, ChecklistGroup]

# Schema with context support for stateless messages
class MessageWithContextCreate(BaseModel):
    message: str
    context_messages: Optional[List[dict]] = Field(default_factory=list)
    current_time: Optional[str] = None

class SubItem(BaseModel):
    title: str
    isCompleted: bool

class ChecklistItem(BaseModel):
    title: str
    isCompleted: bool
    group: str
    notification: Optional[str] = None
    subitems: Optional[List[SubItem]] = []

class Checklist(BaseModel):
    date: str
    items: List[ChecklistItem]

class CheckinRequest(BaseModel):
    checklist: Checklist
    current_time: Optional[str] = None
    alfred_personality: Optional[str] = None
    user_objectives: Optional[str] = None

# Stateless message endpoint that doesn't use the chat model
@router.post("/messages", response_model=OptimizedChatResponse)
async def send_stateless_message(
    *,
    current_user: User = Depends(deps.get_current_user),
    request_data: MessageWithContextCreate,
    response: Response
):
    """
    Send a message without requiring a chat ID.
    
    This is a simplified, stateless version that doesn't store messages in the database.
    It only creates a Firebase task and returns a task ID for the client to listen to.
    All context is provided by the client.
    
    Args:
        request_data: Contains the message content and optional context messages
        
    Returns:
        An optimized response with a task ID
    """
    try:
        # Extract data from request
        message_content = request_data.message
        context_messages = request_data.context_messages or []
        client_time = request_data.current_time
        
        # Set the content type header for the optimized format
        response.headers["Content-Type"] = "application/vnd.promptly.optimized+json"
        
        # Add task directly to message processing queue
        task_data = {
            "user_id": str(current_user.id),
            "message_content": message_content,
            "message_history": context_messages,
            "user_full_name": current_user.full_name
        }
        
        # Include client time if provided
        if client_time:
            task_data["client_time"] = client_time
            
        # Create the task in Firebase
        task_id = firebase_service.add_message_task(**task_data)
        
        # Create the optimized response with pending status and task_id
        optimized_response = OptimizedChatResponse(
            response=MessageResponse(
                id=task_id,  # Use the task_id as the message id
                content=json.dumps({
                    "status": "pending"
                })
            ),
            metadata={
                "status": "pending",
                "message_id": task_id
            }
        )
        
        print(f"Created stateless message task: {task_id}")
        return optimized_response
        
    except Exception as e:
        print(f"DEBUG: ERROR in stateless message processing: {str(e)}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Failed to process message: {str(e)}",
        )

@router.post("/checkin", response_model=OptimizedChatResponse)
async def send_checkin(
    *,
    current_user: User = Depends(deps.get_current_user),
    request_data: CheckinRequest,
    response: Response
):
    """
    Process a checkin request containing checklist data.
    
    This endpoint creates a Firebase task for processing checklist data
    and returns a task ID for the client to listen to.
    """
    try:
        # Set the content type header for the optimized format
        response.headers["Content-Type"] = "application/vnd.promptly.optimized+json"
        
        # Create the checkin task using the dedicated method
        task_id = firebase_service.add_checkin_task(
            user_id=str(current_user.id),
            user_full_name=current_user.full_name,
            checklist_data=request_data.checklist.dict(),
            client_time=request_data.current_time,
            alfred_personality=request_data.alfred_personality,
            user_objectives=request_data.user_objectives
        )
        
        # Create the optimized response with pending status and task_id
        optimized_response = OptimizedChatResponse(
            response=MessageResponse(
                id=task_id,  # Use the task_id as the message id
                content=json.dumps({
                    "status": "pending"
                })
            ),
            metadata={
                "status": "pending",
                "message_id": task_id,
                "task_type": "checkin_task"
            }
        )
        
        print(f"Created checkin task: {task_id}")
        return optimized_response
        
    except Exception as e:
        print(f"DEBUG: ERROR in checkin processing: {str(e)}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Failed to process checkin: {str(e)}",
        ) 