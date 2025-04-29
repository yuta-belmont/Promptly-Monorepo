from sqlalchemy import Boolean, Column, String, DateTime, ForeignKey, Text, Index, UniqueConstraint, Float
from sqlalchemy.sql import func
from sqlalchemy.orm import relationship
import uuid

from app.db.base_class import Base
from app.models.group import Group

class Checklist(Base):
    __tablename__ = "checklists"

    id = Column(String, primary_key=True, index=True, default=lambda: str(uuid.uuid4()))
    date = Column(String, nullable=False)  # YYYY-MM-DD format
    notes = Column(Text, nullable=True)
    user_id = Column(String, ForeignKey("users.id"), nullable=False)
    created_at = Column(DateTime(timezone=True), server_default=func.now())
    updated_at = Column(DateTime(timezone=True), onupdate=func.now())

    # Relationships
    user = relationship("User", back_populates="checklists")
    items = relationship("ChecklistItem", back_populates="checklist", cascade="all, delete-orphan")

    # Unique constraint for one checklist per day per user
    __table_args__ = (
        UniqueConstraint('user_id', 'date', name='uix_user_date'),
        Index('ix_checklists_user_date', 'user_id', 'date'),
    )

class ChecklistItem(Base):
    __tablename__ = "checklist_items"

    id = Column(String, primary_key=True, index=True, default=lambda: str(uuid.uuid4()))
    title = Column(String, nullable=False)
    notification = Column(DateTime(timezone=True), nullable=True)
    is_completed = Column(Boolean, default=False)
    
    # Foreign Keys
    checklist_id = Column(String, ForeignKey("checklists.id"), nullable=False)
    group_id = Column(String, ForeignKey("groups.id"), nullable=True)
    
    # Relationships
    checklist = relationship("Checklist", back_populates="items")
    group = relationship("Group", back_populates="items")
    sub_items = relationship("SubItem", back_populates="checklist_item", cascade="all, delete-orphan")

    # Index for completion queries
    __table_args__ = (
        Index('ix_checklist_items_completion', 'checklist_id', 'is_completed'),
    )

class SubItem(Base):
    __tablename__ = "sub_items"

    id = Column(String, primary_key=True, index=True, default=lambda: str(uuid.uuid4()))
    title = Column(String, nullable=False)
    is_completed = Column(Boolean, default=False)
    
    # Foreign Keys
    checklist_item_id = Column(String, ForeignKey("checklist_items.id"), nullable=False)
    
    # Relationships
    checklist_item = relationship("ChecklistItem", back_populates="sub_items") 