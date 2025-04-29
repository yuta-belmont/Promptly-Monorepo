from sqlalchemy import text
from app.db.session import SessionLocal

def init_db() -> None:
    db = SessionLocal()
    try:
        # Create groups table
        db.execute(text("""
            CREATE TABLE IF NOT EXISTS groups (
                id VARCHAR(36) PRIMARY KEY,
                name VARCHAR(255) NOT NULL,
                notes TEXT
            );
        """))
        
        # Add group_id column to checklist_items if it doesn't exist
        db.execute(text("""
            DO $$ 
            BEGIN
                IF NOT EXISTS (
                    SELECT 1 
                    FROM information_schema.columns 
                    WHERE table_name = 'checklist_items' 
                    AND column_name = 'group_id'
                ) THEN
                    ALTER TABLE checklist_items 
                    ADD COLUMN group_id VARCHAR(36);
                END IF;
            END $$;
        """))
        
        # Add foreign key constraint if it doesn't exist
        db.execute(text("""
            DO $$ 
            BEGIN
                IF NOT EXISTS (
                    SELECT 1 
                    FROM information_schema.table_constraints 
                    WHERE constraint_name = 'checklist_items_group_id_fkey'
                ) THEN
                    ALTER TABLE checklist_items 
                    ADD CONSTRAINT checklist_items_group_id_fkey 
                    FOREIGN KEY (group_id) 
                    REFERENCES groups(id);
                END IF;
            END $$;
        """))
        
        # Update sub_items foreign key to cascade delete
        db.execute(text("""
            DO $$ 
            BEGIN
                -- First drop the existing constraint if it exists
                IF EXISTS (
                    SELECT 1 
                    FROM information_schema.table_constraints 
                    WHERE constraint_name = 'sub_items_checklist_item_id_fkey'
                ) THEN
                    ALTER TABLE sub_items 
                    DROP CONSTRAINT sub_items_checklist_item_id_fkey;
                END IF;
                
                -- Add the new constraint with ON DELETE CASCADE
                ALTER TABLE sub_items 
                ADD CONSTRAINT sub_items_checklist_item_id_fkey 
                FOREIGN KEY (checklist_item_id) 
                REFERENCES checklist_items(id) 
                ON DELETE CASCADE;
            END $$;
        """))
        
        db.commit()
    except Exception as e:
        db.rollback()
        raise e
    finally:
        db.close() 