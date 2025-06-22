import aio_pika
from aio_pika import ExchangeType
import json
from typing import Dict, Any, Optional, List
from common.config import get_settings
from .metrics_service import MetricsService, track_time

settings = get_settings()


class RabbitMQService:
    def __init__(self):
        self.connection: Optional[aio_pika.Connection] = None
        self.channel: Optional[aio_pika.Channel] = None
        self.exchange: Optional[aio_pika.Exchange] = None
        self.metrics = MetricsService()

    async def connect(self):
        """Connect to RabbitMQ"""
        self.connection = await aio_pika.connect_robust(settings.rabbitmq_url)
        self.channel = await self.connection.channel()
        await self.channel.set_qos(prefetch_count=10)

    async def setup_exchanges(self):
        """Set up optimized exchanges for balanced distribution"""
        # Create consistent hash exchange with optimized settings
        self.exchange = await self.channel.declare_exchange(
            "tweet_events_balanced",
            ExchangeType.X_CONSISTENT_HASH,
            durable=True,
            arguments={
                "hash-header": "routing_hash",
                "hash-on": "header"
            }
        )
        
        # Create queues with optimized bindings
        num_workers = 4
        for i in range(num_workers):
            queue = await self.channel.declare_queue(
                f"feed_updates_balanced_{i}",
                durable=True,
                arguments={
                    "x-max-length": 100000,  # Limit queue size
                    "x-message-ttl": 3600000  # 1 hour TTL
                }
            )
            
            # Bind with weight 20 for better distribution
            await queue.bind(self.exchange, routing_key="20")

    @track_time("rabbitmq.publish_batch")
    async def publish_tweet_event_batch(self, tweet_data: Dict[str, Any], follower_ids: List[int]):
        """
        Step 5: Optimized batch publishing with metrics
        """
        if not self.exchange:
            await self.connect()
            await self.setup_exchanges()
        
        # Track metrics
        self.metrics.increment("tweets.published")
        self.metrics.gauge("tweets.fanout_size", len(follower_ids))
        
        # Batch messages for better performance
        messages = []
        for follower_id in follower_ids:
            message_data = {
                **tweet_data,
                "user_id": follower_id
            }
            
            # Use optimized routing hash
            routing_hash = str(follower_id % 20)  # Better distribution
            
            message = aio_pika.Message(
                body=json.dumps(message_data).encode(),
                delivery_mode=aio_pika.DeliveryMode.PERSISTENT,
                headers={
                    "routing_hash": routing_hash,
                    "user_id": str(follower_id)
                }
            )
            messages.append((message, routing_hash))
        
        # Publish in batches
        batch_size = 100
        for i in range(0, len(messages), batch_size):
            batch = messages[i:i + batch_size]
            async with self.channel.transaction():
                for message, routing_key in batch:
                    await self.exchange.publish(message, routing_key=routing_key)
            
            self.metrics.increment("rabbitmq.batch_published")

    async def close(self):
        """Close RabbitMQ connection"""
        if self.connection:
            await self.connection.close()