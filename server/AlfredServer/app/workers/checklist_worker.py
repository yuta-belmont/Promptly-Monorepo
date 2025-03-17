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
from app.utils.firestore_utils import convert_firestore_data, firestore_data_to_json

# Set up logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

# Maximum time for processing a single task
MAX_TASK_PROCESSING_TIME = 30  # 30 seconds per task
MAX_CONCURRENT_TASKS = 50  # Maximum number of tasks to process concurrently

class ChecklistWorker:
    """
    Worker for processing checklist generation tasks from Firestore.
    """
    
    def __init__(self):
        """Initialize the worker with Firebase and AI services."""
        self.firebase_service = FirebaseService()
        self.ai_service = AIService()
        self.active_tasks: Set[str] = set()  # Track active task IDs
        self.semaphore = asyncio.Semaphore(MAX_CONCURRENT_TASKS)  # Limit concurrent tasks
    
    async def process_tasks(self, max_runtime=None):
        """
        Process pending checklist tasks from Firestore.
        This method runs in a loop, polling for new tasks.
        
        Args:
            max_runtime: Maximum time in seconds to run before returning (None for infinite)
                         This controls how long we poll for tasks, not how long we process each task
        """
        logger.info(f"Starting checklist worker with polling window: {max_runtime or 'infinite'} seconds")
        logger.info(f"Maximum concurrent tasks: {MAX_CONCURRENT_TASKS}")
        
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
                    logger.info(f"Reached max polling window of {max_runtime} seconds, processed {tasks_processed} tasks, returning")
                    # Wait for any remaining tasks to complete before returning
                    if pending_tasks:
                        logger.info(f"Waiting for {len(pending_tasks)} pending tasks to complete before returning")
                        await asyncio.gather(*pending_tasks)
                    return
                
                # Log current task status
                active_task_count = len(self.active_tasks)
                logger.info(f"Active tasks: {active_task_count}/{MAX_CONCURRENT_TASKS}, processed so far: {tasks_processed}")
                
                # Calculate available capacity
                available_capacity = MAX_CONCURRENT_TASKS - active_task_count
                
                if available_capacity > 0:
                    # Get pending tasks up to available capacity
                    fetch_limit = min(available_capacity, 10)  # Fetch at most 10 at a time to avoid large batches
                    logger.info(f"Checking Firestore for new tasks (available capacity: {available_capacity}, fetch limit: {fetch_limit})")
                    
                    tasks = self.firebase_service.get_pending_tasks('checklist_tasks', limit=fetch_limit)
                    
                    if tasks:
                        logger.info(f"Found {len(tasks)} pending tasks")
                        
                        # Start processing new tasks concurrently
                        for task in tasks:
                            task_id = task['id']
                            
                            # Skip if task is already being processed
                            if task_id in self.active_tasks:
                                logger.warning(f"Task {task_id} is already being processed, skipping")
                                continue
                                
                            # Update status to processing
                            self.firebase_service.update_task_status(
                                collection='checklist_tasks',
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
                logger.info(f"Starting task {task_id} with max processing time of {MAX_TASK_PROCESSING_TIME} seconds")
                
                try:
                    # Process with timeout
                    await asyncio.wait_for(
                        self.process_task(task_id, task_data),
                        timeout=MAX_TASK_PROCESSING_TIME
                    )
                    logger.info(f"Task {task_id} completed successfully")
                except asyncio.TimeoutError:
                    logger.error(f"Task {task_id} timed out after {MAX_TASK_PROCESSING_TIME} seconds")
                    # Update task status to failed due to timeout
                    self.firebase_service.update_task_status(
                        collection='checklist_tasks',
                        task_id=task_id,
                        status='failed',
                        data={
                            'error': f'Task processing timed out after {MAX_TASK_PROCESSING_TIME} seconds'
                        }
                    )
        except Exception as e:
            logger.error(f"Error in process_task_with_tracking for task {task_id}: {e}")
        finally:
            # Always remove from active tasks when done
            self.active_tasks.discard(task_id)
            
    async def process_task(self, task_id: str, task_data: Dict[str, Any]):
        """
        Process a single checklist task.
        
        Args:
            task_id: The ID of the task
            task_data: The task data from Firestore
        """
        # Convert Firestore data to JSON-serializable format
        task_data = convert_firestore_data(task_data)
        
        logger.info(f"Processing task {task_id}")
        
        try:
            # Extract task data
            user_id = task_data.get('user_id')
            chat_id = task_data.get('chat_id')
            message_id = task_data.get('message_id')
            message_content = task_data.get('message_content')
            message_history = task_data.get('message_history', [])
            
            logger.info(f"Task {task_id}: Generating checklist for message: {message_content[:50]}...")
            # Generate checklist
            checklist_data = await self.ai_service.generate_checklist(
                message=message_content,
                message_history=message_history
            )
            logger.info(f"Task {task_id}: Generated checklist with {len(checklist_data.get('items', []))} items")
            
            if checklist_data:
                # Create database session
                db = SessionLocal()
                try:
                    # Get the next sequence number
                    next_sequence = crud.chat_message.get_last_message_sequence(db, chat_id=chat_id) + 1
                    logger.info(f"Task {task_id}: Creating checklist message with sequence {next_sequence}")
                    
                    # Create a message for the checklist data
                    checklist_message = schemas.ChatMessageCreate(
                        chat_id=chat_id,
                        role="assistant",
                        content=json.dumps({"checklists": checklist_data}),
                        sequence=next_sequence
                    )
                    checklist_message_db = crud.chat_message.create(db, obj_in=checklist_message)
                    logger.info(f"Task {task_id}: Created checklist message {checklist_message_db.id} in PostgreSQL")
                    
                    # Store the checklist in Firestore using the new date-sharded method
                    logger.info(f"Task {task_id}: Storing checklist in Firestore...")
                    self.firebase_service.store_checklist(
                        user_id=user_id,
                        chat_id=chat_id,
                        message_id=message_id,
                        checklist_content=checklist_data
                    )
                    
                    # Update task status to completed
                    self.firebase_service.update_task_status(
                        collection='checklist_tasks',
                        task_id=task_id,
                        status='completed',
                        data={
                            'checklist_data': checklist_data,
                            'checklist_message_id': checklist_message_db.id
                        }
                    )
                    logger.info(f"Task {task_id}: Updated task status to completed in Firestore")
                    
                finally:
                    db.close()
            else:
                # Update task status to failed if no checklist data
                logger.warning(f"Task {task_id}: No checklist data generated")
                self.firebase_service.update_task_status(
                    collection='checklist_tasks',
                    task_id=task_id,
                    status='failed',
                    data={
                        'error': 'No checklist data generated'
                    }
                )
                
        except Exception as e:
            logger.error(f"Error processing checklist task {task_id}: {e}")
            # Update task status to failed
            self.firebase_service.update_task_status(
                collection='checklist_tasks',
                task_id=task_id,
                status='failed',
                data={
                    'error': str(e)
                }
            )

async def main():
    """Main entry point for the worker."""
    worker = ChecklistWorker()
    await worker.process_tasks()

if __name__ == "__main__":
    asyncio.run(main()) 