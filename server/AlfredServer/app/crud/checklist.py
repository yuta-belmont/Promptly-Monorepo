from typing import Optional, List, Dict, Any
from sqlalchemy.orm import Session
from sqlalchemy import and_

from app.models.checklist import Checklist, ChecklistItem, SubItem
from app.models.user import User

class ChecklistCRUD:
    def get_by_user_and_date(
        db: Session, 
        user_id: str, 
        date: str
    ) -> Optional[Checklist]:
        """Get a checklist by user_id and date."""
        return db.query(Checklist).filter(
            and_(
                Checklist.user_id == user_id,
                Checklist.date == date
            )
        ).first()
    
    def create_or_update_checklist(
        db: Session,
        user_id: str,
        checklist_data: Dict[str, Any]
    ) -> Checklist:
        """
        Create or update a checklist for a user.
        If a checklist exists for the given date, it will be updated.
        """
        date = checklist_data["date"]
        
        # Try to get existing checklist
        checklist = ChecklistCRUD.get_by_user_and_date(db, user_id, date)
        
        if checklist:
            # Update existing checklist
            checklist.notes = checklist_data.get("notes")
            # Delete existing items (cascade will handle sub_items)
            for item in checklist.items:
                db.delete(item)
        else:
            # Create new checklist
            checklist = Checklist(
                user_id=user_id,
                date=date,
                notes=checklist_data.get("notes")
            )
            db.add(checklist)
        
        # Create new items
        for item_data in checklist_data.get("items", []):
            item = ChecklistItem(
                title=item_data["title"],
                is_completed=item_data["is_completed"],
                group_name=item_data["group_name"],
                notification=item_data.get("notification"),
                checklist=checklist
            )
            db.add(item)
            
            # Create sub-items if any
            for subitem_data in item_data.get("subitems", []):
                subitem = SubItem(
                    title=subitem_data["title"],
                    is_completed=subitem_data["is_completed"],
                    checklist_item=item
                )
                db.add(subitem)
        
        db.commit()
        db.refresh(checklist)
        return checklist 