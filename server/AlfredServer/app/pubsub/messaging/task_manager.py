"""
Task manager for creating and publishing tasks to the unified Pub/Sub topic.
This provides a high-level interface for creating different types of tasks.
"""

import json
import uuid
import logging
from typing import Dict, Any, List, Optional

from app.pubsub.messaging.publisher import TaskPublisher

logger = logging.getLogger(__name__)

class PubSubTaskManager:
    """
    Manages task creation and publishing for Pub/Sub.
    Provides methods for creating different types of tasks and publishing them to the unified topic.
    """
    
    def __init__(self):
        """Initialize the task manager."""
        self.publisher = TaskPublisher()
    
    def create_message_task(self, 
                            user_id: str, 
                            message_content: str, 
                            message_history: Optional[List[Dict[str, Any]]] = None,
                            user_full_name: Optional[str] = None,
                            client_time: Optional[str] = None) -> str:
        """
        Create and publish a message task.
        
        Args:
            user_id: The ID of the user
            message_content: The content of the user's message
            message_history: Previous message history for context (optional)
            user_full_name: The user's full name for personalization (optional)
            client_time: The current time on the client device (optional)
            
        Returns:
            The request ID (useful for correlation)
        """
        # Create task data
        task_data = {
            "task_type": "message",
            "request_id": str(uuid.uuid4()),
            "user_id": user_id,
            "message_content": message_content,
        }
        
        # Add optional fields if provided
        if message_history:
            task_data["message_history"] = message_history
        if user_full_name:
            task_data["user_full_name"] = user_full_name
        if client_time:
            task_data["client_time"] = client_time
        
        # Publish to the unified topic
        return self.publisher.publish_to_unified_topic(task_data)
    
    def create_checklist_task(self,
                              user_id: str,
                              message_content: str,
                              message_history: Optional[List[Dict[str, Any]]] = None,
                              client_time: Optional[str] = None,
                              outline_data: Optional[Dict[str, Any]] = None) -> str:
        """
        Create and publish a checklist task.
        
        Args:
            user_id: The ID of the user
            message_content: The content of the user's message
            message_history: Previous message history for context (optional)
            client_time: The current time on the client device (optional)
            outline_data: Outline data for generating a structured checklist (optional)
            
        Returns:
            The request ID (useful for correlation)
        """
        # Create task data
        task_data = {
            "task_type": "checklist",
            "request_id": str(uuid.uuid4()),
            "user_id": user_id,
            "message_content": message_content
        }
        
        # Add optional fields if provided
        if message_history:
            task_data["message_history"] = message_history
        if client_time:
            task_data["client_time"] = client_time
        if outline_data:
            task_data["outline_data"] = outline_data
        
        # Publish to the unified topic
        return self.publisher.publish_to_unified_topic(task_data)
    
    def create_checkin_task(self,
                            user_id: str,
                            checklist_data: Dict[str, Any],
                            user_full_name: Optional[str] = None,
                            client_time: Optional[str] = None,
                            alfred_personality: Optional[str] = None,
                            user_objectives: Optional[str] = None) -> str:
        """
        Create and publish a check-in task.
        
        Args:
            user_id: The ID of the user
            checklist_data: The checklist data to analyze
            user_full_name: The user's full name (optional)
            client_time: The current time on the client device (optional)
            alfred_personality: The personality setting for Alfred (optional)
            user_objectives: The user's objectives (optional)
            
        Returns:
            The request ID (useful for correlation)
        """
        # Create task data
        task_data = {
            "task_type": "checkin",
            "request_id": str(uuid.uuid4()),
            "user_id": user_id,
            "checklist_data": checklist_data
        }
        
        # Add optional fields if provided
        if user_full_name:
            task_data["user_full_name"] = user_full_name
        if client_time:
            task_data["client_time"] = client_time
        if alfred_personality:
            task_data["alfred_personality"] = alfred_personality
        if user_objectives:
            task_data["user_objectives"] = user_objectives
        
        # Publish to the unified topic
        return self.publisher.publish_to_unified_topic(task_data) 