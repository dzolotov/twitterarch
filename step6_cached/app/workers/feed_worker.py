import asyncio
import aio_pika
import json
import logging
import uuid
from typing import Optional
from sqlalchemy.ext.asyncio import AsyncSession
from common.database import async_session_maker
from common.config import get_settings
from ..services.feed_service import FeedService
from ..services.cache_service import CacheService

logger = logging.getLogger(__name__)
settings = get_settings()


class FeedWorker:
    def __init__(self, worker_id: int, cache_service: CacheService):
        self.worker_id = worker_id
        self.cache_service = cache_service
        self.connection: Optional[aio_pika.Connection] = None
        self.channel: Optional[aio_pika.Channel] = None
        self.queue: Optional[aio_pika.Queue] = None
        self.running = False

    async def start(self):
        """Start the feed worker with caching support"""
        self.running = True
        logger.info(f"Starting cached feed worker {self.worker_id}...")
        
        try:
            # Connect to RabbitMQ
            self.connection = await aio_pika.connect_robust(settings.rabbitmq_url)
            self.channel = await self.connection.channel()
            await self.channel.set_qos(prefetch_count=50)
            
            # Connect to specific worker queue
            self.queue = await self.channel.declare_queue(
                f"feed_updates_cached_{self.worker_id}",
                durable=True
            )
            
            # Start consuming messages
            await self.queue.consume(self.process_message)
            
            logger.info(f"Cached feed worker {self.worker_id} started successfully")
            
            # Start cache warming task
            warmup_task = asyncio.create_task(self._periodic_cache_warmup())
            
            # Keep the worker running
            while self.running:
                await asyncio.sleep(1)
            
            warmup_task.cancel()
                
        except Exception as e:
            logger.error(f"Feed worker {self.worker_id} error: {e}")
            raise
        finally:
            await self.cleanup()

    async def process_message(self, message: aio_pika.IncomingMessage):
        """Process message with caching and deduplication"""
        message_id = message.message_id or str(uuid.uuid4())
        
        async with message.process():
            try:
                # Parse message
                data = json.loads(message.body.decode())
                user_id = data["user_id"]
                
                logger.info(f"Worker {self.worker_id} processing tweet {data['tweet_id']} for user {user_id}")
                
                # Create database session
                async with async_session_maker() as db:
                    feed_service = FeedService(db, self.cache_service)
                    await feed_service.add_tweet_to_user_feed(data, message_id)
                
                logger.info(f"Worker {self.worker_id} successfully processed for user {user_id}")
                
            except Exception as e:
                logger.error(f"Worker {self.worker_id} error processing message: {e}")
                raise

    async def _periodic_cache_warmup(self):
        """Periodically warm cache for hot users"""
        while self.running:
            try:
                await asyncio.sleep(300)  # Every 5 minutes
                
                # Get hot users
                hot_users = await self.cache_service.get_hot_users(20)
                
                if hot_users:
                    logger.info(f"Warming cache for {len(hot_users)} hot users")
                    
                    async with async_session_maker() as db:
                        feed_service = FeedService(db, self.cache_service)
                        
                        for user_id in hot_users:
                            # Force cache refresh by getting feed
                            await feed_service.get_user_feed(user_id, limit=100)
                
            except Exception as e:
                logger.error(f"Cache warmup error: {e}")

    async def stop(self):
        """Stop the feed worker gracefully"""
        logger.info(f"Stopping cached feed worker {self.worker_id}...")
        self.running = False
        await self.cleanup()

    async def cleanup(self):
        """Clean up resources"""
        if self.queue:
            await self.queue.cancel_consumer()
        if self.channel:
            await self.channel.close()
        if self.connection:
            await self.connection.close()