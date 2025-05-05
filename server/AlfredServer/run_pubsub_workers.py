#!/usr/bin/env python3
"""
Script to run Pub/Sub workers for processing AI tasks.
This script starts worker processes for handling different types of tasks.
"""

import os
import sys
import logging
import signal
import argparse
import time
import threading
from concurrent.futures import ThreadPoolExecutor

# Add the project root to the path so we can import app modules
sys.path.append(os.path.dirname(os.path.abspath(__file__)))

# Import the set_env module to set environment variables
import set_env

from app.pubsub.workers.message_worker import MessageWorker
from app.pubsub.workers.checklist_worker import ChecklistWorker
from app.pubsub.workers.checkin_worker import CheckinWorker
from app.pubsub.workers.unified_pubsub_worker import UnifiedPubSubWorker

# Set up logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

# Global flag to signal workers to shut down
shutdown_flag = False

class WorkerManager:
    """Manages multiple worker instances."""
    
    def __init__(self, message_workers=1, checklist_workers=1, checkin_workers=1, unified_workers=0):
        """
        Initialize the worker manager.
        
        Args:
            message_workers: Number of message workers to start
            checklist_workers: Number of checklist workers to start
            checkin_workers: Number of checkin workers to start
            unified_workers: Number of unified workers to start
        """
        self.worker_threads = []
        self.workers = []
        self.message_workers = message_workers
        self.checklist_workers = checklist_workers
        self.checkin_workers = checkin_workers
        self.unified_workers = unified_workers
        
    def start(self):
        """Start all worker instances."""
        logger.info(
            f"Starting {self.message_workers} message workers, "
            f"{self.checklist_workers} checklist workers, "
            f"{self.checkin_workers} checkin workers, and "
            f"{self.unified_workers} unified workers"
        )
        
        # Create worker instances
        worker_count = 0
        
        # Message workers
        for i in range(self.message_workers):
            worker_id = f"message-worker-{i}"
            worker = MessageWorker(worker_id=worker_id)
            self.workers.append(worker)
            worker_count += 1
            
        # Checklist workers
        for i in range(self.checklist_workers):
            worker_id = f"checklist-worker-{i}"
            worker = ChecklistWorker(worker_id=worker_id)
            self.workers.append(worker)
            worker_count += 1
            
        # Check-in workers
        for i in range(self.checkin_workers):
            worker_id = f"checkin-worker-{i}"
            worker = CheckinWorker(worker_id=worker_id)
            self.workers.append(worker)
            worker_count += 1
        
        # Unified workers
        for i in range(self.unified_workers):
            worker_id = f"unified-worker-{i}"
            worker = UnifiedPubSubWorker(worker_id=worker_id)
            self.workers.append(worker)
            worker_count += 1
            
        logger.info(f"Created {worker_count} worker instances")
        
        # Create and start threads for each worker
        for worker in self.workers:
            thread = threading.Thread(
                target=worker.start,
                name=worker.worker_id
            )
            thread.daemon = True
            thread.start()
            self.worker_threads.append(thread)
            logger.info(f"Started thread for worker {worker.worker_id}")
            
        # Allow a short time for workers to initialize
        time.sleep(1)
        
        logger.info(f"All {worker_count} workers started successfully")
    
    def stop(self):
        """Stop all worker instances gracefully."""
        logger.info(f"Stopping {len(self.workers)} workers")
        
        # Stop each worker
        for worker in self.workers:
            try:
                worker.stop()
            except Exception as e:
                logger.error(f"Error stopping worker {worker.worker_id}: {e}")
        
        # Wait for threads to finish (with timeout)
        for thread in self.worker_threads:
            if thread.is_alive():
                logger.info(f"Waiting for thread {thread.name} to finish")
                thread.join(timeout=5)
                
        # Check if any threads are still running
        running_threads = [t for t in self.worker_threads if t.is_alive()]
        if running_threads:
            logger.warning(f"{len(running_threads)} threads still running after timeout")
        else:
            logger.info("All worker threads stopped successfully")

def signal_handler(sig, frame):
    """Handle signals."""
    logger.info(f"Received signal {sig}")
    global shutdown_flag
    shutdown_flag = True

def parse_arguments():
    """Parse command line arguments."""
    parser = argparse.ArgumentParser(description='Run Pub/Sub workers for AI tasks')
    
    parser.add_argument('--message-workers', type=int, default=1,
                        help='Number of message workers to start (default: 1)')
    parser.add_argument('--checklist-workers', type=int, default=1,
                        help='Number of checklist workers to start (default: 1)')
    parser.add_argument('--checkin-workers', type=int, default=1,
                        help='Number of checkin workers to start (default: 1)')
    parser.add_argument('--unified-workers', type=int, default=0,
                        help='Number of unified workers to start (default: 0)')
    
    return parser.parse_args()

def main():
    """Main entry point for the script."""
    global manager
    
    # Parse command line arguments
    args = parse_arguments()
    
    # Register signal handlers
    signal.signal(signal.SIGINT, signal_handler)
    signal.signal(signal.SIGTERM, signal_handler)
    
    # Create a PID file to help with process management
    pid = os.getpid()
    with open("pubsub_workers.pid", "w") as f:
        f.write(str(pid))
    
    logger.info(f"Pub/Sub worker manager started with PID {pid}")
    
    # Start worker manager with specified number of workers
    manager = WorkerManager(
        message_workers=args.message_workers,
        checklist_workers=args.checklist_workers,
        checkin_workers=args.checkin_workers,
        unified_workers=args.unified_workers
    )
    manager.start()
    
    try:
        # Keep the main process running to handle signals
        while not shutdown_flag:
            time.sleep(1)
    
    except KeyboardInterrupt:
        # This will be caught by the signal handler
        pass
    
    finally:
        # Clean up
        logger.info("Shutting down worker manager")
        if 'manager' in globals():
            manager.stop()
        if os.path.exists("pubsub_workers.pid"):
            os.remove("pubsub_workers.pid")
        logger.info("Worker manager shutdown complete")

if __name__ == "__main__":
    main() 