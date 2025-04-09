import json
from datetime import datetime
from google.cloud.firestore_v1._helpers import DatetimeWithNanoseconds
import logging

logger = logging.getLogger(__name__)

def convert_firestore_data(data):
    """
    Convert Firestore data types to JSON serializable types.
    
    Args:
        data: The data to convert, can be a dict, list, or primitive type
        
    Returns:
        The converted data that is JSON serializable
    """
    if isinstance(data, dict):
        return {k: convert_firestore_data(v) for k, v in data.items()}
    elif isinstance(data, list):
        return [convert_firestore_data(item) for item in data]
    elif isinstance(data, (DatetimeWithNanoseconds, datetime)):
        # Convert to Unix timestamp (float)
        logger.debug(f"Converting datetime object to timestamp: {data}")
        return data.timestamp()
    elif hasattr(data, 'seconds') and hasattr(data, 'nanos'):
        # This handles any Timestamp-like object with seconds and nanos attributes
        # Convert to Unix timestamp (float)
        logger.debug(f"Converting timestamp object to float: {data}")
        return data.seconds + data.nanos / 1e9
    else:
        logger.debug(f"Returning data as-is: {data} (type: {type(data)})")
        return data

def firestore_data_to_json(data):
    """
    Convert Firestore data to a JSON string.
    
    Args:
        data: The Firestore data to convert
        
    Returns:
        A JSON string representation of the data
    """
    converted_data = convert_firestore_data(data)
    return json.dumps(converted_data) 