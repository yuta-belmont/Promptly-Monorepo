#!/bin/bash
set -e

# Configuration
IMAGE_NAME="promptly-server"
PORT=8080

echo "Building Docker image..."
docker build -t $IMAGE_NAME .

echo "Running container locally on port $PORT..."
docker run -p $PORT:$PORT \
  -e PORT=$PORT \
  -e OPENAI_API_KEY="your_test_key_here" \
  -e DEBUG=True \
  --name $IMAGE_NAME-container \
  $IMAGE_NAME

# The container will keep running. To stop it:
# docker stop $IMAGE_NAME-container
# docker rm $IMAGE_NAME-container

# To deploy to Cloud Run, you would use:
# gcloud builds submit --tag gcr.io/YOUR_PROJECT_ID/$IMAGE_NAME
# gcloud run deploy --image gcr.io/YOUR_PROJECT_ID/$IMAGE_NAME --platform managed 