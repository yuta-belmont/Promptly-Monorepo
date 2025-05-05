#!/usr/bin/env python3
"""
Test script to publish tasks to the unified Pub/Sub topic.
"""

import sys
import os
import time
import json
import argparse

# Add the project root to the path so we can import app modules
sys.path.append(os.path.dirname(os.path.abspath(__file__)))

# Import the set_env module to set environment variables
import set_env

from app.pubsub.messaging.publisher import TaskPublisher

def create_message_task():
    """Create a test message task."""
    publisher = TaskPublisher()
    request_id = publisher.publish_to_unified_topic({
        "task_type": "message",
        "user_id": "test_user",
        "message_content": "Hello from the unified Pub/Sub worker!",
        "message_history": [],
        "user_full_name": "Test User"
    })
    return request_id

def create_checklist_task():
    """Create a test checklist task."""
    publisher = TaskPublisher()
    request_id = publisher.publish_to_unified_topic({
        "task_type": "checklist",
        "user_id": "test_user",
        "message_content": "Create a checklist for my day",
        "message_history": [],
        "user_full_name": "Test User"
    })
    return request_id

def create_checkin_task():
    """Create a test check-in task."""
    publisher = TaskPublisher()
    request_id = publisher.publish_to_unified_topic({
        "task_type": "checkin",
        "user_id": "test_user",
        "checklist_data": {
            "date": "2023-01-01",
            "items": [
                {"title": "Exercise", "is_completed": True},
                {"title": "Read a book", "is_completed": False}
            ]
        },
        "user_full_name": "Test User"
    })
    return request_id

def main():
    """Parse arguments and run the specified test."""
    parser = argparse.ArgumentParser(description='Test unified Pub/Sub task publishing')
    parser.add_argument('task_type', choices=['message', 'checklist', 'checkin', 'all'],
                        help='Type of task to publish (or "all" to publish all types)')
    
    args = parser.parse_args()
    
    print(f"Testing unified Pub/Sub task publishing for task type: {args.task_type}")
    
    if args.task_type == 'message' or args.task_type == 'all':
        request_id = create_message_task()
        print(f"Published message task with request_id: {request_id}")
        
    if args.task_type == 'checklist' or args.task_type == 'all':
        request_id = create_checklist_task()
        print(f"Published checklist task with request_id: {request_id}")
        
    if args.task_type == 'checkin' or args.task_type == 'all':
        request_id = create_checkin_task()
        print(f"Published check-in task with request_id: {request_id}")
    
    print("Check the worker logs to see if the tasks were received and processed.")
    print("Waiting 5 seconds...")
    time.sleep(5)
    print("Done!")

if __name__ == "__main__":
    main() 