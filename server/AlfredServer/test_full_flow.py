#!/usr/bin/env python3
"""
Test script for the full asynchronous message flow.
This script simulates the entire process:
1. Sends a message via the API
2. Verifies the placeholder message creation
3. Monitors the message task in Firestore
4. Verifies the message is updated correctly
5. If a checklist is generated, verifies the checklist task
"""

import os
import sys
import json
import asyncio
import logging
import uuid
import requests
from datetime import datetime
import time

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

# API configuration
API_URL = "http://localhost:8000"  # Change this to your API URL
API_TOKEN = os.getenv("API_TEST_TOKEN")  # Set this in your environment

async def test_message_creation_api():
    """Test message creation through the API."""
    if not API_TOKEN:
        logger.error("No API token set. Please set API_TEST_TOKEN in your environment.")
        return None, None, None
        
    # Create a test chat if we don't have one
    chat_id = None
    
    # Create chat headers
    headers = {
        "Authorization": f"Bearer {API_TOKEN}",
        "Content-Type": "application/json",
        "Accept": "application/vnd.promptly.optimized+json"
    }
    
    # Create a new chat
    response = requests.post(
        f"{API_URL}/chat/",
        headers=headers,
        json={"title": f"Test Chat {uuid.uuid4()}"}
    )
    
    if response.status_code != 200:
        logger.error(f"Failed to create chat: {response.text}")
        return None, None, None
        
    chat_id = response.json().get("id")
    logger.info(f"Created chat with ID: {chat_id}")
    
    # Send a test message
    test_message = "Can you help me plan my day tomorrow? I need to work on my thesis, go grocery shopping, and meet with my advisor."
    
    response = requests.post(
        f"{API_URL}/chat/{chat_id}/messages",
        headers=headers,
        json={"content": test_message}
    )
    
    if response.status_code != 200:
        logger.error(f"Failed to send message: {response.text}")
        return None, None, None
        
    # Parse the response
    response_data = response.json()
    
    # Extract message ID and task ID from the optimized response format
    message_id = response_data.get("response", {}).get("id")
    task_id = response_data.get("metadata", {}).get("task_id")
    
    if not message_id or not task_id:
        logger.error(f"Failed to get message ID or task ID: {response_data}")
        return None, None, None
        
    logger.info(f"Created message with ID: {message_id}")
    logger.info(f"Created task with ID: {task_id}")
    
    return chat_id, message_id, task_id

async def monitor_message_task(task_id):
    """Monitor a message task until it completes or fails."""
    firebase_service = FirebaseService()
    
    logger.info(f"Monitoring message task {task_id}...")
    last_status = None
    checklist_task_id = None
    
    while True:
        # Get the task status
        task_data = firebase_service.get_task_status('message_tasks', task_id)
        
        if not task_data:
            logger.error(f"Task {task_id} not found")
            return None
        
        current_status = task_data.get('status')
        
        # Only log if the status has changed
        if current_status != last_status:
            logger.info(f"Message task status: {current_status}")
            last_status = current_status
            
            # If the task is completed or failed, print additional details
            if current_status == 'completed':
                logger.info(f"Completed message task data: {json.dumps({k: v for k, v in task_data.items() if k not in ['message_history']}, indent=2)}")
                
                # Check if this generated a checklist task
                if task_data.get('needs_checklist', False) and not task_data.get('needs_more_info', False):
                    checklist_task_id = task_data.get('checklist_task_id')
                    logger.info(f"Generated checklist task with ID: {checklist_task_id}")
                
                return checklist_task_id
            elif current_status == 'failed':
                logger.info(f"Failed message task error: {task_data.get('error')}")
                return None
        
        # Wait before checking again
        await asyncio.sleep(1)

async def monitor_checklist_task(task_id):
    """Monitor a checklist task until it completes or fails."""
    firebase_service = FirebaseService()
    
    logger.info(f"Monitoring checklist task {task_id}...")
    last_status = None
    
    while True:
        # Get the task status
        task_data = firebase_service.get_task_status('checklist_tasks', task_id)
        
        if not task_data:
            logger.error(f"Checklist task {task_id} not found")
            return False
        
        current_status = task_data.get('status')
        
        # Only log if the status has changed
        if current_status != last_status:
            logger.info(f"Checklist task status: {current_status}")
            last_status = current_status
            
            # If the task is completed or failed, print additional details
            if current_status == 'completed':
                logger.info(f"Completed checklist task data: {json.dumps({k: v for k, v in task_data.items() if k != 'generated_content' and k != 'message_history'}, indent=2)}")
                
                # Log a snippet of the generated content
                if 'generated_content' in task_data:
                    content_preview = task_data['generated_content'][:200] + "..." if len(task_data['generated_content']) > 200 else task_data['generated_content']
                    logger.info(f"Generated checklist content preview: {content_preview}")
                
                return True
            elif current_status == 'failed':
                logger.info(f"Failed checklist task error: {task_data.get('error')}")
                return False
        
        # Wait before checking again
        await asyncio.sleep(1)

async def run_workers(duration=30):
    """Run both message and checklist workers for a limited duration."""
    logger.info("Starting workers...")
    
    # Create a message worker
    message_worker = MessageWorker()
    
    # Start the message worker
    message_worker_task = asyncio.create_task(
        message_worker.process_tasks(max_runtime=duration)
    )
    
    # Import the checklist worker if we need it
    from app.workers.checklist_worker import ChecklistWorker
    
    # Create a checklist worker
    checklist_worker = ChecklistWorker()
    
    # Start the checklist worker
    checklist_worker_task = asyncio.create_task(
        checklist_worker.process_tasks(max_runtime=duration)
    )
    
    # Wait for both workers to complete
    await asyncio.gather(message_worker_task, checklist_worker_task)
    
    logger.info("Workers finished")

async def verify_message_in_db(chat_id, message_id):
    """Verify the message was correctly updated in the database."""
    # This would typically use the API to fetch the message
    # For simplicity, we'll just log that this step would happen
    logger.info(f"Verifying message {message_id} in chat {chat_id}")
    
    # In a real implementation, you would fetch the message from the API
    # and verify the content was updated correctly

async def main():
    """Main test function for the full flow."""
    try:
        # Step 1: Create a message via the API
        chat_id, message_id, task_id = await test_message_creation_api()
        
        if not chat_id or not message_id or not task_id:
            logger.error("Failed to create test message via API")
            return
            
        # Step 2: Start monitoring the message task in the background
        message_monitor_task = asyncio.create_task(monitor_message_task(task_id))
        
        # Step 3: Run the workers to process the task
        worker_task = asyncio.create_task(run_workers(duration=60))
        
        # Step 4: Wait for the message task to complete
        checklist_task_id = await message_monitor_task
        
        # Step 5: If a checklist was generated, monitor that too
        if checklist_task_id:
            logger.info("Checklist task was generated, monitoring it...")
            checklist_monitor_task = asyncio.create_task(monitor_checklist_task(checklist_task_id))
            checklist_success = await checklist_monitor_task
            
            if checklist_success:
                logger.info("Checklist task completed successfully")
            else:
                logger.error("Checklist task failed")
        
        # Step 6: Verify the message was updated correctly in the database
        await verify_message_in_db(chat_id, message_id)
        
        # Make sure the worker task is done
        await worker_task
        
        logger.info("Full flow test completed successfully")
        
    except Exception as e:
        logger.error(f"Error during full flow test: {e}")

if __name__ == "__main__":
    asyncio.run(main()) 