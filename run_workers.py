#!/usr/bin/env python3
"""
Script to run the Alfred checklist worker from the root directory.
This script is a wrapper around the manage_workers.py script.
"""

import os
import sys
import subprocess
import argparse

def main():
    """Main entry point for the script."""
    parser = argparse.ArgumentParser(description="Manage Alfred workers")
    parser.add_argument("command", nargs="?", default="start", choices=["start", "stop", "restart", "status"], 
                        help="Command to execute (default: start)")
    
    args = parser.parse_args()
    
    # Check if psutil is installed
    try:
        import psutil
    except ImportError:
        print("Installing required dependency: psutil")
        subprocess.run([sys.executable, "-m", "pip", "install", "psutil"])
    
    # Run the manage_workers.py script
    cmd = [sys.executable, "server/manage_workers.py", args.command]
    print(f"Running command: {' '.join(cmd)}")
    subprocess.run(cmd)

if __name__ == "__main__":
    main() 