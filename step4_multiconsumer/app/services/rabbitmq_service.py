import aio_pika
from aio_pika import ExchangeType
import json
from typing import Dict, Any, Optional, List
from common.config import get_settings

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
        await self.channel.set_qos(prefetch_count=10)

    async def setup_exchanges(self):
        """Set up exchanges and queues for multi-consumer pattern"""
        # Create consistent hash exchange for even distribution
        self.exchange = await self.channel.declare_exchange(
            "tweet_events_consistent",
            ExchangeType.X_CONSISTENT_HASH,
            durable=True,
            arguments={"hash-header": "user_id"}
        )
        
        # Create multiple queues for workers
        num_workers = 4  # Could be configurable
        for i in range(num_workers):
            queue = await self.channel.declare_queue(
                f"feed_updates_worker_{i}",
                durable=True
            )
            
            # Bind with weight for consistent hash distribution
            await queue.bind(self.exchange, routing_key="20")

    async def publish_tweet_event_to_followers(self, tweet_data: Dict[str, Any], follower_ids: List[int]):
        """
        Step 4: Publish individual messages for each follower.
        This allows parallel processing by multiple workers.
        """
        if not self.exchange:
            await self.connect()
            await self.setup_exchanges()
        
        # Publish a message for each follower
        for follower_id in follower_ids:
            message_data = {
                **tweet_data,
                "user_id": follower_id  # This will be used for routing
            }
            
            message = aio_pika.Message(
                body=json.dumps(message_data).encode(),
                delivery_mode=aio_pika.DeliveryMode.PERSISTENT,
                headers={"user_id": str(follower_id)}  # Routing key for consistent hash
            )
            
            await self.exchange.publish(
                message,
                routing_key=str(follower_id % 100)  # Simple hash for routing
            )

    async def close(self):
        """Close RabbitMQ connection"""
        if self.connection:
            await self.connection.close()