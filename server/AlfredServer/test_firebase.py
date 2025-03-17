#!/usr/bin/env python3
"""
Test script to verify Firebase connection.
"""

import os
import sys
import logging
import json

# Add the project root to the path so we can import app modules
sys.path.append(os.path.dirname(os.path.abspath(__file__)))

# Set up logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

def test_firebase_connection():
    """Test the Firebase connection by adding and retrieving a test document."""
    try:
        # Set environment variables for Firebase
        os.environ["FIREBASE_SERVICE_ACCOUNT"] = os.path.join(
            os.path.dirname(os.path.abspath(__file__)),
            "firebase-credentials",
            "alfred-9fa73-firebase-adminsdk-fbsvc-294854bb8e.json"  # Use the new credentials file
        )
        
        # Extract project ID from the credentials file
        credentials_path = os.environ["FIREBASE_SERVICE_ACCOUNT"]
        if os.path.exists(credentials_path):
            try:
                with open(credentials_path, 'r') as f:
                    creds_data = json.loads(f.read())
                    if 'project_id' in creds_data:
                        os.environ["FIREBASE_PROJECT_ID"] = creds_data['project_id']
                        logger.info(f"Extracted project ID from credentials: {creds_data['project_id']}")
            except Exception as e:
                logger.warning(f"Could not extract project ID from credentials: {e}")
        
        # Print environment variables for debugging
        service_account_path = os.environ.get("FIREBASE_SERVICE_ACCOUNT", "Not set")
        project_id = os.environ.get("FIREBASE_PROJECT_ID", "Not set")
        
        logger.info(f"FIREBASE_SERVICE_ACCOUNT: {service_account_path}")
        logger.info(f"FIREBASE_PROJECT_ID: {project_id}")
        
        # Check if the service account file exists
        if os.path.exists(service_account_path):
            logger.info(f"Service account file exists at: {service_account_path}")
        else:
            logger.warning(f"Service account file does NOT exist at: {service_account_path}")
            # Try to find the file in the firebase-credentials directory
            credentials_dir = os.path.join(os.path.dirname(os.path.abspath(__file__)), "firebase-credentials")
            logger.info(f"Checking credentials directory: {credentials_dir}")
            if os.path.exists(credentials_dir):
                files = os.listdir(credentials_dir)
                logger.info(f"Files in credentials directory: {files}")
        
        # Import Firebase service after logging
        from app.services.firebase_service import FirebaseService
        from firebase_admin import firestore
        
        # Initialize Firebase service
        firebase_service = FirebaseService()
        
        # Add a test document
        test_collection = 'test_collection'
        test_doc_ref = firebase_service.db.collection(test_collection).document()
        test_doc_ref.set({
            'test_field': 'test_value',
            'timestamp': firestore.SERVER_TIMESTAMP
        })
        
        logger.info(f"Added test document with ID: {test_doc_ref.id}")
        
        # Retrieve the test document
        test_doc = test_doc_ref.get()
        logger.info(f"Retrieved test document: {test_doc.to_dict()}")
        
        # Delete the test document
        test_doc_ref.delete()
        logger.info(f"Deleted test document with ID: {test_doc_ref.id}")
        
        logger.info("Firebase connection test successful!")
        return True
        
    except Exception as e:
        logger.error(f"Firebase connection test failed: {e}")
        return False

if __name__ == "__main__":
    test_firebase_connection() 