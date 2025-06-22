import sys
from pathlib import Path
sys.path.append(str(Path(__file__).parent.parent))

from fastapi import FastAPI
from contextlib import asynccontextmanager
import asyncio
import multiprocessing
from common.database import engine
from common.models import Base
from app.api import users, tweets, subscriptions, feed
from app.workers.feed_worker import FeedWorker
from app.services.rabbitmq_service import RabbitMQService

# Number of workers based on CPU cores
NUM_WORKERS = min(multiprocessing.cpu_count(), 4)

@asynccontextmanager
async def lifespan(app: FastAPI):
    # Startup
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)
    
    # Initialize RabbitMQ with consistent hash exchange
    rabbitmq = RabbitMQService()
    await rabbitmq.connect()
    await rabbitmq.setup_exchanges()
    await rabbitmq.close()
    
    # Note: In production, workers would run as separate processes
    # For demo purposes, we'll show the configuration
    print(f"Configured for {NUM_WORKERS} workers with consistent hash exchange")
    
    yield
    
    # Shutdown
    await engine.dispose()


app = FastAPI(
    title="Twitter Architecture - Step 4: Multi-Consumer",
    description="Twitter-like API with multiple consumers and consistent hash routing",
    version="4.0.0",
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
        "message": "Twitter Architecture Demo - Step 4: Multi-Consumer",
        "features": [
            "Multiple feed workers for parallel processing",
            "Consistent hash exchange for even distribution",
            "Each follower update is a separate message",
            "Horizontal scaling of feed updates",
            f"Configured for {NUM_WORKERS} workers"
        ]
    }


@app.get("/workers/status")
async def workers_status():
    """Get worker configuration status"""
    return {
        "num_workers": NUM_WORKERS,
        "exchange_type": "x-consistent-hash",
        "routing_strategy": "user_id based routing",
        "message": "Run worker.py separately for each worker instance"
    }