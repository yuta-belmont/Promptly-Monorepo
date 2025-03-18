from typing import List, Any, Union
from fastapi import APIRouter, Depends, HTTPException, status, Header, Response
from sqlalchemy.orm import Session
from pydantic import BaseModel
import json

from app import crud, schemas
from app.schemas.chat import ChatBase, ChatCreate, OptimizedChatResponse, MessageResponse
from app.api import deps
from app.models.user import User
from app.services.ai_service import AIService
from app.services.firebase_service import FirebaseService

router = APIRouter(prefix="/chat", tags=["chat"])

# Initialize services
firebase_service = FirebaseService()
ai_service = AIService()


# Simple message schema for mobile app
class SimpleMessageCreate(BaseModel):
    content: str


@router.get("/", response_model=List[schemas.Chat])
def get_user_chats(
    db: Session = Depends(deps.get_db),
    current_user: User = Depends(deps.get_current_user),
    skip: int = 0,
    limit: int = 100,
):
    """
    Get all chats for the current user.
    """
    chats = crud.chat.get_by_user_id(
        db, user_id=current_user.id, skip=skip, limit=limit
    )
    return chats


@router.post("/", response_model=schemas.Chat)
def create_chat(
    *,
    db: Session = Depends(deps.get_db),
    current_user: User = Depends(deps.get_current_user),
    chat_in: ChatBase,
):
    """
    Create a new chat.
    """
    # Create a ChatCreate object with the user_id
    chat_create = ChatCreate(
        user_id=current_user.id,
        title=chat_in.title,
        is_active=chat_in.is_active
    )
    chat = crud.chat.create(db, obj_in=chat_create)
    return chat


@router.get("/{chat_id}", response_model=schemas.ChatWithMessages)
def get_chat(
    *,
    db: Session = Depends(deps.get_db),
    current_user: User = Depends(deps.get_current_user),
    chat_id: str,
):
    """
    Get a specific chat with all messages.
    """
    chat = crud.chat.get(db, id=chat_id)
    if not chat:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Chat not found",
        )
    if chat.user_id != current_user.id:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Not enough permissions",
        )
    
    # Get all messages for this chat
    messages = crud.chat_message.get_by_chat_id(db, chat_id=chat_id)
    
    # Create a ChatWithMessages object
    chat_with_messages = schemas.ChatWithMessages(
        **chat.__dict__,
        messages=messages
    )
    
    return chat_with_messages


@router.post("/{chat_id}/messages", response_model=Union[OptimizedChatResponse, schemas.ChatWithMessages])
async def send_message(
    *,
    db: Session = Depends(deps.get_db),
    current_user: User = Depends(deps.get_current_user),
    chat_id: str,
    message_in: SimpleMessageCreate,
    accept: str = Header(None),
    response: Response,
):
    """
    Send a message to the chat.
    
    This endpoint supports two response formats:
    1. Standard format: Returns the full chat with all messages
    2. Optimized format: Returns only the assistant's response and metadata (70-80% smaller payload)
    
    The format is determined by the Accept header:
    - application/vnd.promptly.optimized+json: Returns the optimized format
    - Any other value: Returns the standard format
    
    For user messages, the endpoint will:
    1. Store the user message in the database
    2. Generate an AI response
    3. Store the AI response in the database
    4. Return the response in the requested format
    """
    
    try:
        # Check if the client requested the optimized format
        use_optimized_format = accept and "application/vnd.promptly.optimized+json" in accept
        
        # Check if the chat exists and belongs to the user
        chat = crud.chat.get(db, id=chat_id)
        if not chat or str(chat.user_id) != str(current_user.id):
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="Chat not found",
            )
        
        # Get the next sequence number
        next_sequence = crud.chat_message.get_last_message_sequence(db, chat_id=chat_id) + 1
        
        # Create the user message
        user_message = schemas.ChatMessageCreate(
            chat_id=chat_id,
            role="user",
            content=message_in.content,
            sequence=next_sequence
        )
        user_message_db = crud.chat_message.create(db, obj_in=user_message)
        
        # Get all messages for this chat to provide context
        all_messages = crud.chat_message.get_by_chat_id(db, chat_id=chat_id)
        
        # Format messages for the AI service
        ai_messages = []
        for msg in all_messages:
            ai_messages.append({
                "role": msg.role,
                "content": msg.content,
                "timestamp": msg.created_at.isoformat()  # Include timestamp for proper time filtering
            })
        
        # Initialize task_info dictionary
        task_info = {}
        
        # Get the next sequence number for the AI response
        next_sequence = crud.chat_message.get_last_message_sequence(db, chat_id=chat_id) + 1
        
        # -----------------------------------------------------------------
        # Optimized Response Generation
        # -----------------------------------------------------------------
        result = await ai_service.generate_optimized_response(
            message=message_in.content,
            message_history=ai_messages,
            user_full_name=current_user.full_name,
            user_id=str(current_user.id)
        )
        
        # Extract the results from the optimized response
        ai_response = result['response_text']
        needs_checklist = result['needs_checklist']
        needs_more_info = result['needs_more_info']
        query_type = result['query_type']
        
        # Log the decision flow for debugging
        print(f"\n=== API Decision Flow ===")
        print(f"Query Type: {query_type}")
        print(f"Needs Checklist: {needs_checklist}")
        print(f"Needs More Info: {needs_more_info}")
        print("======================\n")
        
        # If this is a checklist request and we have enough information, create a task
        if needs_checklist and not needs_more_info:
            # Create a checklist task
            checklist_task_id = firebase_service.add_checklist_task(
                user_id=str(current_user.id),
                chat_id=chat_id,
                message_id=user_message_db.id,  # Use the user message ID
                message_content=message_in.content,
                message_history=ai_messages
            )
            
            # Store the checklist task ID in the task_info dictionary
            task_info["checklist_task_id"] = checklist_task_id
            
            # Create a structured response with the checklist task ID
            structured_response = json.dumps({
                "message": ai_response,
                "checklist_task_id": checklist_task_id
            })
            
            # Create AI response message with the structured content
            ai_message = schemas.ChatMessageCreate(
                chat_id=chat_id,
                role="assistant",
                content=structured_response,
                sequence=next_sequence
            )
        else:
            # Create AI response message with the raw content
            # This handles both standard responses and inquiry responses
            ai_message = schemas.ChatMessageCreate(
                chat_id=chat_id,
                role="assistant",
                content=ai_response,
                sequence=next_sequence
            )
        
        # Create the message in the database
        ai_message_db = crud.chat_message.create(db, obj_in=ai_message)
        
        try:
            # Update chat's updated_at timestamp and title
            crud.chat.update(db, db_obj=chat, obj_in={"title": message_in.content[:50]})
            
            # If client requested optimized format, return the optimized response
            if use_optimized_format:
                # Set the content type header for the optimized format
                response.headers["Content-Type"] = "application/vnd.promptly.optimized+json"
                
                # Create the optimized response
                # This format reduces payload size by 70-80% by:
                # 1. Not returning the user's message (client already has it)
                # 2. Not returning chat metadata (title, timestamps, etc.)
                # 3. Not returning sequence numbers and other unnecessary fields
                # 4. Only including the absolutely essential data: 
                #    - The assistant's response 
                #    - Optional metadata like checklist_task_id if needed
                optimized_response = OptimizedChatResponse(
                    response=MessageResponse(
                        id=ai_message_db.id,
                        content=ai_response
                    ),
                    metadata=task_info if task_info else None
                )
                
                # Log the optimized response size for debugging
                print(f"Using OPTIMIZED response format (Accept: {accept})")
                
                return optimized_response
            
            # Otherwise, return the standard format
            # Return updated chat with messages
            updated_chat = crud.chat.get(db, id=chat_id)
            updated_messages = crud.chat_message.get_by_chat_id(db, chat_id=chat_id)
            
            # Create the response
            response = schemas.ChatWithMessages(
                **updated_chat.__dict__,
                messages=updated_messages
            )
            
            # Add task_info to the response if it's not empty
            if task_info:
                # Convert response to dict to add task_info
                response_dict = response.dict()
                response_dict["task_info"] = task_info
                return response_dict
            
            return response
        except Exception as e:
            raise
        
    except Exception as e:
        print(f"DEBUG: ERROR in message processing: {str(e)}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Failed to generate AI response: {str(e)}",
        )

