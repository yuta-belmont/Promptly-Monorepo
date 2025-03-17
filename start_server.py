#!/usr/bin/env python3
"""
Script to start the Promptly server with the correct environment variables.
"""

import os
import sys
import subprocess

# Add the server directory to the path
sys.path.append(os.path.join(os.path.dirname(os.path.abspath(__file__)), "server"))

# Import the set_env module to set environment variables
import set_env

def main():
    """Main entry point for the script."""
    # Build the command to start the server
    cmd = ["uvicorn", "server.main:app", "--reload"]
    
    # Run the command
    print(f"Running command: {' '.join(cmd)}")
    subprocess.run(cmd)

if __name__ == "__main__":
    main() 