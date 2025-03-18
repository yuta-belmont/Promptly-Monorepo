from sqlalchemy import create_engine
from sqlalchemy.ext.declarative import declarative_base
from sqlalchemy.orm import sessionmaker

from app.core.config import settings

# Configure engine with connection pool settings
engine = create_engine(
    settings.DATABASE_URI,
    # Recycle connections after 4 minutes (before PostgreSQL's default idle timeout)
    pool_recycle=240,
    # Test connections on checkout to avoid using stale connections
    pool_pre_ping=True,
    # Only keep a few connections in the pool for workers
    pool_size=5,
    # Allow some overflow connections during traffic spikes
    max_overflow=10
)
SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)

Base = declarative_base()

# Dependency to get DB session
def get_db():
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close() 