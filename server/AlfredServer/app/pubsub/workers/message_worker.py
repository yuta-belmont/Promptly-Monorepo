"""
Worker for processing message tasks from Pub/Sub.
"""

import json
import logging
import asyncio
from typing import Dict, Any

from app.pubsub.workers.base_worker import PubSubWorker
from app.pubsub.config import MESSAGE_TASKS_SUBSCRIPTION
from app.services.ai_service import AIService
from app.services.firebase_service import FirebaseService

logger = logging.getLogger(__name__)

class MessageWorker(PubSubWorker):
    """Worker for processing message tasks."""
    
    def __init__(self, worker_id: str = None):
        """
        Initialize the message worker.
        
        Args:
            worker_id: A unique identifier for this worker instance
        """
        super().__init__(
            subscription_id=MESSAGE_TASKS_SUBSCRIPTION,
            worker_id=worker_id
        )
        
        # Initialize services
        self.ai_service = AIService()
        self.firebase = FirebaseService()
        
        # Create an asyncio event loop for this worker
        self.loop = asyncio.new_event_loop()
        asyncio.set_event_loop(self.loop)
        
        logger.info(f"Message worker {self.worker_id} initialized")
    
    def _process_message(self, data: Dict[str, Any]) -> bool:
        """
        Process a message task.
        
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
            user_full_name = data.get("user_full_name")
            client_time = data.get("client_time")
            chat_id = data.get("chat_id")
            message_id = data.get("message_id")
            
            # Validate required parameters
            if not user_id or not message_content:
                logger.error(f"Missing required parameters for message task {request_id}")
                return False
            
            # Use the event loop to run the async task
            response = self.loop.run_until_complete(
                self.ai_service.generate_optimized_response(
                    message=message_content,
                    message_history=message_history,
                    user_full_name=user_full_name,
                    user_id=user_id,
                    client_time=client_time
                )
            )
            
            # Update Firestore with the result (for client sync and backward compatibility)
            if chat_id and message_id:
                # If we have chat_id and message_id, we can update the message in Firestore
                try:
                    self.firebase.db.collection("chats").document(chat_id).collection("messages").document(message_id).update({
                        "assistant_response": response.get("response_text", ""),
                        "needs_checklist": response.get("needs_checklist", False),
                        "needs_more_info": response.get("needs_more_info", False),
                        "outline": response.get("outline", None),
                        "processed": True,
                        "processed_at": self.firebase.db.field_value.server_timestamp()
                    })
                    logger.info(f"Updated Firestore for message {message_id} in chat {chat_id}")
                except Exception as e:
                    logger.error(f"Error updating Firestore: {e}")
                    # Continue anyway - we'll still publish the result via Redis
            
            # Stream the result back via Redis Pub/Sub for real-time delivery
            response_text = response.get("response_text", "")
            if response_text:
                self.results_publisher.publish_chunk(request_id, response_text)
            
            # Publish completion with any additional data
            completion_data = {
                "needs_checklist": response.get("needs_checklist", False),
                "needs_more_info": response.get("needs_more_info", False)
            }
            
            # Add outline if available
            if "outline" in response:
                completion_data["outline"] = response["outline"]
                
            # Publish completion event
            self.results_publisher.publish_completion(request_id, json.dumps(completion_data))
            
            logger.info(f"Message task {request_id} completed successfully")
            return True
            
        except Exception as e:
            logger.error(f"Error processing message task: {e}")
            
            # Try to publish error via Redis
            try:
                if 'request_id' in locals():
                    self.results_publisher.publish_error(request_id, str(e))
            except Exception:
                pass
                
            return False 