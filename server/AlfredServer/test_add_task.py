#!/usr/bin/env python3
"""
Test script to add a task to Firestore.
"""

import os
import sys
import logging
import json
import uuid

# Add the project root to the path so we can import app modules
sys.path.append(os.path.dirname(os.path.abspath(__file__)))

# Set up logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

def add_test_task():
    """Add a test task to Firestore."""
    try:
        # Set environment variables for Firebase
        os.environ["FIREBASE_SERVICE_ACCOUNT"] = os.path.join(
            os.path.dirname(os.path.abspath(__file__)),
            "firebase-credentials",
            "alfred-9fa73-firebase-adminsdk-fbsvc-294854bb8e.json"  # Use the new credentials file
        )
        
        # Extract project ID from the credentials file
        credentials_path = os.environ["FIREBASE_SERVICE_ACCOUNT"]
        if os.path.exists(credentials_path):
            try:
                with open(credentials_path, 'r') as f:
                    creds_data = json.loads(f.read())
                    if 'project_id' in creds_data:
                        os.environ["FIREBASE_PROJECT_ID"] = creds_data['project_id']
                        logger.info(f"Extracted project ID from credentials: {creds_data['project_id']}")
            except Exception as e:
                logger.warning(f"Could not extract project ID from credentials: {e}")
        
        # Import Firebase service
        from app.services.firebase_service import FirebaseService
        
        # Initialize Firebase service
        firebase_service = FirebaseService()
        
        # Create a test user ID and chat ID
        user_id = str(uuid.uuid4())
        chat_id = str(uuid.uuid4())
        message_id = str(uuid.uuid4())
        
        # Add a test checklist task
        task_id = firebase_service.add_checklist_task(
            user_id=user_id,
            chat_id=chat_id,
            message_id=message_id,
            message_content="Create a checklist for my day tomorrow. I need to work on my thesis in the morning, go grocery shopping in the afternoon, and prepare for my presentation in the evening.",
            message_history=[
                {
                    "role": "user",
                    "content": "Hello, how are you?",
                    "timestamp": "2025-03-16T12:00:00Z"
                },
                {
                    "role": "assistant",
                    "content": "I'm doing well, thank you for asking! How can I help you today?",
                    "timestamp": "2025-03-16T12:00:05Z"
                }
            ]
        )
        
        logger.info(f"Added test checklist task with ID: {task_id}")
        logger.info(f"User ID: {user_id}")
        logger.info(f"Chat ID: {chat_id}")
        logger.info(f"Message ID: {message_id}")
        
        return True
        
    except Exception as e:
        logger.error(f"Failed to add test task: {e}")
        return False

if __name__ == "__main__":
    add_test_task() 