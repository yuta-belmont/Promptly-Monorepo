#!/usr/bin/env python3
"""
Script to set environment variables for the Alfred server.
This script should be imported before running the workers.
"""

import os
import json
import logging
from pathlib import Path
from dotenv import load_dotenv

# Set up logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

def set_environment_variables():
    """Set environment variables for the Alfred server."""
    # Load environment variables from consolidated .env file in the server directory
    env_path = Path(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))) / '.env'
    if env_path.exists():
        logger.info(f"Loading environment variables from {env_path}")
        load_dotenv(dotenv_path=env_path)
    else:
        # Fallback to local .env file if consolidated one doesn't exist
        local_env_path = Path(os.path.dirname(os.path.abspath(__file__))) / '.env'
        if local_env_path.exists():
            logger.info(f"Loading environment variables from {local_env_path}")
            load_dotenv(dotenv_path=local_env_path)
        else:
            logger.warning("No .env file found")
    
    # Get the Firebase service account path from environment variables
    firebase_credentials_path = os.getenv("FIREBASE_SERVICE_ACCOUNT")
    
    # If not set in environment, use the default path
    if not firebase_credentials_path:
        firebase_credentials_path = os.path.join(
            os.path.dirname(os.path.abspath(__file__)),
            "firebase-credentials",
            "alfred-9fa73-firebase-adminsdk-fbsvc-294854bb8e.json"
        )
        os.environ["FIREBASE_SERVICE_ACCOUNT"] = firebase_credentials_path
    
    # Extract project ID from the credentials file if not already set
    if not os.getenv("FIREBASE_PROJECT_ID") and os.path.exists(firebase_credentials_path):
        try:
            with open(firebase_credentials_path, 'r') as f:
                creds_data = json.loads(f.read())
                if 'project_id' in creds_data:
                    os.environ["FIREBASE_PROJECT_ID"] = creds_data['project_id']
                    logger.info(f"Extracted project ID from credentials: {creds_data['project_id']}")
        except Exception as e:
            logger.warning(f"Could not extract project ID from credentials: {e}")
    
    # Check if OpenAI API key is set
    openai_api_key = os.getenv("OPENAI_API_KEY")
    if openai_api_key:
        logger.info("OpenAI API key is set")
    else:
        logger.warning("OpenAI API key is not set. Please set it in the .env file.")
    
    # Log environment variables (excluding sensitive values)
    logger.info(f"FIREBASE_SERVICE_ACCOUNT: {os.environ.get('FIREBASE_SERVICE_ACCOUNT', 'Not set')}")
    logger.info(f"FIREBASE_PROJECT_ID: {os.environ.get('FIREBASE_PROJECT_ID', 'Not set')}")
    logger.info(f"OPENAI_API_KEY: {'Set' if os.environ.get('OPENAI_API_KEY') else 'Not set'}")

# Set environment variables when the module is imported
set_environment_variables() 