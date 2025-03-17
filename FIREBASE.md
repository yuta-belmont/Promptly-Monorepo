# Firebase Integration for Promptly

This document explains how to set up and use the Firebase integration for the Promptly application.

## Setup

1. **Firebase Credentials**: Place your Firebase service account credentials JSON file in the `server/AlfredServer/firebase-credentials/` directory.

2. **Environment Variables**: Update the `.env` file in the root directory with the following Firebase-related variables:

```
FIREBASE_SERVICE_ACCOUNT=./server/AlfredServer/firebase-credentials/your-credentials-file.json
FIREBASE_PROJECT_ID=your-firebase-project-id
```

## Running the Workers

The application uses background workers to process tasks asynchronously. These workers interact with Firebase Firestore to store and retrieve data.

To run the workers:

```bash
# Run both message and checklist workers
./run_workers.py

# Run only the message worker
./run_workers.py --message-only

# Run only the checklist worker
./run_workers.py --checklist-only
```

## Testing the Firebase Connection

You can test the Firebase connection using the test scripts in the `server/AlfredServer/` directory:

```bash
# Test the basic Firebase connection
cd server/AlfredServer
python3 test_firebase.py

# Test adding a task to Firestore
python3 test_add_task.py

# Test the worker processing
python3 test_worker_processing.py
```

## Firebase Data Structure

The application uses the following Firestore collections:

- `checklist_tasks`: Stores tasks to be processed by the checklist worker
- `users/{user_id}/chats/{chat_id}/messages/{message_id}`: Stores chat messages and generated checklists

## Troubleshooting

If you encounter issues with the Firebase connection:

1. Check that your Firebase credentials file exists and is correctly formatted
2. Verify that the environment variables are set correctly
3. Check the worker logs for error messages:
   ```bash
   cd server/AlfredServer
   cat worker.log
   ```

## Security Considerations

- Keep your Firebase credentials secure and never commit them to version control
- Use Firebase Security Rules to restrict access to your Firestore data
- Consider using Firebase Authentication to secure your application 