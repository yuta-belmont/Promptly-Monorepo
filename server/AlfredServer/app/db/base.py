# Import all the models, so that Base has them before being imported by Alembic
from app.db.base_class import Base
from app.models.user import User
# Chat models have been removed as we're now using a stateless architecture 