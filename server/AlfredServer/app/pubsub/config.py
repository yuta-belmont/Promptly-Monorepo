"""
Configuration settings for Google Cloud Pub/Sub and Redis.
"""

import os
import json
import tempfile
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

# Handle credentials from environment variable
def setup_credentials():
    """
    Set up Google Cloud credentials from environment variables.
    This creates a temporary credentials file if the GOOGLE_CLOUD_CREDENTIALS
    environment variable is set.
    
    Returns:
        The path to the credentials file, or None if using default credentials
    """
    credentials_json = os.getenv("GOOGLE_CLOUD_CREDENTIALS")
    
    # If credentials are provided as an environment variable
    if credentials_json:
        try:
            # Create a temporary file for the credentials
            fd, temp_path = tempfile.mkstemp(suffix='.json')
            with os.fdopen(fd, 'w') as f:
                f.write(credentials_json)
            
            # Set the credentials path environment variable
            os.environ["GOOGLE_APPLICATION_CREDENTIALS"] = temp_path
            return temp_path
        except Exception as e:
            print(f"Error setting up credentials: {e}")
            return None
    
    # Otherwise, use the existing GOOGLE_APPLICATION_CREDENTIALS environment variable
    return None

# Set up credentials at module import time
CREDENTIALS_PATH = setup_credentials() 