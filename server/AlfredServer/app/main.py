from fastapi import FastAPI, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles
from fastapi.templating import Jinja2Templates
from fastapi.responses import HTMLResponse, FileResponse
import os
import logging

from app.api import auth, users, chat
from app.core.config import settings
from app.db.base import Base
from app.db.session import engine

# Set up logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger("alfred")

# Create tables if they don't exist
Base.metadata.create_all(bind=engine)

# Log important settings at startup
logger.info("⚙️ SERVER SETTINGS ⚙️")
logger.info(f"API Version: {settings.API_V1_STR}")
logger.info(f"Token Expiration: {settings.ACCESS_TOKEN_EXPIRE_MINUTES} minutes")
# Don't log the actual SECRET_KEY, just whether it's from env or random
if os.getenv("SECRET_KEY"):
    logger.info("SECRET_KEY: Using persistent key from environment")
else:
    logger.info("⚠️ SECRET_KEY: Using randomly generated key - tokens will invalidate on restart!")

app = FastAPI(
    title="Alfred - Your Personal Life Assistant",
    description="Backend API for Alfred mobile app AI communication",
    version="0.1.0"
)

# CORS middleware setup
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],  # Update with specific origins in production
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Mount static files
app.mount("/static", StaticFiles(directory="app/static"), name="static")

@app.get("/", response_class=HTMLResponse)
async def read_root():
    # Return the index.html file
    return FileResponse("app/static/index.html")

@app.get("/health")
def health_check():
    return {"status": "ok"}

# Include routers
app.include_router(auth.router, prefix=settings.API_V1_STR)
app.include_router(users.router, prefix=settings.API_V1_STR)
app.include_router(chat.router, prefix=settings.API_V1_STR) 