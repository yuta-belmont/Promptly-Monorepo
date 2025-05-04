"""
Worker for processing check-in tasks from Pub/Sub.
"""

import json
import logging
from typing import Dict, Any

from app.pubsub.workers.base_worker import PubSubWorker
from app.pubsub.config import CHECKIN_TASKS_SUBSCRIPTION
from app.services.ai_service import AIService
from app.services.firebase_service import FirebaseService

logger = logging.getLogger(__name__)

class CheckinWorker(PubSubWorker):
    """Worker for processing check-in analysis tasks."""
    
    def __init__(self, worker_id: str = None):
        """
        Initialize the check-in worker.
        
        Args:
            worker_id: A unique identifier for this worker instance
        """
        super().__init__(
            subscription_id=CHECKIN_TASKS_SUBSCRIPTION,
            worker_id=worker_id
        )
        
        # Initialize services
        self.ai_service = AIService()
        self.firebase = FirebaseService()
        
        logger.info(f"Check-in worker {self.worker_id} initialized")
    
    def _process_message(self, data: Dict[str, Any]) -> bool:
        """
        Process a check-in task.
        
        Args:
            data: The decoded message data
            
        Returns:
            True if processing was successful, False otherwise
        """
        try:
            # Extract task parameters
            request_id = data.get("request_id", "unknown")
            user_id = data.get("user_id")
            user_full_name = data.get("user_full_name")
            checklist_data = data.get("checklist_data")
            alfred_personality = data.get("alfred_personality")
            user_objectives = data.get("user_objectives")
            
            # Validate required parameters
            if not user_id or not checklist_data:
                logger.error(f"Missing required parameters for check-in task {request_id}")
                return False
            
            # Process the check-in
            logger.info(f"Processing check-in for user {user_id}, request {request_id}")
            
            # Analyze the checklist
            analysis_json = self.ai_service.analyze_checkin(
                checklist_data=checklist_data,
                user_full_name=user_full_name,
                alfred_personality=alfred_personality,
                user_objectives=user_objectives
            )
            
            # Check if we successfully generated analysis data
            if not analysis_json:
                logger.error(f"Failed to analyze check-in data for task {request_id}")
                return False
            
            # Try to parse the JSON
            try:
                analysis_data = json.loads(analysis_json)
            except json.JSONDecodeError:
                logger.error(f"Failed to parse check-in analysis JSON for task {request_id}")
                # Set a default value
                analysis_data = {
                    "summary": "Analysis completed",
                    "analysis": "Unable to parse detailed analysis",
                    "response": analysis_json  # Use the raw response as a fallback
                }
            
            # Store the check-in in Firestore (for client sync and backward compatibility)
            try:
                # Prepare data for storage
                checkin_data = {
                    "analysis": analysis_data,
                    "checklist_data": checklist_data
                }
                
                # Store the check-in data
                self.firebase.store_checkin(
                    user_id=user_id,
                    checkin_data=checkin_data
                )
                logger.info(f"Stored check-in in Firestore for user {user_id}")
            except Exception as e:
                logger.error(f"Error storing check-in in Firestore: {e}")
                # Continue anyway - we'll still publish the result via Redis
            
            # Stream the result back via Redis Pub/Sub for real-time delivery
            self.results_publisher.publish_completion(request_id, analysis_json)
            
            logger.info(f"Check-in task {request_id} completed successfully")
            return True
            
        except Exception as e:
            logger.error(f"Error processing check-in task: {e}")
            
            # Try to publish error via Redis
            try:
                if 'request_id' in locals():
                    self.results_publisher.publish_error(request_id, str(e))
            except Exception:
                pass
                
            return False 