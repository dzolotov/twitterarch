import sys
from pathlib import Path
sys.path.append(str(Path(__file__).parent.parent))

from fastapi import FastAPI
from contextlib import asynccontextmanager
import asyncio
from common.database import engine
from common.models import Base
from app.api import users, tweets, subscriptions, feed
from app.workers.feed_worker import FeedWorker
from app.services.rabbitmq_service import RabbitMQService

# Global worker instance
feed_worker = None
worker_task = None

@asynccontextmanager
async def lifespan(app: FastAPI):
    global feed_worker, worker_task
    
    # Startup
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)
    
    # Initialize RabbitMQ
    rabbitmq = RabbitMQService()
    await rabbitmq.connect()
    await rabbitmq.setup_exchanges()
    await rabbitmq.close()
    
    # Start feed worker in background
    feed_worker = FeedWorker()
    worker_task = asyncio.create_task(feed_worker.start())
    
    yield
    
    # Shutdown
    if feed_worker:
        await feed_worker.stop()
    if worker_task:
        worker_task.cancel()
        try:
            await worker_task
        except asyncio.CancelledError:
            pass
    await engine.dispose()


app = FastAPI(
    title="Twitter Architecture - Step 3: Async Feed",
    description="Twitter-like API with asynchronous feed updates via RabbitMQ",
    version="3.0.0",
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
        "message": "Twitter Architecture Demo - Step 3: Async Feed with RabbitMQ",
        "features": [
            "User management",
            "Non-blocking tweet posting",
            "Asynchronous feed updates via RabbitMQ",
            "Background feed worker",
            "Better write performance"
        ]
    }