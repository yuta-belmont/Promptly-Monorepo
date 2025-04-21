from sqlalchemy import Boolean, Column, String, DateTime
from sqlalchemy.sql import func
from sqlalchemy.orm import relationship
import uuid

from app.db.base_class import Base


class User(Base):
    __tablename__ = "users"

    id = Column(String, primary_key=True, index=True, default=lambda: str(uuid.uuid4()))
    email = Column(String, unique=True, index=True, nullable=False)
    hashed_password = Column(String, nullable=False)
    full_name = Column(String, index=True)
    is_active = Column(Boolean, default=True)
    is_superuser = Column(Boolean, default=False)
    created_at = Column(DateTime(timezone=True), server_default=func.now())
    updated_at = Column(DateTime(timezone=True), onupdate=func.now())
    
    # Add relationship to checklists
    checklists = relationship("Checklist", back_populates="user", cascade="all, delete-orphan")
    
    # Relationships have been removed as we've moved to a stateless architecture
    # The Chat model has been removed from the application 