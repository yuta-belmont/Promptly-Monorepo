"""
Unified worker for processing all types of tasks from Pub/Sub.
This worker can handle message, checklist, and check-in tasks.
"""

import json
import logging
import asyncio
from typing import Dict, Any, Optional

from app.pubsub.workers.base_worker import PubSubWorker
from app.pubsub.config import UNIFIED_TASKS_SUBSCRIPTION
from app.pubsub.messaging.publisher import TaskPublisher
from app.pubsub.messaging.redis_publisher import ResultsPublisher
from app.services.ai_service import AIService

logger = logging.getLogger(__name__)

class UnifiedPubSubWorker(PubSubWorker):
    """Worker for processing all types of tasks from a single Pub/Sub subscription."""
    
    def __init__(self, worker_id: str = None):
        """
        Initialize the unified worker.
        
        Args:
            worker_id: A unique identifier for this worker instance
        """
        super().__init__(
            subscription_id=UNIFIED_TASKS_SUBSCRIPTION,
            worker_id=worker_id
        )
        
        # Initialize services
        self.ai_service = AIService()
        self.task_publisher = TaskPublisher()
        
        # Create an asyncio event loop for this worker
        self.loop = asyncio.new_event_loop()
        asyncio.set_event_loop(self.loop)
        
        logger.info(f"Unified PubSub worker {self.worker_id} initialized")
    
    def _process_message(self, data: Dict[str, Any]) -> bool:
        """
        Process any task from Pub/Sub based on task_type.
        
        Args:
            data: The decoded message data
            
        Returns:
            True if processing was successful, False otherwise
        """
        try:
            # Extract task parameters
            request_id = data.get("request_id", "unknown")
            task_type = data.get("task_type")
            
            if not task_type:
                logger.error(f"Missing task_type for task {request_id}")
                return False
                
            logger.info(f"Processing {task_type} task {request_id}")
            
            # Route to appropriate processor based on task_type
            if task_type == "message":
                return self._process_message_task(request_id, data)
            elif task_type == "checklist":
                return self._process_checklist_task(request_id, data)
            elif task_type == "checkin":
                return self._process_checkin_task(request_id, data)
            else:
                logger.error(f"Unknown task type: {task_type} for task {request_id}")
                return False
                
        except Exception as e:
            logger.error(f"Error processing task: {e}")
            
            # Try to publish error via Redis if we have a request_id
            try:
                if 'request_id' in locals():
                    self.results_publisher.publish_error(request_id, str(e))
            except Exception:
                pass
                
            return False
    
    def _process_message_task(self, request_id: str, data: Dict[str, Any]) -> bool:
        """
        Process a message task.
        
        Args:
            request_id: The request ID
            data: The task data
            
        Returns:
            True if processing was successful, False otherwise
        """
        try:
            # Extract task parameters
            user_id = data.get("user_id")
            message_content = data.get("message_content")
            message_history = data.get("message_history", [])
            user_full_name = data.get("user_full_name")
            client_time = data.get("client_time")
            
            # Validate required parameters
            if not user_id or not message_content:
                logger.error(f"Missing required parameters for message task {request_id}")
                return False
            
            # Create a callback function for streaming chunks to Redis
            def stream_callback(chunk: str):
                # Stream the chunk via Redis for real-time delivery
                self.results_publisher.publish_chunk(request_id, chunk)
            
            # Generate optimized response using the AI service with streaming
            response = self.loop.run_until_complete(
                self.ai_service.generate_streaming_response(
                    message=message_content,
                    message_history=message_history,
                    user_full_name=user_full_name,
                    user_id=user_id,
                    client_time=client_time,
                    stream_callback=stream_callback
                )
            )
            
            # Extract results
            response_text = response.get("response_text", "")
            needs_checklist = response.get("needs_checklist", False)
            needs_more_info = response.get("needs_more_info", False)
            
            # Create completion data
            completion_data = {
                "needs_checklist": needs_checklist,
                "needs_more_info": needs_more_info
            }
            
            # Add outline if available
            if "outline" in response:
                completion_data["outline"] = response["outline"]
                
            # If checklist is needed and we have enough info, create a new checklist task
            if needs_checklist and not needs_more_info and "outline" not in response:
                # Create checklist task
                checklist_task_data = {
                    "task_type": "checklist",
                    "request_id": str(request_id) + "-checklist",
                    "user_id": user_id,
                    "message_content": message_content,
                    "message_history": message_history
                }
                
                # Include optional fields if they exist
                if client_time:
                    checklist_task_data["client_time"] = client_time
                    
                # Publish to the unified topic
                checklist_request_id = self.task_publisher.publish_to_unified_topic(checklist_task_data)
                
                # Add checklist task ID to completion data
                completion_data["checklist_request_id"] = checklist_request_id
                
                logger.info(f"Created checklist task {checklist_request_id} from message task {request_id}")
            
            # Publish completion event
            self.results_publisher.publish_completion(request_id, json.dumps(completion_data))
            
            logger.info(f"Message task {request_id} completed successfully")
            return True
            
        except Exception as e:
            logger.error(f"Error processing message task {request_id}: {e}")
            
            # Try to publish error via Redis
            try:
                self.results_publisher.publish_error(request_id, str(e))
            except Exception:
                pass
                
            return False
    
    def _process_checklist_task(self, request_id: str, data: Dict[str, Any]) -> bool:
        """
        Process a checklist task.
        
        Args:
            request_id: The request ID
            data: The task data
            
        Returns:
            True if processing was successful, False otherwise
        """
        try:
            # Extract task parameters
            user_id = data.get("user_id")
            message_content = data.get("message_content")
            message_history = data.get("message_history", [])
            client_time = data.get("client_time")
            outline_data = data.get("outline_data")
            
            # Validate required parameters
            if not user_id:
                logger.error(f"Missing required user_id for checklist task {request_id}")
                return False
                
            # Either generate checklist from an outline or directly from the message
            if outline_data:
                # Extract outline components
                summary = outline_data.get("summary", "")
                start_date = outline_data.get("start_date", "")
                end_date = outline_data.get("end_date", "")
                line_items = outline_data.get("details", [])
                
                # Generate checklist from outline
                logger.info(f"Generating checklist from outline for task {request_id}")
                checklist_data = self.loop.run_until_complete(
                    self.ai_service.generate_checklist_from_outline(
                        summary=summary,
                        start_date=start_date,
                        end_date=end_date,
                        line_items=line_items
                    )
                )
            else:
                # Generate checklist directly from message
                if not message_content:
                    logger.error(f"Missing message_content for checklist task {request_id}")
                    return False
                    
                logger.info(f"Generating checklist from message for task {request_id}")
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
                self.results_publisher.publish_error(request_id, "Failed to generate checklist data")
                return False
                
            # Convert checklist data to JSON string
            checklist_json = json.dumps(checklist_data)
            
            # Publish the results
            self.results_publisher.publish_completion(request_id, checklist_json)
            
            logger.info(f"Checklist task {request_id} completed successfully")
            return True
            
        except Exception as e:
            logger.error(f"Error processing checklist task {request_id}: {e}")
            
            # Try to publish error via Redis
            try:
                self.results_publisher.publish_error(request_id, str(e))
            except Exception:
                pass
                
            return False
    
    def _process_checkin_task(self, request_id: str, data: Dict[str, Any]) -> bool:
        """
        Process a check-in task.
        
        Args:
            request_id: The request ID
            data: The task data
            
        Returns:
            True if processing was successful, False otherwise
        """
        try:
            # Extract task parameters
            user_id = data.get("user_id")
            user_full_name = data.get("user_full_name")
            checklist_data = data.get("checklist_data")
            alfred_personality = data.get("alfred_personality")
            user_objectives = data.get("user_objectives")
            
            # Validate required parameters
            if not user_id or not checklist_data:
                logger.error(f"Missing required parameters for check-in task {request_id}")
                return False
            
            # Process the check-in analysis
            logger.info(f"Analyzing check-in for user {user_id}, request {request_id}")
            
            # Use the AI service to analyze the checklist
            analysis_json = self.ai_service.analyze_checkin(
                checklist_data=checklist_data,
                user_full_name=user_full_name,
                alfred_personality=alfred_personality,
                user_objectives=user_objectives
            )
            
            # Check if we successfully generated analysis data
            if not analysis_json:
                logger.error(f"Failed to analyze check-in data for task {request_id}")
                self.results_publisher.publish_error(request_id, "Failed to analyze check-in data")
                return False
                
            # Publish the analysis as the result
            self.results_publisher.publish_completion(request_id, analysis_json)
            
            logger.info(f"Check-in task {request_id} completed successfully")
            return True
            
        except Exception as e:
            logger.error(f"Error processing check-in task {request_id}: {e}")
            
            # Try to publish error via Redis
            try:
                self.results_publisher.publish_error(request_id, str(e))
            except Exception:
                pass
                
            return False 