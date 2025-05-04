"""
Module for publishing task messages to Google Cloud Pub/Sub.
"""

import json
import uuid
import time
import logging
from typing import Dict, Any, Optional
from google.cloud import pubsub_v1

from app.pubsub.config import (
    GCP_PROJECT_ID,
    MESSAGE_TASKS_TOPIC,
    CHECKLIST_TASKS_TOPIC,
    CHECKIN_TASKS_TOPIC
)

logger = logging.getLogger(__name__)

class TaskPublisher:
    """Handles publishing AI tasks to Pub/Sub."""
    
    _instance = None
    
    def __new__(cls):
        """Singleton pattern to ensure only one publisher instance."""
        if cls._instance is None:
            cls._instance = super(TaskPublisher, cls).__new__(cls)
            cls._instance._initialized = False
        return cls._instance
    
    def __init__(self):
        """Initialize the publisher if not already initialized."""
        if self._initialized:
            return
            
        try:
            self.project_id = GCP_PROJECT_ID
            self.publisher = pubsub_v1.PublisherClient()
            
            # Define topic paths for each task type
            self.topics = {
                'message': self.publisher.topic_path(self.project_id, MESSAGE_TASKS_TOPIC),
                'checklist': self.publisher.topic_path(self.project_id, CHECKLIST_TASKS_TOPIC),
                'checkin': self.publisher.topic_path(self.project_id, CHECKIN_TASKS_TOPIC)
            }
            
            self._initialized = True
            logger.info(f"TaskPublisher initialized with project: {self.project_id}")
            
        except Exception as e:
            logger.error(f"Error initializing TaskPublisher: {e}")
            raise
    
    def publish_message_task(self, 
                           user_id: str,
                           message_content: str,
                           message_history: list,
                           user_full_name: Optional[str] = None,
                           client_time: Optional[str] = None,
                           chat_id: Optional[str] = None,
                           message_id: Optional[str] = None) -> str:
        """
        Publish a message task to Pub/Sub.
        
        Args:
            user_id: The ID of the user
            message_content: The content of the user's message
            message_history: The history of messages in the chat
            user_full_name: The full name of the user (optional)
            client_time: The current time on the client device (optional)
            chat_id: The ID of the chat (optional in stateless mode)
            message_id: The ID of the message (optional in stateless mode)
            
        Returns:
            The request ID (useful for correlation)
        """
        request_id = str(uuid.uuid4())
        
        # Create a task payload similar to your existing Firestore structure
        payload = {
            'task_type': 'message',
            'request_id': request_id,
            'user_id': user_id,
            'message_content': message_content,
            'message_history': message_history,
        }
        
        # Add optional fields if they exist
        if user_full_name:
            payload['user_full_name'] = user_full_name
        if client_time:
            payload['client_time'] = client_time
        if chat_id:
            payload['chat_id'] = chat_id
        if message_id:
            payload['message_id'] = message_id
        
        # Add timestamp
        payload['timestamp'] = int(time.time())
        
        try:
            # Encode and publish
            message_data = json.dumps(payload).encode("utf-8")
            future = self.publisher.publish(self.topics['message'], message_data)
            
            # Wait for confirmation (optional)
            pub_message_id = future.result()
            logger.info(f"Published message task {request_id} with Pub/Sub message ID: {pub_message_id}")
            
            return request_id
        except Exception as e:
            logger.error(f"Error publishing message task: {e}")
            raise
    
    def publish_checklist_task(self,
                             user_id: str,
                             chat_id: str,
                             message_id: str,
                             message_content: str,
                             message_history: list,
                             client_time: Optional[str] = None,
                             outline_data: Optional[Dict[str, Any]] = None) -> str:
        """
        Publish a checklist task to Pub/Sub.
        
        Args:
            user_id: The ID of the user
            chat_id: The ID of the chat
            message_id: The ID of the message
            message_content: The content of the user's message
            message_history: The history of messages in the chat
            client_time: The current time on the client device (optional)
            outline_data: The outline data to use for checklist generation (optional)
            
        Returns:
            The request ID (useful for correlation)
        """
        request_id = str(uuid.uuid4())
        
        # Create a task payload 
        payload = {
            'task_type': 'checklist',
            'request_id': request_id,
            'user_id': user_id,
            'chat_id': chat_id,
            'message_id': message_id, 
            'message_content': message_content,
            'message_history': message_history,
        }
        
        # Add optional fields if they exist
        if client_time:
            payload['client_time'] = client_time
        if outline_data:
            payload['outline_data'] = outline_data
            
        # Add timestamp
        payload['timestamp'] = int(time.time())
        
        try:
            # Encode and publish
            message_data = json.dumps(payload).encode("utf-8")
            future = self.publisher.publish(self.topics['checklist'], message_data)
            
            pub_message_id = future.result()
            logger.info(f"Published checklist task {request_id} with Pub/Sub message ID: {pub_message_id}")
            
            return request_id
        except Exception as e:
            logger.error(f"Error publishing checklist task: {e}")
            raise
    
    def publish_checkin_task(self,
                           user_id: str,
                           user_full_name: str,
                           checklist_data: Dict[str, Any],
                           client_time: Optional[str] = None,
                           alfred_personality: Optional[str] = None,
                           user_objectives: Optional[str] = None) -> str:
        """
        Publish a checkin analysis task to Pub/Sub.
        
        Args:
            user_id: The ID of the user
            user_full_name: The full name of the user
            checklist_data: The checklist data to analyze
            client_time: The current time on the client device (optional)
            alfred_personality: The personality setting for Alfred (optional)
            user_objectives: The user's objectives (optional)
            
        Returns:
            The request ID (useful for correlation)
        """
        request_id = str(uuid.uuid4())
        
        # Create a task payload
        payload = {
            'task_type': 'checkin',
            'request_id': request_id,
            'user_id': user_id,
            'user_full_name': user_full_name,
            'checklist_data': checklist_data,
        }
        
        # Add optional fields if they exist
        if client_time:
            payload['client_time'] = client_time
        if alfred_personality:
            payload['alfred_personality'] = alfred_personality
        if user_objectives:
            payload['user_objectives'] = user_objectives
            
        # Add timestamp
        payload['timestamp'] = int(time.time())
        
        try:
            # Encode and publish
            message_data = json.dumps(payload).encode("utf-8")
            future = self.publisher.publish(self.topics['checkin'], message_data)
            
            pub_message_id = future.result()
            logger.info(f"Published checkin task {request_id} with Pub/Sub message ID: {pub_message_id}")
            
            return request_id
        except Exception as e:
            logger.error(f"Error publishing checkin task: {e}")
            raise 