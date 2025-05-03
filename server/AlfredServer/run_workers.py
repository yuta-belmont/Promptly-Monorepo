#!/usr/bin/env python3
"""
Script to run the background workers.
This script starts multiple worker threads for handling tasks.
"""

import os
import sys
import asyncio
import logging
import threading
import signal
import time
import random
from typing import List
import traceback

# Add the project root to the path so we can import app modules
sys.path.append(os.path.dirname(os.path.abspath(__file__)))

# Import the set_env module to set environment variables
import set_env

from app.workers.unified_worker import UnifiedWorker

# Set up logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

# Global flag to signal workers to shut down
shutdown_flag = False

# Worker configuration
MAX_TASKS_PER_THREAD = 25  # Each thread handles up to 10 tasks
NUM_WORKER_THREADS = 1     # Number of worker threads
POLL_FREQUENCY = 0.2       # How often to poll for new tasks (in seconds)
MAX_RUNTIME = 60.0         # Maximum time to run before checking for shutdown (in seconds)
RESTART_PROCESSING_DELAY = 5.0

class WorkerThread:
    """Thread that runs a worker with its own event loop."""
    
    def __init__(self, thread_id: int, worker_id: str):
        self.thread_id = thread_id
        self.worker_id = worker_id
        self.thread = None
        self.loop = None
        self.worker = None
        self.running = False
        # Add initial delay based on thread index (0-4)
        self.initial_delay = thread_id * float(POLL_FREQUENCY/NUM_WORKER_THREADS)  # Stagger by thread index
    
    async def _run_worker(self):
        """Run the worker in an event loop."""
        logger.info(f"Worker thread {self.thread_id} started")
        try:
            # Add initial staggered delay
            if self.initial_delay > 0:
                logger.info(f"Thread {self.thread_id} waiting {self.initial_delay:.1f}s before starting")
                await asyncio.sleep(self.initial_delay)
            
            worker = UnifiedWorker(
                max_concurrent_tasks=MAX_TASKS_PER_THREAD,
                worker_id=f"worker-{self.thread_id}"
            )
            logger.info(f"Thread {self.thread_id} initialized with capacity for {MAX_TASKS_PER_THREAD} tasks")
            
            # Main work loop
            while not shutdown_flag:
                try:
                    # Process available tasks
                    await worker.process_tasks(
                        max_runtime=MAX_RUNTIME,
                        poll_frequency=POLL_FREQUENCY
                    )
                except Exception as e:
                    logger.error(f"Error in worker thread {self.thread_id}: {e}")
                    logger.error(traceback.format_exc())
                    # Avoid tight error loops
                    await asyncio.sleep(1)
        except Exception as e:
            logger.error(f"Fatal error in worker thread {self.thread_id}: {e}")
            logger.error(traceback.format_exc())
        finally:
            logger.info(f"Worker thread {self.thread_id} shutting down")

class WorkerManager:
    """Manages multiple worker threads."""
    
    def __init__(self):
        """Initialize the worker manager."""
        self.worker_threads: List[WorkerThread] = []
        
    def start(self):
        """Start all worker threads."""
        logger.info(f"Starting {NUM_WORKER_THREADS} worker threads")
        for i in range(NUM_WORKER_THREADS):
            worker = WorkerThread(i, f"thread-{i}")
            # Create a proper thread that runs the worker's _run_worker method
            worker.thread = threading.Thread(
                target=asyncio.run,
                args=(worker._run_worker(),),
                name=f"worker-thread-{i}"
            )
            # Start the thread
            worker.thread.start()
            self.worker_threads.append(worker)
            
    def shutdown(self, signum=None, frame=None):
        """Shutdown all worker threads."""
        logger.info("Shutting down worker threads")
        global shutdown_flag
        shutdown_flag = True
        # Wait for threads to finish
        for worker in self.worker_threads:
            if worker.thread and worker.thread.is_alive():
                logger.info(f"Waiting for worker thread {worker.thread_id} to finish")
                worker.thread.join()
        logger.info("All worker threads shut down")

def signal_handler(sig, frame):
    """Handle signals."""
    logger.info(f"Received signal {sig}")
    global shutdown_flag
    shutdown_flag = True
    # Let the manager handle the shutdown
    if 'manager' in globals():
        manager.shutdown(sig, frame)

def main():
    """Main entry point for the script."""
    global manager
    
    # Register signal handlers
    signal.signal(signal.SIGINT, signal_handler)
    signal.signal(signal.SIGTERM, signal_handler)
    
    # Create a PID file to help with process management
    pid = os.getpid()
    with open("worker.pid", "w") as f:
        f.write(str(pid))
    logger.info(f"Worker manager started with PID {pid}")
    
    # Start worker manager
    manager = WorkerManager()
    manager.start()
    
    try:
        # Keep the main process running to handle signals
        while not shutdown_flag:
            time.sleep(1)
            
            # Check if any threads died and restart them if needed
            for i, worker in enumerate(manager.worker_threads[:]):
                if not worker.thread.is_alive() and not shutdown_flag:
                    logger.warning(f"Worker thread {i} died unexpectedly, restarting...")
                    # Create a new worker thread
                    new_worker = WorkerThread(i, f"thread-{i}")
                    # Create and start a new thread
                    new_worker.thread = threading.Thread(
                        target=asyncio.run,
                        args=(new_worker._run_worker(),),
                        name=f"worker-thread-{i}"
                    )
                    new_worker.thread.start()
                    # Replace the old worker in the list
                    manager.worker_threads[i] = new_worker
    
    except KeyboardInterrupt:
        # This will be caught by the signal handler
        pass
    
    finally:
        # Clean up
        manager.shutdown()
        if os.path.exists("worker.pid"):
            os.remove("worker.pid")

if __name__ == "__main__":
    main() 