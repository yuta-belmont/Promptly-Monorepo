"""
Worker for processing checklist tasks from Pub/Sub.
"""

import json
import logging
import asyncio
from typing import Dict, Any

from app.pubsub.workers.base_worker import PubSubWorker
from app.pubsub.config import CHECKLIST_TASKS_SUBSCRIPTION
from app.services.ai_service import AIService
from app.services.firebase_service import FirebaseService

logger = logging.getLogger(__name__)

class ChecklistWorker(PubSubWorker):
    """Worker for processing checklist tasks."""
    
    def __init__(self, worker_id: str = None):
        """
        Initialize the checklist worker.
        
        Args:
            worker_id: A unique identifier for this worker instance
        """
        super().__init__(
            subscription_id=CHECKLIST_TASKS_SUBSCRIPTION,
            worker_id=worker_id
        )
        
        # Initialize services
        self.ai_service = AIService()
        self.firebase = FirebaseService()
        
        # Create an asyncio event loop for this worker
        self.loop = asyncio.new_event_loop()
        asyncio.set_event_loop(self.loop)
        
        logger.info(f"Checklist worker {self.worker_id} initialized")
    
    def _process_message(self, data: Dict[str, Any]) -> bool:
        """
        Process a checklist task.
        
        Args:
            data: The decoded message data
            
        Returns:
            True if processing was successful, False otherwise
        """
        try:
            # Extract task parameters
            request_id = data.get("request_id", "unknown")
            user_id = data.get("user_id")
            message_content = data.get("message_content")
            message_history = data.get("message_history", [])
            chat_id = data.get("chat_id")
            message_id = data.get("message_id")
            client_time = data.get("client_time")
            outline_data = data.get("outline_data")
            
            # Validate required parameters
            if not user_id or not message_content:
                logger.error(f"Missing required parameters for checklist task {request_id}")
                return False
            
            # Either generate a checklist from an outline or directly from the message
            if outline_data:
                # Use the outline to generate a detailed checklist
                try:
                    logger.info(f"Generating checklist from outline for task {request_id}")
                    
                    # Extract outline components
                    summary = outline_data.get("outline", {}).get("summary", "")
                    start_date = outline_data.get("outline", {}).get("start_date", "")
                    end_date = outline_data.get("outline", {}).get("end_date", "")
                    details = outline_data.get("outline", {}).get("details", [])
                    
                    # Generate checklist from outline
                    checklist_data = self.loop.run_until_complete(
                        self.ai_service.generate_checklist_from_outline(
                            summary=summary,
                            start_date=start_date,
                            end_date=end_date,
                            line_items=details
                        )
                    )
                except Exception as e:
                    logger.error(f"Error generating checklist from outline: {e}")
                    # Fall back to standard checklist generation
                    checklist_data = self.loop.run_until_complete(
                        self.ai_service.generate_checklist(
                            message=message_content,
                            message_history=message_history,
                            client_time=client_time
                        )
                    )
            else:
                # Generate the checklist directly
                checklist_data = self.loop.run_until_complete(
                    self.ai_service.generate_checklist(
                        message=message_content,
                        message_history=message_history,
                        client_time=client_time
                    )
                )
            
            # Check if we successfully generated checklist data
            if not checklist_data:
                logger.error(f"Failed to generate checklist data for task {request_id}")
                return False
                
            # Store the checklist in Firestore (for client sync and backward compatibility)
            try:
                # Store the checklist data
                self.firebase.store_checklist(
                    user_id=user_id,
                    checklist_content=checklist_data,
                    chat_id=chat_id,
                    message_id=message_id
                )
                logger.info(f"Stored checklist in Firestore for user {user_id}")
            except Exception as e:
                logger.error(f"Error storing checklist in Firestore: {e}")
                # Continue anyway - we'll still publish the result via Redis
            
            # Stream the result back via Redis Pub/Sub for real-time delivery
            # First, convert the checklist data to a string
            checklist_json = json.dumps(checklist_data)
            
            # Publish the checklist data as the result
            self.results_publisher.publish_completion(request_id, checklist_json)
            
            logger.info(f"Checklist task {request_id} completed successfully")
            return True
            
        except Exception as e:
            logger.error(f"Error processing checklist task: {e}")
            
            # Try to publish error via Redis
            try:
                if 'request_id' in locals():
                    self.results_publisher.publish_error(request_id, str(e))
            except Exception:
                pass
                
            return False 