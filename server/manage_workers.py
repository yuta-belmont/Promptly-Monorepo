#!/usr/bin/env python3
"""
Script to manage worker processes.
This script provides commands to start, stop, and check the status of workers.
"""

import os
import sys
import argparse
import subprocess
import signal
import time
import psutil

def get_worker_pid():
    """Get the worker PID from the PID file."""
    pid_file = "server/AlfredServer/worker.pid"
    if not os.path.exists(pid_file):
        # Try alternate location
        pid_file = "worker.pid"
        if not os.path.exists(pid_file):
            return None
    
    with open(pid_file, "r") as f:
        try:
            pid = int(f.read().strip())
            return pid
        except ValueError:
            return None

def is_worker_running(pid=None):
    """Check if the worker process is running."""
    if pid is None:
        pid = get_worker_pid()
    
    if pid is None:
        return False
    
    try:
        process = psutil.Process(pid)
        return process.is_running() and "run_workers.py" in " ".join(process.cmdline())
    except psutil.NoSuchProcess:
        return False

def start_workers():
    """Start the worker processes."""
    if is_worker_running():
        print("Workers are already running.")
        return
    
    print("Starting workers...")
    # Start the worker process in the background
    subprocess.Popen(
        ["python3", "server/AlfredServer/run_workers.py"],
        stdout=open("server/worker.log", "a"),
        stderr=subprocess.STDOUT,
        start_new_session=True
    )
    
    # Wait for the PID file to be created
    for _ in range(5):
        time.sleep(1)
        if get_worker_pid() is not None:
            break
    
    if is_worker_running():
        print(f"Workers started with PID {get_worker_pid()}")
    else:
        print("Failed to start workers. Check the logs.")

def stop_workers():
    """Stop the worker processes."""
    pid = get_worker_pid()
    
    if pid is None or not is_worker_running(pid):
        print("No workers are running.")
        return
    
    print(f"Stopping workers (PID {pid})...")
    
    try:
        # Send SIGTERM for graceful shutdown
        os.kill(pid, signal.SIGTERM)
        
        # Wait for the process to terminate
        for _ in range(10):
            time.sleep(1)
            if not is_worker_running(pid):
                print("Workers stopped gracefully.")
                return
        
        # If still running, force kill
        print("Workers didn't stop gracefully, force killing...")
        os.kill(pid, signal.SIGKILL)
        print("Workers force killed.")
    except ProcessLookupError:
        print("Workers already stopped.")
    except Exception as e:
        print(f"Error stopping workers: {e}")

def check_status():
    """Check the status of the worker processes."""
    pid = get_worker_pid()
    
    if pid is None:
        print("No worker PID file found.")
        return
    
    if is_worker_running(pid):
        print(f"Workers are running with PID {pid}")
        
        # Get more details about the process
        try:
            process = psutil.Process(pid)
            print(f"Started at: {time.ctime(process.create_time())}")
            print(f"CPU usage: {process.cpu_percent(interval=0.1)}%")
            print(f"Memory usage: {process.memory_info().rss / (1024 * 1024):.2f} MB")
            
            # Check for child processes
            children = process.children(recursive=True)
            if children:
                print(f"Child processes: {len(children)}")
                for child in children:
                    print(f"  - PID {child.pid}: {' '.join(child.cmdline())[:60]}...")
        except Exception as e:
            print(f"Error getting process details: {e}")
    else:
        print(f"No workers running (stale PID file: {pid})")

def main():
    """Main entry point for the script."""
    parser = argparse.ArgumentParser(description="Manage worker processes")
    parser.add_argument("command", choices=["start", "stop", "restart", "status"], help="Command to execute")
    
    args = parser.parse_args()
    
    if args.command == "start":
        start_workers()
    elif args.command == "stop":
        stop_workers()
    elif args.command == "restart":
        stop_workers()
        time.sleep(2)
        start_workers()
    elif args.command == "status":
        check_status()

if __name__ == "__main__":
    main() 