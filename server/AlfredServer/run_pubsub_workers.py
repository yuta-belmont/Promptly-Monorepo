#!/usr/bin/env python3
"""
Script to run the unified Pub/Sub worker for processing AI tasks.
This script starts a worker process for handling all types of tasks through a single subscription.
"""

import os
import sys
import logging
import signal
import argparse
import time
import threading

# Add the project root to the path so we can import app modules
sys.path.append(os.path.dirname(os.path.abspath(__file__)))

# Import the set_env module to set environment variables
import set_env

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
    """Manages unified worker instances."""
    
    def __init__(self, unified_workers=1):
        """
        Initialize the worker manager.
        
        Args:
            unified_workers: Number of unified workers to start
        """
        self.worker_threads = []
        self.workers = []
        self.unified_workers = unified_workers
        
    def start(self):
        """Start all worker instances."""
        logger.info(f"Starting {self.unified_workers} unified workers")
        
        # Create worker instances
        worker_count = 0
        
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
    parser = argparse.ArgumentParser(description='Run unified Pub/Sub worker for AI tasks')
    
    parser.add_argument('--unified-workers', type=int, default=1,
                        help='Number of unified workers to start (default: 1)')
    
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
    
    logger.info(f"Unified Pub/Sub worker manager started with PID {pid}")
    
    # Start worker manager with specified number of workers
    manager = WorkerManager(
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