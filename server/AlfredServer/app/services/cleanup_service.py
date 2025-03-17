import os
import logging
from datetime import datetime, timedelta
from typing import List, Dict, Any, Optional
from firebase_admin import firestore
from app.services.firebase_service import FirebaseService

# Set up logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

class CleanupService:
    """
    Service for cleaning up old data in Firestore.
    This service handles the deletion of data older than yesterday.
    """
    
    def __init__(self):
        """Initialize the cleanup service with Firebase service."""
        self.firebase_service = FirebaseService()
        self.db = self.firebase_service.db
    
    def _get_date_range_to_keep(self) -> List[str]:
        """
        Get the date range to keep (today and yesterday).
        
        Returns:
            A list of dates in YYYY-MM-DD format to keep
        """
        today = datetime.now().strftime('%Y-%m-%d')
        yesterday = (datetime.now() - timedelta(days=1)).strftime('%Y-%m-%d')
        return [today, yesterday]
    
    def delete_collection(self, collection_ref, batch_size: int = 500) -> int:
        """
        Delete a collection in batches.
        
        Args:
            collection_ref: The reference to the collection to delete
            batch_size: The number of documents to delete in each batch
            
        Returns:
            The number of documents deleted
        """
        docs = collection_ref.limit(batch_size).stream()
        deleted = 0
        
        for doc in docs:
            doc.reference.delete()
            deleted += 1
        
        if deleted >= batch_size:
            return deleted + self.delete_collection(collection_ref, batch_size)
        
        return deleted
    
    def cleanup_old_data(self) -> Dict[str, Any]:
        """
        Clean up Firestore data older than yesterday.
        
        Returns:
            A dictionary with statistics about the cleanup operation
        """
        # Get the dates to keep
        dates_to_keep = self._get_date_range_to_keep()
        logger.info(f"Keeping data for dates: {dates_to_keep}")
        
        # Statistics
        stats = {
            'dates_processed': 0,
            'messages_deleted': 0,
            'checklists_deleted': 0
        }
        
        # Get all date documents
        date_docs = self.db.collection('dates').stream()
        
        for date_doc in date_docs:
            date = date_doc.id
            
            # Skip dates we want to keep
            if date in dates_to_keep:
                logger.info(f"Skipping date {date} as it's in the keep list")
                continue
            
            stats['dates_processed'] += 1
            logger.info(f"Processing date {date} for deletion")
            
            # Delete all messages for this date
            messages_ref = self.db.collection('dates').document(date).collection('messages')
            deleted_count = self.delete_collection(messages_ref)
            stats['messages_deleted'] += deleted_count
            logger.info(f"Deleted {deleted_count} messages for date {date}")
            
            # Delete all checklists for this date
            checklists_ref = self.db.collection('dates').document(date).collection('checklists')
            deleted_count = self.delete_collection(checklists_ref)
            stats['checklists_deleted'] += deleted_count
            logger.info(f"Deleted {deleted_count} checklists for date {date}")
            
            # Update the metadata to remove this date
            try:
                # Remove from active_dates metadata
                metadata_ref = self.db.collection('metadata').document('active_dates')
                metadata_ref.update({
                    date: firestore.DELETE_FIELD
                })
                logger.info(f"Removed date {date} from active_dates metadata")
                
                # Remove from user_dates metadata
                # This is more complex as we need to find all users with this date
                user_dates_ref = self.db.collection('metadata').document('user_dates')
                user_collections = user_dates_ref.collections()
                
                for user_collection in user_collections:
                    user_id = user_collection.id
                    
                    for chat_doc in user_collection.stream():
                        chat_id = chat_doc.id
                        chat_data = chat_doc.to_dict()
                        
                        # Remove date from messages array if present
                        if 'messages' in chat_data and date in chat_data['messages']:
                            user_dates_ref.collection(user_id).document(chat_id).update({
                                'messages': firestore.ArrayRemove([date])
                            })
                        
                        # Remove date from checklists array if present
                        if 'checklists' in chat_data and date in chat_data['checklists']:
                            user_dates_ref.collection(user_id).document(chat_id).update({
                                'checklists': firestore.ArrayRemove([date])
                            })
                
            except Exception as e:
                logger.error(f"Error updating metadata for date {date}: {e}")
        
        logger.info(f"Cleanup completed. Stats: {stats}")
        return stats

def run_cleanup():
    """Run the cleanup operation."""
    cleanup_service = CleanupService()
    stats = cleanup_service.cleanup_old_data()
    print(f"Cleanup completed. Stats: {stats}")
    return stats

if __name__ == "__main__":
    run_cleanup() 