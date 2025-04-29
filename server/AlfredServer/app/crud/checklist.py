from typing import Optional, List, Dict, Any
from sqlalchemy.orm import Session
from sqlalchemy import and_, desc
from datetime import datetime, timedelta

from app.models.checklist import Checklist, ChecklistItem, SubItem
from app.models.user import User
from app.models.group import Group

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
        Handles both new checklist creation and updates to existing ones.
        """
        # Get or create the checklist
        checklist = db.query(Checklist).filter(
            Checklist.user_id == user_id,
            Checklist.date == checklist_data["date"]
        ).first()

        if not checklist:
            checklist = Checklist(
                user_id=user_id,
                date=checklist_data["date"],
                notes=checklist_data.get("notes", "")
            )
            db.add(checklist)
            db.flush()  # Get the ID for the new checklist

        # Clear existing items
        db.query(ChecklistItem).filter(ChecklistItem.checklist_id == checklist.id).delete()

        # Create new items
        for item_data in checklist_data.get("items", []):
            # Create or get the group
            group = None
            if "group" in item_data and item_data["group"]:
                group = db.query(Group).filter(Group.id == item_data["group"]["id"]).first()
                if not group:
                    group = Group(
                        name=item_data["group"]["name"],
                        notes=item_data["group"].get("notes")
                    )
                    db.add(group)
                    db.flush()

            item = ChecklistItem(
                title=item_data["title"],
                is_completed=item_data.get("is_completed", False),
                notification=item_data.get("notification"),
                checklist=checklist,
                group=group
            )
            db.add(item)
            
            # Create sub-items if any
            for subitem_data in item_data.get("subitems", []):
                subitem = SubItem(
                    title=subitem_data["title"],
                    is_completed=subitem_data.get("is_completed", False),
                    checklist_item=item
                )
                db.add(subitem)
        
        db.commit()
        db.refresh(checklist)
        return checklist
        
    def get_recent_checklists(
        db: Session,
        user_id: str,
        days_back: int
    ) -> List[Dict[str, Any]]:
        """
        Get recent checklists for a user within the specified number of days.
        
        Args:
            db: Database session
            user_id: The user ID to get checklists for
            days_back: Number of days to look back
            
        Returns:
            A list of serialized checklists with their items and subitems
        """
        # Calculate the date threshold
        today = datetime.now().date()
        start_date = (today - timedelta(days=days_back)).strftime("%Y-%m-%d")
        
        # Query checklists within the date range, ordered by date descending
        checklists = db.query(Checklist).filter(
            and_(
                Checklist.user_id == user_id,
                Checklist.date >= start_date
            )
        ).order_by(desc(Checklist.date)).all()
        
        # Serialize the checklists with their items and subitems
        result = []
        for checklist in checklists:
            checklist_dict = {
                "date": checklist.date,
                "notes": checklist.notes,
                "items": []
            }
            
            for item in checklist.items:
                item_dict = {
                    "title": item.title,
                    "is_completed": item.is_completed,
                    "group_name": item.group.name if item.group else None,
                    "notification": item.notification,
                    "subitems": []
                }
                
                for subitem in item.sub_items:
                    subitem_dict = {
                        "title": subitem.title,
                        "is_completed": subitem.is_completed
                    }
                    item_dict["subitems"].append(subitem_dict)
                
                checklist_dict["items"].append(item_dict)
            
            result.append(checklist_dict)
        
        return result 