"""
AI Firebase Connector for the Promptly application.
This module connects the AI service with Firebase for asynchronous task processing.
"""

import os
import sys
import json
import logging
from typing import Dict, Any, List, Optional

# Import the Firebase integration
from server.services.firebase_integration import (
    add_message_task,
    add_checklist_task,
    get_task_status
)

# Import the AI service from AlfredServer
sys.path.append(os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), 'AlfredServer'))
from app.services.ai_service import AIService

# Set up logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

class AIFirebaseConnector:
    """
    Connector class that integrates the AI service with Firebase.
    This class provides methods to process user messages and generate responses
    using the AI service, while offloading heavy processing to Firebase tasks.
    """
    
    def __init__(self):
        """Initialize the connector with the AI service."""
        self.ai_service = AIService()
    
    async def process_message(self, 
                             user_id: str, 
                             chat_id: str, 
                             message_id: str,
                             message_content: str,
                             message_history: List[Dict[str, Any]],
                             user_full_name: Optional[str] = None) -> Dict[str, Any]:
        """
        Process a user message and create appropriate Firebase tasks.
        
        Args:
            user_id: The ID of the user
            chat_id: The ID of the chat
            message_id: The ID of the user's message
            message_content: The content of the user's message
            message_history: The history of messages in the chat
            user_full_name: The full name of the user (optional)
            
        Returns:
            A dictionary containing task IDs and classification results
        """
        try:
            # Classify the query to determine if it's simple or complex
            query_type = await self.ai_service.classify_query(message_content)
            
            # Determine if we should generate a checklist
            should_generate_checklist = await self.ai_service.should_generate_checklist(
                message_content, 
                message_history
            )
            
            # Create message task
            message_task_id = add_message_task(
                user_id=user_id,
                chat_id=chat_id,
                message_id=message_id,
                message_content=message_content,
                message_history=message_history,
                user_full_name=user_full_name
            )
            
            # Create checklist task if needed
            checklist_task_id = None
            if should_generate_checklist:
                checklist_task_id = add_checklist_task(
                    user_id=user_id,
                    chat_id=chat_id,
                    message_id=message_id,
                    message_content=message_content,
                    message_history=message_history
                )
            
            return {
                'message_task_id': message_task_id,
                'checklist_task_id': checklist_task_id,
                'query_type': query_type,
                'should_generate_checklist': should_generate_checklist
            }
            
        except Exception as e:
            logger.error(f"Error processing message: {e}")
            raise
    
    def get_message_task_status(self, task_id: str) -> Optional[Dict[str, Any]]:
        """
        Get the status of a message task.
        
        Args:
            task_id: The ID of the message task
            
        Returns:
            The task data, or None if the task doesn't exist
        """
        return get_task_status('message_tasks', task_id)
    
    def get_checklist_task_status(self, task_id: str) -> Optional[Dict[str, Any]]:
        """
        Get the status of a checklist task.
        
        Args:
            task_id: The ID of the checklist task
            
        Returns:
            The task data, or None if the task doesn't exist
        """
        return get_task_status('checklist_tasks', task_id)

# Create a singleton instance
_connector = None

def get_connector() -> AIFirebaseConnector:
    """
    Get the AIFirebaseConnector instance.
    
    Returns:
        AIFirebaseConnector: The connector instance
    """
    global _connector
    if _connector is None:
        _connector = AIFirebaseConnector()
    return _connector 