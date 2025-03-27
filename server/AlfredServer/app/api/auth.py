from datetime import timedelta, datetime
from typing import Any
import time

from fastapi import APIRouter, Body, Depends, HTTPException
from fastapi.security import OAuth2PasswordRequestForm
from sqlalchemy.orm import Session
from jose import jwt

from app import crud, schemas
from app.models.user import User
from app.api import deps
from app.core import security
from app.core.config import settings

router = APIRouter(prefix="/auth", tags=["auth"])


@router.post("/login", response_model=schemas.Token)
def login_access_token(
    db: Session = Depends(deps.get_db), form_data: OAuth2PasswordRequestForm = Depends()
) -> Any:
    """
    OAuth2 compatible token login, get an access token for future requests
    """
    print(f"[AUTH LOG] Login attempt for username: {form_data.username}")
    
    user = crud.user.authenticate(
        db, email=form_data.username, password=form_data.password
    )
    if not user:
        print(f"[AUTH LOG] Authentication failed for username: {form_data.username}")
        raise HTTPException(status_code=400, detail="Incorrect email or password")
    elif not crud.user.is_active(user):
        print(f"[AUTH LOG] Inactive user attempted login: {form_data.username}")
        raise HTTPException(status_code=400, detail="Inactive user")
        
    access_token_expires = timedelta(minutes=settings.ACCESS_TOKEN_EXPIRE_MINUTES)
    current_time = time.time()
    expiration_time = current_time + (settings.ACCESS_TOKEN_EXPIRE_MINUTES * 60)
    
    token = security.create_access_token(
        user.id, expires_delta=access_token_expires
    )
    
    # Decode token to log expiration details
    try:
        decoded_token = jwt.decode(
            token, settings.SECRET_KEY, algorithms=[security.ALGORITHM]
        )
        expiration = decoded_token.get("exp", "unknown")
        print(f"[AUTH LOG] Token issued for user: {user.id}, email: {user.email}")
        print(f"[AUTH LOG] Token expiration: {datetime.fromtimestamp(expiration).isoformat()}")
        print(f"[AUTH LOG] Token lifetime: {settings.ACCESS_TOKEN_EXPIRE_MINUTES} minutes")
    except Exception as e:
        print(f"[AUTH LOG] Error decoding token for logging: {str(e)}")
    
    return {
        "access_token": token,
        "token_type": "bearer",
    }


@router.post("/register", response_model=schemas.User)
def register_user(
    *,
    db: Session = Depends(deps.get_db),
    user_in: schemas.UserCreate,
) -> Any:
    """
    Register a new user
    """
    user = crud.user.get_by_email(db, email=user_in.email)
    if user:
        raise HTTPException(
            status_code=400,
            detail="A user with this email already exists",
        )
    user = crud.user.create(db, obj_in=user_in)
    return user


@router.get("/me", response_model=schemas.User)
def read_users_me(
    current_user: User = Depends(deps.get_current_active_user),
) -> Any:
    """
    Get current user
    """
    return current_user 