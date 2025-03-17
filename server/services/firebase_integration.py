"""
Firebase integration for the Promptly application.
This module provides functions to interact with Firebase Firestore for asynchronous task processing.
"""

import os
import json
from typing import Dict, Any, List, Optional
from datetime import datetime
import logging

# Import the Firebase service from AlfredServer
import sys
sys.path.append(os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), 'AlfredServer'))
from app.services.firebase_service import FirebaseService

# Set up logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

def get_firebase_service() -> FirebaseService:
    """
    Get the Firebase service instance.
    
    Returns:
        FirebaseService: The Firebase service instance
    """
    return FirebaseService()

def add_message_task(
    user_id: str, 
    chat_id: str, 
    message_id: str,
    message_content: str,
    message_history: List[Dict[str, Any]],
    user_full_name: Optional[str] = None
) -> str:
    """
    Add a message generation task to Firestore.
    
    Args:
        user_id: The ID of the user
        chat_id: The ID of the chat
        message_id: The ID of the user's message
        message_content: The content of the user's message
        message_history: The history of messages in the chat
        user_full_name: The full name of the user (optional)
        
    Returns:
        The ID of the created task
    """
    firebase_service = get_firebase_service()
    return firebase_service.add_message_task(
        user_id=user_id,
        chat_id=chat_id,
        message_id=message_id,
        message_content=message_content,
        message_history=message_history,
        user_full_name=user_full_name
    )

def add_checklist_task(
    user_id: str,
    chat_id: str,
    message_id: str,
    message_content: str,
    message_history: List[Dict[str, Any]]
) -> str:
    """
    Add a checklist generation task to Firestore.
    
    Args:
        user_id: The ID of the user
        chat_id: The ID of the chat
        message_id: The ID of the message
        message_content: The content of the user's message
        message_history: The history of messages in the chat
        
    Returns:
        The ID of the created task
    """
    firebase_service = get_firebase_service()
    return firebase_service.add_checklist_task(
        user_id=user_id,
        chat_id=chat_id,
        message_id=message_id,
        message_content=message_content,
        message_history=message_history
    )

def get_task_status(collection: str, task_id: str) -> Optional[Dict[str, Any]]:
    """
    Get the status of a task.
    
    Args:
        collection: The collection name ('message_tasks' or 'checklist_tasks')
        task_id: The ID of the task
        
    Returns:
        The task data, or None if the task doesn't exist
    """
    firebase_service = get_firebase_service()
    try:
        task_doc = firebase_service.db.collection(collection).document(task_id).get()
        if task_doc.exists:
            task_data = task_doc.to_dict()
            task_data['id'] = task_doc.id
            return task_data
        return None
    except Exception as e:
        logger.error(f"Error getting task status: {e}")
        return None

def get_message_by_id(user_id: str, chat_id: str, message_id: str) -> Optional[Dict[str, Any]]:
    """
    Get a message by ID.
    
    Args:
        user_id: The ID of the user
        chat_id: The ID of the chat
        message_id: The ID of the message
        
    Returns:
        The message data, or None if the message doesn't exist
    """
    firebase_service = get_firebase_service()
    try:
        message_doc = firebase_service.db.collection('users').document(user_id) \
            .collection('chats').document(chat_id) \
            .collection('messages').document(message_id).get()
        
        if message_doc.exists:
            message_data = message_doc.to_dict()
            message_data['id'] = message_doc.id
            return message_data
        return None
    except Exception as e:
        logger.error(f"Error getting message: {e}")
        return None 