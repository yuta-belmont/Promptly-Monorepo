import os
import sys
import json
import asyncio
import logging
import time
from typing import Dict, Any, List, Set

# Add the project root to the path so we can import app modules
sys.path.append(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))

from app.services.firebase_service import FirebaseService
from app.services.ai_service import AIService
from app.db.session import SessionLocal
from app import crud, schemas
from firebase_admin import firestore
from app.utils.firestore_utils import convert_firestore_data

# Set up logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

# Maximum time for processing a single task
MAX_TASK_PROCESSING_TIME = 30  # 30 seconds per task
MAX_CONCURRENT_TASKS = 50  # Maximum number of tasks to process concurrently

class MessageWorker:
    """
    Worker for processing message tasks from Firestore.
    """
    
    def __init__(self):
        """Initialize the worker with Firebase and AI services."""
        self.firebase_service = FirebaseService()
        self.ai_service = AIService()
        self.active_tasks: Set[str] = set()  # Track active task IDs
        self.semaphore = asyncio.Semaphore(MAX_CONCURRENT_TASKS)  # Limit concurrent tasks
    
    async def process_tasks(self, max_runtime=None):
        """
        Process pending message tasks from Firestore.
        This method runs in a loop, polling for new tasks.
        
        Args:
            max_runtime: Maximum time in seconds to run before returning (None for infinite)
                         This controls how long we poll for tasks, not how long we process each task
        """
        
        # Track start time for the polling window
        start_time = time.time() if max_runtime else None
        tasks_processed = 0
        pending_tasks = []  # List to track pending task coroutines
        
        while True:
            try:
                # Check if we've exceeded our polling window
                elapsed_time = time.time() - start_time if start_time else 0
                remaining_time = max_runtime - elapsed_time if max_runtime else None
                
                if max_runtime and elapsed_time > max_runtime:
                    # Wait for any remaining tasks to complete before shutting down
                    if pending_tasks:
                        logger.info(f"Waiting for {len(pending_tasks)} pending tasks to complete before shutting down")
                        await asyncio.gather(*pending_tasks)
                    return
                
                # Log current task status
                active_task_count = len(self.active_tasks)
                
                # Calculate available capacity
                available_capacity = MAX_CONCURRENT_TASKS - active_task_count
                
                if available_capacity > 0:
                    # Get pending tasks up to available capacity
                    fetch_limit = min(available_capacity, 10)  # Fetch at most 10 at a time
                    
                    tasks = self.firebase_service.get_pending_tasks('message_tasks', limit=fetch_limit)
                    
                    if tasks:
                        logger.info(f"Found {len(tasks)} pending message tasks")
                        
                        # Start processing new tasks concurrently
                        for task in tasks:
                            task_id = task['id']
                            
                            # Skip if task is already being processed
                            if task_id in self.active_tasks:
                                logger.warning(f"Task {task_id} is already being processed, skipping")
                                continue
                                
                            # Update status to processing
                            self.firebase_service.update_task_status(
                                collection='message_tasks',
                                task_id=task_id,
                                status='processing'
                            )
                            
                            # Add to active tasks
                            self.active_tasks.add(task_id)
                            
                            # Create and start task coroutine with semaphore and timeout
                            task_coroutine = self.process_task_with_tracking(task_id, task)
                            task_future = asyncio.create_task(task_coroutine)
                            
                            # Add to pending tasks
                            pending_tasks.append(task_future)
                
                # Clean up completed tasks
                pending_tasks = [task for task in pending_tasks if not task.done()]
                
                # Brief pause before next polling cycle
                await asyncio.sleep(0.1)  # Very short wait to check for task completions
                
            except Exception as e:
                logger.error(f"Error in process_tasks loop: {e}")
                
                # Check if we should return due to max_runtime
                if max_runtime and start_time and (time.time() - start_time) > max_runtime:
                    logger.info(f"Reached max polling window of {max_runtime} seconds after error, returning")
                    return
                    
                # Wait a bit before retrying
                await asyncio.sleep(1.0)
    
    async def process_task_with_tracking(self, task_id: str, task_data: Dict[str, Any]):
        """
        Process a task with semaphore and timeout, and track completion.
        
        Args:
            task_id: The ID of the task
            task_data: The task data from Firestore
        """
        try:
            # Use semaphore to limit concurrency
            async with self.semaphore:
                logger.info(f"Starting message task {task_id}")
                
                try:
                    # Process with timeout
                    await asyncio.wait_for(
                        self.process_task(task_id, task_data),
                        timeout=MAX_TASK_PROCESSING_TIME
                    )
                    logger.info(f"Message task {task_id} completed successfully")
                except asyncio.TimeoutError:
                    logger.error(f"Message task {task_id} timed out after {MAX_TASK_PROCESSING_TIME} seconds")
                    # Update task status to failed due to timeout
                    self.firebase_service.update_task_status(
                        collection='message_tasks',
                        task_id=task_id,
                        status='failed',
                        data={
                            'error': f'Task processing timed out after {MAX_TASK_PROCESSING_TIME} seconds'
                        }
                    )
        except Exception as e:
            logger.error(f"Error in process_task_with_tracking for message task {task_id}: {e}")
        finally:
            # Always remove from active tasks when done
            self.active_tasks.discard(task_id)
            
    async def process_task(self, task_id: str, task_data: Dict[str, Any]):
        """
        Process a single message task.
        
        Args:
            task_id: The ID of the task
            task_data: The task data from Firestore
        """
        # Convert Firestore data to JSON-serializable format
        task_data = convert_firestore_data(task_data)
        
        try:
            # Extract task data
            user_id = task_data.get('user_id')
            chat_id = task_data.get('chat_id')
            message_id = task_data.get('message_id')
            message_content = task_data.get('message_content')
            message_history = task_data.get('message_history', [])
            user_full_name = task_data.get('user_full_name')
            
            # Generate optimized response using the AI service
            result = await self.ai_service.generate_optimized_response(
                message=message_content,
                message_history=message_history,
                user_full_name=user_full_name,
                user_id=user_id
            )
            
            # Extract the results
            ai_response = result['response_text']
            needs_checklist = result['needs_checklist']
            needs_more_info = result['needs_more_info']
            
            # Create database session
            db = SessionLocal()
            try:
                # Check if the message_id exists (it should be the placeholder message)
                existing_message = None
                if message_id:
                    existing_message = crud.chat_message.get(db, id=message_id)
                
                # Prepare the message content
                final_message_content = ai_response
                
                # If this is a checklist request and we have enough information, create a task
                checklist_task_id = None
                if needs_checklist and not needs_more_info:
                    # Create a checklist task
                    checklist_task_id = self.firebase_service.add_checklist_task(
                        user_id=user_id,
                        chat_id=chat_id,
                        message_id=message_id,
                        message_content=message_content,
                        message_history=message_history
                    )
                    
                    # Create a structured response with the checklist task ID
                    final_message_content = json.dumps({
                        "message": ai_response,
                        "checklist_task_id": checklist_task_id
                    })
                
                ai_message_id = None
                # If the placeholder message exists and matches the chat_id, update it
                if existing_message and existing_message.chat_id == chat_id:
                    # Update the existing message with the generated content
                    crud.chat_message.update(
                        db, 
                        db_obj=existing_message, 
                        obj_in={"content": final_message_content}
                    )
                    ai_message_id = existing_message.id
                    logger.info(f"Updated existing message {message_id} with generated content")
                else:
                    # If message_id doesn't exist or doesn't match chat_id, create a new message
                    # Get the next sequence number
                    next_sequence = crud.chat_message.get_last_message_sequence(db, chat_id=chat_id) + 1
                    
                    # Create AI response message
                    ai_message = schemas.ChatMessageCreate(
                        chat_id=chat_id,
                        role="assistant",
                        content=final_message_content,
                        sequence=next_sequence
                    )
                    
                    # Create the message in the database
                    ai_message_db = crud.chat_message.create(db, obj_in=ai_message)
                    ai_message_id = ai_message_db.id
                    logger.info(f"Created new message {ai_message_id} with generated content")
                
                # Update the task with the completed response
                update_data = {
                    'response': ai_response,
                    'ai_message_id': ai_message_id,
                    'needs_checklist': needs_checklist,
                    'needs_more_info': needs_more_info
                }
                
                # Add checklist task ID if applicable
                if checklist_task_id:
                    update_data['checklist_task_id'] = checklist_task_id
                
                # Update task status to completed
                self.firebase_service.update_task_status(
                    collection='message_tasks',
                    task_id=task_id,
                    status='completed',
                    data=update_data
                )
                
            finally:
                db.close()
                
        except Exception as e:
            logger.error(f"Error processing message task {task_id}: {e}")
            # Update task status to failed
            self.firebase_service.update_task_status(
                collection='message_tasks',
                task_id=task_id,
                status='failed',
                data={
                    'error': str(e)
                }
            )

async def main():
    """Main entry point for the worker."""
    worker = MessageWorker()
    await worker.process_tasks()

if __name__ == "__main__":
    asyncio.run(main()) 