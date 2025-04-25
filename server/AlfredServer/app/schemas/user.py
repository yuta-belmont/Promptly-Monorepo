from typing import Optional
from enum import Enum
from datetime import datetime

from pydantic import BaseModel, EmailStr


class PlanType(str, Enum):
    free = "free"
    plus = "plus"
    pro = "pro"
    credit = "credit"


# Shared properties
class UserBase(BaseModel):
    email: Optional[EmailStr] = None
    is_active: Optional[bool] = True
    is_superuser: bool = False
    full_name: Optional[str] = None
    plan: PlanType = PlanType.free
    is_admin: bool = False
    plan_expiry: Optional[datetime] = None


# Properties to receive via API on creation
class UserCreate(UserBase):
    email: EmailStr
    password: str


# Properties to receive via API on update
class UserUpdate(UserBase):
    password: Optional[str] = None


class UserInDBBase(UserBase):
    id: Optional[str] = None

    class Config:
        from_attributes = True


# Additional properties to return via API
class User(UserInDBBase):
    pass


# Additional properties stored in DB
class UserInDB(UserInDBBase):
    hashed_password: str 