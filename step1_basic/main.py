import sys
from pathlib import Path
sys.path.append(str(Path(__file__).parent.parent))

from fastapi import FastAPI
from contextlib import asynccontextmanager
from common.database import engine
from common.models import Base
from common.init_db import init_database
from step1_basic.app.api import users, tweets, subscriptions, feed
import asyncio
import os

@asynccontextmanager
async def lifespan(app: FastAPI):
    # Startup - Initialize database based on DB_TYPE
    loop = asyncio.get_event_loop()
    await loop.run_in_executor(None, init_database)
    
    db_type = os.getenv('DB_TYPE', 'postgres')
    print(f"\nStep 1 running in {db_type.upper()} mode")
    
    yield
    # Shutdown
    await engine.dispose()


app = FastAPI(
    title="Twitter Architecture - Step 1: Basic",
    description="Simple synchronous Twitter-like API",
    version="1.0.0",
    lifespan=lifespan
)

# Include routers
app.include_router(users.router, prefix="/api/users", tags=["users"])
app.include_router(tweets.router, prefix="/api/tweets", tags=["tweets"])
app.include_router(subscriptions.router, prefix="/api/subscriptions", tags=["subscriptions"])
app.include_router(feed.router, prefix="/api/feed", tags=["feed"])


@app.get("/")
async def root():
    return {
        "message": "Twitter Architecture Demo - Step 1: Basic Synchronous",
        "features": [
            "User management",
            "Tweet posting",
            "Follow/Unfollow",
            "Real-time feed generation (slow with many followers)"
        ]
    }