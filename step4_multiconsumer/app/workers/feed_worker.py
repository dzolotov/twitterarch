import asyncio
import aio_pika
import json
import logging
import sys
from typing import Optional
from sqlalchemy.ext.asyncio import AsyncSession
from common.database import async_session_maker
from common.config import get_settings
from ..services.feed_service import FeedService

logger = logging.getLogger(__name__)
settings = get_settings()


class FeedWorker:
    def __init__(self, worker_id: int):
        self.worker_id = worker_id
        self.connection: Optional[aio_pika.Connection] = None
        self.channel: Optional[aio_pika.Channel] = None
        self.queue: Optional[aio_pika.Queue] = None
        self.running = False

    async def start(self):
        """Start the feed worker to consume messages from its specific queue"""
        self.running = True
        logger.info(f"Starting feed worker {self.worker_id}...")
        
        try:
            # Connect to RabbitMQ
            self.connection = await aio_pika.connect_robust(settings.rabbitmq_url)
            self.channel = await self.connection.channel()
            await self.channel.set_qos(prefetch_count=10)
            
            # Connect to specific worker queue
            self.queue = await self.channel.declare_queue(
                f"feed_updates_worker_{self.worker_id}",
                durable=True
            )
            
            # Start consuming messages
            await self.queue.consume(self.process_message)
            
            logger.info(f"Feed worker {self.worker_id} started successfully")
            
            # Keep the worker running
            while self.running:
                await asyncio.sleep(1)
                
        except Exception as e:
            logger.error(f"Feed worker {self.worker_id} error: {e}")
            raise
        finally:
            await self.cleanup()

    async def process_message(self, message: aio_pika.IncomingMessage):
        """Process a single message for a specific user"""
        async with message.process():
            try:
                # Parse message
                data = json.loads(message.body.decode())
                user_id = data["user_id"]
                logger.info(f"Worker {self.worker_id} processing tweet {data['tweet_id']} for user {user_id}")
                
                # Create database session
                async with async_session_maker() as db:
                    feed_service = FeedService(db)
                    await feed_service.add_tweet_to_user_feed(data)
                
                logger.info(f"Worker {self.worker_id} successfully processed for user {user_id}")
                
            except Exception as e:
                logger.error(f"Worker {self.worker_id} error processing message: {e}")
                raise

    async def stop(self):
        """Stop the feed worker gracefully"""
        logger.info(f"Stopping feed worker {self.worker_id}...")
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


async def main():
    """Run worker as standalone process"""
    if len(sys.argv) < 2:
        print("Usage: python -m app.workers.feed_worker <worker_id>")
        sys.exit(1)
    
    worker_id = int(sys.argv[1])
    worker = FeedWorker(worker_id)
    
    try:
        await worker.start()
    except KeyboardInterrupt:
        await worker.stop()


if __name__ == "__main__":
    logging.basicConfig(level=logging.INFO)
    asyncio.run(main())