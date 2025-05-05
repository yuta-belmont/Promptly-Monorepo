"""
Base worker class for consuming tasks from Pub/Sub.
"""

import json
import logging
import threading
import time
import traceback
from typing import Dict, Any, Optional
from google.cloud import pubsub_v1
from google.api_core.exceptions import GoogleAPICallError

from app.pubsub.config import GCP_PROJECT_ID
from app.pubsub.messaging.redis_publisher import ResultsPublisher

logger = logging.getLogger(__name__)

class PubSubWorker:
    """Base class for workers that consume tasks from Pub/Sub."""
    
    def __init__(self, subscription_id: str, worker_id: Optional[str] = None):
        """
        Initialize the worker.
        
        Args:
            subscription_id: The subscription ID to listen to
            worker_id: A unique identifier for this worker instance (defaults to a timestamp)
        """
        self.project_id = GCP_PROJECT_ID
        self.subscription_id = subscription_id
        self.worker_id = worker_id or f"worker-{int(time.time())}"
        self.running = False
        
        # Initialize Pub/Sub subscriber client
        self.subscriber = pubsub_v1.SubscriberClient()
        self.subscription_path = self.subscriber.subscription_path(
            self.project_id, self.subscription_id
        )
        
        # Initialize Redis publisher for streaming results
        self.results_publisher = ResultsPublisher()
        
        self.max_retries = 5  # Maximum number of retry attempts
        self.retry_counts = {}  # Track retry counts per message
        
        logger.info(f"Worker {self.worker_id} initialized for subscription {self.subscription_id}")
    
    def process_message(self, message):
        """
        Process a message from Pub/Sub.
        
        This method is a wrapper around _process_message that provides error handling.
        Subclasses should override _process_message, not this method.
        
        Args:
            message: The Pub/Sub message
        """
        try:
            # Extract request ID for correlation
            data = json.loads(message.data.decode("utf-8"))
            request_id = data.get("request_id", "unknown")
            
            logger.info(f"Worker {self.worker_id} processing message {request_id}")
            
            # Call the implementation in the subclass
            success = self._process_message(data)
            
            if success:
                # Acknowledge the message
                message.ack()
                # Reset retry count on success
                if request_id in self.retry_counts:
                    del self.retry_counts[request_id]
                logger.info(f"Message {request_id} processed successfully")
            else:
                # Check retry count
                retry_count = self.retry_counts.get(request_id, 0) + 1
                self.retry_counts[request_id] = retry_count
                
                if retry_count <= self.max_retries:
                    # Negative acknowledge to retry
                    message.nack()
                    logger.warning(f"Message {request_id} processing failed, retry {retry_count}/{self.max_retries}")
                else:
                    # Max retries reached, acknowledge to stop retrying
                    message.ack()
                    logger.error(f"Message {request_id} processing failed after {self.max_retries} retries, giving up")
                    # Publish error via Redis
                    try:
                        self.results_publisher.publish_error(
                            request_id, 
                            f"Processing failed after {self.max_retries} retries"
                        )
                    except Exception as e:
                        logger.error(f"Error publishing failure via Redis: {e}")
                
        except json.JSONDecodeError as e:
            logger.error(f"Error decoding message: {e}")
            # This message will never process correctly, so acknowledge it
            message.ack()
        except Exception as e:
            logger.error(f"Error processing message: {e}")
            logger.error(traceback.format_exc())
            # Check retry count using message ID if request_id not available
            message_id = message.message_id if hasattr(message, 'message_id') else 'unknown'
            retry_key = message_id if 'request_id' not in locals() else locals()['request_id']
            
            retry_count = self.retry_counts.get(retry_key, 0) + 1
            self.retry_counts[retry_key] = retry_count
            
            if retry_count <= self.max_retries:
                # Negative acknowledge to retry
                message.nack()
                logger.warning(f"Message {retry_key} processing failed, retry {retry_count}/{self.max_retries}")
            else:
                # Max retries reached, acknowledge to stop retrying
                message.ack()
                logger.error(f"Message {retry_key} processing failed after {self.max_retries} retries, giving up")
    
    def _process_message(self, data: Dict[str, Any]) -> bool:
        """
        Process the message data.
        
        This method should be overridden by subclasses to implement specific task processing.
        
        Args:
            data: The decoded message data
            
        Returns:
            True if processing was successful, False otherwise
        """
        logger.warning("Base class _process_message called, no processing performed")
        return False
    
    def start(self):
        """Start the worker."""
        if self.running:
            logger.warning(f"Worker {self.worker_id} already running")
            return
            
        self.running = True
        
        # Configure flow control - adjust based on your performance needs
        flow_control = pubsub_v1.types.FlowControl(max_messages=10)
        
        logger.info(f"Worker {self.worker_id} starting on {self.subscription_path}")
        
        # Subscribe to the subscription
        self.streaming_pull_future = self.subscriber.subscribe(
            self.subscription_path, 
            callback=self.process_message,
            flow_control=flow_control
        )
        
        logger.info(f"Worker {self.worker_id} started successfully")
        
        try:
            # Keep the worker running until stop() is called or an error occurs
            self.streaming_pull_future.result()
        except Exception as e:
            logger.error(f"Worker {self.worker_id} encountered an error: {e}")
            self.running = False
    
    def stop(self):
        """Stop the worker."""
        if not self.running:
            logger.warning(f"Worker {self.worker_id} not running")
            return
            
        logger.info(f"Stopping worker {self.worker_id}")
        
        # Cancel the streaming pull
        if hasattr(self, 'streaming_pull_future'):
            self.streaming_pull_future.cancel()
            
        # Close the subscriber client
        self.subscriber.close()
        
        self.running = False
        logger.info(f"Worker {self.worker_id} stopped") 