@router.get("/{chat_id}/tasks/{task_id}", response_model=dict)
def get_task_status(
    *,
    db: Session = Depends(deps.get_db),
    current_user: User = Depends(deps.get_current_user),
    chat_id: str,
    task_id: str,
    task_type: str = "message"  # Can be "message" or "checklist"
):
    """
    Check the status of a Firebase task.
    This endpoint allows the mobile app to poll for updates on asynchronous tasks.
    """
    # Check if chat exists and belongs to user
    chat = crud.chat.get(db, id=chat_id)
    if not chat:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Chat not found",
        )
    if chat.user_id != current_user.id:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Not enough permissions",
        )
    
    # Determine the collection based on task type
    collection = "message_tasks" if task_type == "message" else "checklist_tasks"
    
    # Get task status from Firebase
    try:
        task_data = firebase_service.db.collection(collection).document(task_id).get()
        
        if not task_data.exists:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail=f"Task {task_id} not found",
            )
        
        task_dict = task_data.to_dict()
        task_dict["id"] = task_id
        
        # If the task is completed, update the message in the database
        if task_dict.get("status") == "completed" and task_type == "message":
            # Get the message ID from the task data
            message_id = task_dict.get("message_id")
            if message_id:
                # Get the message from the database
                message = crud.chat_message.get(db, id=message_id)
                if message and message.chat_id == chat_id:
                    # Update the message with the generated content
                    generated_content = task_dict.get("generated_content")
                    if generated_content:
                        crud.chat_message.update(
                            db, 
                            db_obj=message, 
                            obj_in={"content": generated_content}
                        )
        
        return task_dict
        
    except Exception as e:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Failed to get task status: {str(e)}",
        )

@router.get("/{chat_id}/poll", response_model=schemas.ChatWithMessages)
def poll_for_updates(
    *,
    db: Session = Depends(deps.get_db),
    current_user: User = Depends(deps.get_current_user),
    chat_id: str,
):
    """
    Poll for updates to a chat.
    This endpoint allows the mobile app to check for new messages and updates.
    """
    # Check if chat exists and belongs to user
    chat = crud.chat.get(db, id=chat_id)
    if not chat:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Chat not found",
        )
    if chat.user_id != current_user.id:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Not enough permissions",
        )
    
    # Get all messages for this chat
    messages = crud.chat_message.get_by_chat_id(db, chat_id=chat_id)
    
    # Create a ChatWithMessages object
    chat_with_messages = schemas.ChatWithMessages(
        **chat.__dict__,
        messages=messages
    )
    
    return chat_with_messages 