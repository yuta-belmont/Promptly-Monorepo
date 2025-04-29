from app.models.user import User, PlanType
from app.db.session import SessionLocal
from datetime import datetime, timedelta

def upgrade_user_to_pro(email):
    """Upgrade a user to Pro plan with 1 year expiry."""
    # Create a database session
    db = SessionLocal()

    try:
        # Find user by email
        user = db.query(User).filter(User.email == email).first()

        if user:
            # Print current status
            print(f'Current plan: {user.plan}')
            print(f'Current expiry: {user.plan_expiry}')
            
            # Update to Pro plan with 1 year expiry
            user.plan = PlanType.pro
            user.plan_expiry = datetime.now() + timedelta(days=365)
            
            # Commit the changes
            db.commit()
            
            # Verify changes
            print(f'Updated plan: {user.plan}')
            print(f'Updated expiry: {user.plan_expiry}')
            print('Account successfully upgraded to Pro!')
        else:
            print(f'User not found with email: {email}')
    finally:
        db.close()

if __name__ == "__main__":
    # Update the user with the specified email
    upgrade_user_to_pro('yutabel@gmail.com') 