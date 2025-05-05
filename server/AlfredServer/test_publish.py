#!/usr/bin/env python3
import os
import json
import time
import uuid
from google.cloud import pubsub_v1

# Get project ID from environment
project_id = os.environ.get('GOOGLE_CLOUD_PROJECT')
if not project_id:
    print("GOOGLE_CLOUD_PROJECT environment variable not set")
    exit(1)

# Create publisher client
publisher = pubsub_v1.PublisherClient()

# Topic name
topic_name = 'alfred-unified-tasks'
topic_path = publisher.topic_path(project_id, topic_name)

# Create a unique request ID
request_id = f"test-{uuid.uuid4()}"
current_time = time.time()

# Create a more complete test message with correct structure
message = {
    "task_type": "message",
    "request_id": request_id,
    "user_id": "test-user",
    "message_content": "Hello from the Pub/Sub test!",
    "message_history": [],
    "user_full_name": "Test User",
    "client_time": current_time,
    "openai_model": "gpt-4",
    "temperature": 0.7,
    "timestamp": current_time
}

# Publish the message
data = json.dumps(message).encode('utf-8')
future = publisher.publish(topic_path, data)
message_id = future.result()

print(f"Published message with ID: {message_id}")
print(f"Message content: {json.dumps(message, indent=2)}")
print(f"Request ID: {request_id}")
print(f"Check the worker logs to see if it was processed correctly.") 