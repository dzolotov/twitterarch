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
    title="Twitter Architecture - Step 2: Prepared Feed",
    description="Twitter-like API with pre-computed feeds",
    version="2.0.0",
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
        "message": "Twitter Architecture Demo - Step 2: Prepared Feed",
        "features": [
            "User management",
            "Tweet posting with feed fanout",
            "Follow/Unfollow with feed updates",
            "Pre-computed feeds for fast reads",
            "Synchronous feed updates (still blocking on tweet creation)"
        ]
    }