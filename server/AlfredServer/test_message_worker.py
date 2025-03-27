#!/usr/bin/env python3
"""
Test script for the message worker.
This script tests the message worker by adding a test message task to Firestore
and verifying that the worker processes it correctly.
"""

import os
import sys
import json
import asyncio
import logging
import uuid
from datetime import datetime

# Add the project root to the path so we can import app modules
sys.path.append(os.path.dirname(os.path.abspath(__file__)))

# Import the set_env module to set environment variables
import set_env

from app.services.firebase_service import FirebaseService
from app.workers.message_worker import MessageWorker

# Set up logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

async def add_test_task():
    """Add a test message task to Firestore."""
    firebase_service = FirebaseService()
    
    # Generate unique IDs for testing
    user_id = str(uuid.uuid4())
    chat_id = str(uuid.uuid4())
    message_id = str(uuid.uuid4())
    
    # Create a test message history
    message_history = [
        {
            "role": "user",
            "content": "Hello, how are you?",
            "timestamp": datetime.now().isoformat()
        },
        {
            "role": "assistant",
            "content": "I'm doing well, thank you for asking! How can I help you today?",
            "timestamp": datetime.now().isoformat()
        }
    ]
    
    # Add a test task
    test_message = "Can you help me plan my day tomorrow? I need to work on my thesis, go grocery shopping, and meet with my advisor."
    
    task_id = firebase_service.add_message_task(
        user_id=user_id,
        chat_id=chat_id,
        message_id=message_id,
        message_content=test_message,
        message_history=message_history,
        user_full_name="Test User"
    )
    
    logger.info(f"Added test message task with ID: {task_id}")
    logger.info(f"Test data: user_id={user_id}, chat_id={chat_id}, message_id={message_id}")
    
    return task_id

async def monitor_task(task_id):
    """Monitor a task and print updates when its status changes."""
    firebase_service = FirebaseService()
    
    logger.info(f"Monitoring task {task_id}...")
    last_status = None
    
    while True:
        # Get the task status
        task_data = firebase_service.get_task_status('message_tasks', task_id)
        
        if not task_data:
            logger.error(f"Task {task_id} not found")
            return
        
        current_status = task_data.get('status')
        
        # Only log if the status has changed
        if current_status != last_status:
            logger.info(f"Task status: {current_status}")
            last_status = current_status
            
            # If the task is completed or failed, print additional details
            if current_status == 'completed':
                logger.info(f"Completed task data: {json.dumps({k: v for k, v in task_data.items() if k not in ['message_history']}, indent=2)}")
                
                # Check if this generated a checklist task
                if task_data.get('needs_checklist', False) and not task_data.get('needs_more_info', False):
                    checklist_task_id = task_data.get('checklist_task_id')
                    logger.info(f"Generated checklist task with ID: {checklist_task_id}")
                
                return
            elif current_status == 'failed':
                logger.info(f"Failed task error: {task_data.get('error')}")
                return
        
        # Wait before checking again
        await asyncio.sleep(1)

async def run_worker_briefly():
    """Run the message worker for a short time to process the test task."""
    logger.info("Starting message worker...")
    worker = MessageWorker()
    
    # Process tasks for a limited time
    # This is just for testing - in production, the worker would run continuously
    await worker.process_tasks(max_runtime=30)
    
    logger.info("Worker finished")

async def main():
    """Main test function."""
    try:
        # Add a test task
        task_id = await add_test_task()
        
        # Start monitoring the task in the background
        monitor_task_coroutine = asyncio.create_task(monitor_task(task_id))
        
        # Run the worker to process the task
        await run_worker_briefly()
        
        # Wait for the monitoring to complete
        await monitor_task_coroutine
        
        logger.info("Test completed successfully")
        
    except Exception as e:
        logger.error(f"Error during test: {e}")

if __name__ == "__main__":
    asyncio.run(main()) 