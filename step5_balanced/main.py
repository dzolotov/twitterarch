import sys
from pathlib import Path
sys.path.append(str(Path(__file__).parent.parent))

from fastapi import FastAPI
from contextlib import asynccontextmanager
import asyncio
import multiprocessing
from prometheus_client import make_asgi_app, Counter, Histogram, Gauge
from common.database import engine
from common.models import Base
from app.api import users, tweets, subscriptions, feed
from app.services.rabbitmq_service import RabbitMQService
from app.services.metrics_service import MetricsService

# Prometheus metrics
tweet_counter = Counter('tweets_created_total', 'Total number of tweets created')
feed_update_counter = Counter('feed_updates_total', 'Total number of feed updates')
api_request_duration = Histogram('api_request_duration_seconds', 'API request duration')
active_workers = Gauge('active_workers', 'Number of active workers')

# Number of workers
NUM_WORKERS = min(multiprocessing.cpu_count(), 4)

@asynccontextmanager
async def lifespan(app: FastAPI):
    # Startup
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)
    
    # Initialize RabbitMQ
    rabbitmq = RabbitMQService()
    await rabbitmq.connect()
    await rabbitmq.setup_exchanges()
    await rabbitmq.close()
    
    # Initialize metrics
    metrics = MetricsService()
    await metrics.initialize()
    
    active_workers.set(NUM_WORKERS)
    
    yield
    
    # Shutdown
    await engine.dispose()


app = FastAPI(
    title="Twitter Architecture - Step 5: Balanced Multi-Consumer",
    description="Production-ready Twitter-like API with monitoring and optimized routing",
    version="5.0.0",
    lifespan=lifespan
)

# Mount Prometheus metrics endpoint
metrics_app = make_asgi_app()
app.mount("/metrics", metrics_app)

# Include routers
app.include_router(users.router, prefix="/api/users", tags=["users"])
app.include_router(tweets.router, prefix="/api/tweets", tags=["tweets"])
app.include_router(subscriptions.router, prefix="/api/subscriptions", tags=["subscriptions"])
app.include_router(feed.router, prefix="/api/feed", tags=["feed"])


@app.get("/")
async def root():
    return {
        "message": "Twitter Architecture Demo - Step 5: Production Ready",
        "features": [
            "Optimized consistent hash routing",
            "Prometheus metrics integration",
            "StatsD for custom metrics",
            "Grafana dashboards",
            "Load-balanced workers",
            "Production monitoring"
        ],
        "endpoints": {
            "metrics": "/metrics",
            "grafana": "http://localhost:3000",
            "api_docs": "/docs"
        }
    }


@app.get("/health")
async def health_check():
    """Health check endpoint for monitoring"""
    return {"status": "healthy", "workers": NUM_WORKERS}