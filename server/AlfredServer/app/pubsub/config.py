"""
Configuration settings for Google Cloud Pub/Sub and Redis.
"""

import os
from dotenv import load_dotenv

# Load environment variables
load_dotenv()

# Google Cloud Project ID
GCP_PROJECT_ID = os.getenv("GCP_PROJECT_ID", "alfred-9fa73")

# Pub/Sub Topic name for unified tasks
UNIFIED_TASKS_TOPIC = os.getenv("UNIFIED_TASKS_TOPIC", "alfred-unified-tasks")

# Pub/Sub Subscription name for unified tasks
UNIFIED_TASKS_SUBSCRIPTION = os.getenv("UNIFIED_TASKS_SUBSCRIPTION", "alfred-unified-tasks-subscription")

# Redis configuration for streaming results
REDIS_HOST = os.getenv("REDIS_HOST", "localhost")
REDIS_PORT = int(os.getenv("REDIS_PORT", "6379"))
REDIS_DB = int(os.getenv("REDIS_DB", "0"))
REDIS_PASSWORD = os.getenv("REDIS_PASSWORD", None) 