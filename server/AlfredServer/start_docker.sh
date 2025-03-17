#!/bin/bash
# Script to start Docker Compose services with the correct environment variables

# Load environment variables from the consolidated .env file
export $(grep -v '^#' ../.env | xargs)

# Start Docker Compose services
docker-compose up "$@" 