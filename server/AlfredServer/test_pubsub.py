#!/usr/bin/env python3
"""
Test script to publish a message to Pub/Sub.
"""

import sys
import os
import time

# Add the project root to the path so we can import app modules
sys.path.append(os.path.dirname(os.path.abspath(__file__)))

# Import the set_env module to set environment variables
import set_env

from app.pubsub.messaging.publisher import TaskPublisher

def main():
    """Publish a test message to Pub/Sub."""
    print("Publishing a test message to Pub/Sub...")
    
    # Initialize the publisher
    publisher = TaskPublisher()
    
    # Publish a test message
    request_id = publisher.publish_message_task(
        user_id="test_user",
        message_content="Hello from Pub/Sub!",
        message_history=[],
        user_full_name="Test User"
    )
    
    print(f"Published message with request_id: {request_id}")
    print("Check the worker logs to see if it was received and processed.")
    
    # Wait a moment to observe the logs
    print("Waiting 5 seconds...")
    time.sleep(5)
    print("Done!")

if __name__ == "__main__":
    main() 