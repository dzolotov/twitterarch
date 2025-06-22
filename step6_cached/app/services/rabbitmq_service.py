import aio_pika
from aio_pika import ExchangeType
import json
from typing import Dict, Any, Optional, List
from common.config import get_settings
import uuid

settings = get_settings()


class RabbitMQService:
    def __init__(self):
        self.connection: Optional[aio_pika.Connection] = None
        self.channel: Optional[aio_pika.Channel] = None
        self.exchange: Optional[aio_pika.Exchange] = None

    async def connect(self):
        """Connect to RabbitMQ"""
        self.connection = await aio_pika.connect_robust(settings.rabbitmq_url)
        self.channel = await self.connection.channel()
        await self.channel.set_qos(prefetch_count=100)  # Higher prefetch for cache

    async def setup_exchanges(self):
        """Set up exchanges for cached architecture"""
        # Create consistent hash exchange
        self.exchange = await self.channel.declare_exchange(
            "tweet_events_cached",
            ExchangeType.X_CONSISTENT_HASH,
            durable=True,
            arguments={
                "hash-header": "routing_hash",
                "hash-on": "header"
            }
        )
        
        # Create queues with cache-optimized settings
        for i in range(4):
            queue = await self.channel.declare_queue(
                f"feed_updates_cached_{i}",
                durable=True,
                arguments={
                    "x-max-length": 500000,      # Larger queue for burst handling
                    "x-message-ttl": 7200000,    # 2 hour TTL
                    "x-max-priority": 10         # Priority support
                }
            )
            
            # Bind with optimized weight
            await queue.bind(self.exchange, routing_key="25")

    async def publish_tweet_event_batch(self, tweet_data: Dict[str, Any], follower_ids: List[int]):
        """Publish with message IDs for deduplication"""
        if not self.exchange:
            await self.connect()
            await self.setup_exchanges()
        
        # Batch messages with unique IDs
        messages = []
        base_message_id = str(uuid.uuid4())
        
        for idx, follower_id in enumerate(follower_ids):
            message_data = {
                **tweet_data,
                "user_id": follower_id
            }
            
            # Unique message ID for deduplication
            message_id = f"{base_message_id}-{idx}"
            routing_hash = str(follower_id % 25)
            
            message = aio_pika.Message(
                body=json.dumps(message_data).encode(),
                delivery_mode=aio_pika.DeliveryMode.PERSISTENT,
                message_id=message_id,
                headers={
                    "routing_hash": routing_hash,
                    "user_id": str(follower_id)
                },
                priority=5 if follower_id < 100 else 1  # Prioritize active users
            )
            messages.append((message, routing_hash))
        
        # Publish in optimized batches
        batch_size = 200  # Larger batches for cache
        for i in range(0, len(messages), batch_size):
            batch = messages[i:i + batch_size]
            async with self.channel.transaction():
                for message, routing_key in batch:
                    await self.exchange.publish(message, routing_key=routing_key)

    async def close(self):
        """Close RabbitMQ connection"""
        if self.connection:
            await self.connection.close()