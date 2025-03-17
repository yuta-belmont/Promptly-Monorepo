# Alfred Server

Backend server for the Alfred application.

## Setup

### Prerequisites
- Docker
- Docker Compose

### Installation

1. Clone this repository
   ```bash
   git clone https://github.com/yourusername/AlfredServer.git
   cd AlfredServer
   ```

2. Make sure the `.env` file exists with the following variables:
   ```
   # API Configuration
   OPENAI_API_KEY=your_openai_api_key

   # Security
   SECRET_KEY=your_secret_key_here

   # Database
   POSTGRES_SERVER=db
   POSTGRES_USER=postgres
   POSTGRES_PASSWORD=postgres
   POSTGRES_DB=promptly

   # Environment
   DEBUG=True
   ```

3. Run the server using Docker Compose:
   ```bash
   ./run.sh up -d
   ```

4. The server will be available at http://localhost:8080

## Development

### Running the Server

- Start the server: `./run.sh up -d`
- Stop the server: `./run.sh down`
- View logs: `./run.sh logs -f`
- Restart the server: `./run.sh restart`

### Database Migrations

Database migrations are handled using Alembic:

- Run migrations: `./run.sh exec api alembic upgrade head`
- Create a new migration: `./run.sh exec api alembic revision --autogenerate -m "description"`

## Deployment

For deployment to Google Cloud Run, see the [CLOUD_RUN.md](CLOUD_RUN.md) file.

## API Documentation

### Authentication
- POST /api/auth/login - User login
- POST /api/auth/register - User registration

### Other Endpoints
- GET /api/users/me - Get current user information 