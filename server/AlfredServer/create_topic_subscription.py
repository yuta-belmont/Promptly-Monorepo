#!/usr/bin/env python3
import os
from google.cloud import pubsub_v1

# Get project ID from environment
project_id = os.environ.get('GOOGLE_CLOUD_PROJECT')
if not project_id:
    print("GOOGLE_CLOUD_PROJECT environment variable not set")
    exit(1)

# Create publisher and subscriber clients
publisher = pubsub_v1.PublisherClient()
subscriber = pubsub_v1.SubscriberClient()

# Topic and subscription names
topic_name = 'alfred-unified-tasks'
subscription_name = 'alfred-unified-tasks-subscription'

# Create full paths
topic_path = publisher.topic_path(project_id, topic_name)
subscription_path = subscriber.subscription_path(project_id, subscription_name)

# Create the topic
try:
    topic = publisher.create_topic(request={"name": topic_path})
    print(f"Topic created: {topic.name}")
except Exception as e:
    print(f"Topic creation error (may already exist): {e}")

# Create the subscription
try:
    subscription = subscriber.create_subscription(
        request={"name": subscription_path, "topic": topic_path}
    )
    print(f"Subscription created: {subscription.name}")
except Exception as e:
    print(f"Subscription creation error (may already exist): {e}")

# List all topics and subscriptions to verify
print("\nVerifying configuration:")
try:
    topics = publisher.list_topics(request={"project": f"projects/{project_id}"})
    print("Available topics:")
    for topic in topics:
        print(f"  {topic.name}")
except Exception as e:
    print(f"Error listing topics: {e}")

try:
    subscriptions = subscriber.list_subscriptions(request={"project": f"projects/{project_id}"})
    print("Available subscriptions:")
    for subscription in subscriptions:
        print(f"  {subscription.name}")
except Exception as e:
    print(f"Error listing subscriptions: {e}") 