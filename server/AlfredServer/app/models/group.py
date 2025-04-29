from sqlalchemy import Column, String, Text, ForeignKey
from sqlalchemy.orm import relationship
import uuid

from app.db.base_class import Base

class Group(Base):
    __tablename__ = "groups"

    id = Column(String, primary_key=True, index=True, default=lambda: str(uuid.uuid4()))
    name = Column(String, nullable=False)
    notes = Column(Text, nullable=True)

    # Relationships
    items = relationship("ChecklistItem", back_populates="group") 