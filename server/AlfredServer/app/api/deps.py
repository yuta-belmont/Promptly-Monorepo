from typing import Generator, Optional
import time
import json
from jose.exceptions import JWTError, ExpiredSignatureError

from fastapi import Depends, HTTPException, status
from fastapi.security import OAuth2PasswordBearer
from jose import jwt
from pydantic import ValidationError
from sqlalchemy.orm import Session

from app.models.user import User
from app import schemas
from app.core import security
from app.core.config import settings
from app.db.session import get_db

oauth2_scheme = OAuth2PasswordBearer(tokenUrl=f"{settings.API_V1_STR}/auth/login")


def get_current_user(
    db: Session = Depends(get_db), token: str = Depends(oauth2_scheme)
) -> User:
    # Log token validation attempt (only first 10 chars for security)
    token_prefix = token[:10] + "..." if len(token) > 10 else token
    print(f"[AUTH LOG] Token validation attempt: {token_prefix} at {time.time()}")
    
    try:
        payload = jwt.decode(
            token, settings.SECRET_KEY, algorithms=[security.ALGORITHM]
        )
        token_data = schemas.TokenPayload(**payload)
        
        # Check if token has expired
        current_time = time.time()
        if "exp" in payload and payload["exp"] < current_time:
            # Token has expired
            print(f"[AUTH LOG] Token expired: exp={payload['exp']}, current={current_time}, diff={(current_time - payload['exp']) / 60} minutes")
            raise ExpiredSignatureError("Token expired")
            
        # Log successful decode
        print(f"[AUTH LOG] Token successfully decoded for subject: {token_data.sub}")
        
    except ExpiredSignatureError as e:
        print(f"[AUTH LOG] Token expired error: {str(e)}")
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Token has expired",
        )
    except (JWTError, ValidationError) as e:
        print(f"[AUTH LOG] Token validation error: {str(e)}")
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Could not validate credentials",
        )
        
    user = db.query(User).filter(User.id == token_data.sub).first()
    if not user:
        print(f"[AUTH LOG] User not found for token subject: {token_data.sub}")
        raise HTTPException(status_code=404, detail="User not found")
        
    # Log successful authentication
    print(f"[AUTH LOG] Authentication successful for user ID: {user.id}, email: {user.email}")
    return user


def get_current_active_user(
    current_user: User = Depends(get_current_user),
) -> User:
    if not current_user.is_active:
        print(f"[AUTH LOG] Inactive user attempted access: {current_user.id}")
        raise HTTPException(status_code=400, detail="Inactive user")
    return current_user


def get_current_active_superuser(
    current_user: User = Depends(get_current_user),
) -> User:
    if not current_user.is_superuser:
        print(f"[AUTH LOG] Non-superuser attempted privileged access: {current_user.id}")
        raise HTTPException(
            status_code=400, detail="The user doesn't have enough privileges"
        )
    return current_user 