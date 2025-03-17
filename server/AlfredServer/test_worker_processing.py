#!/usr/bin/env python3
"""
Test script to check if the worker is processing tasks.
This script adds a task to Firestore and then checks if it's being processed.
"""

import os
import sys
import time
import logging
import json
import uuid

# Add the project root to the path so we can import app modules
sys.path.append(os.path.dirname(os.path.abspath(__file__)))

# Import the set_env module to set environment variables
import set_env

# Set up logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

def test_worker_processing():
    """Test if the worker is processing tasks."""
    try:
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
        
        # Wait for the worker to process the task
        logger.info("Waiting for the worker to process the task...")
        
        # Check the task status every 5 seconds for up to 60 seconds
        max_wait_time = 60  # seconds
        check_interval = 5  # seconds
        elapsed_time = 0
        
        while elapsed_time < max_wait_time:
            # Get the task document
            task_doc = firebase_service.db.collection('checklist_tasks').document(task_id).get()
            
            if task_doc.exists:
                task_data = task_doc.to_dict()
                status = task_data.get('status', 'pending')
                
                logger.info(f"Task status: {status}")
                
                if status == 'completed':
                    logger.info("Task has been processed successfully!")
                    
                    # Check if the checklist was generated
                    checklist_doc = firebase_service.db.collection('users').document(user_id) \
                        .collection('chats').document(chat_id) \
                        .collection('messages').document(message_id).get()
                    
                    if checklist_doc.exists:
                        checklist_data = checklist_doc.to_dict()
                        logger.info(f"Checklist data: {json.dumps(checklist_data, indent=2)}")
                        return True
                    else:
                        logger.warning("Checklist document not found")
                        return False
                
                elif status == 'failed':
                    logger.error("Task processing failed")
                    error = task_data.get('error', 'Unknown error')
                    logger.error(f"Error: {error}")
                    return False
            
            # Wait before checking again
            time.sleep(check_interval)
            elapsed_time += check_interval
        
        logger.warning(f"Timed out after {max_wait_time} seconds. Task may still be processing.")
        return False
        
    except Exception as e:
        logger.error(f"Error testing worker processing: {e}")
        return False

if __name__ == "__main__":
    test_worker_processing() 