import os
import sys
import json
import asyncio
import logging
import time
from typing import Dict, Any, List, Set, Tuple, Optional
from datetime import datetime

# Add the project root to the path so we can import app modules
sys.path.append(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))

from app.services.firebase_service import FirebaseService
from app.services.ai_service import AIService
from firebase_admin import firestore
from app.utils.firestore_utils import convert_firestore_data, firestore_data_to_json

# Set up logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

# Maximum time for processing a single task
MAX_TASK_PROCESSING_TIME = 60  # 60 seconds per task
MAX_PENDING_TASK_AGE = 60  # 60 seconds

class UnifiedWorker:
    """
    Unified worker that handles both message and checklist tasks.
    Each worker runs in its own thread with a limited number of concurrent tasks.
    """
    
    def __init__(self, worker_id: str = "default", max_concurrent_tasks: int = 10):
        """Initialize the worker with thread-specific settings."""
        self.worker_id = worker_id
        self.firebase_service = FirebaseService()
        self.ai_service = AIService()
        self.active_message_tasks: Set[str] = set()
        self.active_checklist_tasks: Set[str] = set()
        self.semaphore = asyncio.Semaphore(max_concurrent_tasks)  # Thread-specific limit
    
    @property
    def total_active_tasks(self) -> int:
        """Get the total number of active tasks across both types."""
        return len(self.active_message_tasks) + len(self.active_checklist_tasks)
    
    async def process_tasks(self, max_runtime=None):
        """
        Process pending tasks from Firestore, handling all task types.
        This method runs in a loop, polling for new tasks.
        """
        # Track start time for the polling window
        start_time = time.time() if max_runtime else None
        tasks_processed = 0
        pending_tasks = []
        
        while True:
            try:
                # Check if we've exceeded our polling window
                elapsed_time = time.time() - start_time if start_time else 0
                if max_runtime and elapsed_time > max_runtime:
                    # Wait for any remaining tasks to complete before shutting down
                    if pending_tasks:
                        logger.info(f"Waiting for {len(pending_tasks)} pending tasks to complete before shutting down")
                        await asyncio.gather(*pending_tasks)
                    return
                
                # Calculate available capacity
                total_active = self.total_active_tasks
                available_capacity = self.semaphore._value - total_active
                
                if available_capacity > 0:
                    # IMPORTANT: We need to poll for all three types of tasks:
                    # 1. Message tasks: Regular chat messages that need AI responses
                    # 2. Checklist tasks: Tasks for generating checklists (created by message tasks when they detect a checklist request)
                    # 3. Checkin tasks: Tasks for analyzing completed checklists and providing insights
                    # DO NOT REMOVE any of these task types as they are all critical for the system to function properly
                    
                    message_tasks = self.firebase_service.get_pending_tasks(
                        collection=self.firebase_service.MESSAGE_TASKS_COLLECTION,
                        limit=available_capacity
                    )
                    
                    checklist_tasks = self.firebase_service.get_pending_tasks(
                        collection=self.firebase_service.CHECKLIST_TASKS_COLLECTION,
                        limit=available_capacity
                    )
                    
                    checkin_tasks = self.firebase_service.get_pending_tasks(
                        collection=self.firebase_service.CHECKIN_TASKS_COLLECTION,
                        limit=available_capacity
                    )
                    
                    # Process all tasks from all collections
                    for task in message_tasks + checklist_tasks + checkin_tasks:
                        task_id = task['id']
                        task_data = task
                        
                        # Debug logging for timestamp
                        logger.debug(f"Task {task_id} created_at type: {type(task_data.get('created_at'))}, value: {task_data.get('created_at')}")
                        
                        # Check task age
                        created_at = task_data.get('created_at')
                        if created_at:
                            try:
                                # Handle different timestamp formats
                                if isinstance(created_at, str):
                                    # Try to parse string timestamp
                                    try:
                                        # First try ISO format
                                        dt = datetime.fromisoformat(created_at.replace('Z', '+00:00'))
                                        created_at = dt.timestamp()
                                    except ValueError:
                                        # If it fails, try to convert directly to float
                                        created_at = float(created_at)
                                
                                # Now calculate task age
                                task_age = time.time() - float(created_at)
                                logger.debug(f"Task {task_id} age calculation: current_time={time.time()}, created_at={created_at}, age={task_age}")
                                logger.debug(f"Task {task_id} age: {task_age:.1f} seconds")
                                
                                if task_age > MAX_PENDING_TASK_AGE:
                                    # Task is too old, mark as failed without processing
                                    collection = task_data.get('collection', self.firebase_service.MESSAGE_TASKS_COLLECTION)
                                    logger.warning(f"Task {task_id} is too old ({task_age:.1f} seconds), marking as failed")
                                    self.firebase_service.update_task_status(
                                        collection=collection,
                                        task_id=task_id,
                                        status='failed',
                                        data={
                                            'error': f'Task expired after waiting in queue for {task_age:.1f} seconds'
                                        }
                                    )
                                    continue
                            except Exception as e:
                                logger.error(f"Error calculating task age for task {task_id}: {e}")
                                logger.error(f"created_at type: {type(created_at)}, value: {created_at}")
                                # Don't skip processing the task if we can't calculate age
                        
                        # Determine task type and process accordingly
                        if task.get('collection') == self.firebase_service.CHECKIN_TASKS_COLLECTION:
                            # Process checkin task (analyzing completed checklists)
                            task_coroutine = self.process_checkin_task(task_id, task_data)
                        elif task.get('collection') == self.firebase_service.CHECKLIST_TASKS_COLLECTION:
                            # Process checklist task (generating new checklists)
                            task_coroutine = self.process_checklist_task(task_id, task_data)
                        else:
                            # Process regular message task (chat messages)
                            task_coroutine = self.process_message_task(task_id, task_data)
                        
                        # Create and start task with tracking
                        task_future = asyncio.create_task(task_coroutine)
                        pending_tasks.append(task_future)
                
                # Clean up completed tasks
                pending_tasks = [task for task in pending_tasks if not task.done()]
                
                # Brief pause before next polling cycle
                await asyncio.sleep(0.1)
                
            except Exception as e:
                logger.error(f"Error in process_tasks: {e}")
                await asyncio.sleep(1.0)  # Sleep before retrying
    
    async def process_message_task_with_tracking(self, task_id, task_data):
        """
        Process a message task with tracking and timeout.
        
        Args:
            task_id: The task ID
            task_data: The task data
        """
        try:
            # Use semaphore to limit concurrency
            async with self.semaphore:
                logger.info(f"Starting message task {task_id}")
                
                try:
                    # Process with timeout
                    await asyncio.wait_for(
                        self.process_message_task(task_id, task_data),
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
            logger.error(f"Error in process_message_task_with_tracking for task {task_id}: {e}")
        finally:
            # Always remove from active tasks when done
            self.active_message_tasks.discard(task_id)
    
    async def process_checklist_task_with_tracking(self, task_id, task_data):
        """
        Process a checklist task with tracking and timeout.
        
        Args:
            task_id: The task ID
            task_data: The task data
        """
        try:
            # Use semaphore to limit concurrency
            async with self.semaphore:
                logger.info(f"Starting checklist task {task_id}")
                
                try:
                    # Process with timeout
                    await asyncio.wait_for(
                        self.process_checklist_task(task_id, task_data),
                        timeout=MAX_TASK_PROCESSING_TIME
                    )
                    logger.info(f"Checklist task {task_id} completed successfully")
                except asyncio.TimeoutError:
                    logger.error(f"Checklist task {task_id} timed out after {MAX_TASK_PROCESSING_TIME} seconds")
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
            logger.error(f"Error in process_checklist_task_with_tracking for task {task_id}: {e}")
        finally:
            # Always remove from active tasks when done
            self.active_checklist_tasks.discard(task_id)
    
    async def process_message_task(self, task_id, task_data):
        """
        Process a message task.
        All tasks are now processed as stateless tasks.
        
        Args:
            task_id: The task ID
            task_data: The task data
        """
        # Convert Firestore data to JSON-serializable format
        task_data = convert_firestore_data(task_data)
        return await self.process_stateless_message_task(task_id, task_data)
    
    async def process_checklist_task(self, task_id, task_data):
        """
        Process a checklist task.
        
        Args:
            task_id: The task ID
            task_data: The task data
        """
        # Convert Firestore data to JSON-serializable format
        task_data = convert_firestore_data(task_data)
        
        try:
            # Extract task data
            user_id = task_data.get('user_id')
            message_content = task_data.get('message_content')
            message_history = task_data.get('message_history', [])
            client_time = task_data.get('client_time')  # Get client time if provided
            
            # Parse client time if provided
            client_datetime = None
            if client_time:
                try:
                    client_datetime = datetime.fromisoformat(client_time.replace('Z', '+00:00'))
                    logger.info(f"Using client time for checklist generation: {client_datetime}")
                except (ValueError, TypeError) as e:
                    logger.warning(f"Error parsing client time: {e}. Using server time instead.")
            
            # Generate the checklist
            checklist_data = await self.ai_service.generate_checklist(
                message=message_content,
                message_history=message_history,
                now=client_datetime
            )
            
            if checklist_data:
                # Store the checklist in Firestore using the date-sharded method
                # Note that we're now using a stateless approach with no chat_id/message_id
                self.firebase_service.store_checklist(
                    user_id=user_id,
                    checklist_content=checklist_data
                )
                
                # Update task status to completed
                self.firebase_service.update_task_status(
                    collection='checklist_tasks',
                    task_id=task_id,
                    status='completed',
                    data={
                        'checklist_data': checklist_data
                    }
                )
                
                logger.info(f"Checklist task {task_id} completed")
                return True
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
                return False
        
        except Exception as e:
            logger.error(f"Error in process_checklist_task for task {task_id}: {e}")
            # Update task status to failed
            self.firebase_service.update_task_status(
                collection='checklist_tasks',
                task_id=task_id,
                status='failed',
                data={
                    'error': str(e)
                }
            )
            return False
    
    async def process_stateless_message_task(self, task_id, task_data):
        """
        Process a stateless message task without database dependency.
        
        Args:
            task_id: The task ID
            task_data: The task data
        """
        logger.info(f"Processing stateless message task {task_id}")
        
        try:
            # Extract task data
            user_id = task_data.get('user_id')
            message_content = task_data.get('message_content')
            message_history = task_data.get('message_history', [])
            user_full_name = task_data.get('user_full_name')
            client_time = task_data.get('client_time')  # Get client time if provided
            
            # Generate optimized response using the AI service
            result = await self.ai_service.generate_optimized_response(
                message=message_content,
                message_history=message_history,
                user_full_name=user_full_name,
                user_id=user_id,
                client_time=client_time  # Pass client time to AI service
            )
            
            # Extract the results
            ai_response = result['response_text']
            needs_checklist = result['needs_checklist']
            needs_more_info = result['needs_more_info']
            
            # Process checklist if needed
            checklist_task_id = None
            
            if needs_checklist and not needs_more_info:
                # Create a checklist task in "pending" state
                checklist_task_data = {
                    'user_id': user_id,
                    'message_content': message_content,
                    'message_history': message_history,
                    'status': 'pending',
                    'created_at': firestore.SERVER_TIMESTAMP,
                    'updated_at': firestore.SERVER_TIMESTAMP
                }
                
                # Include client time if provided
                if client_time:
                    checklist_task_data['client_time'] = client_time
                
                # Add the checklist task to Firestore
                task_ref = self.firebase_service.db.collection('checklist_tasks').document()
                task_ref.set(checklist_task_data)
                checklist_task_id = task_ref.id
                logger.info(f"Created checklist task {checklist_task_id} from message task {task_id}")
            
            # Create the initial response with checklist task ID if applicable
            final_message_content = ai_response
            if checklist_task_id:
                # Include checklist task ID in the response
                final_message_content = json.dumps({
                    "message": ai_response,
                    "checklist_task_id": checklist_task_id
                })
            
            # Update message task status to completed immediately
            self.firebase_service.update_task_status(
                collection='message_tasks',
                task_id=task_id,
                status='completed',
                data={
                    'response': final_message_content,
                    'checklist_task_id': checklist_task_id
                }
            )
            
            logger.info(f"Completed message task {task_id} with initial response")
            return True
            
        except Exception as e:
            logger.error(f"Error processing stateless message task {task_id}: {e}")
            # Update task status to failed
            self.firebase_service.update_task_status(
                collection='message_tasks',
                task_id=task_id,
                status='failed',
                data={
                    'error': str(e)
                }
            )
            return False

    async def process_checkin_task(self, task_id: str, task_data: Dict[str, Any]) -> bool:
        """Process a check-in task."""
        try:
            # Extract data from task
            user_id = task_data.get('user_id')
            user_full_name = task_data.get('user_full_name')
            checklist_data = task_data.get('checklist_data', {})
            alfred_personality = task_data.get('alfred_personality')
            user_objectives = task_data.get('user_objectives')
            
            logger.info(f"Processing checkin task {task_id} for user {user_id}")
            
            # Generate analysis
            analysis = self.ai_service.analyze_checkin(
                checklist_data=checklist_data,
                user_full_name=user_full_name,
                alfred_personality=alfred_personality,
                user_objectives=user_objectives
            )
            
            if analysis:
                # Update task status to completed with the analysis
                self.firebase_service.update_task_status(
                    collection=self.firebase_service.CHECKIN_TASKS_COLLECTION,
                    task_id=task_id,
                    status='completed',
                    data={
                        'response': analysis
                    }
                )
                
                logger.info(f"Completed checkin task {task_id}")
                return True
            else:
                # Update task status to failed if no analysis generated
                logger.warning(f"Task {task_id}: No analysis generated")
                self.firebase_service.update_task_status(
                    collection=self.firebase_service.CHECKIN_TASKS_COLLECTION,
                    task_id=task_id,
                    status='failed',
                    data={
                        'error': 'No analysis generated'
                    }
                )
                return False
        
        except Exception as e:
            logger.error(f"Error processing checkin task {task_id}: {e}")
            # Update task status to failed
            self.firebase_service.update_task_status(
                collection=self.firebase_service.CHECKIN_TASKS_COLLECTION,
                task_id=task_id,
                status='failed',
                data={
                    'error': str(e)
                }
            )
            return False 