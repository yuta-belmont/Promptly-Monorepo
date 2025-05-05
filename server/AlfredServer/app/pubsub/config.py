"""
Configuration settings for Google Cloud Pub/Sub and Redis.
"""

import os
from dotenv import load_dotenv

# Load environment variables
load_dotenv()

# Google Cloud Project ID
GCP_PROJECT_ID = os.getenv("GCP_PROJECT_ID", "your-project-id")

# Pub/Sub Topic names
MESSAGE_TASKS_TOPIC = os.getenv("MESSAGE_TASKS_TOPIC", "alfred-message-tasks")
CHECKLIST_TASKS_TOPIC = os.getenv("CHECKLIST_TASKS_TOPIC", "alfred-checklist-tasks")
CHECKIN_TASKS_TOPIC = os.getenv("CHECKIN_TASKS_TOPIC", "alfred-checkin-tasks")
UNIFIED_TASKS_TOPIC = os.getenv("UNIFIED_TASKS_TOPIC", "alfred-unified-tasks")

# Pub/Sub Subscription names
MESSAGE_TASKS_SUBSCRIPTION = os.getenv("MESSAGE_TASKS_SUBSCRIPTION", "alfred-message-tasks-subscription")
CHECKLIST_TASKS_SUBSCRIPTION = os.getenv("CHECKLIST_TASKS_SUBSCRIPTION", "alfred-checklist-tasks-subscription")
CHECKIN_TASKS_SUBSCRIPTION = os.getenv("CHECKIN_TASKS_SUBSCRIPTION", "alfred-checkin-tasks-subscription")
UNIFIED_TASKS_SUBSCRIPTION = os.getenv("UNIFIED_TASKS_SUBSCRIPTION", "alfred-unified-tasks-subscription")

# Redis configuration for streaming results
REDIS_HOST = os.getenv("REDIS_HOST", "localhost")
REDIS_PORT = int(os.getenv("REDIS_PORT", "6379"))
REDIS_DB = int(os.getenv("REDIS_DB", "0"))
REDIS_PASSWORD = os.getenv("REDIS_PASSWORD", None) 