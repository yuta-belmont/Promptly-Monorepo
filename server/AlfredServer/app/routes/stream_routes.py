"""
Stream-related API routes for real-time delivery of AI responses.
These routes provide Server-Sent Events (SSE) endpoints for streaming.
"""

from fastapi import APIRouter, Request, Response, HTTPException
from fastapi.responses import StreamingResponse
import asyncio
import json
import logging
import redis.asyncio as aioredis
from typing import AsyncGenerator, Optional

from app.pubsub.config import REDIS_HOST, REDIS_PORT, REDIS_DB, REDIS_PASSWORD

router = APIRouter()
logger = logging.getLogger(__name__)

async def create_redis_connection() -> aioredis.Redis:
    """Create an async Redis connection."""
    return await aioredis.Redis(
        host=REDIS_HOST,
        port=REDIS_PORT,
        db=REDIS_DB,
        password=REDIS_PASSWORD,
        decode_responses=True  # Automatically decode responses to strings
    )

async def stream_generator(request_id: str, request: Request) -> AsyncGenerator[str, None]:
    """
    Generate an event stream from Redis Pub/Sub messages.
    
    Args:
        request_id: The unique ID for the request to subscribe to
        request: The FastAPI request object
        
    Yields:
        SSE-formatted events
    """
    redis = await create_redis_connection()
    pubsub = redis.pubsub()
    
    # Subscribe to the channel for this request
    channel = f"ai-stream:{request_id}"
    await pubsub.subscribe(channel)
    
    try:
        # Send an initial event to establish the connection
        yield "event: connected\ndata: {\"request_id\":\"" + request_id + "\"}\n\n"
        
        # Stream messages as they arrive
        while True:
            # Check if client disconnected
            if await request.is_disconnected():
                break
                
            # Get next message, with timeout
            message = await pubsub.get_message(timeout=1.0)
            
            if message and message["type"] == "message":
                data = message["data"]
                
                # Try to parse as JSON
                try:
                    payload = json.loads(data)
                    
                    # Handle different message types
                    if "chunk" in payload:
                        # Text chunk - send as text event
                        yield f"event: text\ndata: {json.dumps(payload)}\n\n"
                    elif "event" in payload and payload["event"] == "DONE":
                        # Completion event - send as completion
                        yield f"event: done\ndata: {json.dumps(payload)}\n\n"
                        # After completion, we can break the loop
                        break
                    elif "event" in payload and payload["event"] == "ERROR":
                        # Error event - send as error
                        yield f"event: error\ndata: {json.dumps(payload)}\n\n"
                        # After error, we should break the loop
                        break
                    else:
                        # Unknown event type - send as raw data
                        yield f"data: {data}\n\n"
                        
                except json.JSONDecodeError:
                    # If not valid JSON, send as raw data
                    yield f"data: {data}\n\n"
            
            # Brief pause to prevent CPU spinning
            await asyncio.sleep(0.01)
            
    except Exception as e:
        logger.error(f"Error in stream_generator: {e}")
        yield f"event: error\ndata: {{\"error\": \"{str(e)}\"}}\n\n"
        
    finally:
        # Always clean up
        await pubsub.unsubscribe(channel)
        await redis.close()
        
@router.get("/api/v1/stream/{request_id}")
async def stream_response(request_id: str, request: Request) -> StreamingResponse:
    """
    Stream an AI response as Server-Sent Events.
    
    Args:
        request_id: The unique ID for the request to subscribe to
        request: The FastAPI request object
        
    Returns:
        A streaming response with SSE events
    """
    return StreamingResponse(
        stream_generator(request_id, request),
        media_type="text/event-stream",
        headers={
            "Cache-Control": "no-cache",
            "Connection": "keep-alive",
            "Content-Type": "text/event-stream"
        }
    ) 