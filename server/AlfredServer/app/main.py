from fastapi import FastAPI, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles
from fastapi.templating import Jinja2Templates
from fastapi.responses import HTMLResponse, FileResponse, JSONResponse
from fastapi.exceptions import RequestValidationError
import os
import logging
import json

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
    version="0.1.0",
    openapi_url=f"{settings.API_V1_STR}/openapi.json"
)

@app.exception_handler(RequestValidationError)
async def validation_exception_handler(request: Request, exc: RequestValidationError):
    print("🚨 Validation Error Details:")
    body = await request.body()
    print(f"Raw request body: {body.decode()}")
    print("Validation errors:")
    for error in exc.errors():
        print(f"  Location: {' -> '.join(str(loc) for loc in error['loc'])}")
        print(f"  Message: {error['msg']}")
        print(f"  Error Type: {error['type']}")
    return JSONResponse(
        status_code=422,
        content={"detail": [
            {
                "loc": error["loc"],
                "msg": error["msg"],
                "type": error["type"]
            } for error in exc.errors()
        ]}
    )

# Set all CORS enabled origins
if settings.BACKEND_CORS_ORIGINS:
    app.add_middleware(
        CORSMiddleware,
        allow_origins=[str(origin) for origin in settings.BACKEND_CORS_ORIGINS],
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