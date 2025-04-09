#!/usr/bin/env python3
"""
Test script to measure the throughput of processing expired tasks.
Creates tasks across all task types and measures processing time by WORKERS.
"""

import os
import sys
import time
import asyncio
import signal
import logging
import argparse
from datetime import datetime
from typing import Set, Dict, List, Any
from firebase_admin import firestore

# Add the project root to the path
sys.path.append(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from app.services.firebase_service import FirebaseService

# Set up logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

# Configuration
NUM_TASKS = 300  # Create 300 tasks (100 per collection)
BATCH_SIZE = 50  # Process 50 tasks at a time
QUERY_BATCH_SIZE = 25  # Match the default batch size in Firebase service
DEFAULT_MAX_WAIT = 300  # Default max wait time (5 minutes)

class ThroughputTester:
    def __init__(self, max_wait_time=DEFAULT_MAX_WAIT, skip_cleanup=False):
        self.firebase_service = FirebaseService()
        self.task_ids: Dict[str, Set[str]] = {
            self.firebase_service.MESSAGE_TASKS_COLLECTION: set(),
            self.firebase_service.CHECKLIST_TASKS_COLLECTION: set(),
            self.firebase_service.CHECKIN_TASKS_COLLECTION: set()
        }
        self.start_time = None
        self.end_time = None
        self.shutdown = False
        self.max_wait_time = max_wait_time
        self.skip_cleanup = skip_cleanup
        
        # Statistics tracking
        self.tasks_processed_by_workers = 0
        self.tasks_still_pending = 0
        self.collection_stats = {
            collection: {'processed': 0, 'pending': 0}
            for collection in self.task_ids.keys()
        }
    
    def create_message_task(self) -> Dict:
        """Create a message task with required fields."""
        # Create timestamp from 10 minutes ago
        expired_timestamp = time.time() - 600
        return {
            'status': 'pending',
            'created_at': expired_timestamp,
            'updated_at': expired_timestamp,
            'user_id': 'test_user',
            'user_full_name': 'Test User',
            'message_content': 'Test message',
            'message_history': [],
            'collection': self.firebase_service.MESSAGE_TASKS_COLLECTION
        }
    
    def create_checklist_task(self) -> Dict:
        """Create a checklist task with required fields."""
        # Create timestamp from 10 minutes ago
        expired_timestamp = time.time() - 600
        return {
            'status': 'pending',
            'created_at': expired_timestamp,
            'updated_at': expired_timestamp,
            'user_id': 'test_user',
            'message_content': 'Test checklist',
            'message_history': [],
            'collection': self.firebase_service.CHECKLIST_TASKS_COLLECTION
        }
    
    def create_checkin_task(self) -> Dict:
        """Create a checkin task with required fields."""
        # Create timestamp from 10 minutes ago
        expired_timestamp = time.time() - 600
        return {
            'status': 'pending',
            'created_at': expired_timestamp,
            'updated_at': expired_timestamp,
            'user_id': 'test_user',
            'user_full_name': 'Test User',
            'checklist_data': {'items': []},
            'collection': self.firebase_service.CHECKIN_TASKS_COLLECTION
        }
    
    async def write_expired_tasks(self):
        """Write expired tasks to Firebase in batches."""
        logger.info(f"Writing {NUM_TASKS} expired tasks ({NUM_TASKS//3} per collection)...")
        
        tasks_per_collection = NUM_TASKS // 3
        collections = [
            (self.firebase_service.MESSAGE_TASKS_COLLECTION, self.create_message_task),
            (self.firebase_service.CHECKLIST_TASKS_COLLECTION, self.create_checklist_task),
            (self.firebase_service.CHECKIN_TASKS_COLLECTION, self.create_checkin_task)
        ]
        
        for collection, create_task_fn in collections:
            tasks_written = 0
            while tasks_written < tasks_per_collection:
                # Create a batch
                batch = self.firebase_service.db.batch()
                batch_count = 0
                
                # Add tasks to the batch
                while batch_count < BATCH_SIZE and tasks_written < tasks_per_collection:
                    task_ref = self.firebase_service.db.collection(collection).document()
                    task_data = create_task_fn()
                    batch.set(task_ref, task_data)
                    self.task_ids[collection].add(task_ref.id)
                    batch_count += 1
                    tasks_written += 1
                
                # Commit the batch
                await asyncio.to_thread(batch.commit)
                logger.info(f"Wrote batch of {batch_count} tasks to {collection} ({tasks_written}/{tasks_per_collection})")
                
                # Small delay to avoid overwhelming Firebase
                await asyncio.sleep(0.1)
        
        total_tasks = sum(len(ids) for ids in self.task_ids.values())
        logger.info(f"Successfully wrote {total_tasks} tasks")
        
        # Initialize collection stats
        for collection in self.task_ids:
            self.collection_stats[collection]['pending'] = len(self.task_ids[collection])
        
        # Wait for server timestamps to be set
        await asyncio.sleep(2)
    
    async def check_task_batch(self, collection: str, task_ids: List[str]) -> Set[str]:
        """Check status of a batch of tasks."""
        if not task_ids:
            return set()
        
        processed_ids = set()
        
        # Instead of using a complex query with __name__, check each document individually
        for task_id in task_ids:
            doc_ref = self.firebase_service.db.collection(collection).document(task_id)
            doc = await asyncio.to_thread(doc_ref.get)
            
            if doc.exists:
                doc_data = doc.to_dict()
                status = doc_data.get('status', 'pending')
                
                if status in ['completed', 'failed']:
                    processed_ids.add(task_id)
                    
                    # Log details for analytics
                    error = doc_data.get('error', None)
                    if error:
                        logger.info(f"Task {task_id} in {collection} failed with error: {error}")
                    else:
                        logger.info(f"Task {task_id} in {collection} processed successfully")
        
        return processed_ids
    
    async def monitor_processing(self):
        """Monitor the processing of expired tasks by workers."""
        logger.info("Starting to monitor task processing by workers...")
        self.start_time = time.time()
        
        pending_tasks = {col: set(ids) for col, ids in self.task_ids.items()}
        total_pending = sum(len(ids) for ids in pending_tasks.values())
        last_log_time = time.time()
        last_total = total_pending
        
        # Set end time based on max wait
        end_time = time.time() + self.max_wait_time
        
        while total_pending > 0 and not self.shutdown and time.time() < end_time:
            # Check each collection
            for collection in self.task_ids.keys():
                # Process tasks in batches
                task_list = list(pending_tasks[collection])
                completed = set()
                
                for i in range(0, len(task_list), QUERY_BATCH_SIZE):
                    batch = task_list[i:i + QUERY_BATCH_SIZE]
                    processed = await self.check_task_batch(collection, batch)
                    completed.update(processed)
                    
                    # Update collection stats
                    self.collection_stats[collection]['processed'] += len(processed)
                
                # Remove completed tasks
                pending_tasks[collection] -= completed
                self.collection_stats[collection]['pending'] = len(pending_tasks[collection])
            
            # Calculate new total
            new_total = sum(len(ids) for ids in pending_tasks.values())
            tasks_processed = last_total - new_total
            self.tasks_processed_by_workers += tasks_processed
            
            # Log progress every 5 seconds
            current_time = time.time()
            if current_time - last_log_time >= 5:
                elapsed = current_time - last_log_time
                rate = tasks_processed / elapsed if elapsed > 0 else 0
                logger.info(f"Processed {tasks_processed} tasks in last 5s ({rate:.1f} tasks/second)")
                logger.info(f"Remaining tasks: {new_total}")
                
                # Log collection-specific progress
                for collection, stats in self.collection_stats.items():
                    col_name = collection.split('_')[0]  # Just the first part for cleaner logs
                    logger.info(f"  - {col_name}: {stats['processed']} processed, {stats['pending']} pending")
                
                last_log_time = current_time
                last_total = new_total
            
            total_pending = new_total
            await asyncio.sleep(1)  # Poll every 1 second
        
        # Record final stats
        self.tasks_still_pending = total_pending
        self.end_time = time.time()
        
        # Report timeout if applicable
        if total_pending > 0 and time.time() >= end_time:
            logger.warning(f"Reached maximum wait time of {self.max_wait_time}s. {total_pending} tasks still pending.")
            
            # Show breakdown of remaining tasks
            for collection, pending in pending_tasks.items():
                if pending:
                    logger.warning(f"  - {collection}: {len(pending)} tasks still pending")
    
    async def cleanup(self):
        """Clean up test tasks."""
        if self.skip_cleanup:
            logger.info("Skipping cleanup as requested")
            return
            
        logger.info("Cleaning up test tasks...")
        
        for collection, task_ids in self.task_ids.items():
            # Delete in batches
            task_list = list(task_ids)
            for i in range(0, len(task_list), BATCH_SIZE):
                batch = self.firebase_service.db.batch()
                for task_id in task_list[i:i + BATCH_SIZE]:
                    ref = self.firebase_service.db.collection(collection).document(task_id)
                    batch.delete(ref)
                await asyncio.to_thread(batch.commit)
                logger.info(f"Deleted {min(BATCH_SIZE, len(task_list) - i)} tasks from {collection}")
                await asyncio.sleep(0.1)
    
    def print_results(self):
        """Print the final results of worker processing."""
        if not self.end_time or not self.start_time:
            logger.warning("Test did not complete")
            return
            
        total_time = self.end_time - self.start_time
        total_tasks = sum(len(ids) for ids in self.task_ids.values())
        processed_by_workers = self.tasks_processed_by_workers
        still_pending = self.tasks_still_pending
        
        # Calculate rate based on tasks actually processed by workers
        if processed_by_workers > 0:
            rate = processed_by_workers / total_time
            avg_time_per_task = (total_time / processed_by_workers) * 1000
        else:
            rate = 0
            avg_time_per_task = 0
        
        logger.info("=== Worker Test Results ===")
        logger.info(f"Total tasks created: {total_tasks}")
        logger.info(f"Tasks processed by workers: {processed_by_workers}")
        logger.info(f"Tasks still pending: {still_pending}")
        logger.info(f"Total test time: {total_time:.2f} seconds")
        
        if processed_by_workers > 0:
            logger.info(f"Worker processing rate: {rate:.1f} tasks/second")
            logger.info(f"Tasks per minute: {rate * 60:.1f}")
            logger.info(f"Average time per task: {avg_time_per_task:.2f}ms")
        else:
            logger.warning("No tasks were processed by workers!")
        
        # Collection-specific statistics
        logger.info("=== Collection Stats ===")
        for collection, stats in self.collection_stats.items():
            logger.info(f"{collection}:")
            logger.info(f"  - Tasks processed: {stats['processed']}")
            logger.info(f"  - Tasks still pending: {stats['pending']}")

# Add individual test functions
async def add_expired_message_task():
    """Add a single expired message task to Firebase. That's it."""
    firebase_service = FirebaseService()
    
    # Created 10 minutes ago (600 seconds)
    expired_timestamp = time.time() - 600
    
    # Create a single message task
    task_ref = firebase_service.db.collection(firebase_service.MESSAGE_TASKS_COLLECTION).document()
    task_data = {
        'status': 'pending',
        'created_at': expired_timestamp,
        'updated_at': expired_timestamp,
        'user_id': 'test_user',
        'user_full_name': 'Test User',
        'message_content': 'Test expired message',
        'message_history': [],
        'collection': firebase_service.MESSAGE_TASKS_COLLECTION
    }
    
    # Set the task
    await asyncio.to_thread(task_ref.set, task_data)
    task_id = task_ref.id
    
    logger.info(f"Added expired message task with ID: {task_id}")
    return task_id

async def add_expired_checklist_task():
    """Add a single expired checklist task to Firebase. That's it."""
    firebase_service = FirebaseService()
    
    # Created 10 minutes ago (600 seconds)
    expired_timestamp = time.time() - 600
    
    # Create a single checklist task
    task_ref = firebase_service.db.collection(firebase_service.CHECKLIST_TASKS_COLLECTION).document()
    task_data = {
        'status': 'pending',
        'created_at': expired_timestamp,
        'updated_at': expired_timestamp,
        'user_id': 'test_user',
        'message_content': 'Test expired checklist',
        'message_history': [],
        'collection': firebase_service.CHECKLIST_TASKS_COLLECTION
    }
    
    # Set the task
    await asyncio.to_thread(task_ref.set, task_data)
    task_id = task_ref.id
    
    logger.info(f"Added expired checklist task with ID: {task_id}")
    return task_id

async def add_expired_checkin_task():
    """Add a single expired checkin task to Firebase. That's it."""
    firebase_service = FirebaseService()
    
    # Created 10 minutes ago (600 seconds)
    expired_timestamp = time.time() - 600
    
    # Create a single checkin task
    task_ref = firebase_service.db.collection(firebase_service.CHECKIN_TASKS_COLLECTION).document()
    task_data = {
        'status': 'pending',
        'created_at': expired_timestamp,
        'updated_at': expired_timestamp,
        'user_id': 'test_user',
        'user_full_name': 'Test User',
        'checklist_data': {
            'date': datetime.now().strftime('%Y-%m-%d'),
            'items': [
                {'title': 'Test item 1', 'isCompleted': True, 'group': 'Test Group'},
                {'title': 'Test item 2', 'isCompleted': False, 'group': 'Test Group'}
            ]
        },
        'collection': firebase_service.CHECKIN_TASKS_COLLECTION
    }
    
    # Set the task
    await asyncio.to_thread(task_ref.set, task_data)
    task_id = task_ref.id
    
    logger.info(f"Added expired checkin task with ID: {task_id}")
    return task_id

# Update main function to support individual task addition
async def main():
    """Main entry point for the test."""
    # Parse command line arguments
    parser = argparse.ArgumentParser(description='Test expired tasks processing')
    parser.add_argument('--max-wait', type=int, default=DEFAULT_MAX_WAIT, 
                       help=f'Maximum wait time in seconds (default: {DEFAULT_MAX_WAIT})')
    parser.add_argument('--no-cleanup', action='store_true',
                       help='Skip cleanup of test tasks')
    parser.add_argument('--test-mode', choices=['all', 'message', 'checklist', 'checkin'], default='all',
                       help='Test mode: all tasks or specific task type (default: all)')
    args = parser.parse_args()
    
    # Run in single test mode if specified
    if args.test_mode != 'all':
        if args.test_mode == 'message':
            task_id = await add_expired_message_task()
            logger.info(f"Added expired message task: {task_id}")
        elif args.test_mode == 'checklist':
            task_id = await add_expired_checklist_task()
            logger.info(f"Added expired checklist task: {task_id}")
        elif args.test_mode == 'checkin':
            task_id = await add_expired_checkin_task()
            logger.info(f"Added expired checkin task: {task_id}")
        return
    
    # Create tester with command line options for full test
    tester = ThroughputTester(max_wait_time=args.max_wait, skip_cleanup=args.no_cleanup)
    
    def signal_handler(signum, frame):
        logger.info(f"Received signal {signum}, initiating graceful shutdown...")
        tester.shutdown = True
    
    # Set up signal handlers
    signal.signal(signal.SIGINT, signal_handler)
    signal.signal(signal.SIGTERM, signal_handler)
    
    try:
        # Write the tasks with proper timestamps
        await tester.write_expired_tasks()
        
        # Log that we're starting to monitor workers
        logger.info("Starting monitoring task processing - workers should be running")
        
        # Monitor their processing
        await tester.monitor_processing()
        
        # Print results
        tester.print_results()
        
    except Exception as e:
        logger.error(f"Error during test: {e}")
        raise
    finally:
        # Ask user if they want to clean up (unless already shutting down)
        if not tester.shutdown and not args.no_cleanup:
            cleanup = input("Clean up test tasks? [Y/n]: ").strip().lower() != 'n'
            tester.skip_cleanup = not cleanup
        
        # Clean up test tasks
        await tester.cleanup()

if __name__ == "__main__":
    asyncio.run(main()) 