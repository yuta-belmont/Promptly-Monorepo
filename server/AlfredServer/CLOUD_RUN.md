# Deploying to Google Cloud Run

This document provides instructions for deploying the Promptly server to Google Cloud Run.

## Prerequisites

1. [Google Cloud SDK](https://cloud.google.com/sdk/docs/install) installed and configured
2. Docker installed locally
3. A Google Cloud project with billing enabled
4. Required APIs enabled:
   - Cloud Run API
   - Container Registry API or Artifact Registry API
   - Secret Manager API
   - Cloud SQL Admin API (for database)

## Local Testing

Before deploying to Cloud Run, test your container locally:

### Option 1: Using Docker Compose (Recommended)

```bash
# Start the server and database
docker-compose up
```

This will start both the PostgreSQL database and the API server.

### Option 2: Using the Setup Script

```bash
# Make the setup script executable if not already
chmod +x cloud-run-setup.sh

# Run the setup script
./cloud-run-setup.sh
```

Test your API endpoints to ensure everything works as expected.

## Database Setup

For production, you should use a managed database service like Cloud SQL:

1. **Create a PostgreSQL instance in Cloud SQL**:
   ```bash
   gcloud sql instances create promptly-db \
     --database-version=POSTGRES_13 \
     --tier=db-f1-micro \
     --region=us-central1 \
     --root-password=YOUR_ROOT_PASSWORD
   ```

2. **Create a database**:
   ```bash
   gcloud sql databases create promptly \
     --instance=promptly-db
   ```

3. **Create a user**:
   ```bash
   gcloud sql users create promptly-user \
     --instance=promptly-db \
     --password=YOUR_USER_PASSWORD
   ```

## Deployment Steps

1. **Authenticate with Google Cloud**:
   ```bash
   gcloud auth login
   gcloud config set project YOUR_PROJECT_ID
   ```

2. **Set up secrets**:
   ```bash
   # Create secrets for sensitive values
   gcloud secrets create openai-api-key --replication-policy="automatic"
   echo -n "your_actual_openai_api_key" | gcloud secrets versions add openai-api-key --data-file=-
   
   gcloud secrets create postgres-password --replication-policy="automatic"
   echo -n "YOUR_USER_PASSWORD" | gcloud secrets versions add postgres-password --data-file=-
   
   gcloud secrets create jwt-secret-key --replication-policy="automatic"
   echo -n "your_secure_random_string" | gcloud secrets versions add jwt-secret-key --data-file=-
   ```

3. **Build and push your container**:
   ```bash
   # Using Cloud Build
   gcloud builds submit --tag gcr.io/YOUR_PROJECT_ID/promptly-server
   
   # Or build locally and push
   docker build -t gcr.io/YOUR_PROJECT_ID/promptly-server .
   docker push gcr.io/YOUR_PROJECT_ID/promptly-server
   ```

4. **Deploy to Cloud Run with Cloud SQL connection**:
   ```bash
   gcloud run deploy promptly-server \
     --image gcr.io/YOUR_PROJECT_ID/promptly-server \
     --platform managed \
     --region us-central1 \
     --allow-unauthenticated \
     --add-cloudsql-instances YOUR_PROJECT_ID:us-central1:promptly-db \
     --set-env-vars="DEBUG=False,POSTGRES_SERVER=/cloudsql/YOUR_PROJECT_ID:us-central1:promptly-db,POSTGRES_DB=promptly,POSTGRES_USER=promptly-user" \
     --set-secrets="OPENAI_API_KEY=openai-api-key:latest,POSTGRES_PASSWORD=postgres-password:latest,SECRET_KEY=jwt-secret-key:latest"
   ```

## Environment Variables

Configure these environment variables in Cloud Run:

- `PORT`: Set automatically by Cloud Run
- `DEBUG`: Set to False in production
- `POSTGRES_SERVER`: Path to Cloud SQL socket
- `POSTGRES_USER`: Database user
- `POSTGRES_PASSWORD`: Database password (from Secret Manager)
- `POSTGRES_DB`: Database name
- `OPENAI_API_KEY`: OpenAI API key (from Secret Manager)
- `SECRET_KEY`: JWT secret key (from Secret Manager)

## Database Migrations

To run migrations on the deployed database:

1. **Connect to the database**:
   ```bash
   gcloud sql connect promptly-db --user=promptly-user
   ```

2. **Run migrations using a temporary Cloud Run job**:
   ```bash
   gcloud run jobs create migration-job \
     --image gcr.io/YOUR_PROJECT_ID/promptly-server \
     --set-cloudsql-instances YOUR_PROJECT_ID:us-central1:promptly-db \
     --set-env-vars="POSTGRES_SERVER=/cloudsql/YOUR_PROJECT_ID:us-central1:promptly-db,POSTGRES_DB=promptly,POSTGRES_USER=promptly-user" \
     --set-secrets="POSTGRES_PASSWORD=postgres-password:latest,SECRET_KEY=jwt-secret-key:latest" \
     --command="alembic" \
     --args="upgrade,head"
   
   gcloud run jobs execute migration-job
   ```

## Monitoring and Logs

Access logs and monitoring:
```bash
gcloud logging read "resource.type=cloud_run_revision AND resource.labels.service_name=promptly-server" --limit=10
```

View the Cloud Run dashboard for metrics on request volume, latency, and errors.

## Scaling and Cost Management

Cloud Run automatically scales based on traffic. To control costs:

1. Set concurrency and maximum instances:
   ```bash
   gcloud run services update promptly-server \
     --concurrency=80 \
     --max-instances=10
   ```

2. Set CPU allocation to "CPU is only allocated during request processing" for cost efficiency.

## Troubleshooting

If your deployment fails:
1. Check container logs in Cloud Run console
2. Verify your container works locally
3. Ensure all required environment variables and secrets are set
4. Check that your service account has necessary permissions
5. Verify database connectivity by checking the logs 