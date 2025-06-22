from sqlalchemy.ext.asyncio import create_async_engine, AsyncSession, async_sessionmaker
from sqlalchemy.ext.declarative import declarative_base
from sqlalchemy.orm import sessionmaker
from sqlalchemy import create_engine
from .config import get_settings

settings = get_settings()

# Async engine for FastAPI
engine = create_async_engine(settings.database_url, echo=settings.debug)
async_session_maker = async_sessionmaker(engine, class_=AsyncSession, expire_on_commit=False)

# Sync engine for migrations and scripts
sync_engine = create_engine(settings.database_url_sync, echo=settings.debug)
SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=sync_engine)

Base = declarative_base()


async def get_async_session():
    async with async_session_maker() as session:
        yield session


def get_db():
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()