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
MAX_TASKS_PER_THREAD = 10  # Each thread handles up to 10 tasks
NUM_WORKER_THREADS = 5     # Number of worker threads
POLL_INTERVAL = 0.1        # 100ms between cycles
POLL_FREQUENCY = 1.0       # 1 second between polling Firebase when no tasks are found

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
        self.initial_delay = thread_id * 0.2  # Stagger by 200ms per thread
    
    async def _run_worker(self):
        """Run the worker in this thread's event loop."""
        try:
            # Add initial staggered delay
            if self.initial_delay > 0:
                logger.info(f"Thread {self.thread_id} waiting {self.initial_delay:.1f}s before starting")
                await asyncio.sleep(self.initial_delay)
            
            self.worker = UnifiedWorker(
                worker_id=f"worker-{self.worker_id}-{self.thread_id}",
                max_concurrent_tasks=MAX_TASKS_PER_THREAD
            )
            
            # Run the worker until shutdown
            while not shutdown_flag:
                try:
                    # Process tasks with a timeout to allow for graceful shutdown
                    await self.worker.process_tasks(max_runtime=POLL_FREQUENCY)
                except Exception as e:
                    logger.error(f"Error in worker thread {self.thread_id}: {e}")
                    if not shutdown_flag:
                        await asyncio.sleep(POLL_FREQUENCY)  # Wait before retrying
                        
            logger.info(f"Worker thread {self.thread_id} shutting down")
            
        except Exception as e:
            logger.error(f"Worker thread {self.thread_id} error: {e}")
            raise

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
            asyncio.run(worker._run_worker())
            self.worker_threads.append(worker)
            
    def stop(self):
        """Stop all worker threads."""
        logger.info("Stopping all worker threads")
        for worker in self.worker_threads:
            if worker.thread:
                worker.thread.join(timeout=5.0)

def signal_handler(sig, frame):
    """Handle termination signals to gracefully shut down workers."""
    global shutdown_flag
    logger.info(f"Received signal {sig}, initiating graceful shutdown...")
    shutdown_flag = True
    
    # Give workers time to shut down gracefully
    time.sleep(2)
    
    logger.info("All workers shut down")
    sys.exit(0)

def main():
    """Main entry point for the script."""
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
                    new_worker = WorkerThread(i, f"thread-{i}")
                    asyncio.run(new_worker._run_worker())
                    manager.worker_threads[i] = new_worker
    
    except KeyboardInterrupt:
        # This will be caught by the signal handler
        pass
    
    finally:
        # Clean up
        manager.stop()
        if os.path.exists("worker.pid"):
            os.remove("worker.pid")

if __name__ == "__main__":
    main() 