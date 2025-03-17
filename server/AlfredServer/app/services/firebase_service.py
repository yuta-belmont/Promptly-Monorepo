import os
import json
import firebase_admin
from firebase_admin import credentials, firestore
from typing import Dict, Any, List, Optional
from datetime import datetime, timedelta
import logging
from dotenv import load_dotenv
from app.utils.firestore_utils import convert_firestore_data

# Load environment variables
load_dotenv()

logger = logging.getLogger(__name__)

class FirebaseService:
    """
    Service for interacting with Firebase Firestore.
    This service handles the creation and management of asynchronous tasks
    for OpenAI API calls.
    """
    _instance = None
    
    def __new__(cls):
        """Singleton pattern to ensure only one Firebase connection."""
        if cls._instance is None:
            cls._instance = super(FirebaseService, cls).__new__(cls)
            cls._instance._initialized = False
        return cls._instance
    
    def __init__(self):
        """Initialize the Firebase connection if not already initialized."""
        if self._initialized:
            return
            
        try:
            # Get the path to the service account key file from environment variables
            service_account_path = os.getenv(
                "FIREBASE_SERVICE_ACCOUNT", 
                os.path.join(os.path.dirname(os.path.dirname(os.path.dirname(__file__))), 
                            "firebase-credentials.json")
            )
            
            # Get the Firebase project ID from environment variables
            project_id = os.getenv("FIREBASE_PROJECT_ID")
            
            print(f"[FIREBASE] Initializing Firebase with project ID: {project_id}")
            print(f"[FIREBASE] Service account path: {service_account_path}")
            
            # Check if the file exists
            if not os.path.exists(service_account_path):
                logger.warning(f"Firebase credentials file not found at {service_account_path}")
                
                if project_id:
                    logger.info(f"Using application default credentials with project ID: {project_id}")
                    print(f"[FIREBASE] Using application default credentials with project ID: {project_id}")
                    # Initialize with application default credentials and project ID
                    if not firebase_admin._apps:
                        firebase_admin.initialize_app(options={
                            'projectId': project_id,
                        })
                else:
                    logger.warning("Using application default credentials without project ID")
                    print(f"[FIREBASE] Using application default credentials without project ID")
                    # Initialize without credentials (will use application default credentials)
                    if not firebase_admin._apps:
                        firebase_admin.initialize_app()
            else:
                logger.info(f"Using service account credentials from {service_account_path}")
                print(f"[FIREBASE] Using service account credentials from {service_account_path}")
                # Initialize with service account credentials
                if not firebase_admin._apps:
                    cred = credentials.Certificate(service_account_path)
                    firebase_admin.initialize_app(cred)
            
            # Get Firestore client
            self.db = firestore.client()
            self._initialized = True
            logger.info("Firebase initialized successfully")
            print(f"[FIREBASE] Firebase initialized successfully with project: {project_id}")
            
        except Exception as e:
            logger.error(f"Error initializing Firebase: {e}")
            print(f"[FIREBASE] Error initializing Firebase: {e}")
            raise

    # MARK: - Task Management
    
    def add_checklist_task(self,
                          user_id: str,
                          chat_id: str,
                          message_id: str,
                          message_content: str,
                          message_history: List[Dict[str, Any]]) -> str:
        """
        Add a checklist generation task to Firestore.
        
        Args:
            user_id: The ID of the user
            chat_id: The ID of the chat
            message_id: The ID of the message
            message_content: The content of the user's message
            message_history: The history of messages in the chat
            
        Returns:
            The ID of the created task
        """
        try:
            # Create a reference to the checklist tasks collection
            task_ref = self.db.collection('checklist_tasks').document()
            
            # Set the task data
            task_data = {
                'status': 'pending',
                'user_id': user_id,
                'chat_id': chat_id,
                'message_id': message_id,
                'message_content': message_content,
                'message_history': message_history,
                'created_at': firestore.SERVER_TIMESTAMP,
                'updated_at': firestore.SERVER_TIMESTAMP
            }
            task_ref.set(task_data)
            
            print(f"[FIREBASE] Added checklist task {task_ref.id} for user {user_id}, chat {chat_id}, message {message_id}")
            logger.info(f"Added checklist task {task_ref.id} for user {user_id}, chat {chat_id}")
            return task_ref.id
            
        except Exception as e:
            logger.error(f"Error adding checklist task: {e}")
            print(f"[FIREBASE] Error adding checklist task: {e}")
            raise
    
    def update_task_status(self, collection: str, task_id: str, status: str, data: Optional[Dict[str, Any]] = None) -> None:
        """
        Update the status of a task in Firestore.
        
        Args:
            collection: The collection name ('message_tasks' or 'checklist_tasks')
            task_id: The ID of the task
            status: The new status ('pending', 'processing', 'completed', 'failed')
            data: Additional data to update (optional)
        """
        try:
            # Create a reference to the task document
            task_ref = self.db.collection(collection).document(task_id)
            
            # Prepare the update data
            update_data = {
                'status': status,
                'updated_at': firestore.SERVER_TIMESTAMP
            }
            
            # Add any additional data
            if data:
                # If this is a completed checklist task and we have checklist_data, add it as generated_content
                if status == 'completed' and collection == 'checklist_tasks' and 'checklist_data' in data and 'generated_content' not in data:
                    data['generated_content'] = json.dumps(data['checklist_data'])
                
                update_data.update(data)
            
            # Update the task
            task_ref.update(update_data)
            
            print(f"[FIREBASE] Updated {collection} task {task_id} status to {status}")
            logger.info(f"Updated {collection} task {task_id} status to {status}")
            
        except Exception as e:
            logger.error(f"Error updating task status: {e}")
            print(f"[FIREBASE] Error updating task status: {e}")
            raise
    
    def get_pending_tasks(self, collection: str, limit: int = 10) -> List[Dict[str, Any]]:
        """
        Get pending tasks from Firestore.
        
        Args:
            collection: The collection name ('message_tasks' or 'checklist_tasks')
            limit: The maximum number of tasks to return
            
        Returns:
            A list of pending tasks
        """
        try:
            # Use a simpler query that doesn't require a composite index
            query = self.db.collection(collection).where('status', '==', 'pending')
            
            # Get the results
            tasks = []
            for doc in query.stream():
                task_data = doc.to_dict()
                task_data['id'] = doc.id
                # Convert Firestore data types to JSON serializable types
                task_data = convert_firestore_data(task_data)
                tasks.append(task_data)
            
            if tasks:
                # Sort tasks by created_at in Python instead of in the query
                tasks.sort(key=lambda x: x.get('created_at', 0))
                # Limit the number of tasks
                tasks = tasks[:limit]
                
                logger.info(f"Found {len(tasks)} pending tasks in {collection}")
            
            return tasks
            
        except Exception as e:
            logger.error(f"Error getting pending tasks: {e}")
            return []
    
    def get_task_status(self, collection: str, task_id: str) -> Optional[Dict[str, Any]]:
        """
        Get the status of a task.
        
        Args:
            collection: The collection name ('message_tasks' or 'checklist_tasks')
            task_id: The ID of the task
            
        Returns:
            The task data, or None if the task doesn't exist
        """
        try:
            # Get the task document
            task_doc = self.db.collection(collection).document(task_id).get()
            
            if task_doc.exists:
                task_data = task_doc.to_dict()
                task_data['id'] = task_doc.id
                # Convert Firestore data types to JSON serializable types
                task_data = convert_firestore_data(task_data)
                return task_data
            
            return None
            
        except Exception as e:
            logger.error(f"Error getting task status: {e}")
            return None
    
    def update_checklist_task(self, task_id: str, message_id: str) -> None:
        """
        Update the message ID of a checklist task in Firestore.
        
        Args:
            task_id: The ID of the task
            message_id: The new message ID
        """
        try:
            # Create a reference to the task document
            task_ref = self.db.collection('checklist_tasks').document(task_id)
            
            # Update the message ID
            task_ref.update({
                'message_id': message_id,
                'updated_at': firestore.SERVER_TIMESTAMP
            })
            
            print(f"[FIREBASE] Updated checklist task {task_id} with message ID {message_id}")
            logger.info(f"Updated checklist task {task_id} with message ID {message_id}")
            
        except Exception as e:
            logger.error(f"Error updating checklist task: {e}")
            print(f"[FIREBASE] Error updating checklist task: {e}")
            # Don't raise the exception, as this is a non-critical operation
    
    def store_checklist(self, user_id: str, chat_id: str, message_id: str, checklist_content: Dict[str, Any]) -> None:
        """
        Store the generated checklist data in Firestore.
        
        Args:
            user_id: The ID of the user
            chat_id: The ID of the chat
            message_id: The ID of the message
            checklist_content: The generated checklist content
        """
        try:
            # Create a reference to the task document
            task_ref = self.db.collection('checklist_tasks').document()
            
            # Set the task data
            task_data = {
                'user_id': user_id,
                'chat_id': chat_id,
                'message_id': message_id,
                'generated_content': json.dumps(checklist_content),
                'created_at': firestore.SERVER_TIMESTAMP,
                'updated_at': firestore.SERVER_TIMESTAMP,
                'status': 'completed'
            }
            
            # Set the document
            task_ref.set(task_data)
            
            print(f"[FIREBASE] Stored checklist data for user {user_id}, chat {chat_id}")
            logger.info(f"Stored checklist data for user {user_id}, chat {chat_id}")
            
        except Exception as e:
            logger.error(f"Error storing checklist data: {e}")
            print(f"[FIREBASE] Error storing checklist data: {e}")
            raise 