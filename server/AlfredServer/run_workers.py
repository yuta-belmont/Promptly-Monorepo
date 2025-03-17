#!/usr/bin/env python3
"""
Script to run the checklist worker.
This script starts the checklist worker process.
"""

import os
import sys
import asyncio
import logging
import multiprocessing
import signal
import time
import random

# Add the project root to the path so we can import app modules
sys.path.append(os.path.dirname(os.path.abspath(__file__)))

# Import the set_env module to set environment variables
import set_env

from app.workers.checklist_worker import ChecklistWorker

# Set up logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

# Global flag to signal workers to shut down
shutdown_flag = False

# Store worker processes
worker_processes = []

# Worker configuration
MAX_RUNTIME = 30  # 30 seconds max time allowed for processing a single task
POLL_INTERVAL = 0.1  # 100ms between cycles
POLL_FREQUENCY = 1.0  # 1 second between polling Firebase when no tasks are found

# Counter to track which worker is being started
worker_count = 0

async def run_checklist_worker(worker_id=0):
    """
    Run the checklist worker.
    
    Args:
        worker_id: ID of this worker instance, used for jitter calculation
    """
    worker = ChecklistWorker()
    
    # No jitter needed for a single worker
    
    # Modify the loop to check for shutdown flag
    while not shutdown_flag:
        try:
            # Check for tasks with short max_runtime to enable more frequent polling
            # But process each task with the full MAX_RUNTIME limit
            start_time = time.time()
            
            # Process tasks, but only poll for POLL_FREQUENCY seconds
            await worker.process_tasks(max_runtime=POLL_FREQUENCY)
            
            # Calculate how much time we have left in our desired polling interval
            elapsed = time.time() - start_time
            remaining_sleep = max(0, POLL_FREQUENCY - elapsed)
            
            # Check shutdown flag
            if shutdown_flag:
                logger.info(f"Checklist worker {worker_id} received shutdown signal")
                break
                
            # Sleep for any remaining time to maintain our polling frequency
            if remaining_sleep > 0:
                logger.debug(f"Worker {worker_id} sleeping for {remaining_sleep:.2f}s to maintain polling frequency")
                await asyncio.sleep(remaining_sleep)
            
        except Exception as e:
            logger.error(f"Error in checklist worker {worker_id}: {e}")
            if not shutdown_flag:
                await asyncio.sleep(POLL_FREQUENCY)  # Wait before retrying
    
    logger.info(f"Checklist worker {worker_id} shutting down gracefully")

def start_checklist_worker(worker_id=0):
    """
    Start the checklist worker in a separate process.
    
    Args:
        worker_id: ID of this worker instance, passed to run_checklist_worker
    """
    logger.info(f"Starting checklist worker {worker_id}")
    asyncio.run(run_checklist_worker(worker_id))

def signal_handler(sig, frame):
    """Handle termination signals to gracefully shut down workers."""
    global shutdown_flag
    logger.info(f"Received signal {sig}, initiating graceful shutdown...")
    shutdown_flag = True
    
    # Give workers time to shut down gracefully
    time.sleep(2)
    
    # Terminate any remaining processes
    for process in worker_processes:
        if process.is_alive():
            logger.info(f"Terminating worker process {process.pid}")
            process.terminate()
    
    logger.info("All workers shut down")
    sys.exit(0)

def main():
    """Main entry point for the script."""
    global worker_count
    
    # Register signal handlers
    signal.signal(signal.SIGINT, signal_handler)
    signal.signal(signal.SIGTERM, signal_handler)
    
    # Create a PID file to help with process management
    pid = os.getpid()
    with open("worker.pid", "w") as f:
        f.write(str(pid))
    logger.info(f"Worker manager started with PID {pid}")
    
    # Start a single worker (ID 0) which polls every 1 second
    logger.info("Starting single checklist worker process (polls every 1 second)")
    checklist_process = multiprocessing.Process(target=start_checklist_worker, args=(worker_count,))
    checklist_process.start()
    worker_processes.append(checklist_process)
    worker_count += 1
    
    # We no longer start a second worker
    
    try:
        # Keep the main process running to handle signals
        while not shutdown_flag:
            time.sleep(1)
            
            # Check if workers are still alive and restart them if needed
            for i, process in enumerate(worker_processes[:]):
                if not process.is_alive() and not shutdown_flag:
                    worker_id = i  # Use the original index as the worker_id
                    logger.warning(f"Checklist worker {worker_id} died unexpectedly, restarting...")
                    new_process = multiprocessing.Process(target=start_checklist_worker, args=(worker_id,))
                    new_process.start()
                    
                    # Replace the dead process in our list
                    worker_processes[i] = new_process
    
    except KeyboardInterrupt:
        # This will be caught by the signal handler
        pass
    
    finally:
        # Clean up PID file
        if os.path.exists("worker.pid"):
            os.remove("worker.pid")

if __name__ == '__main__':
    main() 