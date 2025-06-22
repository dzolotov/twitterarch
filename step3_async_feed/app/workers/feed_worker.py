import asyncio
import aio_pika
import json
import logging
from typing import Optional
from sqlalchemy.ext.asyncio import AsyncSession
from common.database import async_session_maker
from common.config import get_settings
from ..services.feed_service import FeedService

logger = logging.getLogger(__name__)
settings = get_settings()


class FeedWorker:
    def __init__(self):
        self.connection: Optional[aio_pika.Connection] = None
        self.channel: Optional[aio_pika.Channel] = None
        self.queue: Optional[aio_pika.Queue] = None
        self.running = False

    async def start(self):
        """Start the feed worker to consume messages from RabbitMQ"""
        self.running = True
        logger.info("Starting feed worker...")
        
        try:
            # Connect to RabbitMQ
            self.connection = await aio_pika.connect_robust(settings.rabbitmq_url)
            self.channel = await self.connection.channel()
            await self.channel.set_qos(prefetch_count=10)
            
            # Declare exchange and queue
            exchange = await self.channel.declare_exchange(
                "tweet_events",
                aio_pika.ExchangeType.DIRECT,
                durable=True
            )
            
            self.queue = await self.channel.declare_queue(
                "feed_updates",
                durable=True
            )
            
            await self.queue.bind(exchange, routing_key="new_tweet")
            
            # Start consuming messages
            await self.queue.consume(self.process_message)
            
            logger.info("Feed worker started successfully")
            
            # Keep the worker running
            while self.running:
                await asyncio.sleep(1)
                
        except Exception as e:
            logger.error(f"Feed worker error: {e}")
            raise
        finally:
            await self.cleanup()

    async def process_message(self, message: aio_pika.IncomingMessage):
        """Process a single message from the queue"""
        async with message.process():
            try:
                # Parse message
                tweet_data = json.loads(message.body.decode())
                logger.info(f"Processing tweet {tweet_data['tweet_id']} for feed updates")
                
                # Create database session
                async with async_session_maker() as db:
                    feed_service = FeedService(db)
                    await feed_service.add_tweet_to_followers_feeds_async(tweet_data)
                
                logger.info(f"Successfully processed tweet {tweet_data['tweet_id']}")
                
            except Exception as e:
                logger.error(f"Error processing message: {e}")
                # In production, you might want to send to a dead letter queue
                raise

    async def stop(self):
        """Stop the feed worker gracefully"""
        logger.info("Stopping feed worker...")
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