#!/usr/bin/env python3
"""
Test script for Firebase integration.
This script tests the integration between the AI service and Firebase.
"""

import os
import sys
import json
import asyncio
import logging
from datetime import datetime

# Add the server directory to the path
sys.path.append(os.path.dirname(os.path.abspath(__file__)))

# Import the Firebase integration
from services.firebase_integration import (
    add_message_task,
    add_checklist_task,
    get_task_status
)

# Set up logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

async def test_message_task():
    """Test creating a message task and checking its status."""
    logger.info("Testing message task creation...")
    
    # Create a test message task
    user_id = "test_user_123"
    chat_id = "test_chat_456"
    message_id = "test_message_789"
    message_content = "Plan my day tomorrow. I need to work on my thesis, go grocery shopping, and meet with my advisor."
    message_history = [
        {"role": "user", "content": "Hello", "timestamp": datetime.now().isoformat()},
        {"role": "assistant", "content": "Hi there! How can I help you today?", "timestamp": datetime.now().isoformat()}
    ]
    user_full_name = "Test User"
    
    # Add the message task
    task_id = add_message_task(
        user_id=user_id,
        chat_id=chat_id,
        message_id=message_id,
        message_content=message_content,
        message_history=message_history,
        user_full_name=user_full_name
    )
    
    logger.info(f"Created message task with ID: {task_id}")
    
    # Wait for a few seconds to allow the worker to process the task
    logger.info("Waiting for worker to process the task...")
    await asyncio.sleep(5)
    
    # Check the task status
    task_status = get_task_status("message_tasks", task_id)
    logger.info(f"Task status: {json.dumps(task_status, indent=2, default=str)}")
    
    return task_id

async def test_checklist_task():
    """Test creating a checklist task and checking its status."""
    logger.info("Testing checklist task creation...")
    
    # Create a test checklist task
    user_id = "test_user_123"
    chat_id = "test_chat_456"
    message_id = "test_message_789"
    message_content = "Plan my day tomorrow. I need to work on my thesis, go grocery shopping, and meet with my advisor."
    message_history = [
        {"role": "user", "content": "Hello", "timestamp": datetime.now().isoformat()},
        {"role": "assistant", "content": "Hi there! How can I help you today?", "timestamp": datetime.now().isoformat()}
    ]
    
    # Add the checklist task
    task_id = add_checklist_task(
        user_id=user_id,
        chat_id=chat_id,
        message_id=message_id,
        message_content=message_content,
        message_history=message_history
    )
    
    logger.info(f"Created checklist task with ID: {task_id}")
    
    # Wait for a few seconds to allow the worker to process the task
    logger.info("Waiting for worker to process the task...")
    await asyncio.sleep(5)
    
    # Check the task status
    task_status = get_task_status("checklist_tasks", task_id)
    logger.info(f"Task status: {json.dumps(task_status, indent=2, default=str)}")
    
    return task_id

async def main():
    """Main entry point for the test script."""
    logger.info("Starting Firebase integration test...")
    
    # Test message task
    message_task_id = await test_message_task()
    
    # Test checklist task
    checklist_task_id = await test_checklist_task()
    
    # Wait for a longer period to allow the workers to complete processing
    logger.info("Waiting for workers to complete processing...")
    await asyncio.sleep(30)
    
    # Check final status of both tasks
    message_task_status = get_task_status("message_tasks", message_task_id)
    logger.info(f"Final message task status: {json.dumps(message_task_status, indent=2, default=str)}")
    
    checklist_task_status = get_task_status("checklist_tasks", checklist_task_id)
    logger.info(f"Final checklist task status: {json.dumps(checklist_task_status, indent=2, default=str)}")
    
    logger.info("Firebase integration test completed.")

if __name__ == "__main__":
    asyncio.run(main()) 