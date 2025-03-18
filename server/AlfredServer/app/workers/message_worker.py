import os
import sys
import json
import asyncio
import logging
from typing import Dict, Any, List

# Add the project root to the path so we can import app modules
sys.path.append(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))

from app.services.firebase_service import FirebaseService
from app.services.ai_service import AIService
from app.db.session import SessionLocal
from app import crud, schemas
from app.utils.firestore_utils import convert_firestore_data, firestore_data_to_json

# Set up logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

class MessageWorker:
    """
    Worker for processing message generation tasks from Firestore.
    """
    
    def __init__(self):
        """Initialize the worker with Firebase and AI services."""
        self.firebase_service = FirebaseService()
        self.ai_service = AIService()
    
    async def process_tasks(self):
        """
        Process pending message tasks from Firestore.
        This method runs in an infinite loop, polling for new tasks.
        """
        logger.info("Starting message worker")
        
        while True:
            try:
                # Get pending tasks
                tasks = self.firebase_service.get_pending_tasks('message_tasks', limit=5)
                
                if not tasks:
                    # No tasks to process, wait before checking again
                    await asyncio.sleep(5)
                    continue
                
                logger.info(f"Found {len(tasks)} pending message tasks")
                
                # Process each task
                for task in tasks:
                    task_id = task['id']
                    
                    # Update status to processing
                    self.firebase_service.update_task_status(
                        collection='message_tasks',
                        task_id=task_id,
                        status='processing'
                    )
                    
                    # Process the task
                    await self.process_task(task_id, task)
                
                # Wait a short time before checking for more tasks
                await asyncio.sleep(1)
                
            except Exception as e:
                logger.error(f"Error processing message tasks: {e}")
                # Wait longer on error
                await asyncio.sleep(10)
    
    async def process_task(self, task_id: str, task_data: Dict[str, Any]):

        """
        Process a single message task.
        
        Args:
            task_id: The ID of the task
            task_data: The task data from Firestore
        """
        """
        logger.info(f"Processing message task {task_id}")
        
        # Convert Firestore data to JSON-serializable format
        task_data = convert_firestore_data(task_data)
        
        print(f"[MESSAGE WORKER] Processing task {task_id} with data: {json.dumps({k: v for k, v in task_data.items() if k != 'message_history'}, indent=2)}")
        
        try:
            # Extract task data
            user_id = task_data.get('user_id')
            chat_id = task_data.get('chat_id')
            message_id = task_data.get('message_id')
            message_content = task_data.get('message_content')
            message_history = task_data.get('message_history', [])
            user_full_name = task_data.get('user_full_name')
            
            print(f"[MESSAGE WORKER] Task {task_id}: Checking if message needs checklist...")
            # Check if this needs a checklist
            needs_checklist = await self.ai_service.should_generate_checklist(
                message=message_content,
                message_history=message_history
            )
            print(f"[MESSAGE WORKER] Task {task_id}: Needs checklist: {needs_checklist}")
            
            print(f"[MESSAGE WORKER] Task {task_id}: Generating AI response...")
            # Generate message response
            message_text = await self.ai_service.generate_response(
                message=message_content,
                user_id=user_id,
                message_history=message_history,
                user_full_name=user_full_name
            )
            print(f"[MESSAGE WORKER] Task {task_id}: Generated response of length {len(message_text)} chars")
            
            # Create database session
            db = SessionLocal()
            try:
                # Check if the message_id exists (it should be the placeholder message)
                existing_message = None
                if message_id:
                    existing_message = crud.chat_message.get(db, id=message_id)
                
                if existing_message and existing_message.chat_id == chat_id:
                    # Update the existing message with the generated content
                    crud.chat_message.update(
                        db, 
                        db_obj=existing_message, 
                        obj_in={"content": message_text}
                    )
                    print(f"[MESSAGE WORKER] Task {task_id}: Updated existing message {message_id} in PostgreSQL")
                    logger.info(f"Updated existing message {message_id} with generated content")
                    
                    # Update task status to completed
                    self.firebase_service.update_task_status(
                        collection='message_tasks',
                        task_id=task_id,
                        status='completed',
                        data={
                            'generated_content': message_text,
                            'needs_checklist': needs_checklist
                        }
                    )
                    print(f"[MESSAGE WORKER] Task {task_id}: Updated task status to completed in Firestore")
                else:
                    # If message_id doesn't exist or doesn't match chat_id, create a new message
                    # Get the next sequence number
                    next_sequence = crud.chat_message.get_last_message_sequence(db, chat_id=chat_id) + 1
                    
                    # Create AI response message
                    ai_message = schemas.ChatMessageCreate(
                        chat_id=chat_id,
                        role="assistant",
                        content=message_text,
                        sequence=next_sequence
                    )
                    ai_message_db = crud.chat_message.create(db, obj_in=ai_message)
                    print(f"[MESSAGE WORKER] Task {task_id}: Created new message {ai_message_db.id} in PostgreSQL")
                    
                    # Update task status to completed
                    self.firebase_service.update_task_status(
                        collection='message_tasks',
                        task_id=task_id,
                        status='completed',
                        data={
                            'generated_content': message_text,
                            'message_id': ai_message_db.id,
                            'needs_checklist': needs_checklist
                        }
                    )
                    print(f"[MESSAGE WORKER] Task {task_id}: Updated task status to completed in Firestore")
                    
                    logger.info(f"Created new message {ai_message_db.id} with generated content")
                
                logger.info(f"Completed message task {task_id}")
                
                # If needs checklist, create a checklist task
                if needs_checklist:
                    # Use the existing message ID if available, otherwise use the new one
                    response_message_id = message_id if existing_message else ai_message_db.id
                    
                    print(f"[MESSAGE WORKER] Task {task_id}: Creating checklist task for message {response_message_id}")
                    checklist_task_id = self.firebase_service.add_checklist_task(
                        user_id=user_id,
                        chat_id=chat_id,
                        message_id=response_message_id,
                        message_content=message_content,
                        message_history=message_history
                    )
                    
                    print(f"[MESSAGE WORKER] Task {task_id}: Created checklist task {checklist_task_id}")
                    logger.info(f"Created checklist task {checklist_task_id} for message {response_message_id}")
                
            finally:
                db.close()
                
        except Exception as e:
            logger.error(f"Error processing message task {task_id}: {e}")
            print(f"[MESSAGE WORKER] Task {task_id}: ERROR: {str(e)}")
            # Update task status to failed
            self.firebase_service.update_task_status(
                collection='message_tasks',
                task_id=task_id,
                status='failed',
                data={
                    'error': str(e)
                }
            )
            print(f"[MESSAGE WORKER] Task {task_id}: Updated task status to failed in Firestore")
            """

async def main():
    """Main entry point for the worker."""
    worker = MessageWorker()
    await worker.process_tasks()

if __name__ == "__main__":
    asyncio.run(main()) 