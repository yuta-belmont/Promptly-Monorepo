#!/bin/bash

# Navigate to the AlfredServer directory
cd "$(dirname "$0")/AlfredServer"

# Run docker-compose with any passed arguments
docker-compose "$@" 