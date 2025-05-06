"""
Module for publishing streaming results to Redis Pub/Sub.
This enables real-time streaming of AI responses to clients.
"""

import json
import logging
from typing import Dict, Any, Optional
import redis

from app.pubsub.config import REDIS_HOST, REDIS_PORT, REDIS_DB, REDIS_PASSWORD

logger = logging.getLogger(__name__)

class ResultsPublisher:
    """Handles publishing streaming results to Redis Pub/Sub."""
    
    _instance = None
    
    def __new__(cls):
        """Singleton pattern to ensure only one Redis publisher instance."""
        if cls._instance is None:
            cls._instance = super(ResultsPublisher, cls).__new__(cls)
            cls._instance._initialized = False
        return cls._instance
    
    def __init__(self):
        """Initialize the Redis publisher if not already initialized."""
        if self._initialized:
            return
            
        try:
            self.redis = redis.Redis(
                host=REDIS_HOST,
                port=REDIS_PORT,
                db=REDIS_DB,
                password=REDIS_PASSWORD,
                socket_timeout=5,
                socket_connect_timeout=5
            )
            # Test connection
            self.redis.ping()
            self._initialized = True
            logger.info(f"Redis publisher initialized - {REDIS_HOST}:{REDIS_PORT}")
        except redis.ConnectionError as e:
            logger.error(f"Error connecting to Redis: {e}")
            # Initialize with a dummy implementation that logs but doesn't fail
            self._initialized = True
            self._redis_available = False
            logger.warning("Redis unavailable - running in logging-only mode")
        except Exception as e:
            logger.error(f"Error initializing Redis publisher: {e}")
            raise
    
    def publish_chunk(self, request_id: str, chunk_data: str) -> bool:
        """
        Publish a chunk of streaming data to Redis.
        
        Args:
            request_id: The unique ID for the request (correlates with the task)
            chunk_data: The chunk of text data to publish
            
        Returns:
            True if publishing was successful
        """
        try:
            if not hasattr(self, '_redis_available') or self._redis_available:
                channel = f"ai-stream:{request_id}"
                message = json.dumps({"chunk": chunk_data})
                
                # Publish to Redis
                result = self.redis.publish(channel, message)
                
                if result > 0:
                    logger.debug(f"Published chunk to {channel}, {len(chunk_data)} chars")
                    return True
                else:
                    logger.warning(f"No subscribers for channel {channel}")
                    return False
            else:
                # Redis unavailable, just log the chunk
                logger.info(f"CHUNK [{request_id}]: {chunk_data[:50]}...")
                return True
                
        except Exception as e:
            logger.error(f"Error publishing chunk to Redis: {e}")
            # Log the chunk anyway so we don't lose data
            logger.info(f"CHUNK (error) [{request_id}]: {chunk_data[:50]}...")
            return False
    
    def publish_completion(self, request_id: str, full_text: Optional[str] = None) -> bool:
        """
        Publish a completion event to signal the end of a stream.
        
        Args:
            request_id: The unique ID for the request
            full_text: Optional complete text (if you want to include it)
            
        Returns:
            True if publishing was successful
        """
        try:
            if not hasattr(self, '_redis_available') or self._redis_available:
                channel = f"ai-stream:{request_id}"
                message_data = {"event": "DONE"}
                
                # Include full text if provided
                if full_text:
                    message_data["full_text"] = full_text
                    # Log the full_text content for debugging
                    logger.info(f"DEBUG REDIS PUBLISHER: Publishing completion with full_text for {request_id}")
                    logger.info(f"DEBUG REDIS PUBLISHER: First 100 chars of full_text: {full_text[:100]}")
                    
                    # Try parsing the full_text as JSON for detailed logging
                    try:
                        json_data = json.loads(full_text)
                        logger.info(f"DEBUG REDIS PUBLISHER: full_text is valid JSON with keys: {list(json_data.keys())}")
                        
                        # Special logging for outline data
                        if "outline" in json_data:
                            logger.info(f"DEBUG REDIS PUBLISHER: Contains OUTLINE data")
                        elif "checklist_data" in json_data:
                            logger.info(f"DEBUG REDIS PUBLISHER: Contains CHECKLIST data")
                    except json.JSONDecodeError:
                        logger.info(f"DEBUG REDIS PUBLISHER: full_text is not valid JSON")
                    
                message = json.dumps(message_data)
                
                # Publish to Redis
                result = self.redis.publish(channel, message)
                
                if result > 0:
                    logger.info(f"Published completion event to {channel}")
                    return True
                else:
                    logger.warning(f"No subscribers for channel {channel}")
                    return False
            else:
                # Redis unavailable, just log the completion
                logger.info(f"COMPLETION [{request_id}]")
                return True
                
        except Exception as e:
            logger.error(f"Error publishing completion to Redis: {e}")
            # Log the completion anyway
            logger.info(f"COMPLETION (error) [{request_id}]")
            return False
    
    def publish_error(self, request_id: str, error_message: str) -> bool:
        """
        Publish an error event.
        
        Args:
            request_id: The unique ID for the request
            error_message: The error message
            
        Returns:
            True if publishing was successful
        """
        try:
            if not hasattr(self, '_redis_available') or self._redis_available:
                channel = f"ai-stream:{request_id}"
                message = json.dumps({
                    "event": "ERROR",
                    "error": error_message
                })
                
                # Publish to Redis
                result = self.redis.publish(channel, message)
                
                if result > 0:
                    logger.info(f"Published error event to {channel}: {error_message}")
                    return True
                else:
                    logger.warning(f"No subscribers for channel {channel}")
                    return False
            else:
                # Redis unavailable, just log the error
                logger.info(f"ERROR [{request_id}]: {error_message}")
                return True
                
        except Exception as e:
            logger.error(f"Error publishing error to Redis: {e}")
            # Log the error anyway
            logger.info(f"ERROR (error) [{request_id}]: {error_message}")
            return False
    
    def publish_event(self, request_id: str, event_type: str, event_data: Dict[str, Any]) -> bool:
        """
        Publish a custom event type with data to Redis.
        
        This method is used for progressive field-by-field streaming of structured data
        like outlines, checklists, and check-ins.
        
        Args:
            request_id: The unique ID for the request
            event_type: The custom event type (e.g., 'outline_start', 'outline_summary')
            event_data: The event data to publish
            
        Returns:
            True if publishing was successful
        """
        try:
            if not hasattr(self, '_redis_available') or self._redis_available:
                channel = f"ai-stream:{request_id}"
                
                # Always include the request_id in the event data for correlation
                payload = event_data.copy()
                payload["request_id"] = request_id
                
                message = json.dumps({
                    "event": event_type,
                    "data": payload
                })
                
                # Add debug logging for request ID flow
                logger.info(f"DEBUG REQUEST FLOW: Publishing {event_type} event to channel {channel} with request_id: {request_id}")
                
                # Publish to Redis
                result = self.redis.publish(channel, message)
                
                if result > 0:
                    logger.info(f"Published {event_type} event to {channel}")
                    logger.debug(f"Event data: {json.dumps(payload)[:200]}...")
                    return True
                else:
                    logger.warning(f"No subscribers for channel {channel}")
                    return False
            else:
                # Redis unavailable, just log the event
                logger.info(f"EVENT [{request_id}]: {event_type} with data: {json.dumps(event_data)[:50]}...")
                return True
                
        except Exception as e:
            logger.error(f"Error publishing {event_type} event to Redis: {e}")
            # Log the event anyway
            logger.info(f"EVENT (error) [{request_id}]: {event_type}")
            return False 