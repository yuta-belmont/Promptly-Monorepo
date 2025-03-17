#!/usr/bin/env python3
"""
Script to run the Firestore data cleanup operation.
This script can be scheduled to run daily using cron or a similar scheduler.
"""

import os
import sys
import logging
from datetime import datetime

# Add the project root to the path so we can import app modules
sys.path.append(os.path.dirname(os.path.abspath(__file__)))

# Set up environment variables
from set_env import set_environment_variables
set_environment_variables()

from app.services.cleanup_service import run_cleanup

# Set up logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

if __name__ == "__main__":
    logger.info(f"Starting Firestore cleanup at {datetime.now().isoformat()}")
    
    try:
        stats = run_cleanup()
        logger.info(f"Cleanup completed successfully. Stats: {stats}")
    except Exception as e:
        logger.error(f"Error during cleanup: {e}")
        sys.exit(1)
    
    logger.info(f"Cleanup finished at {datetime.now().isoformat()}") 