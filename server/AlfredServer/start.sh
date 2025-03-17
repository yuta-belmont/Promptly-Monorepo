#!/bin/bash
set -e

echo "Waiting for database..."
sleep 5

echo "Running migrations..."
alembic upgrade head || echo "Migration failed, continuing anyway"

mkdir -p /app/firebase-credentials

if [ ! -f "/app/firebase-credentials/alfred-9fa73-firebase-adminsdk-fbsvc-294854bb8e.json" ]; then
    echo "Firebase credentials file not found, creating a placeholder..."
    echo '{
        "type": "service_account",
        "project_id": "alfred-9fa73",
        "private_key_id": "placeholder",
        "private_key": "-----BEGIN PRIVATE KEY-----\nMIIEvQIBADANBgkqhkiG9w0BAQEFAASCBKcwggSjAgEAAoIBAQC7VJTUt9Us8cKj\nMzEfYyjiWA4R4/M2bS1GB4t7NXp98C3SC6dVMvDuictGeurT8jNbvJZHtCSuYEvu\nNMoSfm76oqFvAp8Gy0iz5sxjZmSnXyCdPEovGhLa0VzMaQ8s+CLOyS56YyCFGeJZ\n-----END PRIVATE KEY-----\n",
        "client_email": "firebase-adminsdk-fbsvc@alfred-9fa73.iam.gserviceaccount.com",
        "client_id": "placeholder",
        "auth_uri": "https://accounts.google.com/o/oauth2/auth",
        "token_uri": "https://oauth2.googleapis.com/token",
        "auth_provider_x509_cert_url": "https://www.googleapis.com/oauth2/v1/certs",
        "client_x509_cert_url": "placeholder"
    }' > /app/firebase-credentials/alfred-9fa73-firebase-adminsdk-fbsvc-294854bb8e.json
fi

echo "Starting application..."
exec uvicorn app.main:app --host 0.0.0.0 --port ${PORT:-8080} 