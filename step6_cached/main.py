import sys
from pathlib import Path
sys.path.append(str(Path(__file__).parent.parent))

from fastapi import FastAPI
from contextlib import asynccontextmanager
import asyncio
from common.database import engine
from common.models import Base
from app.api import users, tweets, subscriptions, feed
from app.services.cache_service import CacheService
from app.services.rabbitmq_service import RabbitMQService
from app.workers.feed_worker import FeedWorker

# Global instances
cache_service = None
workers = []

@asynccontextmanager
async def lifespan(app: FastAPI):
    global cache_service, workers
    
    # Startup
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)
    
    # Initialize cache
    cache_service = CacheService()
    await cache_service.initialize()
    app.state.cache_service = cache_service  # Make available to routes
    
    # Initialize RabbitMQ
    rabbitmq = RabbitMQService()
    await rabbitmq.connect()
    await rabbitmq.setup_exchanges()
    await rabbitmq.close()
    
    # Start multiple workers
    for i in range(4):
        worker = FeedWorker(i, cache_service)
        worker_task = asyncio.create_task(worker.start())
        workers.append((worker, worker_task))
    
    yield
    
    # Shutdown
    for worker, task in workers:
        await worker.stop()
        task.cancel()
        try:
            await task
        except asyncio.CancelledError:
            pass
    
    await cache_service.close()
    await engine.dispose()


app = FastAPI(
    title="Twitter Architecture - Step 6: Cached with Circular Buffers",
    description="High-performance Twitter-like API with Redis caching and circular buffers",
    version="6.0.0",
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
        "message": "Twitter Architecture Demo - Step 6: Cached Architecture",
        "features": [
            "Redis cache with circular buffers",
            "Hot feed caching",
            "Message deduplication cache",
            "Cache warming strategies",
            "Automatic cache invalidation",
            "10x performance improvement"
        ]
    }


@app.get("/cache/stats")
async def cache_stats():
    """Get cache statistics"""
    if cache_service:
        return await cache_service.get_stats()
    return {"error": "Cache not initialized"}