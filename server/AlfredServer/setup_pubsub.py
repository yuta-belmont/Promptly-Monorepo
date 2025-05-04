#!/usr/bin/env python3
"""
Script to set up Google Cloud Pub/Sub topics and subscriptions.
This only needs to be run once to set up the infrastructure.
"""

import os
import sys
import argparse
from google.cloud import pubsub_v1

# Add the project root to the path so we can import app modules
sys.path.append(os.path.dirname(os.path.abspath(__file__)))

# Import config to get topic and subscription names
from app.pubsub.config import (
    GCP_PROJECT_ID,
    MESSAGE_TASKS_TOPIC,
    CHECKLIST_TASKS_TOPIC,
    CHECKIN_TASKS_TOPIC,
    MESSAGE_TASKS_SUBSCRIPTION,
    CHECKLIST_TASKS_SUBSCRIPTION,
    CHECKIN_TASKS_SUBSCRIPTION
)

def create_topic_if_not_exists(publisher_client, project_id, topic_id):
    """
    Create a topic if it doesn't already exist.
    
    Args:
        publisher_client: The Pub/Sub publisher client
        project_id: The GCP project ID
        topic_id: The topic ID to create
        
    Returns:
        The topic path
    """
    topic_path = publisher_client.topic_path(project_id, topic_id)
    
    try:
        topic = publisher_client.get_topic(request={"topic": topic_path})
        print(f"Topic {topic_id} already exists")
    except Exception:
        topic = publisher_client.create_topic(request={"name": topic_path})
        print(f"Created topic {topic_id}")
    
    return topic_path

def create_subscription_if_not_exists(subscriber_client, project_id, subscription_id, topic_path):
    """
    Create a subscription if it doesn't already exist.
    
    Args:
        subscriber_client: The Pub/Sub subscriber client
        project_id: The GCP project ID
        subscription_id: The subscription ID to create
        topic_path: The topic path to subscribe to
    """
    subscription_path = subscriber_client.subscription_path(project_id, subscription_id)
    
    try:
        subscription = subscriber_client.get_subscription(request={"subscription": subscription_path})
        print(f"Subscription {subscription_id} already exists")
    except Exception:
        subscription = subscriber_client.create_subscription(
            request={"name": subscription_path, "topic": topic_path}
        )
        print(f"Created subscription {subscription_id}")

def parse_arguments():
    """Parse command line arguments."""
    parser = argparse.ArgumentParser(description='Set up Google Cloud Pub/Sub topics and subscriptions')
    
    parser.add_argument('--project-id', type=str, default=GCP_PROJECT_ID,
                        help='Google Cloud Project ID (default from config)')
    
    return parser.parse_args()

def main():
    """Main entry point for the script."""
    # Parse command line arguments
    args = parse_arguments()
    project_id = args.project_id
    
    print(f"Setting up Pub/Sub topics and subscriptions for project {project_id}")
    
    # Create publisher and subscriber clients
    publisher_client = pubsub_v1.PublisherClient()
    subscriber_client = pubsub_v1.SubscriberClient()
    
    # Dictionary mapping topic IDs to subscription IDs
    topic_subscriptions = {
        MESSAGE_TASKS_TOPIC: MESSAGE_TASKS_SUBSCRIPTION,
        CHECKLIST_TASKS_TOPIC: CHECKLIST_TASKS_SUBSCRIPTION,
        CHECKIN_TASKS_TOPIC: CHECKIN_TASKS_SUBSCRIPTION
    }
    
    # Create topics and subscriptions
    for topic_id, subscription_id in topic_subscriptions.items():
        # Create topic
        topic_path = create_topic_if_not_exists(publisher_client, project_id, topic_id)
        
        # Create subscription
        create_subscription_if_not_exists(subscriber_client, project_id, subscription_id, topic_path)
    
    print("Pub/Sub setup complete")

if __name__ == "__main__":
    main() 