from typing import List, Any
from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session
from pydantic import BaseModel
import json

from app import crud, schemas
from app.schemas.chat import ChatBase, ChatCreate
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


@router.post("/{chat_id}/messages", response_model=schemas.ChatWithMessages)
async def send_message(
    *,
    db: Session = Depends(deps.get_db),
    current_user: User = Depends(deps.get_current_user),
    chat_id: str,
    message_in: SimpleMessageCreate,
):
    """
    Send a message to the chat.
    
    This endpoint handles both user messages and AI responses.
    For user messages, it will:
    1. Store the user message in the database
    2. Generate an AI response
    3. Store the AI response in the database
    4. Return the updated chat with all messages
    
    For AI responses, it will simply store the message in the database.
    """
    print(f"[API] Received message from user {current_user.id} for chat {chat_id}: {message_in.content[:50]}...")
    
    try:
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
        print(f"[API] Created user message {user_message_db.id} in PostgreSQL with sequence {next_sequence}")
        
        # Get all messages for this chat to provide context
        all_messages = crud.chat_message.get_by_chat_id(db, chat_id=chat_id)
        
        # Format messages for the AI service
        ai_messages = []
        for msg in all_messages:
            ai_messages.append({
                "role": msg.role,
                "content": msg.content
            })
        
        # Initialize task_info dictionary
        task_info = {}
        
        # Generate AI response immediately for all queries (no more complex query handling)
        print(f"[API] Processing query immediately")
        # Get the next sequence number for the AI response
        next_sequence = crud.chat_message.get_last_message_sequence(db, chat_id=chat_id) + 1
        
        # Generate AI response
        ai_response = await ai_service.generate_response(
            message=message_in.content,
            user_id=str(current_user.id),
            message_history=ai_messages,
            user_full_name=current_user.full_name
        )
        
        # Check if we should generate a checklist
        needs_checklist = await ai_service.should_generate_checklist(
            message=message_in.content,
            message_history=ai_messages
        )
        print(f"[API] Needs checklist: {needs_checklist}")
        
        # If this is a checklist request, create a Firestore task for that
        if needs_checklist:
            # Log the message history being sent to Firebase
            print(f"[API] Sending the following message history to Firebase:")
            for i, msg in enumerate(ai_messages):
                print(f"[API] Message {i}: role={msg['role']}, content={msg['content'][:50]}...")
            
            checklist_task_id = firebase_service.add_checklist_task(
                user_id=str(current_user.id),
                chat_id=chat_id,
                message_id=user_message_db.id,  # Use the user message ID
                message_content=message_in.content,
                message_history=ai_messages
            )
            
            # Store the checklist task ID in the task_info dictionary
            task_info["checklist_task_id"] = checklist_task_id
            print(f"[API] Created checklist task with ID: {checklist_task_id}")
            
            # Create a structured response with the checklist task ID
            structured_response = json.dumps({
                "message": ai_response,
                "checklist_task_id": checklist_task_id
            })
            print(f"[API] Structured response: {structured_response[:100]}...")
            
            # Create AI response message with the structured content
            ai_message = schemas.ChatMessageCreate(
                chat_id=chat_id,
                role="assistant",
                content=structured_response,
                sequence=next_sequence
            )
        else:
            # Create AI response message with the raw content
            ai_message = schemas.ChatMessageCreate(
                chat_id=chat_id,
                role="assistant",
                content=ai_response,
                sequence=next_sequence
            )
        
        # Create the message in the database
        ai_message_db = crud.chat_message.create(db, obj_in=ai_message)
        print(f"[API] Created AI response message {ai_message_db.id} in PostgreSQL with sequence {next_sequence}")
        
        try:
            # Update chat's updated_at timestamp and title
            crud.chat.update(db, db_obj=chat, obj_in={"title": message_in.content[:50]})
            
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