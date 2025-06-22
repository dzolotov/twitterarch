import sys
from pathlib import Path
sys.path.append(str(Path(__file__).parent.parent))

from fastapi import FastAPI
from contextlib import asynccontextmanager
from common.database import engine
from common.models import Base
from app.api import users, tweets, subscriptions, feed

@asynccontextmanager
async def lifespan(app: FastAPI):
    # Startup
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)
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